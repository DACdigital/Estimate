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

    test "disabled org: member sees notice, no generate button", %{conn: conn, org: org} do
      {:ok, _} = Organizations.update_mcp_settings(org, %{mcp_enabled: false})

      {:ok, _lv, html} = live(conn, mcp_path(org))
      assert html =~ "disabled"
      refute html =~ "Generate API Key"
    end
  end
end
