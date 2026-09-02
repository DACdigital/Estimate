defmodule EstimateWeb.ClientIPTest do
  use ExUnit.Case, async: true
  import Plug.Test
  alias EstimateWeb.ClientIP

  test "uses remote_ip when no forwarded header" do
    conn = conn(:get, "/")
    assert ClientIP.get(conn) == "127.0.0.1"
  end

  test "uses first x-forwarded-for hop" do
    conn = conn(:get, "/") |> Plug.Conn.put_req_header("x-forwarded-for", "203.0.113.7, 10.0.0.1")
    assert ClientIP.get(conn) == "203.0.113.7"
  end
end
