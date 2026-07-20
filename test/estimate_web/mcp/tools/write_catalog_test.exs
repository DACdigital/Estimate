defmodule EstimateWeb.MCP.Tools.WriteCatalogTest do
  use Estimate.DataCase, async: false

  import Plug.Conn
  import Estimate.{AccountsFixtures, MCPFixtures, MCPTestHelpers}

  @write_tools ~w(create_customer update_customer create_project update_project
                  create_estimation update_estimation add_estimation_role update_estimation_role
                  add_epic update_epic add_task update_task set_task_effort)

  setup do
    start_supervised!(
      {EstimateWeb.MCPServer,
       transport: {:streamable_http, start: true},
       authorization: EstimateWeb.MCPServer.runtime_authorization()}
    )

    %{user: user, organization: org} = user_with_organization_fixture()
    {key, _k, org} = mcp_api_key_fixture(user, org)
    _ = enable_mcp_write(org)
    %{key: key, org: org, user: user}
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

  test "tools/list exposes all 13 write tools", %{key: key} do
    session_id = initialize_session(key)

    conn =
      post_mcp(
        %{"jsonrpc" => "2.0", "id" => 2, "method" => "tools/list", "params" => %{}},
        [{"authorization", "Bearer " <> key}, {"mcp-session-id", session_id}]
      )

    assert conn.status == 200

    names = tool_names(conn)
    for t <- @write_tools, do: assert(t in names, "missing tool #{t}")
  end

  # Extract tool names from the tools/list response body. Every request
  # response arrives as a single SSE chunk (`event: message\ndata: <json>\n\n`
  # — see Anubis.Server.Transport.StreamableHTTP.Plug), so decode the
  # `data:` line and pull out the tool names.
  defp tool_names(conn) do
    conn.resp_body
    |> String.split("\n", trim: true)
    |> Enum.flat_map(fn line ->
      line = String.replace_prefix(line, "data: ", "")

      case Jason.decode(line) do
        {:ok, %{"result" => %{"tools" => tools}}} -> Enum.map(tools, & &1["name"])
        _ -> []
      end
    end)
  end
end
