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
  alias Estimate.MCP.OAuth.{Client, Code, PKCE, Token}
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

  def create_code(attrs) do
    plaintext = @code_prefix <> random_token()

    row = %Code{
      code_hash: hash(plaintext),
      redirect_uri: attrs.redirect_uri,
      code_challenge: attrs.code_challenge,
      resource: attrs.resource,
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
  # plain `{:error, :invalid_grant}` tuples (no rollback) after any revocation,
  # so the revocation commits; only the happy-path issue/rotate uses a
  # transaction, and it always commits (never rolls back).

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
          # OAuth 2.1: a reused code invalidates everything it produced.
          # Plain update_all (no surrounding transaction) so this commits.
          Repo.update_all(from(t in Token, where: t.code_id == ^code.id and is_nil(t.revoked_at)),
            set: [revoked_at: now()]
          )

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
        organization_id: code.organization_id
      })

    %{access_token: access, refresh_token: refresh, expires_in: @access_ttl_seconds}
  end

  def refresh_tokens(plaintext, client_id) do
    Repo.without_rls(fn ->
      row = Repo.one(from(t in Token, where: t.refresh_token_hash == ^hash(plaintext)))

      cond do
        is_nil(row) or row.client_id != client_id ->
          {:error, :invalid_grant}

        not is_nil(row.revoked_at) ->
          # Rotated-token reuse: assume theft, kill the family. Plain
          # update_all (no transaction) so the revocation commits.
          revoke_family(row.family_id)
          {:error, :invalid_grant}

        DateTime.compare(row.refresh_expires_at, now()) != :gt ->
          {:error, :invalid_grant}

        true ->
          rotate(row)
      end
    end)
  end

  # Revoke-old + insert-new atomically, re-checking revoked_at under a row lock
  # so two concurrent refreshes of the same token can't both rotate. On success
  # the transaction commits (no rollback-reverts-revocation problem here).
  defp rotate(row) do
    result =
      Repo.transaction(fn ->
        locked = Repo.one(from(t in Token, where: t.id == ^row.id, lock: "FOR UPDATE"))

        if is_nil(locked.revoked_at) do
          Repo.update_all(from(t in Token, where: t.id == ^locked.id), set: [revoked_at: now()])

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
              organization_id: locked.organization_id
            })

          %{access_token: access, refresh_token: refresh, expires_in: @access_ttl_seconds}
        else
          # Lost the race: another request already rotated this exact token.
          Repo.rollback(:invalid_grant)
        end
      end)

    case result do
      {:ok, tokens} -> {:ok, tokens}
      {:error, :invalid_grant} -> {:error, :invalid_grant}
    end
  end

  defp revoke_family(family_id) do
    Repo.update_all(
      from(t in Token, where: t.family_id == ^family_id and is_nil(t.revoked_at)),
      set: [revoked_at: now()]
    )
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
        {:ok, %{user_id: token.user_id, organization_id: token.organization_id, role: hit.role}}
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
