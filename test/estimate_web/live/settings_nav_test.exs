defmodule EstimateWeb.SettingsNavTest do
  use EstimateWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Estimate.AccountsFixtures

  setup :register_and_log_in_org_owner

  defp rail_link(org, page), do: ~s(#settings-rail a[href="/org/#{org.id}/settings#{page}"])

  describe "settings rail" do
    test "admin sees both groups with all 7 items", %{conn: conn, org: org} do
      {:ok, view, html} = live(conn, ~p"/org/#{org.id}/settings")

      assert has_element?(view, "#settings-rail")
      assert html =~ "Workspace"
      assert html =~ "Integrations"

      for page <- ["", "/members", "/currencies", "/trash", "/ai", "/email", "/mcp"] do
        assert has_element?(view, rail_link(org, page)), "missing rail link for #{page}"
      end
    end

    test "member rail hides Trash, AI and Email", %{conn: _conn, org: org} do
      member = user_fixture()
      membership_fixture(member, org, "member")
      conn = log_in_user(build_conn(), member)

      {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/settings")

      assert has_element?(view, "#settings-rail")

      for page <- ["", "/members", "/currencies", "/mcp"] do
        assert has_element?(view, rail_link(org, page)), "missing rail link for #{page}"
      end

      for page <- ["/trash", "/ai", "/email"] do
        refute has_element?(view, rail_link(org, page)), "member must not see #{page}"
      end
    end

    test "rail is absent outside settings", %{conn: conn, org: org} do
      {:ok, view, _html} = live(conn, ~p"/org/#{org.id}")

      refute has_element?(view, "#settings-rail")
    end

    test "trash page renders the rail with trash active", %{conn: conn, org: org} do
      {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/settings/trash")

      assert has_element?(view, "#settings-rail")
      # active styling comes from sidebar_child_link's active class (font-medium)
      assert has_element?(view, rail_link(org, "/trash") <> ".font-medium")
    end

    test "rail carries the entry animation class", %{conn: conn, org: org} do
      {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/settings")

      assert has_element?(view, "#settings-rail.settings-rail-enter")
    end
  end
end
