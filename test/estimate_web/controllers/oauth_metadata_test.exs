defmodule EstimateWeb.OAuthMetadataTest do
  use EstimateWeb.ConnCase, async: true

  test "authorization server metadata advertises the full contract", %{conn: conn} do
    body = conn |> get(~p"/.well-known/oauth-authorization-server") |> json_response(200)

    base = EstimateWeb.MCPServer.base_url()
    assert body["issuer"] == base
    assert body["authorization_endpoint"] == base <> "/oauth/authorize"
    assert body["token_endpoint"] == base <> "/oauth/token"
    assert body["registration_endpoint"] == base <> "/oauth/register"
    assert body["response_types_supported"] == ["code"]
    assert body["grant_types_supported"] == ["authorization_code", "refresh_token"]
    assert body["code_challenge_methods_supported"] == ["S256"]
    assert body["token_endpoint_auth_methods_supported"] == ["none"]
    assert body["scopes_supported"] == ["mcp:read", "mcp:write", "offline_access"]
  end

  test "protected resource metadata matches the MCP URL exactly on both paths", %{conn: conn} do
    for path <- [
          "/.well-known/oauth-protected-resource",
          "/.well-known/oauth-protected-resource/mcp"
        ] do
      body = conn |> get(path) |> json_response(200)
      assert body["resource"] == EstimateWeb.MCPServer.mcp_url()
      assert body["authorization_servers"] == [EstimateWeb.MCPServer.base_url()]
      assert body["scopes_supported"] == ["mcp:read", "mcp:write"]
      assert body["bearer_methods_supported"] == ["header"]
    end
  end
end
