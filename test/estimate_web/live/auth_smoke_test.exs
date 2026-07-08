defmodule EstimateWeb.AuthSmokeTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "registration renders", %{conn: conn} do
    assert {:ok, _view, _html} = live(conn, ~p"/users/register")
  end

  test "login renders", %{conn: conn} do
    assert {:ok, _view, _html} = live(conn, ~p"/users/log_in")
  end

  test "forgot password renders", %{conn: conn} do
    assert {:ok, _view, _html} = live(conn, ~p"/users/reset_password")
  end
end
