defmodule EstimateWeb.SettingsLive.LeaveOrgTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Estimate.{AccountsFixtures, PortfolioFixtures}
  alias Estimate.Organizations

  defp assigns(lv), do: :sys.get_state(lv.pid).socket.assigns

  setup do
    %{user: owner, organization: org} = user_with_organization_fixture()
    member = user_fixture()
    _ = membership_fixture(member, org, "member")
    %{owner: owner, org: org, member: member}
  end

  test "sole owner sees the transfer-first text and cannot leave", %{
    conn: conn,
    owner: owner,
    org: org
  } do
    {:ok, lv, html} = live(log_in_user(conn, owner), ~p"/org/#{org.id}/settings")
    assert html =~ "Transfer ownership to another member before leaving."
    refute html =~ ~s(phx-click="confirm_leave")
    render_click(lv, "confirm_leave", %{})
    html = render_click(lv, "leave_organization", %{})
    assert html =~ "Transfer ownership before leaving."
    assert Organizations.get_user_membership(owner.id, org.id)
  end

  test "member leaves and is redirected", %{conn: conn, member: member, org: org} do
    {:ok, lv, _} = live(log_in_user(conn, member), ~p"/org/#{org.id}/settings")
    render_click(lv, "confirm_leave", %{})
    assert assigns(lv).leaving == true

    assert {:error, {:live_redirect, %{to: "/organizations"}}} =
             render_click(lv, "leave_organization", %{})

    refute Organizations.get_user_membership(member.id, org.id)
  end

  test "sole project owner is refused", %{conn: conn, member: member, org: org} do
    _project = project_fixture(nil, member)
    {:ok, lv, _} = live(log_in_user(conn, member), ~p"/org/#{org.id}/settings")
    render_click(lv, "confirm_leave", %{})
    html = render_click(lv, "leave_organization", %{})
    assert html =~ "Transfer your projects before leaving."
    assert Organizations.get_user_membership(member.id, org.id)
  end
end
