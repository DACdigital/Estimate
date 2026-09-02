defmodule EstimateWeb.OAuthRateLimitTest do
  # async: false — temporarily lowers the shared oauth_ip limit
  use EstimateWeb.ConnCase, async: false

  setup do
    prev = Application.get_env(:estimate, Estimate.RateLimit)
    Application.put_env(:estimate, Estimate.RateLimit, Keyword.put(prev, :oauth_ip, 3))
    on_exit(fn -> Application.put_env(:estimate, Estimate.RateLimit, prev) end)
    # unique forwarded ip so other suites' hits on 127.0.0.1 don't interfere
    %{ip: "198.51.100.#{:rand.uniform(250)}"}
  end

  test "4th request from one ip within a minute gets 429", %{conn: conn, ip: ip} do
    post_reg = fn ->
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-forwarded-for", ip)
      |> post(~p"/oauth/register", Jason.encode!(%{client_name: "X", redirect_uris: ["https://claude.ai/cb"]}))
    end

    for _ <- 1..3, do: assert(post_reg.().status in [201, 400])
    conn = post_reg.()
    assert json_response(conn, 429) == %{"error" => "too_many_requests"}
    assert [retry] = get_resp_header(conn, "retry-after")
    assert String.to_integer(retry) >= 1
  end

  test "token endpoint shares the bucket", %{conn: conn, ip: ip} do
    for _ <- 1..3 do
      conn |> put_req_header("x-forwarded-for", ip) |> post(~p"/oauth/token", %{"grant_type" => "nope"})
    end

    conn = conn |> put_req_header("x-forwarded-for", ip) |> post(~p"/oauth/token", %{"grant_type" => "nope"})
    assert json_response(conn, 429)["error"] == "too_many_requests"
  end
end
