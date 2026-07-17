defmodule EstimateWeb.MCPServerIntegrationTest do
  use Estimate.DataCase, async: false

  import Plug.Conn
  import Plug.Test
  import Estimate.AccountsFixtures
  import Estimate.CRMFixtures
  import Estimate.MCPFixtures

  alias Anubis.Server.Transport.StreamableHTTP

  # Not a module attribute: `Plug.init/1`'s return defaults `subscriber_metadata`
  # to a function local to `StreamableHTTP.Plug` (`&default_subscriber_metadata/1`),
  # which Elixir cannot escape into a `@module_attribute` (only literals and
  # remote `&Mod.fun/arity` captures survive compile-time escaping). Computing
  # it in a function sidesteps that restriction entirely.
  defp plug_opts, do: StreamableHTTP.Plug.init(server: EstimateWeb.MCPServer)

  setup do
    start_supervised!({EstimateWeb.MCPServer, transport: {:streamable_http, start: true}})

    %{user: user, organization: org} = user_with_organization_fixture()
    customer = customer_fixture(org, %{"name" => "Acme Corp"})
    {key, _} = mcp_api_key_fixture(user, org)

    # Foreign org data that must never leak
    %{organization: other_org} = user_with_organization_fixture()
    foreign_customer = customer_fixture(other_org, %{"name" => "Foreign Inc"})

    %{key: key, org: org, customer: customer, foreign_customer: foreign_customer}
  end

  defp post_mcp(body, headers) do
    conn =
      conn(:post, "/", Jason.encode!(body))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json, text/event-stream")

    headers
    |> Enum.reduce(conn, fn {k, v}, c -> put_req_header(c, k, v) end)
    |> StreamableHTTP.Plug.call(plug_opts())
  end

  defp initialize_session(key) do
    conn =
      post_mcp(
        %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "initialize",
          "params" => %{
            "protocolVersion" => "2025-06-18",
            "clientInfo" => %{"name" => "test", "version" => "1.0.0"},
            "capabilities" => %{}
          }
        },
        [{"authorization", "Bearer " <> key}]
      )

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
      assert conn.resp_body =~ ~s("#{tool}")
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

    # `org` is stale in-memory (mcp_enabled: false, its value at creation) —
    # `mcp_api_key_fixture/2` enabled MCP on its own unreturned copy. Reload
    # so the changeset diffs against real current state (see the identical
    # note in mcp_server_auth_test.exs); otherwise `cast/3` sees `false -> false`
    # and never issues the UPDATE.
    org = Estimate.Repo.reload!(org)
    {:ok, _} = Estimate.Organizations.update_mcp_settings(org, %{mcp_enabled: false})

    conn =
      post_mcp(
        %{"jsonrpc" => "2.0", "id" => 3, "method" => "tools/list", "params" => %{}},
        [{"authorization", "Bearer " <> key}, {"mcp-session-id", session_id}]
      )

    assert conn.status == 401
  end
end
