defmodule EstimateWeb.MCPServerAuthTest do
  use Estimate.DataCase, async: false

  import Plug.Conn
  import Plug.Test
  import Estimate.AccountsFixtures
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
    {plaintext, _} = mcp_api_key_fixture(user, org)
    %{user: user, org: org, key: plaintext}
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

  defp init_body do
    %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "initialize",
      "params" => %{
        "protocolVersion" => "2025-06-18",
        "clientInfo" => %{"name" => "test", "version" => "1.0.0"},
        "capabilities" => %{}
      }
    }
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

    # `org` is stale in-memory (mcp_enabled: false, its value at creation) —
    # `mcp_api_key_fixture/2` enabled MCP on its own unreturned copy. Reload
    # so the changeset diffs against real current state (see the identical
    # note in key_validator_test.exs); otherwise `cast/3` sees `false -> false`
    # and never issues the UPDATE.
    org = Estimate.Repo.reload!(org)
    {:ok, _} = Estimate.Organizations.update_mcp_settings(org, %{mcp_enabled: false})
    assert post_mcp(init_body(), [{"authorization", "Bearer " <> key}]).status == 401
  end
end
