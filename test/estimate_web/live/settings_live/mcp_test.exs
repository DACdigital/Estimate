defmodule EstimateWeb.SettingsLive.McpTest do
  use EstimateWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Estimate.AccountsFixtures

  alias Estimate.MCP
  alias Estimate.Organizations

  setup :register_and_log_in_org_owner

  defp mcp_path(org), do: ~p"/org/#{org.id}/settings/mcp"

  describe "admin toggle" do
    test "owner enables MCP (org default is disabled)", %{conn: conn, org: org} do
      refute org.mcp_enabled

      {:ok, lv, html} = live(conn, mcp_path(org))
      assert html =~ "MCP Server"

      lv |> element("button", "Enable") |> render_click()
      assert Estimate.Repo.reload!(org).mcp_enabled
    end

    test "member sees no toggle and cannot flip it", %{conn: _conn, org: org} do
      member = user_fixture()
      membership_fixture(member, org, "member")
      conn = log_in_user(build_conn(), member)

      {:ok, lv, html} = live(conn, mcp_path(org))
      refute html =~ "Enable"

      # Event forged directly must be rejected by require_admin.
      render_click(lv, "toggle_mcp", %{})
      refute Estimate.Repo.reload!(org).mcp_enabled
    end
  end

  describe "personal key" do
    setup %{org: org} do
      {:ok, org} = Organizations.update_mcp_settings(org, %{mcp_enabled: true})
      %{org: org}
    end

    test "generate shows plaintext once; remount shows only prefix", %{
      conn: conn,
      user: user,
      org: org
    } do
      {:ok, lv, _} = live(conn, mcp_path(org))

      html = lv |> element("button", "Generate API Key") |> render_click()
      assert [_, plaintext] = Regex.run(~r/(est_[A-Za-z0-9_-]{43})/, html)
      assert {:ok, _} = MCP.verify_api_key(plaintext)

      {:ok, _lv, remount_html} = live(conn, mcp_path(org))
      refute remount_html =~ plaintext
      assert remount_html =~ String.slice(plaintext, 0, 12)
      assert MCP.get_api_key(user.id, org.id)
    end

    test "regenerate invalidates the old key", %{conn: conn, org: org} do
      {:ok, lv, _} = live(conn, mcp_path(org))

      html1 = lv |> element("button", "Generate API Key") |> render_click()
      [_, key1] = Regex.run(~r/(est_[A-Za-z0-9_-]{43})/, html1)

      html2 = lv |> element("button", "Regenerate") |> render_click()
      [_, key2] = Regex.run(~r/(est_[A-Za-z0-9_-]{43})/, html2)

      assert key1 != key2
      assert {:error, :invalid_key} = MCP.verify_api_key(key1)
      assert {:ok, _} = MCP.verify_api_key(key2)
    end

    test "revoke deletes the key", %{conn: conn, user: user, org: org} do
      {:ok, lv, _} = live(conn, mcp_path(org))
      lv |> element("button", "Generate API Key") |> render_click()

      lv |> element("button", "Revoke") |> render_click()
      assert MCP.get_api_key(user.id, org.id) == nil
    end

    test "toggling MCP off clears the shown-once plaintext key", %{conn: conn, org: org} do
      {:ok, lv, _} = live(conn, mcp_path(org))

      html = lv |> element("button", "Generate API Key") |> render_click()
      assert [_, plaintext] = Regex.run(~r/(est_[A-Za-z0-9_-]{43})/, html)
      assert html =~ plaintext

      html = lv |> element("button[phx-click=toggle_mcp]") |> render_click()
      refute Estimate.Repo.reload!(org).mcp_enabled
      refute html =~ plaintext

      html = lv |> element("button[phx-click=toggle_mcp]") |> render_click()
      assert Estimate.Repo.reload!(org).mcp_enabled
      refute html =~ plaintext
      assert html =~ String.slice(plaintext, 0, 12)
    end

    test "disabled org: member sees notice, no generate button", %{org: org} do
      {:ok, _} = Organizations.update_mcp_settings(org, %{mcp_enabled: false})

      member = user_fixture()
      membership_fixture(member, org, "member")
      conn = log_in_user(build_conn(), member)

      {:ok, lv, html} = live(conn, mcp_path(org))
      assert html =~ "Ask an admin to enable it"
      refute html =~ "Generate API Key"
      # Scoped to the heading tag: the member notice paragraph itself contains
      # the substring "MCP server is disabled", so a plain html =~ check
      # would pass whether or not the admin-only block renders.
      refute has_element?(lv, "h2", "MCP server is disabled")
    end
  end

  describe "server-side mcp_enabled guard on key events" do
    test "forged generate_key on a disabled org creates no key row", %{
      conn: conn,
      user: user,
      org: org
    } do
      refute org.mcp_enabled
      {:ok, lv, _html} = live(conn, mcp_path(org))

      # Event forged directly (button isn't even rendered when disabled).
      render_click(lv, "generate_key", %{})

      assert MCP.get_api_key(user.id, org.id) == nil
    end

    test "forged revoke_key on a disabled org does not delete an existing key", %{
      conn: conn,
      user: user,
      org: org
    } do
      {:ok, org} = Organizations.update_mcp_settings(org, %{mcp_enabled: true})
      {:ok, lv, _html} = live(conn, mcp_path(org))
      lv |> element("button", "Generate API Key") |> render_click()
      assert MCP.get_api_key(user.id, org.id)

      {:ok, org} = Organizations.update_mcp_settings(org, %{mcp_enabled: false})

      # `current_organization` is read fresh only at mount time (OrgAuth on_mount),
      # so the already-connected `lv` above would still see a stale enabled=true
      # snapshot. Re-mount so the guard actually observes mcp_enabled: false.
      {:ok, lv2, _html2} = live(conn, mcp_path(org))

      render_click(lv2, "revoke_key", %{})

      assert MCP.get_api_key(user.id, org.id)
    end
  end
end
