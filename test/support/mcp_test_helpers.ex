defmodule Estimate.MCPTestHelpers do
  @moduledoc """
  Shared MCP test plumbing: the tool-response JSON decoder used by the
  per-tool unit tests, and the anubis streamable-HTTP plug wiring used by
  the server-level auth/integration tests.
  """

  import Plug.Conn
  import Plug.Test

  alias Anubis.Server.Response
  alias Anubis.Server.Transport.StreamableHTTP

  @doc "Decodes an Anubis tool response's text content as JSON."
  def json_content(%Response{content: [%{"type" => "text", "text" => text}]}) do
    Jason.decode!(text)
  end

  @doc "The error text of an Anubis tool error response."
  def json_error(%Anubis.Server.Response{content: [%{"type" => "text", "text" => text}]}),
    do: text

  # Not a module attribute: `Plug.init/1`'s return defaults `subscriber_metadata`
  # to a function local to `StreamableHTTP.Plug` (`&default_subscriber_metadata/1`),
  # which Elixir cannot escape into a `@module_attribute` (only literals and
  # remote `&Mod.fun/arity` captures survive compile-time escaping). Computing
  # it in a function sidesteps that restriction entirely.
  def plug_opts, do: StreamableHTTP.Plug.init(server: EstimateWeb.MCPServer)

  @doc "POSTs a JSON-RPC body to the MCP streamable-HTTP endpoint with the given headers."
  def post_mcp(body, headers) do
    conn =
      conn(:post, "/", Jason.encode!(body))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json, text/event-stream")

    headers
    |> Enum.reduce(conn, fn {k, v}, c -> put_req_header(c, k, v) end)
    |> StreamableHTTP.Plug.call(plug_opts())
  end

  @doc "The standard MCP `initialize` request body."
  def init_body do
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
end
