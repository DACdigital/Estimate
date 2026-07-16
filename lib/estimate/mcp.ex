defmodule Estimate.MCP do
  @moduledoc """
  Per-membership MCP API keys.

  Management functions run under the ambient RLS context (own-key policy).
  `verify_api_key/1` runs via `Repo.without_rls/1` — verification precedes
  any org context by definition, same escape hatch as search reindexing.
  """

  import Ecto.Query

  alias Estimate.Accounts.{Membership, Organization}
  alias Estimate.MCP.APIKey
  alias Estimate.Repo

  @prefix "est_"
  @rand_size 32
  @last_used_resolution_seconds 300

  def generate_api_key(user_id, org_id) do
    plaintext =
      @prefix <> Base.url_encode64(:crypto.strong_rand_bytes(@rand_size), padding: false)

    attrs = %{
      key_hash: :crypto.hash(:sha256, plaintext),
      key_prefix: String.slice(plaintext, 0, 12),
      user_id: user_id,
      organization_id: org_id
    }

    Repo.ensure_org_context(fn ->
      Repo.transaction(fn ->
        Repo.delete_all(own_key_query(user_id, org_id))

        case %APIKey{} |> APIKey.changeset(attrs) |> Repo.insert() do
          {:ok, api_key} -> {plaintext, api_key}
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
    end)
  end

  def get_api_key(user_id, org_id) do
    Repo.ensure_org_context(fn ->
      Repo.get_by(APIKey, user_id: user_id, organization_id: org_id)
    end)
  end

  def revoke_api_key(user_id, org_id) do
    Repo.ensure_org_context(fn ->
      {count, _} = Repo.delete_all(own_key_query(user_id, org_id))
      count
    end)
  end

  def verify_api_key(@prefix <> _rest = plaintext) do
    hash = :crypto.hash(:sha256, plaintext)

    Repo.without_rls(fn ->
      query =
        from k in APIKey,
          join: o in Organization,
          on: o.id == k.organization_id,
          left_join: m in Membership,
          on: m.user_id == k.user_id and m.organization_id == k.organization_id,
          where: k.key_hash == ^hash,
          select: %{key: k, mcp_enabled: o.mcp_enabled, role: m.role}

      case Repo.one(query) do
        nil -> {:error, :invalid_key}
        %{role: nil} -> {:error, :not_a_member}
        %{mcp_enabled: false} -> {:error, :mcp_disabled}
        %{key: key, role: role} -> {:ok, authorize(key, role)}
      end
    end)
  end

  def verify_api_key(_), do: {:error, :invalid_key}

  defp authorize(%APIKey{} = key, role) do
    maybe_touch_last_used(key)
    %{user_id: key.user_id, organization_id: key.organization_id, role: role}
  end

  defp maybe_touch_last_used(%APIKey{} = key) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    stale? =
      is_nil(key.last_used_at) or
        DateTime.diff(now, key.last_used_at) >= @last_used_resolution_seconds

    if stale? do
      from(k in APIKey, where: k.id == ^key.id)
      |> Repo.update_all(set: [last_used_at: now])
    end

    :ok
  end

  defp own_key_query(user_id, org_id) do
    from k in APIKey, where: k.user_id == ^user_id and k.organization_id == ^org_id
  end
end
