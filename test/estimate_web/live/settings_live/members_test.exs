defmodule EstimateWeb.SettingsLive.MembersTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Estimate.AccountsFixtures

  alias Estimate.Organizations

  defp path_for(org_id), do: ~p"/org/#{org_id}/settings/members"

  defp assigns(lv), do: :sys.get_state(lv.pid).socket.assigns

  defp setup_org(_) do
    %{user: owner, organization: org} = user_with_organization_fixture()
    %{org: org, owner: owner}
  end

  # Create a fresh user with the given role in `org`; returns %{user:, membership:}.
  defp add_member(org, role, attrs \\ %{}) do
    user = user_fixture(attrs)
    %{user: user, membership: membership_fixture(user, org, role)}
  end

  describe "mount & render per role" do
    setup :setup_org

    test "owner sees admin cards and all three tabs", %{conn: conn, org: org, owner: owner} do
      {:ok, lv, html} = live(log_in_user(conn, owner), path_for(org.id))

      assert html =~ "Members"
      assert assigns(lv).is_admin == true
      assert assigns(lv).current_tab == :members
      # Admin-only cards (invite by email / invite code / join link) present:
      assert has_element?(lv, ~s(form[phx-submit="send_invite"]))
      assert has_element?(lv, "button", "Team Members")
      assert has_element?(lv, "button", "Pending Invitations")
      assert has_element?(lv, "button", "Join Requests")
    end

    test "admin sees admin cards", %{conn: conn, org: org} do
      %{user: admin} = add_member(org, "admin")
      {:ok, lv, _html} = live(log_in_user(conn, admin), path_for(org.id))

      assert assigns(lv).is_admin == true
      assert has_element?(lv, ~s(form[phx-submit="send_invite"]))
    end

    test "member does NOT see admin cards", %{conn: conn, org: org} do
      %{user: member} = add_member(org, "member")
      {:ok, lv, _html} = live(log_in_user(conn, member), path_for(org.id))

      assert assigns(lv).is_admin == false
      refute has_element?(lv, ~s(form[phx-submit="send_invite"]))
    end

    test "non-member is redirected to /organizations", %{conn: conn, org: org} do
      stranger = user_fixture()

      assert {:error, {:redirect, %{to: "/organizations"}}} =
               live(log_in_user(conn, stranger), path_for(org.id))
    end

    test "anonymous is redirected to log in", %{conn: conn, org: org} do
      assert {:error, {:redirect, %{to: path}}} = live(conn, path_for(org.id))
      assert path =~ "/users/log_in"
    end
  end

  describe "tabs" do
    setup :setup_org

    test "switch_tab moves between the three tabs; invalid tab is a no-op",
         %{conn: conn, org: org, owner: owner} do
      {:ok, lv, _html} = live(log_in_user(conn, owner), path_for(org.id))
      assert assigns(lv).current_tab == :members

      render_click(lv, "switch_tab", %{"tab" => "invites"})
      assert assigns(lv).current_tab == :invites

      render_click(lv, "switch_tab", %{"tab" => "requests"})
      assert assigns(lv).current_tab == :requests

      # invalid value hits the catch-all → unchanged
      render_click(lv, "switch_tab", %{"tab" => "bogus"})
      assert assigns(lv).current_tab == :requests
    end
  end

  describe "authorization gating (member pushing admin-only events)" do
    setup :setup_org

    setup %{conn: conn, org: org} do
      %{user: member} = add_member(org, "member")
      %{user: target} = add_member(org, "member")
      {:ok, lv, _html} = live(log_in_user(conn, member), path_for(org.id))
      %{lv: lv, target: target, org: org}
    end

    # Every require_admin-wrapped event, pushed by a member, flashes
    # "Not authorized" and mutates nothing. Push by name (member DOM lacks
    # the buttons). Payloads are shaped just enough to reach require_admin.
    test "wrapped events flash Not authorized for a member", %{lv: lv, target: target, org: org} do
      pushes = [
        {"send_invite", %{"invite" => %{"email" => "x@example.com", "role" => "member"}}},
        {"change_member_role", %{"id" => Ecto.UUID.generate(), "role" => "admin"}},
        {"confirm_remove_member", %{"id" => Ecto.UUID.generate()}},
        {"remove_member", %{}},
        {"reassign_all", %{"user_id" => target.id}},
        {"reassign_customer", %{"customer_id" => Ecto.UUID.generate(), "user_id" => target.id}},
        {"reassign_project", %{"project_id" => Ecto.UUID.generate(), "user_id" => target.id}},
        {"cancel_invite", %{}},
        {"generate_invite_code", %{"role" => "member"}},
        {"confirm_disable_2fa", %{"id" => target.id}},
        {"disable_user_2fa", %{}},
        {"copy_invite_code", %{"code" => "ABC"}},
        {"copy_join_link", %{}},
        {"copy_invite_link", %{"token" => "tok"}},
        {"approve_request", %{"id" => Ecto.UUID.generate()}},
        {"reject_request", %{"id" => Ecto.UUID.generate()}}
      ]

      for {event, payload} <- pushes do
        assert render_click(lv, event, payload) =~ "Not authorized",
               "expected #{event} to be admin-gated"
      end

      # Nothing changed: still 3 memberships (owner + member + target).
      assert length(Organizations.list_organization_members(org.id)) == 3
    end

    test "member CAN use the non-gated events", %{lv: lv} do
      # switch_tab / switch_reassign_tab / dismiss_* / cancel_* are open.
      render_click(lv, "switch_tab", %{"tab" => "invites"})
      assert assigns(lv).current_tab == :invites

      render_click(lv, "dismiss_generated_code", %{})
      assert assigns(lv).generated_code == nil

      render_click(lv, "cancel_remove_member", %{})
      assert assigns(lv).removing_member == nil
    end
  end
end
