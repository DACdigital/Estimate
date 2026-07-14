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
      %{user: target, membership: target_m} = add_member(org, "member")
      {:ok, lv, _html} = live(log_in_user(conn, member), path_for(org.id))
      %{lv: lv, target: target, target_m: target_m, org: org}
    end

    # Every require_admin-wrapped event, pushed by a member, flashes
    # "Not authorized" and mutates nothing. Push by name (member DOM lacks
    # the buttons). Payloads are shaped just enough to reach require_admin.
    # change_member_role/confirm_remove_member/confirm_disable_2fa/reassign_*
    # use the real target so their UNGATED paths diverge from "Not authorized"
    # (Role updated / open modal / set assign / no-op) — i.e. removing the gate
    # makes the assertion fail, making this a genuine regression guard.
    test "wrapped events flash Not authorized for a member",
         %{lv: lv, target: target, target_m: target_m, org: org} do
      pushes = [
        {"send_invite", %{"invite" => %{"email" => "x@example.com", "role" => "member"}}},
        {"change_member_role", %{"id" => target_m.id, "role" => "admin"}},
        {"confirm_remove_member", %{"id" => target_m.id}},
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
        # lv:clear-flash isolates each iteration: put_flash merges by key and is
        # NOT auto-cleared, so a prior :error would bleed through and mask an
        # ungated event. Clearing first means the assertion reflects THIS event.
        render_click(lv, "lv:clear-flash", %{"key" => "error"})

        assert render_click(lv, event, payload) =~ "Not authorized",
               "expected #{event} to be admin-gated"
      end

      # Nothing changed: still 3 memberships (owner + member + target).
      assert length(Organizations.list_organization_members(org.id)) == 3
    end

    test "member CAN use the non-gated events", %{lv: lv} do
      # switch_tab, dismiss_generated_code and cancel_remove_member are NOT
      # require_admin-wrapped: a member is not blocked from them.
      render_click(lv, "switch_tab", %{"tab" => "invites"})
      assert assigns(lv).current_tab == :invites

      # clear before each refute so a leftover :error can't cause a false failure
      render_click(lv, "lv:clear-flash", %{"key" => "error"})
      refute render_click(lv, "dismiss_generated_code", %{}) =~ "Not authorized"

      render_click(lv, "lv:clear-flash", %{"key" => "error"})
      refute render_click(lv, "cancel_remove_member", %{}) =~ "Not authorized"
    end
  end

  describe "send_invite" do
    setup :setup_org

    test "creates an email invite (non-smtp org) and resets the form",
         %{conn: conn, org: org, owner: owner} do
      {:ok, lv, _html} = live(log_in_user(conn, owner), path_for(org.id))

      html =
        lv
        |> form(~s(form[phx-submit="send_invite"]), %{
          "invite" => %{"email" => "newbie@example.com", "role" => "member"}
        })
        |> render_submit()

      assert html =~ "Invite created — copy link to share"
      emails = Enum.map(Organizations.list_organization_invites(org.id), & &1.email)
      assert "newbie@example.com" in emails
      assert assigns(lv).invite_form.params["email"] == ""
    end

    test "rejects an invalid role before hitting the context",
         %{conn: conn, org: org, owner: owner} do
      {:ok, lv, _html} = live(log_in_user(conn, owner), path_for(org.id))

      html =
        render_click(lv, "send_invite", %{"invite" => %{"email" => "a@b.co", "role" => "owner"}})

      assert html =~ "Invalid role"
      assert Organizations.list_organization_invites(org.id) == []
    end

    test "flashes an error on a malformed email", %{conn: conn, org: org, owner: owner} do
      {:ok, lv, _html} = live(log_in_user(conn, owner), path_for(org.id))

      html =
        render_click(lv, "send_invite", %{"invite" => %{"email" => "nope", "role" => "member"}})

      assert html =~ "Could not create invitation"
      assert Organizations.list_organization_invites(org.id) == []
    end
  end

  describe "invite codes" do
    setup :setup_org

    test "generate_invite_code stores a code and lists it", %{conn: conn, org: org, owner: owner} do
      {:ok, lv, _html} = live(log_in_user(conn, owner), path_for(org.id))

      render_click(lv, "generate_invite_code", %{"role" => "member"})
      code = assigns(lv).generated_code
      assert is_binary(code) and String.length(code) == 8

      codes = Enum.map(Organizations.list_organization_invites(org.id), & &1.code)
      assert code in codes

      render_click(lv, "dismiss_generated_code", %{})
      assert assigns(lv).generated_code == nil
    end

    test "generate_invite_code rejects an invalid role", %{conn: conn, org: org, owner: owner} do
      {:ok, lv, _html} = live(log_in_user(conn, owner), path_for(org.id))
      html = render_click(lv, "generate_invite_code", %{"role" => "owner"})
      assert html =~ "Invalid role"
      assert assigns(lv).generated_code == nil
    end

    test "copy_invite_code pushes to clipboard with a flash", %{
      conn: conn,
      org: org,
      owner: owner
    } do
      {:ok, lv, _html} = live(log_in_user(conn, owner), path_for(org.id))
      html = render_click(lv, "copy_invite_code", %{"code" => "ZZZ12345"})
      assert_push_event(lv, "copy_to_clipboard", %{text: "ZZZ12345"})
      assert html =~ "Code copied to clipboard!"
    end
  end

  describe "copy join & invite links" do
    setup :setup_org

    test "copy_join_link pushes the org join url", %{conn: conn, org: org, owner: owner} do
      {:ok, lv, _html} = live(log_in_user(conn, owner), path_for(org.id))
      html = render_click(lv, "copy_join_link", %{})
      assert_push_event(lv, "copy_to_clipboard", %{text: text})
      assert text =~ "/organizations/#{org.id}/join"
      assert html =~ "Join link copied to clipboard!"
    end

    test "copy_invite_link pushes the invite url for a token",
         %{conn: conn, org: org, owner: owner} do
      {:ok, lv, _html} = live(log_in_user(conn, owner), path_for(org.id))
      html = render_click(lv, "copy_invite_link", %{"token" => "tok-abc"})
      assert_push_event(lv, "copy_to_clipboard", %{text: text})
      assert text =~ "/invites/tok-abc"
      assert html =~ "Link copied to clipboard!"
    end
  end

  describe "cancel invite" do
    setup :setup_org

    test "confirm → cancel deletes the invite; dismiss clears the modal state",
         %{conn: conn, org: org, owner: owner} do
      {:ok, invite} =
        Organizations.create_invite(
          org.id,
          %{email: "gone@example.com", role: "member"},
          owner.id
        )

      {:ok, lv, _html} = live(log_in_user(conn, owner), path_for(org.id))

      render_click(lv, "confirm_cancel_invite", %{"id" => invite.id})
      assert assigns(lv).canceling_invite.id == invite.id

      render_click(lv, "dismiss_cancel_invite", %{})
      assert assigns(lv).canceling_invite == nil

      # re-open and actually cancel
      render_click(lv, "confirm_cancel_invite", %{"id" => invite.id})
      html = render_click(lv, "cancel_invite", %{})
      assert html =~ "Invitation cancelled"
      assert assigns(lv).canceling_invite == nil
      refute invite.id in Enum.map(Organizations.list_organization_invites(org.id), & &1.id)
    end
  end

  describe "change_member_role" do
    setup :setup_org

    test "updates a plain member's role", %{conn: conn, org: org, owner: owner} do
      %{user: member, membership: m} = add_member(org, "member")
      {:ok, lv, _html} = live(log_in_user(conn, owner), path_for(org.id))

      html = render_click(lv, "change_member_role", %{"id" => m.id, "role" => "admin"})
      assert html =~ "Role updated"
      assert Organizations.get_user_membership(member.id, org.id).role == "admin"
    end

    test "refuses to change an owner's role", %{conn: conn, org: org, owner: owner} do
      owner_m = Organizations.get_user_membership(owner.id, org.id)
      %{user: admin} = add_member(org, "admin")
      {:ok, lv, _html} = live(log_in_user(conn, admin), path_for(org.id))

      html = render_click(lv, "change_member_role", %{"id" => owner_m.id, "role" => "member"})
      assert html =~ "Not authorized"
      assert Organizations.get_user_membership(owner.id, org.id).role == "owner"
    end

    test "refuses to change your own role", %{conn: conn, org: org} do
      %{user: admin, membership: am} = add_member(org, "admin")
      {:ok, lv, _html} = live(log_in_user(conn, admin), path_for(org.id))

      html = render_click(lv, "change_member_role", %{"id" => am.id, "role" => "member"})
      assert html =~ "Not authorized"
    end

    test "flashes Member not found for an unknown id", %{conn: conn, org: org, owner: owner} do
      {:ok, lv, _html} = live(log_in_user(conn, owner), path_for(org.id))

      html =
        render_click(lv, "change_member_role", %{"id" => Ecto.UUID.generate(), "role" => "admin"})

      assert html =~ "Member not found"
    end

    test "flashes Invalid role for a non-assignable role", %{conn: conn, org: org, owner: owner} do
      %{membership: m} = add_member(org, "member")
      {:ok, lv, _html} = live(log_in_user(conn, owner), path_for(org.id))
      html = render_click(lv, "change_member_role", %{"id" => m.id, "role" => "owner"})
      assert html =~ "Invalid role"
    end
  end

  describe "simple member removal (no sole-owned projects)" do
    setup :setup_org

    test "confirm opens the simple confirm modal", %{conn: conn, org: org, owner: owner} do
      %{membership: m} = add_member(org, "member")
      {:ok, lv, _html} = live(log_in_user(conn, owner), path_for(org.id))

      render_click(lv, "confirm_remove_member", %{"id" => m.id})
      assert assigns(lv).removing_member.id == m.id
      assert assigns(lv).sole_owned_projects == []
      assert has_element?(lv, "#remove-member-modal")
      refute has_element?(lv, "#reassign-modal")
    end

    test "remove deletes the membership and resets state", %{conn: conn, org: org, owner: owner} do
      %{user: member, membership: m} = add_member(org, "member")
      {:ok, lv, _html} = live(log_in_user(conn, owner), path_for(org.id))

      render_click(lv, "confirm_remove_member", %{"id" => m.id})
      html = render_click(lv, "remove_member", %{})

      assert html =~ "Member removed"
      assert assigns(lv).removing_member == nil
      refute member.id in Enum.map(Organizations.list_organization_members(org.id), & &1.user_id)
    end

    test "cancel resets removal state", %{conn: conn, org: org, owner: owner} do
      %{membership: m} = add_member(org, "member")
      {:ok, lv, _html} = live(log_in_user(conn, owner), path_for(org.id))

      render_click(lv, "confirm_remove_member", %{"id" => m.id})
      assert assigns(lv).removing_member.id == m.id
      render_click(lv, "cancel_remove_member", %{})
      assert assigns(lv).removing_member == nil
    end

    test "refuses to remove the owner or yourself", %{conn: conn, org: org, owner: owner} do
      owner_m = Organizations.get_user_membership(owner.id, org.id)
      %{user: admin, membership: am} = add_member(org, "admin")
      {:ok, lv, _html} = live(log_in_user(conn, admin), path_for(org.id))

      assert render_click(lv, "confirm_remove_member", %{"id" => owner_m.id}) =~ "Not authorized"
      assert render_click(lv, "confirm_remove_member", %{"id" => am.id}) =~ "Not authorized"
      assert assigns(lv).removing_member == nil
    end
  end
end
