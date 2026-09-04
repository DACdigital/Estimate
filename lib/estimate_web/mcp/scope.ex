defmodule EstimateWeb.MCP.Scope do
  @moduledoc """
  Bridges anubis auth claims to the app's ambient RLS context.

  Anubis executes tools in per-session processes, not the HTTP request
  process — so the RLS pdict is set here, immediately before every tool
  body, never assumed. DB privileges end up identical to the same user's
  LiveView session (OrgAuth.on_mount does the same two puts).
  """

  require Logger

  alias Anubis.Server.Frame
  alias Estimate.Repo

  def claims(%Frame{} = frame) do
    auth = Frame.authorization(frame)

    %{
      user_id: auth.sub,
      org_id: auth.raw_claims["org_id"],
      role: auth.raw_claims["role"],
      scopes: parse_scopes(auth.raw_claims["scope"])
    }
  end

  # Fail closed: a claim set without scope, or with a malformed (non-binary)
  # scope claim, is read-only.
  defp parse_scopes(nil), do: ["mcp:read"]
  defp parse_scopes(scope) when is_binary(scope), do: String.split(scope, " ", trim: true)
  defp parse_scopes(_), do: ["mcp:read"]

  def with_scope(%Frame{} = frame, fun) when is_function(fun, 1) do
    %{user_id: user_id, org_id: org_id} = c = claims(frame)

    Repo.put_org_id(org_id)
    Repo.put_user_id(user_id)
    Logger.metadata(mcp_user_id: user_id, mcp_org_id: org_id)
    :telemetry.execute([:estimate, :mcp, :tool_call], %{count: 1}, c)

    fun.(c)
  end

  @doc "with_scope for lookups: turns NoResultsError/CastError into {:error, :not_found}."
  def fetch(%Frame{} = frame, fun) when is_function(fun, 1) do
    {:ok, with_scope(frame, fun)}
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
    Ecto.Query.CastError -> {:error, :not_found}
  end
end
