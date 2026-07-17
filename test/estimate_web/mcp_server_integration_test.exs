defmodule EstimateWeb.MCPServerIntegrationTest do
  use Estimate.DataCase, async: false

  import Plug.Conn
  import Estimate.AccountsFixtures
  import Estimate.CRMFixtures
  import Estimate.MCPFixtures
  import Estimate.MCPTestHelpers

  setup do
    start_supervised!(
      {EstimateWeb.MCPServer,
       transport: {:streamable_http, start: true},
       authorization: EstimateWeb.MCPServer.runtime_authorization()}
    )

    %{user: user, organization: org} = user_with_organization_fixture()
    customer = customer_fixture(org, %{"name" => "Acme Corp"})
    {key, _key_struct, org} = mcp_api_key_fixture(user, org)

    # Foreign org data that must never leak
    %{organization: other_org} = user_with_organization_fixture()
    foreign_customer = customer_fixture(other_org, %{"name" => "Foreign Inc"})

    %{key: key, org: org, customer: customer, foreign_customer: foreign_customer}
  end

  defp initialize_session(key) do
    conn = post_mcp(init_body(), [{"authorization", "Bearer " <> key}])

    assert conn.status == 200
    [session_id] = get_resp_header(conn, "mcp-session-id")

    post_mcp(
      %{"jsonrpc" => "2.0", "method" => "notifications/initialized"},
      [{"authorization", "Bearer " <> key}, {"mcp-session-id", session_id}]
    )

    session_id
  end

  defp call_tool(key, session_id, name, args, id \\ 2) do
    conn =
      post_mcp(
        %{
          "jsonrpc" => "2.0",
          "id" => id,
          "method" => "tools/call",
          "params" => %{"name" => name, "arguments" => args}
        },
        [{"authorization", "Bearer " <> key}, {"mcp-session-id", session_id}]
      )

    assert conn.status == 200
    conn.resp_body
  end

  test "tools/list exposes the 11-tool catalog", %{key: key} do
    session_id = initialize_session(key)

    conn =
      post_mcp(
        %{"jsonrpc" => "2.0", "id" => 2, "method" => "tools/list", "params" => %{}},
        [{"authorization", "Bearer " <> key}, {"mcp-session-id", session_id}]
      )

    assert conn.status == 200

    for tool <- ~w(list_customers get_customer list_projects get_project list_estimations
                   get_estimation list_templates get_template list_role_templates
                   list_currencies search) do
      assert conn.resp_body =~ ~s("name":"#{tool}")
    end
  end

  test "tools/call list_customers returns own org data over HTTP", %{key: key} do
    session_id = initialize_session(key)
    body = call_tool(key, session_id, "list_customers", %{})

    assert body =~ "Acme Corp"
    refute body =~ "Foreign Inc"
  end

  test "cross-org isolation: foreign customer id → not found", %{
    key: key,
    foreign_customer: foreign
  } do
    session_id = initialize_session(key)
    body = call_tool(key, session_id, "get_customer", %{"id" => foreign.id})

    assert body =~ "customer not found"
    refute body =~ "Foreign Inc"
  end

  test "kill switch: disabling org 401s mid-session", %{key: key, org: org} do
    session_id = initialize_session(key)

    {:ok, _} = Estimate.Organizations.update_mcp_settings(org, %{mcp_enabled: false})

    conn =
      post_mcp(
        %{"jsonrpc" => "2.0", "id" => 3, "method" => "tools/list", "params" => %{}},
        [{"authorization", "Bearer " <> key}, {"mcp-session-id", session_id}]
      )

    assert conn.status == 401
  end
end
