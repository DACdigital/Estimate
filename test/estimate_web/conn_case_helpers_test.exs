defmodule EstimateWeb.ConnCaseHelpersTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "register_and_log_in_org_owner/1" do
    setup :register_and_log_in_org_owner

    test "yields a conn that can load an authenticated org page", %{conn: conn, org: org} do
      assert {:ok, _view, _html} = live(conn, ~p"/org/#{org.id}")
    end

    test "provides user and org in context", %{user: user, org: org} do
      assert user.id
      assert org.id
    end
  end

  describe "register_and_log_in_user/1" do
    setup :register_and_log_in_user

    test "yields a conn that can load the organizations index", %{conn: conn} do
      assert {:ok, _view, _html} = live(conn, ~p"/organizations")
    end
  end
end
