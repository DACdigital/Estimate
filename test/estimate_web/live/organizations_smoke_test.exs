defmodule EstimateWeb.OrganizationsSmokeTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "organizations index renders", %{conn: conn} do
    assert {:ok, _view, _html} = live(conn, ~p"/organizations")
  end

  test "new organization renders", %{conn: conn} do
    assert {:ok, _view, _html} = live(conn, ~p"/organizations/new")
  end
end
