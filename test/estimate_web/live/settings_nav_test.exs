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

        assert has_element?(
                 view,
                 ~s(#settings-rail a[href="/org/#{org.id}/settings#{page}"][data-phx-link="redirect"])
               ),
               "rail link for #{page} must live-navigate (no full reload / no animation replay)"
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

    test "rail carries the entry animation class and its replay-suppression hook", %{
      conn: conn,
      org: org
    } do
      {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/settings")

      assert has_element?(view, "#settings-rail.settings-rail-enter")

      # A live_redirect between settings LiveViews replaces the main container,
      # so the rail is re-created (fresh DOM) on every rail navigation — the
      # SettingsRail JS hook suppresses the entry animation for those swaps.
      # Without the hook the animation replays on every settings click.
      assert has_element?(view, ~s(#settings-rail[phx-hook="SettingsRail"]))
    end

    test "rail navigation between settings pages is a live navigate", %{conn: conn, org: org} do
      {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/settings")

      # A live-nav click never round-trips through the server as a plain HTTP
      # response — it exits with a live_redirect, which we then follow. If
      # sidebar_child_link/1 ever regresses to a bare `href` (no
      # data-phx-link="redirect"), this click instead returns
      # {:error, {:redirect, %{to: to}}} — a different tuple shape — and the
      # match below fails.
      assert {:error, {:live_redirect, %{to: to}}} =
               view
               |> element(~s(#settings-rail a[href="/org/#{org.id}/settings/mcp"]))
               |> render_click()

      {:ok, view, _html} = live(conn, to)

      assert has_element?(view, "#settings-rail")
    end
  end

  describe "global sidebar" do
    test "has a single Settings entry, no expanded settings links", %{conn: conn, org: org} do
      # Dashboard: rail is absent, so any settings child link found here would
      # be a leftover of the old expanded sidebar group.
      {:ok, view, _html} = live(conn, ~p"/org/#{org.id}")

      assert has_element?(view, ~s(#app-sidebar a[href="/org/#{org.id}/settings"]), "Settings")

      for page <- ["/members", "/currencies", "/ai", "/email", "/mcp"] do
        refute has_element?(view, ~s(#app-sidebar a[href="/org/#{org.id}/settings#{page}"])),
               "old sidebar link to settings#{page} still present"
      end
    end

    test "Settings entry is active on settings pages", %{conn: conn, org: org} do
      {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/settings/mcp")

      # sidebar_link active state renders bg-base-200 on the anchor
      assert has_element?(
               view,
               ~s(#app-sidebar a[href="/org/#{org.id}/settings"].bg-base-200),
               "Settings"
             )
    end

    test "sidebar user section renders account + logout", %{conn: conn, org: org, user: user} do
      {:ok, view, _html} = live(conn, ~p"/org/#{org.id}")

      assert has_element?(view, ~s(#app-sidebar a[href="/account"]))
      assert has_element?(view, ~s(#app-sidebar a[href="/users/log_out"]))
      assert view |> element("#app-sidebar") |> render() =~ user.email
    end
  end
end
