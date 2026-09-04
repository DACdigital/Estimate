defmodule Estimate.MCP.KeyValidator do
  @moduledoc """
  Anubis authorization validator backed by personal API keys
  (`mcp_api_keys`) and OAuth access tokens (`oauth_tokens`).

  Sets `aud` to the configured resource because the anubis auth layer
  audience-validates every claims map; we mint the claims ourselves, so
  the audience check is satisfied by construction.
  """

  @behaviour Anubis.Server.Authorization.Validator

  alias Estimate.MCP.OAuth.Scopes

  @impl true
  def validate_token(token, config) do
    case Estimate.MCP.verify_bearer(token) do
      {:ok, auth} ->
        {:ok,
         %{
           "sub" => auth.user_id,
           "org_id" => auth.organization_id,
           "role" => auth.role,
           "scope" => Map.get(auth, :scope, Scopes.read_only()),
           "aud" => config.resource
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
