defmodule EstimateWeb.ClientIPTest do
  # Config is process-global (Application env); this suite mutates
  # `trusted_proxy_hops` per test, so it cannot run concurrently with itself.
  use ExUnit.Case, async: false

  import Plug.Test
  alias EstimateWeb.ClientIP

  setup do
    original = Application.get_env(:estimate, ClientIP, [])
    on_exit(fn -> Application.put_env(:estimate, ClientIP, original) end)
    :ok
  end

  defp put_hops(n), do: Application.put_env(:estimate, ClientIP, trusted_proxy_hops: n)

  defp conn_with_header(header) do
    conn(:get, "/") |> Plug.Conn.put_req_header("x-forwarded-for", header)
  end

  test "uses remote_ip when no forwarded header" do
    conn = conn(:get, "/")
    assert ClientIP.get(conn) == "127.0.0.1"
  end

  test "hops 1 (the config/test.exs default) takes the last hop, the one the trusted proxy appended" do
    put_hops(1)
    assert ClientIP.get(conn_with_header("203.0.113.7, 10.0.0.1")) == "10.0.0.1"
  end

  test "hops 2 takes the 2nd-from-last entry" do
    put_hops(2)
    assert ClientIP.get(conn_with_header("203.0.113.7, 10.0.0.1")) == "203.0.113.7"
  end

  test "hops 3 with only two entries falls back to remote_ip" do
    put_hops(3)
    assert ClientIP.get(conn_with_header("203.0.113.7, 10.0.0.1")) == "127.0.0.1"
  end

  test "hops 0 always uses remote_ip, ignoring the header" do
    put_hops(0)
    assert ClientIP.get(conn_with_header("203.0.113.7, 10.0.0.1")) == "127.0.0.1"
  end
end
