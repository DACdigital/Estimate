defmodule EstimateWeb.OAuthMetadataController do
  use EstimateWeb, :controller

  alias EstimateWeb.MCPServer

  def authorization_server(conn, _params) do
    base = MCPServer.base_url()

    json(conn, %{
      issuer: base,
      authorization_endpoint: base <> "/oauth/authorize",
      token_endpoint: base <> "/oauth/token",
      registration_endpoint: base <> "/oauth/register",
      response_types_supported: ["code"],
      grant_types_supported: ["authorization_code", "refresh_token"],
      code_challenge_methods_supported: ["S256"],
      token_endpoint_auth_methods_supported: ["none"],
      scopes_supported: ["mcp:read", "offline_access"]
    })
  end

  def protected_resource(conn, _params) do
    json(conn, %{
      resource: MCPServer.mcp_url(),
      authorization_servers: [MCPServer.base_url()],
      scopes_supported: ["mcp:read"],
      bearer_methods_supported: ["header"]
    })
  end
end
