defmodule Estimate.MCP.OAuth do
  @moduledoc """
  Minimal OAuth 2.1 authorization server backing the MCP endpoint:
  dynamic client registration, PKCE authorization codes, rotating
  refresh-token families. All DB ops run via `Repo.without_rls/1` —
  OAuth requests carry no org RLS context; identity comes from the
  authenticated session (authorize) or presented token hashes.
  """

  import Ecto.Query

  alias Estimate.Accounts.{Membership, Organization}
  alias Estimate.MCP.OAuth.{Client, Code, PKCE, Scopes, Token}
  alias Estimate.Repo

  @code_prefix "est_ac_"
  @access_prefix "est_at_"
  @refresh_prefix "est_rt_"
  @rand_size 32
  @code_ttl_seconds 120
  @access_ttl_seconds 3600
  @refresh_ttl_seconds 60 * 60 * 24 * 30
  @last_used_resolution_seconds 300

  def register_client(attrs) when is_map(attrs) do
    changeset = Client.registration_changeset(%Client{}, attrs)
    Repo.without_rls(fn -> Repo.insert(changeset) end)
  end

  def get_client(client_id) do
    Repo.without_rls(fn -> Repo.get(Client, client_id) end)
  rescue
    Ecto.Query.CastError -> nil
  end

  # attrs.scope, if present, is stored as-is (no validation); callers must
  # run it through Scopes.parse/1 first.
  def create_code(attrs) do
    plaintext = @code_prefix <> random_token()

    row = %Code{
      code_hash: hash(plaintext),
      redirect_uri: attrs.redirect_uri,
      code_challenge: attrs.code_challenge,
      resource: attrs.resource,
      scope: Map.get(attrs, :scope, Scopes.read_only()),
      expires_at: expires_in(@code_ttl_seconds),
      client_id: attrs.client_id,
      user_id: attrs.user_id,
      organization_id: attrs.organization_id
    }

    Repo.without_rls(fn ->
      {:ok, _} = Repo.insert(row)
      {:ok, plaintext}
    end)
  end

  # NOTE (correctness): the replay and refresh-reuse paths REVOKE tokens and
  # must PERSIST that revocation while still returning an error. Do NOT wrap
  # revoke-then-error in a `Repo.transaction` that ends in `Repo.rollback` —
  # rollback reverts the revocation you just made. The structure below returns
  # plain `{:error, :invalid_grant}` tuples after any revocation. revoke_family/1
  # does run its update inside a `Repo.transaction` now (to hold an advisory
  # lock, see below) — but that transaction always commits, never rolls back.
  # The real invariant isn't "no transaction", it's: no path rolls back after
  # a revoke has happened (a rollback would undo it).

  def exchange_code(plaintext, %{} = params) do
    Repo.without_rls(fn ->
      case consume_code(hash(plaintext)) do
        {:ok, code} ->
          if code.client_id == params.client_id and
               code.redirect_uri == params.redirect_uri and
               code.resource == params.resource and
               PKCE.verify(code.code_challenge, params.code_verifier) do
            {:ok, issue_tokens(code)}
          else
            # Code already consumed (single-use); a bad verifier/redirect/client
            # burns it — the client must restart the flow. Acceptable: a PKCE
            # mismatch is an attack or broken client, not a normal retry.
            {:error, :invalid_grant}
          end

        {:replayed, code} ->
          # OAuth 2.1: a reused code invalidates everything it produced. Route
          # through revoke_family/1 (advisory-lock + always-commit) for every
          # family_id this code_id ever spawned, rather than a bare update_all
          # scoped to code_id -- a concurrent rotation can insert a new family
          # member the plain update_all's READ COMMITTED snapshot misses,
          # exactly the race closed for refresh reuse (see revoke_family/1).
          from(t in Token, where: t.code_id == ^code.id, distinct: true, select: t.family_id)
          |> Repo.all()
          |> Enum.each(&revoke_family/1)

          {:error, :invalid_grant}

        :not_found ->
          {:error, :invalid_grant}
      end
    end)
  end

  # Atomic single-statement consume: the `is_nil(used_at)` guard in the WHERE
  # means only one concurrent caller can flip a given code to used and get the
  # row back — replay-safe without an explicit lock.
  defp consume_code(code_hash) do
    result =
      from(c in Code,
        where: c.code_hash == ^code_hash and is_nil(c.used_at) and c.expires_at > ^now(),
        select: c
      )
      |> Repo.update_all(set: [used_at: now()])

    case result do
      {1, [code]} ->
        {:ok, code}

      {0, _} ->
        case Repo.one(from(c in Code, where: c.code_hash == ^code_hash and not is_nil(c.used_at))) do
          nil -> :not_found
          code -> {:replayed, code}
        end
    end
  end

  defp issue_tokens(code) do
    access = @access_prefix <> random_token()
    refresh = @refresh_prefix <> random_token()

    {:ok, _} =
      Repo.insert(%Token{
        access_token_hash: hash(access),
        refresh_token_hash: hash(refresh),
        family_id: Ecto.UUID.generate(),
        access_expires_at: expires_in(@access_ttl_seconds),
        refresh_expires_at: expires_in(@refresh_ttl_seconds),
        client_id: code.client_id,
        code_id: code.id,
        user_id: code.user_id,
        organization_id: code.organization_id,
        scope: code.scope
      })

    %{
      access_token: access,
      refresh_token: refresh,
      expires_in: @access_ttl_seconds,
      scope: code.scope
    }
  end

  def refresh_tokens(plaintext, client_id) do
    Repo.without_rls(fn ->
      row = Repo.one(from(t in Token, where: t.refresh_token_hash == ^hash(plaintext)))

      cond do
        is_nil(row) or row.client_id != client_id ->
          {:error, :invalid_grant}

        not is_nil(row.revoked_at) ->
          # Rotated-token reuse: assume theft, kill the family.
          # revoke_family/1 wraps its update in an always-commit transaction
          # (advisory lock only, never rolls back), so the revocation persists.
          revoke_family(row.family_id)
          {:error, :invalid_grant}

        DateTime.compare(row.refresh_expires_at, now()) != :gt ->
          {:error, :invalid_grant}

        not org_enabled_and_member?(row) ->
          # Settings page promises "disabling instantly rejects every key" --
          # verify_access_token/1 already gates on this; refresh must too, or
          # a disabled org's connector keeps silently rotating a 30-day
          # family. No rotation on this path: neither revoke nor reissue.
          {:error, :invalid_grant}

        true ->
          rotate(row)
      end
    end)
  end

  # Same join taxonomy as verify_access_token/1's query: org must exist with
  # mcp_enabled true, and the token's user must still hold a membership in it.
  defp org_enabled_and_member?(%Token{user_id: user_id, organization_id: org_id}) do
    query =
      from o in Organization,
        left_join: m in Membership,
        on: m.user_id == ^user_id and m.organization_id == ^org_id,
        where: o.id == ^org_id,
        select: %{mcp_enabled: o.mcp_enabled, role: m.role}

    case Repo.one(query) do
      %{mcp_enabled: true, role: role} -> not is_nil(role)
      _ -> false
    end
  end

  # Revoke-old + insert-new atomically, re-checking revoked_at under a row lock
  # so two concurrent refreshes of the same token can't both rotate. On success
  # the transaction commits (no rollback-reverts-revocation problem here).
  #
  # First statement: a transaction-scoped advisory lock keyed on the token's
  # family. This serializes against revoke_family/1's own lock on the same
  # key, so a concurrent family-kill can never land in the gap between "this
  # rotation's child has committed" and "the kill's snapshot was taken" —
  # closing the READ COMMITTED snapshot-miss race (see revoke_family/1).
  defp rotate(row) do
    result =
      Repo.transaction(fn ->
        Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", [row.family_id])

        locked = Repo.one(from(t in Token, where: t.id == ^row.id, lock: "FOR UPDATE"))

        cond do
          is_nil(locked) ->
            # Row vanished between the outer unlocked read and this locked
            # re-check (e.g. a concurrent revoke_for_membership deleted it).
            # No row => no family to key on, so no revoke_family call.
            Repo.rollback(:not_found)

          is_nil(locked.revoked_at) ->
            Repo.update_all(from(t in Token, where: t.id == ^locked.id),
              set: [revoked_at: now()]
            )

            access = @access_prefix <> random_token()
            refresh = @refresh_prefix <> random_token()

            {:ok, _} =
              Repo.insert(%Token{
                access_token_hash: hash(access),
                refresh_token_hash: hash(refresh),
                family_id: locked.family_id,
                access_expires_at: expires_in(@access_ttl_seconds),
                refresh_expires_at: expires_in(@refresh_ttl_seconds),
                client_id: locked.client_id,
                code_id: locked.code_id,
                user_id: locked.user_id,
                organization_id: locked.organization_id,
                scope: locked.scope
              })

            %{
              access_token: access,
              refresh_token: refresh,
              expires_in: @access_ttl_seconds,
              scope: locked.scope
            }

          true ->
            # Lost the race: another concurrent refresh of this exact token
            # already rotated it — reuse of a rotated refresh token by
            # definition, same threat as the sequential-reuse branch in
            # refresh_tokens/2. Must kill the family too (below).
            Repo.rollback(:reused)
        end
      end)

    case result do
      {:ok, tokens} ->
        {:ok, tokens}

      {:error, :not_found} ->
        {:error, :invalid_grant}

      {:error, :reused} ->
        # Transaction above already rolled back (nothing in it persisted), so
        # this runs as a plain autocommit update_all — it commits regardless
        # of the {:error, ...} this function returns.
        revoke_family(row.family_id)
        {:error, :invalid_grant}
    end
  end

  @doc """
  Always-commit family revoke; see the note above exchange_code/2 for the
  invariant this preserves. Returns the number of rows revoked (the
  update_all count) — callers that only need the side effect (exchange_code's
  replay branch, refresh_tokens, rotate/1) discard it.
  """
  def revoke_family(family_id) do
    # Always commits — never rolls back — so the revoke-must-persist rule
    # holds despite using a transaction. The transaction exists only to hold
    # the advisory lock for its duration: taking the same family-scoped lock
    # as rotate/1 serializes the two, so whichever of a racing rotate/kill
    # pair runs second sees the other's fully-committed effect (either the
    # new child row is visible to this UPDATE, or this revocation is visible
    # to rotate/1's FOR UPDATE re-check) — no snapshot-miss window.
    {:ok, {count, _}} =
      Repo.transaction(fn ->
        Repo.query!("SELECT pg_advisory_xact_lock(hashtext($1))", [family_id])

        Repo.update_all(
          from(t in Token, where: t.family_id == ^family_id and is_nil(t.revoked_at)),
          set: [revoked_at: now()]
        )
      end)

    count
  end

  def verify_access_token(@access_prefix <> _ = plaintext) do
    Repo.without_rls(fn ->
      query =
        from t in Token,
          join: o in Organization,
          on: o.id == t.organization_id,
          left_join: m in Membership,
          on: m.user_id == t.user_id and m.organization_id == t.organization_id,
          where: t.access_token_hash == ^hash(plaintext) and is_nil(t.revoked_at),
          select: %{token: t, mcp_enabled: o.mcp_enabled, role: m.role}

      case Repo.one(query) do
        nil -> {:error, :invalid_key}
        %{token: t} = hit -> check_token(t, hit)
      end
    end)
  end

  def verify_access_token(_), do: {:error, :invalid_key}

  defp check_token(token, hit) do
    cond do
      DateTime.compare(token.access_expires_at, now()) != :gt ->
        {:error, :token_expired}

      is_nil(hit.role) ->
        {:error, :not_a_member}

      hit.mcp_enabled == false ->
        {:error, :mcp_disabled}

      true ->
        maybe_touch_last_used(token)

        {:ok,
         %{
           user_id: token.user_id,
           organization_id: token.organization_id,
           role: hit.role,
           scope: token.scope
         }}
    end
  end

  defp maybe_touch_last_used(%Token{} = token) do
    stale? =
      is_nil(token.last_used_at) or
        DateTime.diff(now(), token.last_used_at) >= @last_used_resolution_seconds

    if stale? do
      Repo.update_all(from(t in Token, where: t.id == ^token.id), set: [last_used_at: now()])
    end

    :ok
  end

  @doc "Active grants (token families) for a user, newest first."
  def list_grants(user_id) do
    Repo.without_rls(fn ->
      from(t in Token,
        join: c in Client,
        on: c.id == t.client_id,
        join: o in Organization,
        on: o.id == t.organization_id,
        left_join: code in Code,
        on: code.id == t.code_id,
        where: t.user_id == ^user_id and is_nil(t.revoked_at) and t.refresh_expires_at > ^now(),
        group_by: [t.family_id, c.name, o.name, t.scope],
        select: %{
          family_id: t.family_id,
          client_name: c.name,
          organization_name: o.name,
          scope: t.scope,
          granted_at: type(min(coalesce(code.inserted_at, t.inserted_at)), :utc_datetime),
          last_used_at: type(max(t.last_used_at), :utc_datetime)
        },
        order_by: [desc: min(coalesce(code.inserted_at, t.inserted_at))]
      )
      |> Repo.all()
    end)
  end

  @doc "Revokes a family only if it belongs to `user_id`. Routes through revoke_family/1 for the advisory-locked, race-safe revoke (see its doc)."
  def revoke_grant(user_id, family_id) do
    Repo.without_rls(fn ->
      owned? =
        Repo.exists?(from(t in Token, where: t.family_id == ^family_id and t.user_id == ^user_id))

      if owned? do
        {:ok, revoke_family(family_id)}
      else
        {:error, :not_found}
      end
    end)
  rescue
    Ecto.Query.CastError -> {:error, :not_found}
  end

  @doc "Revokes every live token of the user (all orgs), one family at a time through revoke_family/1's advisory lock. Called on password change."
  def revoke_all_for_user(user_id) do
    Repo.without_rls(fn ->
      from(t in Token,
        where: t.user_id == ^user_id and is_nil(t.revoked_at),
        distinct: true,
        select: t.family_id
      )
      |> Repo.all()
      |> Enum.each(&revoke_family/1)
    end)

    :ok
  end

  @doc "Plain delete_all — the caller supplies the RLS posture (used inside delete_membership's without_rls step)."
  def revoke_for_membership(user_id, org_id) do
    Repo.delete_all(
      from(c in Code, where: c.user_id == ^user_id and c.organization_id == ^org_id)
    )

    Repo.delete_all(
      from(t in Token, where: t.user_id == ^user_id and t.organization_id == ^org_id)
    )

    :ok
  end

  defp random_token, do: Base.url_encode64(:crypto.strong_rand_bytes(@rand_size), padding: false)
  defp hash(plaintext), do: :crypto.hash(:sha256, plaintext)
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
  defp expires_in(seconds), do: DateTime.add(now(), seconds) |> DateTime.truncate(:second)
end
