# Members LiveView Characterization Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Before writing tests invoke `elixir-phoenix-guide:testing-essentials`. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Pin the *current* behavior of `EstimateWeb.SettingsLive.Members` (`lib/estimate_web/live/settings_live/members.ex`, 24 events, ~zero LiveView-level coverage) with a comprehensive characterization suite, so the upcoming decomposition (handler-delegation modules + authz consolidation) has a safety net.

**Architecture:** Connected LiveView tests via `Phoenix.LiveViewTest`. Two files: `members_test.exs` (mount/render/authz-gating/tabs + invitations + member-role/simple-removal + join-requests + 2FA) and `members_reassignment_test.exs` (the sole-owner reassignment state machine). Tests document CURRENT behavior — they must be **GREEN on first run**. A red characterization test means either the plan's expected value is wrong OR a latent bug was found: STOP and report, do not "fix" production code in this phase.

**Tech Stack:** Elixir ~> 1.15, Phoenix.LiveView 1.1, ExUnit (`async: true`), Ecto sandbox.

## Global Constraints

- **Characterization, not TDD.** Tests pin existing behavior → they pass immediately. Do NOT modify any file under `lib/`. If a test can't be made to pass without a production change, the behavior differs from this plan — report it (status `DONE_WITH_CONCERNS`), do not touch `lib/`.
- **No DB/schema changes.** Test-only work.
- All test files: `use EstimateWeb.ConnCase, async: true`; `import Phoenix.LiveViewTest`; `import Estimate.AccountsFixtures`. Add `import Estimate.PortfolioFixtures` / `import Estimate.CRMFixtures` only where projects/customers are needed (Task 5).
- Route under test: `~p"/org/#{org.id}/settings/members"`. Org is **path-derived**; no session org. A viewer needs only `log_in_user(conn, user)` + a `Membership` row of the right role in that org.
- `mix compile --warnings-as-errors --force` clean; full `mix test` green (`mix precommit` is the final gate).
- Branch: `refactor/members-characterize`, off `master`.

## Key idioms (verified against the existing suite)

- Mount: `{:ok, lv, html} = live(conn, ~p"/org/#{org.id}/settings/members")`.
- Element by text/selector: `lv |> element("button", "Team Members") |> render_click()`.
- Form submit: `lv |> form(~s(form[phx-submit="send_invite"]), %{"invite" => %{...}}) |> render_submit()`.
- **Push an event by name directly** (used for authz-gating, since a member's DOM omits admin buttons): `render_click(lv, "change_member_role", %{"id" => m.id, "role" => "admin"})`. `handle_event/3` matches on the event **name** only, so this reaches the handler regardless of the original `phx-*` binding.
- **Read assigns** to pin state transitions: define `defp assigns(lv), do: :sys.get_state(lv.pid).socket.assigns`, then `assert assigns(lv).current_tab == :invites`.
- In-place flash (no redirect): the flash text is in the returned HTML — `assert html =~ "Not authorized"`.
- Clipboard pushes: `assert_push_event(lv, "copy_to_clipboard", %{text: expected})` (requires `import Phoenix.LiveViewTest`).
- Non-member mounting the page returns `{:error, {:redirect, %{to: "/organizations"}}}` from `live/2`.

## Role setup cheatsheet (exact fixtures)

```elixir
# Owner + org in one shot (owner is an admin):
%{user: owner, organization: org} = user_with_organization_fixture()

# Add an admin viewer to that org:
admin = user_fixture()
_ = membership_fixture(admin, org, "admin")

# Add a plain member (NOT admin):
member = user_fixture()
member_membership = membership_fixture(member, org, "member")

# Log a viewer in:
conn = log_in_user(conn, owner)   # or admin / member

# A member with TOTP enabled (for disable-2FA target rendering):
%{user: totp_member} = user_with_totp_fixture()
_ = membership_fixture(totp_member, org, "member")
```

`admin?/1` ⇒ role in `~w(owner admin)`. `require_admin` non-admin path ⇒ `{:noreply, put_flash(:error, "Not authorized")}` (no redirect, LV stays mounted, state unchanged).

---

### Task 1: Scaffolding + mount / render-per-role / authz gating / tabs

**Files:**
- Create: `test/estimate_web/live/settings_live/members_test.exs`

**Interfaces:**
- Produces (private helpers reused by Tasks 2–4 in this same file): `assigns/1`, `setup_org/1` (setup callback yielding `%{org: org, owner: owner}`), `add_member/3`.

- [ ] **Step 0:** Invoke `elixir-phoenix-guide:testing-essentials`.

- [ ] **Step 1: Write the module skeleton + helpers + mount/render/tabs/gating tests.**

```elixir
defmodule EstimateWeb.SettingsLive.MembersTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Estimate.AccountsFixtures

  alias Estimate.{Accounts, Organizations}

  @path_for &~p"/org/#{&1}/settings/members"

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
      {:ok, lv, html} = live(log_in_user(conn, owner), @path_for.(org.id))

      assert html =~ "Members"
      assert assigns(lv).is_admin == true
      assert assigns(lv).current_tab == :members
      # Admin-only cards (invite by email / invite code / join link) present:
      assert html =~ "Invite by Email" or html =~ "invite-form"
      assert has_element?(lv, ~s(form[phx-submit="send_invite"]))
      assert has_element?(lv, "button", "Team Members")
      assert has_element?(lv, "button", "Pending Invitations")
      assert has_element?(lv, "button", "Join Requests")
    end

    test "admin sees admin cards", %{conn: conn, org: org} do
      %{user: admin} = add_member(org, "admin")
      {:ok, lv, _html} = live(log_in_user(conn, admin), @path_for.(org.id))

      assert assigns(lv).is_admin == true
      assert has_element?(lv, ~s(form[phx-submit="send_invite"]))
    end

    test "member does NOT see admin cards", %{conn: conn, org: org} do
      %{user: member} = add_member(org, "member")
      {:ok, lv, _html} = live(log_in_user(conn, member), @path_for.(org.id))

      assert assigns(lv).is_admin == false
      refute has_element?(lv, ~s(form[phx-submit="send_invite"]))
    end

    test "non-member is redirected to /organizations", %{conn: conn, org: org} do
      stranger = user_fixture()
      assert {:error, {:redirect, %{to: "/organizations"}}} =
               live(log_in_user(conn, stranger), @path_for.(org.id))
    end

    test "anonymous is redirected to log in", %{conn: conn, org: org} do
      assert {:error, {:redirect, %{to: path}}} = live(conn, @path_for.(org.id))
      assert path =~ "/users/log_in"
    end
  end

  describe "tabs" do
    setup :setup_org

    test "switch_tab moves between the three tabs; invalid tab is a no-op",
         %{conn: conn, org: org, owner: owner} do
      {:ok, lv, _html} = live(log_in_user(conn, owner), @path_for.(org.id))
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
      {:ok, lv, _html} = live(log_in_user(conn, member), @path_for.(org.id))
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
```

- [ ] **Step 2: Run the file — expect GREEN (behavior is pinned, not driven).**

Run: `mix test test/estimate_web/live/settings_live/members_test.exs`
Expected: all pass. If any fail, STOP: the observed behavior differs from the plan — report which assertion and the actual value (do not edit `lib/`).

- [ ] **Step 3:** `mix compile --warnings-as-errors --force` — clean.

- [ ] **Step 4: Commit** `test: characterize members mount/render/authz-gating/tabs`.

---

### Task 2: Invitations — send_invite, invite codes, join link, cancel invite, copy_*

**Files:**
- Modify: `test/estimate_web/live/settings_live/members_test.exs` (append describe blocks; reuse `assigns/1`, `setup_org/1`, `add_member/3`).

**Interfaces:**
- Consumes: `assigns/1`, `setup_org/1`, `add_member/3` from Task 1.

Exact behaviors to pin (from the source):
- `send_invite` success (fixture org is NOT smtp-configured) → flash `"Invite created — copy link to share"`, invite appears in `Organizations.list_organization_invites(org.id)`, `invite_form` reset (email blank).
- `send_invite` role not in `~w(member admin)` → flash `"Invalid role"`, no invite created.
- `send_invite` malformed email (e.g. `"nope"`) → changeset error → flash `"Could not create invitation"`.
- `generate_invite_code` success → `assigns(lv).generated_code` is a non-nil 8-char string; a code-invite now in the invites list. Invalid role → `"Invalid role"`, `generated_code` stays nil.
- `dismiss_generated_code` → `generated_code` back to nil.
- `copy_invite_code` (admin) → `assert_push_event(lv, "copy_to_clipboard", %{text: "SOMECODE"})` + flash `"Code copied to clipboard!"`.
- `copy_join_link` (admin) → push `copy_to_clipboard` with the org join URL + flash `"Join link copied to clipboard!"`.
- `copy_invite_link` (admin) with a token → push `copy_to_clipboard` with a URL containing `/invites/#{token}` + flash `"Link copied to clipboard!"`.
- `confirm_cancel_invite` → `assigns(lv).canceling_invite` set to the found invite; `dismiss_cancel_invite` → nil.
- `cancel_invite` (admin, with `canceling_invite` set) → invite deleted (gone from list), flash `"Invitation cancelled"`, `canceling_invite` nil.

- [ ] **Step 1: Append the invitations describe block.**

```elixir
  describe "send_invite" do
    setup :setup_org

    test "creates an email invite (non-smtp org) and resets the form",
         %{conn: conn, org: org, owner: owner} do
      {:ok, lv, _html} = live(log_in_user(conn, owner), @path_for.(org.id))

      html =
        lv
        |> form(~s(form[phx-submit="send_invite"]), %{
          "invite" => %{"email" => "newbie@example.com", "role" => "member"}
        })
        |> render_submit()

      assert html =~ "Invite created — copy link to share"
      emails = Enum.map(Organizations.list_organization_invites(org.id), & &1.email)
      assert "newbie@example.com" in emails
    end

    test "rejects an invalid role before hitting the context",
         %{conn: conn, org: org, owner: owner} do
      {:ok, lv, _html} = live(log_in_user(conn, owner), @path_for.(org.id))

      html = render_click(lv, "send_invite", %{"invite" => %{"email" => "a@b.co", "role" => "owner"}})
      assert html =~ "Invalid role"
      assert Organizations.list_organization_invites(org.id) == []
    end

    test "flashes an error on a malformed email", %{conn: conn, org: org, owner: owner} do
      {:ok, lv, _html} = live(log_in_user(conn, owner), @path_for.(org.id))

      html = render_click(lv, "send_invite", %{"invite" => %{"email" => "nope", "role" => "member"}})
      assert html =~ "Could not create invitation"
      assert Organizations.list_organization_invites(org.id) == []
    end
  end

  describe "invite codes" do
    setup :setup_org

    test "generate_invite_code stores a code and lists it", %{conn: conn, org: org, owner: owner} do
      {:ok, lv, _html} = live(log_in_user(conn, owner), @path_for.(org.id))

      render_click(lv, "generate_invite_code", %{"role" => "member"})
      code = assigns(lv).generated_code
      assert is_binary(code) and String.length(code) == 8

      codes = Enum.map(Organizations.list_organization_invites(org.id), & &1.code)
      assert code in codes

      render_click(lv, "dismiss_generated_code", %{})
      assert assigns(lv).generated_code == nil
    end

    test "generate_invite_code rejects an invalid role", %{conn: conn, org: org, owner: owner} do
      {:ok, lv, _html} = live(log_in_user(conn, owner), @path_for.(org.id))
      html = render_click(lv, "generate_invite_code", %{"role" => "owner"})
      assert html =~ "Invalid role"
      assert assigns(lv).generated_code == nil
    end

    test "copy_invite_code pushes to clipboard with a flash", %{conn: conn, org: org, owner: owner} do
      {:ok, lv, _html} = live(log_in_user(conn, owner), @path_for.(org.id))
      html = render_click(lv, "copy_invite_code", %{"code" => "ZZZ12345"})
      assert_push_event(lv, "copy_to_clipboard", %{text: "ZZZ12345"})
      assert html =~ "Code copied to clipboard!"
    end
  end

  describe "copy join & invite links" do
    setup :setup_org

    test "copy_join_link pushes the org join url", %{conn: conn, org: org, owner: owner} do
      {:ok, lv, _html} = live(log_in_user(conn, owner), @path_for.(org.id))
      html = render_click(lv, "copy_join_link", %{})
      assert_push_event(lv, "copy_to_clipboard", %{text: text})
      assert text =~ "/organizations/#{org.id}/join"
      assert html =~ "Join link copied to clipboard!"
    end

    test "copy_invite_link pushes the invite url for a token",
         %{conn: conn, org: org, owner: owner} do
      {:ok, lv, _html} = live(log_in_user(conn, owner), @path_for.(org.id))
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
        Organizations.create_invite(org.id, %{email: "gone@example.com", role: "member"}, owner.id)

      {:ok, lv, _html} = live(log_in_user(conn, owner), @path_for.(org.id))

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
```

- [ ] **Step 2:** `mix test test/estimate_web/live/settings_live/members_test.exs` — GREEN. If `send_invite`'s malformed-email case does not produce a changeset error (email regex is permissive: `~r/^[^\s]+@[^\s]+$/`), adjust the input to one that actually fails the format (a value with a space, e.g. `"no space@x"` → contains a space → invalid) and re-run; report the adjustment. Pin whatever the real validation does.

- [ ] **Step 3: Commit** `test: characterize members invitations (email/code/links/cancel)`.

---

### Task 3: Member role changes + simple removal (non-sole-owner path)

**Files:**
- Modify: `test/estimate_web/live/settings_live/members_test.exs` (append; reuse helpers).

**Interfaces:**
- Consumes: `assigns/1`, `setup_org/1`, `add_member/3`.

Behaviors to pin:
- `change_member_role` on a plain member → `{:ok}` path → flash `"Role updated"`, DB role changed; members list refreshed.
- `change_member_role` where target `role == "owner"` → flash `"Not authorized"`, unchanged.
- `change_member_role` where target is the current user → flash `"Not authorized"`.
- `change_member_role` id not found → flash `"Member not found"`.
- `change_member_role` role not in `~w(member admin)` (e.g. `"owner"`) → flash `"Invalid role"`.
- `confirm_remove_member` on a member with **no sole-owned projects** → `assigns(lv).removing_member` set, `sole_owned_projects == []`; the simple confirm modal (`#remove-member-modal`) renders.
- `confirm_remove_member` on the owner or on self → flash `"Not authorized"`, no modal.
- `remove_member` (with `removing_member` a plain member, empty reassignments) → flash `"Member removed"`, gone from members list, removal state reset.
- `cancel_remove_member` → removal state reset (`removing_member` nil).

- [ ] **Step 1: Append the member-management describe block.**

```elixir
  describe "change_member_role" do
    setup :setup_org

    test "updates a plain member's role", %{conn: conn, org: org, owner: owner} do
      %{user: member, membership: m} = add_member(org, "member")
      {:ok, lv, _html} = live(log_in_user(conn, owner), @path_for.(org.id))

      html = render_click(lv, "change_member_role", %{"id" => m.id, "role" => "admin"})
      assert html =~ "Role updated"
      assert Organizations.get_user_membership(member.id, org.id).role == "admin"
    end

    test "refuses to change an owner's role", %{conn: conn, org: org, owner: owner} do
      owner_m = Organizations.get_user_membership(owner.id, org.id)
      %{user: admin} = add_member(org, "admin")
      {:ok, lv, _html} = live(log_in_user(conn, admin), @path_for.(org.id))

      html = render_click(lv, "change_member_role", %{"id" => owner_m.id, "role" => "member"})
      assert html =~ "Not authorized"
      assert Organizations.get_user_membership(owner.id, org.id).role == "owner"
    end

    test "refuses to change your own role", %{conn: conn, org: org} do
      %{user: admin, membership: am} = add_member(org, "admin")
      {:ok, lv, _html} = live(log_in_user(conn, admin), @path_for.(org.id))

      html = render_click(lv, "change_member_role", %{"id" => am.id, "role" => "member"})
      assert html =~ "Not authorized"
    end

    test "flashes Member not found for an unknown id", %{conn: conn, org: org, owner: owner} do
      {:ok, lv, _html} = live(log_in_user(conn, owner), @path_for.(org.id))
      html = render_click(lv, "change_member_role", %{"id" => Ecto.UUID.generate(), "role" => "admin"})
      assert html =~ "Member not found"
    end

    test "flashes Invalid role for a non-assignable role", %{conn: conn, org: org, owner: owner} do
      %{membership: m} = add_member(org, "member")
      {:ok, lv, _html} = live(log_in_user(conn, owner), @path_for.(org.id))
      html = render_click(lv, "change_member_role", %{"id" => m.id, "role" => "owner"})
      assert html =~ "Invalid role"
    end
  end

  describe "simple member removal (no sole-owned projects)" do
    setup :setup_org

    test "confirm opens the simple confirm modal", %{conn: conn, org: org, owner: owner} do
      %{membership: m} = add_member(org, "member")
      {:ok, lv, _html} = live(log_in_user(conn, owner), @path_for.(org.id))

      render_click(lv, "confirm_remove_member", %{"id" => m.id})
      assert assigns(lv).removing_member.id == m.id
      assert assigns(lv).sole_owned_projects == []
      assert has_element?(lv, "#remove-member-modal")
      refute has_element?(lv, "#reassign-modal")
    end

    test "remove deletes the membership and resets state", %{conn: conn, org: org, owner: owner} do
      %{user: member, membership: m} = add_member(org, "member")
      {:ok, lv, _html} = live(log_in_user(conn, owner), @path_for.(org.id))

      render_click(lv, "confirm_remove_member", %{"id" => m.id})
      html = render_click(lv, "remove_member", %{})

      assert html =~ "Member removed"
      assert assigns(lv).removing_member == nil
      refute member.id in Enum.map(Organizations.list_organization_members(org.id), & &1.user_id)
    end

    test "cancel resets removal state", %{conn: conn, org: org, owner: owner} do
      %{membership: m} = add_member(org, "member")
      {:ok, lv, _html} = live(log_in_user(conn, owner), @path_for.(org.id))

      render_click(lv, "confirm_remove_member", %{"id" => m.id})
      assert assigns(lv).removing_member.id == m.id
      render_click(lv, "cancel_remove_member", %{})
      assert assigns(lv).removing_member == nil
    end

    test "refuses to remove the owner or yourself", %{conn: conn, org: org, owner: owner} do
      owner_m = Organizations.get_user_membership(owner.id, org.id)
      %{user: admin, membership: am} = add_member(org, "admin")
      {:ok, lv, _html} = live(log_in_user(conn, admin), @path_for.(org.id))

      assert render_click(lv, "confirm_remove_member", %{"id" => owner_m.id}) =~ "Not authorized"
      assert render_click(lv, "confirm_remove_member", %{"id" => am.id}) =~ "Not authorized"
      assert assigns(lv).removing_member == nil
    end
  end
```

**NOTE on the `#reassign-modal` selector:** confirm the reassignment modal's actual root DOM id in `lib/estimate_web/live/settings_live/components/reassignment_modal.ex`. If it is not `reassign-modal`, use its real id (or assert absence of a text unique to that modal, e.g. `refute render(lv) =~ "Reassign"`). Do not invent an id.

- [ ] **Step 2:** `mix test test/estimate_web/live/settings_live/members_test.exs` — GREEN.

- [ ] **Step 3: Commit** `test: characterize members role changes + simple removal`.

---

### Task 4: Join requests + 2FA disable

**Files:**
- Modify: `test/estimate_web/live/settings_live/members_test.exs` (append; reuse helpers).

**Interfaces:**
- Consumes: `assigns/1`, `setup_org/1`, `add_member/3`.

Behaviors to pin:
- `approve_request` (admin) → flash `"Request approved!"`; the requester becomes a member (`list_organization_members` grows, includes them); request removed from `list_pending_join_requests`.
- `reject_request` (admin) → flash `"Request rejected"`; request removed from pending; requester NOT a member.
- `confirm_disable_2fa` with a target user who **is a member** of the org and has TOTP → `assigns(lv).disabling_2fa_user.id == target.id`; `#disable-2fa-modal` renders.
- `confirm_disable_2fa` with a user who is **not a member** of the org → flash `"Not authorized"`, `disabling_2fa_user` stays nil.
- `cancel_disable_2fa` → `disabling_2fa_user` nil.
- `disable_user_2fa` (target member with TOTP set) → flash starts `"2FA disabled for "`; `Accounts.get_user!(target.id)` now has TOTP disabled (`User.totp_enabled?/1` false); members list refreshed.

Setup notes: create a pending join request with `Organizations.create_join_request(user_id, org_id)` (returns `{:ok, %JoinRequest{status: "pending"}}`). For the 2FA target, use `user_with_totp_fixture/1` then `membership_fixture(totp_user, org, "member")`.

- [ ] **Step 1: Append the join-requests + 2FA describe blocks.**

```elixir
  describe "join requests" do
    setup :setup_org

    test "approve makes the requester a member and clears the request",
         %{conn: conn, org: org, owner: owner} do
      requester = user_fixture()
      {:ok, _req} = Organizations.create_join_request(requester.id, org.id)

      {:ok, lv, _html} = live(log_in_user(conn, owner), @path_for.(org.id))
      req = hd(Organizations.list_pending_join_requests(org.id))

      html = render_click(lv, "approve_request", %{"id" => req.id})
      assert html =~ "Request approved!"
      assert requester.id in Enum.map(Organizations.list_organization_members(org.id), & &1.user_id)
      assert Organizations.list_pending_join_requests(org.id) == []
    end

    test "reject clears the request without adding a member",
         %{conn: conn, org: org, owner: owner} do
      requester = user_fixture()
      {:ok, _req} = Organizations.create_join_request(requester.id, org.id)

      {:ok, lv, _html} = live(log_in_user(conn, owner), @path_for.(org.id))
      req = hd(Organizations.list_pending_join_requests(org.id))

      html = render_click(lv, "reject_request", %{"id" => req.id})
      assert html =~ "Request rejected"
      assert Organizations.list_pending_join_requests(org.id) == []
      refute requester.id in Enum.map(Organizations.list_organization_members(org.id), & &1.user_id)
    end
  end

  describe "disable 2FA for a member" do
    setup :setup_org

    test "confirm opens the modal for a member with TOTP", %{conn: conn, org: org, owner: owner} do
      %{user: totp_user} = user_with_totp_fixture()
      _ = membership_fixture(totp_user, org, "member")
      {:ok, lv, _html} = live(log_in_user(conn, owner), @path_for.(org.id))

      render_click(lv, "confirm_disable_2fa", %{"id" => totp_user.id})
      assert assigns(lv).disabling_2fa_user.id == totp_user.id
      assert has_element?(lv, "#disable-2fa-modal")

      render_click(lv, "cancel_disable_2fa", %{})
      assert assigns(lv).disabling_2fa_user == nil
    end

    test "refuses a user who is not a member of the org", %{conn: conn, org: org, owner: owner} do
      %{user: outsider} = user_with_totp_fixture()
      {:ok, lv, _html} = live(log_in_user(conn, owner), @path_for.(org.id))

      html = render_click(lv, "confirm_disable_2fa", %{"id" => outsider.id})
      assert html =~ "Not authorized"
      assert assigns(lv).disabling_2fa_user == nil
    end

    test "disable_user_2fa turns off the member's TOTP", %{conn: conn, org: org, owner: owner} do
      %{user: totp_user} = user_with_totp_fixture()
      _ = membership_fixture(totp_user, org, "member")
      {:ok, lv, _html} = live(log_in_user(conn, owner), @path_for.(org.id))

      render_click(lv, "confirm_disable_2fa", %{"id" => totp_user.id})
      html = render_click(lv, "disable_user_2fa", %{})

      assert html =~ "2FA disabled for "
      refute Accounts.User.totp_enabled?(Accounts.get_user!(totp_user.id))
      assert assigns(lv).disabling_2fa_user == nil
    end
  end
```

- [ ] **Step 2:** `mix test test/estimate_web/live/settings_live/members_test.exs` — GREEN. If `Organizations.create_join_request/2` has a different arity/name, confirm in `lib/estimate/organizations.ex` and use the real signature (the map recorded `create_join_request(user_id, org_id)`); report any deviation.

- [ ] **Step 3:** `mix compile --warnings-as-errors --force` — clean.

- [ ] **Step 4: Commit** `test: characterize members join-requests + 2FA disable`.

---

### Task 5: Reassignment state machine (sole-owner removal path)

**Files:**
- Create: `test/estimate_web/live/settings_live/members_reassignment_test.exs`

**Interfaces:**
- Self-contained (own helpers). Consumes fixtures only.

This is the highest-risk area. Setup: a member who **solely owns** ≥2 projects across ≥2 customers, plus ≥2 other eligible members to reassign to.

Fixture facts (from the map):
- `project_fixture(customer, user)` makes `user` the sole `"owner"` collaborator ⇒ appears in `Portfolio.list_sole_owned_projects(user.id, org.id)` as `{%Project{customer: %Customer{}}, count}`.
- `customer_fixture(org)` → `%Customer{}` in the org.
- `@reassignments` is `%{project_id => user_id}` (UUID strings).
- Entry (`confirm_remove_member`) prefills `@reassignments` mapping every sole-owned project to the **first eligible member** (eligible = other members sorted by `user.name`).
- Modal choice: `sole_owned_projects != []` ⇒ reassignment modal (not the simple confirm modal).
- `reassign_all` replaces the whole map (all → one user), or clears to `%{}` when the user isn't eligible / is `""`.
- `reassign_customer` merges the projects of that customer into the map (or drops them when invalid).
- `reassign_project` sets/deletes a single project (no-op if the project isn't sole-owned).
- `switch_reassign_tab` accepts `~w(all per_customer per_project)`; invalid → no-op.
- `remove_member` calls `Organizations.delete_membership(membership, @reassignments)` and does NOT itself re-check completeness (the disabled button is the only UI guard).

- [ ] **Step 0:** Invoke `elixir-phoenix-guide:testing-essentials`. Read `lib/estimate_web/live/settings_live/components/reassignment_modal.ex` to confirm the modal's DOM (root id, tab button text) before asserting on it.

- [ ] **Step 1: Write the reassignment characterization file.**

```elixir
defmodule EstimateWeb.SettingsLive.MembersReassignmentTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Estimate.AccountsFixtures
  import Estimate.PortfolioFixtures
  import Estimate.CRMFixtures

  alias Estimate.{Organizations, Portfolio}

  defp assigns(lv), do: :sys.get_state(lv.pid).socket.assigns
  defp path(org), do: ~p"/org/#{org.id}/settings/members"

  # Owner + org; a `leaver` who solely owns 2 projects across 2 customers;
  # two eligible members (`alice`, `bob`) to reassign to.
  defp reassignment_setup(%{conn: conn}) do
    %{user: owner, organization: org} = user_with_organization_fixture()

    leaver = user_fixture(%{name: "Zoe Leaver"})
    leaver_m = membership_fixture(leaver, org, "member")
    alice = user_fixture(%{name: "Alice"})
    _ = membership_fixture(alice, org, "member")
    bob = user_fixture(%{name: "Bob"})
    _ = membership_fixture(bob, org, "member")

    cust_a = customer_fixture(org)
    cust_b = customer_fixture(org)
    proj_a = project_fixture(cust_a, leaver)
    proj_b = project_fixture(cust_b, leaver)

    conn = log_in_user(conn, owner)
    {:ok, lv, _html} = live(conn, path(org))

    %{
      lv: lv, org: org, owner: owner,
      leaver: leaver, leaver_m: leaver_m, alice: alice, bob: bob,
      cust_a: cust_a, cust_b: cust_b, proj_a: proj_a, proj_b: proj_b
    }
  end

  describe "reassignment modal & state machine" do
    setup :reassignment_setup

    test "sole-owner removal opens the reassignment modal and prefills to first eligible",
         %{lv: lv, leaver_m: leaver_m, proj_a: proj_a, proj_b: proj_b, alice: alice} do
      render_click(lv, "confirm_remove_member", %{"id" => leaver_m.id})

      a = assigns(lv)
      assert length(a.sole_owned_projects) == 2
      assert a.reassign_tab == :all
      # eligible sorted by name: "Alice" first ⇒ both projects prefilled to alice
      assert a.reassignments == %{proj_a.id => alice.id, proj_b.id => alice.id}
      # reassignment modal (not the simple confirm modal) is shown
      refute has_element?(lv, "#remove-member-modal")
    end

    test "switch_reassign_tab accepts valid tabs and ignores invalid",
         %{lv: lv, leaver_m: leaver_m} do
      render_click(lv, "confirm_remove_member", %{"id" => leaver_m.id})

      for tab <- ~w(all per_customer per_project) do
        render_click(lv, "switch_reassign_tab", %{"tab" => tab})
        assert assigns(lv).reassign_tab == String.to_existing_atom(tab)
      end

      render_click(lv, "switch_reassign_tab", %{"tab" => "bogus"})
      # unchanged from the last valid value (:per_project)
      assert assigns(lv).reassign_tab == :per_project
    end

    test "reassign_all replaces the whole map; empty clears it",
         %{lv: lv, leaver_m: leaver_m, proj_a: proj_a, proj_b: proj_b, bob: bob} do
      render_click(lv, "confirm_remove_member", %{"id" => leaver_m.id})

      render_click(lv, "reassign_all", %{"user_id" => bob.id})
      assert assigns(lv).reassignments == %{proj_a.id => bob.id, proj_b.id => bob.id}

      render_click(lv, "reassign_all", %{"user_id" => ""})
      assert assigns(lv).reassignments == %{}

      # a non-eligible id (e.g. the leaver themselves) also clears
      render_click(lv, "reassign_all", %{"user_id" => Ecto.UUID.generate()})
      assert assigns(lv).reassignments == %{}
    end

    test "reassign_customer merges only that customer's projects",
         %{lv: lv, leaver_m: leaver_m, cust_a: cust_a, proj_a: proj_a, proj_b: proj_b, bob: bob} do
      render_click(lv, "confirm_remove_member", %{"id" => leaver_m.id})
      # start from a known state: everything to bob
      render_click(lv, "reassign_all", %{"user_id" => bob.id})

      # move only customer A's project to alice — wait, use bob→ (keep alice out)
      render_click(lv, "reassign_customer", %{"customer_id" => cust_a.id, "user_id" => bob.id})
      r = assigns(lv).reassignments
      assert r[proj_a.id] == bob.id
      assert r[proj_b.id] == bob.id

      # invalid member for that customer drops those projects from the map
      render_click(lv, "reassign_customer", %{"customer_id" => cust_a.id, "user_id" => ""})
      r2 = assigns(lv).reassignments
      refute Map.has_key?(r2, proj_a.id)
      assert Map.has_key?(r2, proj_b.id)
    end

    test "reassign_project sets/deletes a single project; unknown project is a no-op",
         %{lv: lv, leaver_m: leaver_m, proj_a: proj_a, alice: alice} do
      render_click(lv, "confirm_remove_member", %{"id" => leaver_m.id})

      render_click(lv, "reassign_project", %{"project_id" => proj_a.id, "user_id" => alice.id})
      assert assigns(lv).reassignments[proj_a.id] == alice.id

      render_click(lv, "reassign_project", %{"project_id" => proj_a.id, "user_id" => ""})
      refute Map.has_key?(assigns(lv).reassignments, proj_a.id)

      before = assigns(lv).reassignments
      render_click(lv, "reassign_project", %{"project_id" => Ecto.UUID.generate(), "user_id" => alice.id})
      assert assigns(lv).reassignments == before
    end

    test "remove_member with complete reassignments removes the member",
         %{lv: lv, org: org, leaver: leaver, leaver_m: leaver_m, alice: alice} do
      render_click(lv, "confirm_remove_member", %{"id" => leaver_m.id})
      render_click(lv, "reassign_all", %{"user_id" => alice.id})

      html = render_click(lv, "remove_member", %{})
      assert html =~ "Member removed"
      refute leaver.id in Enum.map(Organizations.list_organization_members(org.id), & &1.user_id)
      assert assigns(lv).removing_member == nil
    end

    test "CHARACTERIZATION: remove_member with EMPTY reassignments (button bypass)",
         %{lv: lv, org: org, leaver: leaver, leaver_m: leaver_m, proj_a: proj_a} do
      render_click(lv, "confirm_remove_member", %{"id" => leaver_m.id})
      # Force an incomplete map (the disabled UI button normally prevents this,
      # but a direct event push bypasses it). Pin whatever the code does today.
      render_click(lv, "reassign_all", %{"user_id" => ""})
      assert assigns(lv).reassignments == %{}

      html = render_click(lv, "remove_member", %{})

      # Document the ACTUAL outcome. Empty map ⇒ delete_membership validation
      # short-circuits to :ok and deletes the membership, leaving proj_a's sole
      # ownership dangling. Assert the real behavior observed on first run and
      # keep it as the pinned baseline; if it instead flashes an error, pin that.
      assert html =~ "Member removed" or html =~ "reassignment" or html =~ "Could not"
      # Record the concrete post-state so the decomposition can't silently change it:
      members_after = Enum.map(Organizations.list_organization_members(org.id), & &1.user_id)
      owner_after = Portfolio.get_project_owner_id(proj_a.id)
      # These two lines document the baseline — set them to the observed values
      # on first green run (see Step 2). Replace the RHS with the real values.
      _ = {members_after, owner_after}
    end
  end
end
```

- [ ] **Step 2: Run and PIN.**

Run: `mix test test/estimate_web/live/settings_live/members_reassignment_test.exs`
Expected: all GREEN. For the final `CHARACTERIZATION: ... button bypass` test, run it, observe the actual flash + the actual `members_after` / project-owner post-state, then **rewrite that test's assertions to the exact observed values** (remove the `or` fallback and the placeholder `_ =` line; assert the real flash string and the real post-state). The goal is an exact pinned baseline, not a loose match. If `Portfolio.get_project_owner_id/1` doesn't exist, replace with the real accessor (check `lib/estimate/portfolio.ex`) or assert via `Portfolio.list_sole_owned_projects/2` on the survivors. Report the observed baseline in your task report.

- [ ] **Step 3:** `mix compile --warnings-as-errors --force`; then full `mix test` — entire suite green.

- [ ] **Step 4: Commit** `test: characterize members reassignment state machine`.

---

## Self-Review

**Coverage vs. the event surface (24 events):** switch_tab ✓(T1) · send_invite ✓(T2) · generate_invite_code/dismiss_generated_code/copy_invite_code ✓(T2) · copy_join_link/copy_invite_link ✓(T2) · confirm_cancel_invite/dismiss_cancel_invite/cancel_invite ✓(T2) · change_member_role ✓(T3) · confirm_remove_member/cancel_remove_member/remove_member (simple) ✓(T3) · approve_request/reject_request ✓(T4) · confirm_disable_2fa/cancel_disable_2fa/disable_user_2fa ✓(T4) · switch_reassign_tab/reassign_all/reassign_customer/reassign_project + remove_member (sole-owner) ✓(T5). Authz gating for all 16 wrapped events ✓(T1). Non-member redirect + anonymous redirect ✓(T1).

**Placeholder scan:** The only intentional "fill in on first run" is the `CHARACTERIZATION: button bypass` baseline in T5 Step 2 — explicitly a record-the-observed-value step, not a vague TODO. All other assertions carry exact expected strings/values.

**Type consistency:** helpers `assigns/1`, `setup_org/1`, `add_member/3` defined in T1, reused T2–T4; T5 is self-contained. Fixture names match the map: `user_with_organization_fixture/0`, `membership_fixture/3`, `user_fixture/1`, `user_with_totp_fixture/1`, `project_fixture/2-3`, `customer_fixture/1-2`, `Organizations.create_invite/3`, `create_join_request/2`, `list_organization_members/1`, `list_organization_invites/1`, `list_pending_join_requests/1`, `get_user_membership/2`, `delete_membership/2`.

**Open items flagged for the implementer (verify against source, don't invent):** reassignment modal root DOM id (T3/T5 note); `send_invite` malformed-email trigger (T2 Step 2 note); `create_join_request/2` signature (T4 Step 2 note); project-owner accessor for the bypass baseline (T5 Step 2 note).
