defmodule EstimateWeb.AuthorizationSmokeTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "anonymous user is redirected from an org route to log in", %{conn: conn} do
    %{organization: org} = Estimate.AccountsFixtures.user_with_organization_fixture()

    assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/org/#{org.id}")
    assert to =~ "/users/log_in"
  end

  test "anonymous user is redirected from account to log in", %{conn: conn} do
    assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/account")
    assert to =~ "/users/log_in"
  end

  test "a logged-in non-member cannot load another org's dashboard", %{conn: conn} do
    %{organization: other_org} = Estimate.AccountsFixtures.user_with_organization_fixture()
    outsider = Estimate.AccountsFixtures.user_fixture()
    conn = log_in_user(conn, outsider)

    assert {:error, {:redirect, %{to: _to}}} = live(conn, ~p"/org/#{other_org.id}")
  end
end
