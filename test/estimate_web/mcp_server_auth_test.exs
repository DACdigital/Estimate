defmodule EstimateWeb.MCPServerAuthTest do
  use Estimate.DataCase, async: false

  import Plug.Conn
  import Estimate.AccountsFixtures
  import Estimate.MCPFixtures
  import Estimate.MCPTestHelpers

  setup do
    start_supervised!(
      {EstimateWeb.MCPServer,
       transport: {:streamable_http, start: true},
       authorization: EstimateWeb.MCPServer.runtime_authorization()}
    )

    %{user: user, organization: org} = user_with_organization_fixture()
    {plaintext, _key, org} = mcp_api_key_fixture(user, org)
    %{user: user, org: org, key: plaintext}
  end

  test "initialize without key → 401" do
    assert post_mcp(init_body(), []).status == 401
  end

  test "initialize with bogus key → 401" do
    assert post_mcp(init_body(), [{"authorization", "Bearer est_bogus"}]).status == 401
  end

  test "initialize with valid key → 200 + session id", %{key: key} do
    conn = post_mcp(init_body(), [{"authorization", "Bearer " <> key}])
    assert conn.status == 200
    assert [_session_id] = get_resp_header(conn, "mcp-session-id")
  end

  test "org toggle off → 401 on next request", %{org: org, key: key} do
    assert post_mcp(init_body(), [{"authorization", "Bearer " <> key}]).status == 200

    {:ok, _} = Estimate.Organizations.update_mcp_settings(org, %{mcp_enabled: false})
    assert post_mcp(init_body(), [{"authorization", "Bearer " <> key}]).status == 401
  end

  test "401 advertises the resource metadata location" do
    conn = post_mcp(init_body(), [])
    assert conn.status == 401

    [www] = Plug.Conn.get_resp_header(conn, "www-authenticate")
    assert www =~ ~s(resource_metadata=")
    assert www =~ "/.well-known/oauth-protected-resource"

    # Discriminating: verify real runtime resource URL, not URN fallback
    runtime_host = URI.parse(EstimateWeb.MCPServer.base_url()).host
    assert www =~ runtime_host
    refute www =~ "urn:"
  end
end
