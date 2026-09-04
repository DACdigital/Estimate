defmodule EstimateWeb.LoginThrottleTest do
  @moduledoc """
  Split out from user_session_controller_test.exs: the throttling test
  shares Estimate.RateLimit's ETS-backed :login_email bucket with every
  other async test that logs in, so it needs its own async: false module
  with a lowered, test-local limit rather than racing the real default (10)
  against unrelated concurrent logins.
  """
  use EstimateWeb.ConnCase, async: false

  import Estimate.AccountsFixtures

  @password valid_user_password()

  setup do
    prev = Application.get_env(:estimate, Estimate.RateLimit, [])
    Application.put_env(:estimate, Estimate.RateLimit, Keyword.put(prev, :login_email, 3))

    on_exit(fn ->
      Application.put_env(:estimate, Estimate.RateLimit, prev)
    end)

    :ok
  end

  test "4th attempt for the same email within the window is refused", %{conn: conn} do
    user = user_fixture()
    params = %{"user" => %{"email" => user.email, "password" => "wrong"}}
    for _ <- 1..3, do: post(build_conn(), ~p"/users/log_in", params)

    conn =
      post(conn, ~p"/users/log_in", %{
        "user" => %{"email" => user.email, "password" => @password}
      })

    refute get_session(conn, :user_token)
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Too many attempts"
    assert redirected_to(conn) == ~p"/users/log_in"
  end
end
