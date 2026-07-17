defmodule Estimate.MCP.KeyValidator do
  @moduledoc """
  Anubis authorization validator backed by personal API keys
  (`mcp_api_keys`) and OAuth access tokens (`oauth_tokens`).

  Sets `aud` to the configured resource because the anubis auth layer
  audience-validates every claims map; we mint the claims ourselves, so
  the audience check is satisfied by construction.
  """

  @behaviour Anubis.Server.Authorization.Validator

  @impl true
  def validate_token(token, config) do
    case Estimate.MCP.verify_bearer(token) do
      {:ok, %{user_id: user_id, organization_id: org_id, role: role}} ->
        {:ok, %{"sub" => user_id, "org_id" => org_id, "role" => role, "aud" => config.resource}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
