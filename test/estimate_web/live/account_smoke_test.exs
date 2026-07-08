defmodule EstimateWeb.AccountSmokeTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "account settings renders", %{conn: conn} do
    assert {:ok, _view, _html} = live(conn, ~p"/account")
  end

  test "totp setup renders", %{conn: conn} do
    assert {:ok, _view, _html} = live(conn, ~p"/account/two-factor/setup")
  end
end
