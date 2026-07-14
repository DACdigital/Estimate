# Members Decomposition + Orphan-Bug Fix — Implementation Plan (Increment 2/2)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Before editing Elixir invoke `elixir-phoenix-guide:elixir-essentials`; before HEEx/components `elixir-phoenix-guide:phoenix-liveview-essentials`; before the Ecto change `elixir-phoenix-guide:ecto-changeset-patterns`. Steps use checkbox (`- [ ]`).

**Goal:** Turn the ~24-`handle_event` soup of `EstimateWeb.SettingsLive.Members` into a thin router + 5 per-feature handler modules, consolidate duplicated authorization, fix the pinned orphaned-project bug, and add two reusable view primitives. Behavior-identical except the deliberate Phase C bug fix.

**Design:** `docs/superpowers/specs/2026-07-14-members-decomposition-design.md`.

**Tech Stack:** Elixir ~> 1.15, Phoenix.LiveView 1.1, Ecto.

## Global Constraints
- **No DB model changes** (no schema/migration/column/index). New schema-module *functions* (e.g. `Membership.assignable_roles/0`) are DB-neutral and allowed.
- **Behavior-identical** for Tasks 1, 2, 3, 5 → the Increment-1 characterization suite (`test/estimate_web/live/settings_live/members_test.exs` + `members_reassignment_test.exs`, currently green as part of the full 201) MUST stay green after each. The ONLY intended behavior change is Task 4 (bug fix), which flips exactly one pinned test.
- No new LiveComponents. Handler logic → plain modules; `members.ex` keeps `handle_event/3` and delegates one-liners.
- Every event's `phx-*` bindings, flash strings, assign transitions, and emitted markup stay identical (Tasks 1–3, 5). Relocation is verbatim.
- `mix format` + `mix compile --warnings-as-errors --force` clean; full `mix test` green per task (`mix precommit` is the gate). Commit trailer: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- Branch `refactor/members-decompose` (already checked out, spec committed at `a84889a`).
- Signing works (1Password unlocked); if a commit hangs retry ≤5×, never `--no-gpg-sign`, never kill the app.

---

### Task 1 (Phase A): Authorization consolidation

**Files:**
- Modify `lib/estimate/accounts/membership.ex` (add `assignable_roles/0`)
- Modify `lib/estimate/organizations.ex` (add `manageable_member?/2`)
- Modify `lib/estimate_web/live/settings_live/members.ex` (rewire 5 call sites; drop `@assignable_roles`)
- Test: `test/estimate/organizations_test.exs` (or `accounts_test.exs` if that's where Organizations context tests live — check; add `manageable_member?/2` cases)

**Interfaces (produced):**
- `Estimate.Accounts.Membership.assignable_roles() :: ["admin", "member"]`
- `Estimate.Organizations.manageable_member?(%Membership{}, actor_user_id :: binary) :: boolean` — `true` iff role != "owner" and user_id != actor_user_id; `false` for non-`%Membership{}`.

- [ ] **Step 0:** Invoke `elixir-phoenix-guide:elixir-essentials`.
- [ ] **Step 1:** In `lib/estimate/accounts/membership.ex`, add after `def admin_roles, do: ~w(owner admin)` (line 26):
```elixir
  def assignable_roles, do: ~w(admin member)
```
- [ ] **Step 2:** In `lib/estimate/organizations.ex`, add a public predicate (near the other membership functions; `%Membership{}` is already aliased in this module). Include a moduledoc-style `@doc`:
```elixir
  @doc """
  Whether `actor_user_id` may change/remove the given membership:
  not an owner, and not the actor themselves. False for a nil/non-membership.
  """
  def manageable_member?(%Membership{} = membership, actor_user_id),
    do: membership.role != "owner" and membership.user_id != actor_user_id

  def manageable_member?(_membership, _actor_user_id), do: false
```
- [ ] **Step 3:** In `members.ex`, add `alias Estimate.Accounts.Membership` to the existing alias line (currently `alias Estimate.{Organizations, Portfolio}`), and **delete** the `@assignable_roles ~w(member admin)` module attribute. Rewire the 5 sites (behavior-identical):
  - `send_invite` — `if params["role"] not in @assignable_roles` → `if params["role"] not in Membership.assignable_roles()`.
  - `generate_invite_code` — `if role not in @assignable_roles` → `if role not in Membership.assignable_roles()`.
  - `change_member_role` — in the `cond`, replace the branch
    `membership.role == "owner" or membership.user_id == socket.assigns.current_user.id -> {:noreply, put_flash(socket, :error, "Not authorized")}`
    with
    `not Organizations.manageable_member?(membership, socket.assigns.current_user.id) -> {:noreply, put_flash(socket, :error, "Not authorized")}`
    (keep the `is_nil(membership) -> "Member not found"` branch **above** it, and `role not in Membership.assignable_roles()` for the "Invalid role" branch).
  - `confirm_remove_member` — replace `if membership && membership.role != "owner" && membership.user_id != socket.assigns.current_user.id do` with `if Organizations.manageable_member?(membership, socket.assigns.current_user.id) do` (else-branch flash "Not authorized" unchanged).
  - `remove_member` — replace `if membership && membership.role != "owner" && membership.user_id != socket.assigns.current_user.id do` with `if Organizations.manageable_member?(membership, socket.assigns.current_user.id) do` (else-branch flash "Cannot remove this member" unchanged).
- [ ] **Step 3b (verify equivalence):** `manageable_member?(nil, _)` returns `false`, so `confirm_remove_member`/`remove_member` still hit their else-branch when the membership isn't found — identical to the old `membership && …`. Confirm by reading; no behavior change.
- [ ] **Step 4 (context test):** In the Organizations context test file, add:
```elixir
  describe "manageable_member?/2" do
    test "false for an owner, false for self, true for another member" do
      %{user: owner, organization: org} = user_with_organization_fixture()
      owner_m = Organizations.get_user_membership(owner.id, org.id)
      member = user_fixture()
      member_m = membership_fixture(member, org, "member")

      refute Organizations.manageable_member?(owner_m, owner.id)        # owner
      refute Organizations.manageable_member?(member_m, member.id)      # self
      assert Organizations.manageable_member?(member_m, owner.id)       # other member
      refute Organizations.manageable_member?(nil, owner.id)            # nil
    end
  end
```
(Confirm the right fixtures are imported in that test file; adapt fixture calls to match.)
- [ ] **Step 5:** `mix format`; `mix test` (FULL suite — the characterization suite must still be **201 green**: the members events behave identically; plus the new context test passes); `mix compile --warnings-as-errors --force` clean.
- [ ] **Step 6: Commit** `refactor: consolidate members authz into Organizations.manageable_member?/2 + Membership.assignable_roles/0`.

---

### Task 2 (Phase B1): `:live_handlers` macro + extract Invites / JoinRequests / TwoFactor

**Files:**
- Modify `lib/estimate_web.ex` (add `live_handlers/0`)
- Create `lib/estimate_web/live/settings_live/members/invites.ex`
- Create `lib/estimate_web/live/settings_live/members/join_requests.ex`
- Create `lib/estimate_web/live/settings_live/members/two_factor.ex`
- Modify `lib/estimate_web/live/settings_live/members.ex` (delegate those events; drop moved private `atomize_keys/1`)

**Interfaces (produced):** each module exposes `fn(socket, params) :: {:noreply, socket}`:
- `Members.Invites`: `send_invite/2`, `generate_invite_code/2`, `copy_invite_code/2`, `dismiss_generated_code/2`, `copy_join_link/2`, `copy_invite_link/2`, `confirm_cancel_invite/2`, `dismiss_cancel_invite/2`, `cancel_invite/2`
- `Members.JoinRequests`: `approve_request/2`, `reject_request/2`
- `Members.TwoFactor`: `confirm_disable_2fa/2`, `cancel_disable_2fa/2`, `disable_user_2fa/2`

- [ ] **Step 0:** Invoke `elixir-phoenix-guide:phoenix-liveview-essentials`.
- [ ] **Step 1 (macro):** In `lib/estimate_web.ex`, add a `live_handlers/0` clause (mirrors the existing `def live_view`/`def html` style). Place it after `def live_component`:
```elixir
  @doc """
  Shared setup for per-feature LiveView event-handler modules
  (functions of `(socket, params) -> {:noreply, socket}`, no rendering).
  """
  def live_handlers do
    quote do
      import Phoenix.LiveView
      import Phoenix.Component
      import EstimateWeb.AuthHelpers
      unquote(verified_routes())
    end
  end
```
(`__using__/1` already dispatches via `apply(__MODULE__, which, [])`, so `use EstimateWeb, :live_handlers` works with no further change.)
- [ ] **Step 2 (Invites):** Create `lib/estimate_web/live/settings_live/members/invites.ex`:
```elixir
defmodule EstimateWeb.SettingsLive.Members.Invites do
  @moduledoc "Event handlers for the members invitations panel (email/code/links/cancel)."
  use EstimateWeb, :live_handlers

  alias Estimate.Organizations
  alias Estimate.Accounts.Membership

  # <<< move the VERBATIM bodies of these members.ex handle_event clauses here,
  # renaming each `def handle_event("<event>", <params>, socket) do … end`
  # to `def <event>(socket, <params>) do … end` (identical body):
  #   send_invite, generate_invite_code, copy_invite_code, dismiss_generated_code,
  #   copy_join_link, copy_invite_link, confirm_cancel_invite, dismiss_cancel_invite,
  #   cancel_invite
  # Also move the private `atomize_keys/1` helper (used by send_invite) here. >>>
end
```
The bodies already reference `socket`, `require_admin`, `Organizations`, `Membership.assignable_roles()`, `put_flash`, `assign`, `push_event`, `to_form`, and `url(~p"…")` — all available via `:live_handlers` + the aliases. `send_invite` also references `Estimate.Emails.InviteEmail` and `Estimate.Mailer` — keep them fully qualified (as in the current body). Example of the mechanical rename for one:
```elixir
  # was: def handle_event("dismiss_generated_code", _params, socket), do: {:noreply, assign(socket, :generated_code, nil)}
  def dismiss_generated_code(socket, _params), do: {:noreply, assign(socket, :generated_code, nil)}
```
- [ ] **Step 3 (JoinRequests):** Create `members/join_requests.ex` (same pattern) with `approve_request/2`, `reject_request/2` — verbatim bodies. `use EstimateWeb, :live_handlers`; `alias Estimate.Organizations`.
- [ ] **Step 4 (TwoFactor):** Create `members/two_factor.ex` with `confirm_disable_2fa/2`, `cancel_disable_2fa/2`, `disable_user_2fa/2` — verbatim bodies. `use EstimateWeb, :live_handlers`; `alias Estimate.Organizations`; the bodies reference `Estimate.Accounts.get_user!/1` and `Estimate.Accounts.Totp.disable_totp/1` — keep fully qualified (or alias `Estimate.Accounts`).
- [ ] **Step 5 (delegate in members.ex):** Replace those 14 `handle_event/3` clauses in `members.ex` with one-line delegations, and add `alias EstimateWeb.SettingsLive.Members.{Invites, JoinRequests, TwoFactor}` (grouped with the other module aliases). Delegations:
```elixir
  def handle_event("send_invite", params, socket), do: Invites.send_invite(socket, params)
  def handle_event("generate_invite_code", params, socket), do: Invites.generate_invite_code(socket, params)
  def handle_event("copy_invite_code", params, socket), do: Invites.copy_invite_code(socket, params)
  def handle_event("dismiss_generated_code", params, socket), do: Invites.dismiss_generated_code(socket, params)
  def handle_event("copy_join_link", params, socket), do: Invites.copy_join_link(socket, params)
  def handle_event("copy_invite_link", params, socket), do: Invites.copy_invite_link(socket, params)
  def handle_event("confirm_cancel_invite", params, socket), do: Invites.confirm_cancel_invite(socket, params)
  def handle_event("dismiss_cancel_invite", params, socket), do: Invites.dismiss_cancel_invite(socket, params)
  def handle_event("cancel_invite", params, socket), do: Invites.cancel_invite(socket, params)
  def handle_event("approve_request", params, socket), do: JoinRequests.approve_request(socket, params)
  def handle_event("reject_request", params, socket), do: JoinRequests.reject_request(socket, params)
  def handle_event("confirm_disable_2fa", params, socket), do: TwoFactor.confirm_disable_2fa(socket, params)
  def handle_event("cancel_disable_2fa", params, socket), do: TwoFactor.cancel_disable_2fa(socket, params)
  def handle_event("disable_user_2fa", params, socket), do: TwoFactor.disable_user_2fa(socket, params)
```
Remove the now-moved `atomize_keys/1` from `members.ex`. Leave the Roster/Removal clauses (`change_member_role`, `confirm_remove_member`, `remove_member`, `switch_reassign_tab`, `reassign_*`, `cancel_remove_member`, `switch_tab`) untouched — Task 3 handles them.
- [ ] **Step 6:** `mix format`; `mix test` (FULL suite — **201 green**, behavior-identical); `mix compile --warnings-as-errors --force` clean (watch for unused-alias / unused-import warnings in the new modules — trim to what's used).
- [ ] **Step 7: Commit** `refactor: extract members invites/join-requests/2fa handlers into modules (+ :live_handlers)`.

---

### Task 3 (Phase B2): extract Roster + Removal; members.ex becomes the thin router

**Files:**
- Create `lib/estimate_web/live/settings_live/members/roster.ex`
- Create `lib/estimate_web/live/settings_live/members/removal.ex`
- Modify `lib/estimate_web/live/settings_live/members.ex` (delegate remaining events; mount calls `Removal.reset_removal_state/1`; drop moved private helpers)

**Interfaces (produced):**
- `Members.Roster`: `change_member_role/2`
- `Members.Removal`: `confirm_remove_member/2`, `cancel_remove_member/2`, `remove_member/2`, `switch_reassign_tab/2` (takes the validated tab string), `reassign_all/2`, `reassign_customer/2`, `reassign_project/2`, and `reset_removal_state/1` (public — `mount` and the handlers call it); private `valid_eligible_member?/2`, `valid_sole_owned_project?/2`, `sole_owned_project_ids_for_customer/2`.

- [ ] **Step 0:** Invoke `elixir-phoenix-guide:phoenix-liveview-essentials`.
- [ ] **Step 1 (Roster):** Create `members/roster.ex`:
```elixir
defmodule EstimateWeb.SettingsLive.Members.Roster do
  @moduledoc "Event handlers for member role changes."
  use EstimateWeb, :live_handlers

  alias Estimate.Organizations
  alias Estimate.Accounts.Membership

  # move the VERBATIM body of handle_event("change_member_role", %{"id"=>id,"role"=>role}, socket)
  # into: def change_member_role(socket, %{"id" => id, "role" => role}) do … end
end
```
(The body already uses `Organizations.manageable_member?/2` and `Membership.assignable_roles()` after Task 1.)
- [ ] **Step 2 (Removal):** Create `members/removal.ex`:
```elixir
defmodule EstimateWeb.SettingsLive.Members.Removal do
  @moduledoc "Event handlers + state for member removal and its ownership-reassignment flow."
  use EstimateWeb, :live_handlers

  alias Estimate.{Organizations, Portfolio}

  # Move VERBATIM (renaming heads to (socket, params)):
  #   confirm_remove_member/2, cancel_remove_member/2, remove_member/2,
  #   reassign_all/2, reassign_customer/2, reassign_project/2
  # switch_reassign_tab: the LiveView keeps the `when tab in @valid_reassign_tabs`
  #   guard and passes the tab string:
  #     def switch_reassign_tab(socket, tab),
  #       do: {:noreply, assign(socket, :reassign_tab, String.to_existing_atom(tab))}
  # Move the private helpers VERBATIM: valid_eligible_member?/2,
  #   valid_sole_owned_project?/2, sole_owned_project_ids_for_customer/2.
  # Make reset_removal_state/1 PUBLIC (def, not defp) — mount + handlers call it.
end
```
- [ ] **Step 3 (thin the router):** In `members.ex`:
  - Add `alias EstimateWeb.SettingsLive.Members.{Invites, JoinRequests, TwoFactor, Roster, Removal}` (merge with Task 2's alias).
  - `mount/3`: change the trailing `|> reset_removal_state()` to `|> Removal.reset_removal_state()`.
  - Replace the remaining handler clauses with delegations (keep the `switch_tab`/`switch_reassign_tab` **guards** and both invalid-value catch-alls in `members.ex`):
```elixir
  def handle_event("change_member_role", params, socket), do: Roster.change_member_role(socket, params)
  def handle_event("confirm_remove_member", params, socket), do: Removal.confirm_remove_member(socket, params)
  def handle_event("cancel_remove_member", params, socket), do: Removal.cancel_remove_member(socket, params)
  def handle_event("remove_member", params, socket), do: Removal.remove_member(socket, params)
  def handle_event("reassign_all", params, socket), do: Removal.reassign_all(socket, params)
  def handle_event("reassign_customer", params, socket), do: Removal.reassign_customer(socket, params)
  def handle_event("reassign_project", params, socket), do: Removal.reassign_project(socket, params)

  def handle_event("switch_reassign_tab", %{"tab" => tab}, socket)
      when tab in @valid_reassign_tabs,
      do: Removal.switch_reassign_tab(socket, tab)

  # existing switch_tab clauses stay inline:
  def handle_event("switch_tab", %{"tab" => tab}, socket) when tab in @valid_tabs,
    do: {:noreply, assign(socket, :current_tab, String.to_existing_atom(tab))}

  # catch-alls (unchanged):
  def handle_event("switch_tab", _params, socket), do: {:noreply, socket}
  def handle_event("switch_reassign_tab", _params, socket), do: {:noreply, socket}
```
  - **Delete** the now-moved private helpers from `members.ex`: `reset_removal_state/1`, `valid_eligible_member?/2`, `valid_sole_owned_project?/2`, `sole_owned_project_ids_for_customer/2` (they live in `Removal` now). `members.ex` should retain only: `mount`, `render`, the two `@valid_*` attrs, all the `handle_event` delegations/guards/catch-alls.
- [ ] **Step 4:** `mix format`; `mix test` (FULL suite — **201 green**, behavior-identical incl. the whole reassignment state machine); `mix compile --warnings-as-errors --force` clean.
- [ ] **Step 5 (structure check):** Confirm `members.ex` is now a thin router (no handler bodies except `switch_tab`'s trivial assign + catch-alls). Report its new line count.
- [ ] **Step 6: Commit** `refactor: extract members roster + removal/reassignment handlers into modules`.

---

### Task 4 (Phase C): Fix the orphaned-project bug (context full-coverage validation)

**Files:**
- Modify `lib/estimate/organizations.ex` (`validate_reassignments/3`)
- Modify `lib/estimate_web/live/settings_live/members/removal.ex` (`remove_member/2` error match + flash)
- Modify `test/estimate_web/live/settings_live/members_reassignment_test.exs` (flip the bypass test)
- Modify the Organizations context test (add `delete_membership` incomplete-map cases)

**Interfaces (changed):** `Organizations.delete_membership/2` now returns `{:error, :incomplete_reassignment}` when the removed user's sole-owned projects aren't all covered by the reassignment map (previously it silently orphaned them).

- [ ] **Step 0:** Invoke `elixir-phoenix-guide:ecto-changeset-patterns` (for the `Ecto.Multi`/validation context) and `superpowers:test-driven-development`.
- [ ] **Step 1 (write the failing/flipped tests FIRST):**
  - In `members_reassignment_test.exs`, rewrite the `CHARACTERIZATION: remove_member with EMPTY reassignments (button bypass)` test to assert the CORRECTED behavior:
```elixir
    test "remove_member with EMPTY reassignments is rejected (no orphaning)",
         %{lv: lv, org: org, leaver: leaver, leaver_m: leaver_m, proj_a: proj_a, proj_b: proj_b} do
      render_click(lv, "confirm_remove_member", %{"id" => leaver_m.id})
      render_click(lv, "reassign_all", %{"user_id" => ""})
      assert assigns(lv).reassignments == %{}

      html = render_click(lv, "remove_member", %{})

      assert html =~ "Reassign all projects before removing"
      # member NOT removed, projects NOT orphaned (leaver still their owner):
      assert leaver.id in Enum.map(Organizations.list_organization_members(org.id), & &1.user_id)
      assert leaver.id in Enum.map(Portfolio.list_collaborators(proj_a.id), & &1.user_id)
      assert leaver.id in Enum.map(Portfolio.list_collaborators(proj_b.id), & &1.user_id)
    end
```
  - In the Organizations context test, add:
```elixir
    test "delete_membership/2 refuses to orphan sole-owned projects" do
      %{user: owner, organization: org} = user_with_organization_fixture()
      leaver = user_fixture()
      leaver_m = membership_fixture(leaver, org, "member")
      customer = customer_fixture(org)
      project = project_fixture(customer, leaver)   # leaver = sole owner

      assert {:error, :incomplete_reassignment} = Organizations.delete_membership(leaver_m, %{})
      # nothing deleted:
      assert Organizations.get_user_membership(leaver.id, org.id)
      assert leaver.id in Enum.map(Portfolio.list_collaborators(project.id), & &1.user_id)

      # a complete map still succeeds:
      assert {:ok, _} =
               Organizations.delete_membership(leaver_m, %{project.id => owner.id})
    end
```
- [ ] **Step 2 (run — expect RED):** `mix test test/estimate_web/live/settings_live/members_reassignment_test.exs <context test file>` — both new assertions FAIL against current code (today it orphans + flashes "Member removed"). Confirm the failure messages match that expectation.
- [ ] **Step 3 (fix the context):** In `organizations.ex`, **delete** the clause
```elixir
  defp validate_reassignments(reassignments, _org_id, _removed_user_id)
       when map_size(reassignments) == 0,
       do: :ok
```
and add a sole-owned-coverage guard as the FIRST `cond` branch of the remaining `validate_reassignments/3` (keep the existing `:invalid_project`/`:self_reassignment`/`:invalid_member` branches after it):
```elixir
  defp validate_reassignments(reassignments, org_id, removed_user_id) do
    sole_owned_ids =
      Estimate.Portfolio.list_sole_owned_projects(removed_user_id, org_id)
      |> Enum.map(fn {p, _count} -> p.id end)
      |> MapSet.new()

    mapped_ids = reassignments |> Map.keys() |> MapSet.new()
    project_ids = Map.keys(reassignments)
    new_owner_ids = reassignments |> Map.values() |> Enum.uniq()

    org_project_ids =
      from(p in Project,
        where: p.id in ^project_ids and p.organization_id == ^org_id,
        select: p.id
      )
      |> Repo.all()
      |> MapSet.new()

    member_ids =
      from(m in Membership, where: m.organization_id == ^org_id, select: m.user_id)
      |> Repo.all()
      |> MapSet.new()

    cond do
      not MapSet.subset?(sole_owned_ids, mapped_ids) -> {:error, :incomplete_reassignment}
      Enum.any?(project_ids, &(not MapSet.member?(org_project_ids, &1))) -> {:error, :invalid_project}
      Enum.any?(new_owner_ids, &(&1 == removed_user_id)) -> {:error, :self_reassignment}
      Enum.any?(new_owner_ids, &(not MapSet.member?(member_ids, &1))) -> {:error, :invalid_member}
      true -> :ok
    end
  end
```
Note: `delete_membership/2` already runs inside `Repo.ensure_org_context/1`; `list_sole_owned_projects/2` wraps its own `ensure_org_context` (idempotent same-org). The Step-2 context test exercises this nested path — if it errors on the nested context, fall back to an inline sole-owned query (projects in `org_id` where `removed_user_id` is an `"owner"` `ProjectCollaborator` and no other collaborator is `"owner"`) and report the change.
- [ ] **Step 4 (fix the handler flash):** In `members/removal.ex`, `remove_member/2`, add a clause to the `case Organizations.delete_membership(...)` error handling — extend the existing guarded error clause to include `:incomplete_reassignment`, OR add a dedicated one so the flash reads exactly:
```elixir
        {:error, :incomplete_reassignment} ->
          {:noreply,
           socket
           |> put_flash(:error, "Reassign all projects before removing")
           |> reset_removal_state()}
```
(Place it alongside the existing `{:error, reason} when reason in [:invalid_project, :invalid_member, :self_reassignment]` clause; keep that one and the generic `{:error, _}` clause intact.)
- [ ] **Step 5 (run — expect GREEN):** the two new tests pass; then FULL `mix test` — **202** (201 minus the removed old-baseline assertions plus the new ones — confirm the count and that everything is green); `mix format`; `mix compile --warnings-as-errors --force` clean.
- [ ] **Step 6: Commit** `fix: reject membership removal that would orphan sole-owned projects`.

---

### Task 5 (Phase D): `<.badge>` + `Format.date/1`, adopt in member components

**Files:**
- Modify `lib/estimate_web/components/core_components.ex` (add `badge/1`)
- Modify `lib/estimate_web/format.ex` (add `date/1`)
- Modify `lib/estimate_web/live/settings_live/components/member_components.ex` (adopt both)
- Test: `test/estimate_web/components/core_components_test.exs` (badge render) — create if absent; `test/estimate_web/format_test.exs` (date)

**Interfaces (produced):**
- `<.badge variant={:neutral | :muted | :success} class?>text</.badge>` — a pill span.
- `EstimateWeb.Format.date(date_or_datetime | nil) :: String.t()` (nil → `""`, else `"%b %d, %Y"`).

- [ ] **Step 0:** Invoke `elixir-phoenix-guide:phoenix-liveview-essentials`.
- [ ] **Step 1 (badge):** In `core_components.ex`, add:
```elixir
  @doc """
  A small status/label pill.

      <.badge variant={:success}>Active</.badge>
  """
  attr :variant, :atom, default: :neutral, values: [:neutral, :muted, :success]
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def badge(assigns) do
    ~H"""
    <span class={["text-[10px] px-1.5 py-0.5 rounded-full font-medium", badge_variant(@variant), @class]}>
      {render_slot(@inner_block)}
    </span>
    """
  end

  defp badge_variant(:neutral), do: "bg-base-200 text-base-content/60"
  defp badge_variant(:muted), do: "bg-base-200 text-base-content/40"
  defp badge_variant(:success), do: "bg-success/10 text-success"
```
- [ ] **Step 2 (Format.date):** In `format.ex`, add:
```elixir
  @doc ~S(Formats a Date/DateTime as `Jul 14, 2026`. nil → "".)
  def date(nil), do: ""
  def date(date), do: Calendar.strftime(date, "%b %d, %Y")
```
- [ ] **Step 3 (adopt in member_components.ex):** Add `alias EstimateWeb.Format` to the module. Then:
  - The 3 role/status pills (currently `<span class="text-[10px] px-1.5 py-0.5 bg-base-200 text-base-content/60 rounded-full font-medium">…`, and the `bg-success/10 text-success` and `bg-base-200 text-base-content/40` variants) → `<.badge variant={:neutral}>…</.badge>` / `<.badge variant={:success}>…</.badge>` / `<.badge variant={:muted}>…</.badge>` respectively, preserving the inner text exactly. Read the current file to map each pill to its variant by its color classes.
  - The 3 `Calendar.strftime(<x>, "%b %d, %Y")` sites (invite `expires_at` ×2, request `inserted_at`) → `Format.date(<x>)`.
- [ ] **Step 4 (tests):**
```elixir
  # core_components_test.exs
  test "badge renders variant classes and content" do
    html = render_component(&EstimateWeb.CoreComponents.badge/1, %{variant: :success, inner_block: ...})  # use the component test helper idiom for slots
    assert html =~ "bg-success/10 text-success"
    assert html =~ "rounded-full"
  end

  # format_test.exs
  test "date/1 formats and handles nil" do
    assert EstimateWeb.Format.date(~D[2026-07-14]) == "Jul 14, 2026"
    assert EstimateWeb.Format.date(nil) == ""
  end
```
(Use the project's existing component-test idiom for the slot; check `test/estimate_web/` for `render_component` usage and match it.)
- [ ] **Step 5:** `mix format`; `mix test` (FULL — the characterization suite stays green; the pill class-string order changes but no char test asserts on pill classes, and the visual output is identical); `mix compile --warnings-as-errors --force` clean.
- [ ] **Step 6 (visual verify):** Start the dev server (`preview_start` name from `.claude/launch.json`), open the members page for a seeded org, screenshot the members/invites/requests tabs, confirm pills + dates render identically. (If seeding a logged-in org member in the preview is impractical, note it and rely on the green suite + the byte-equivalence of the rendered classes.)
- [ ] **Step 7: Commit** `feat: add <.badge> + Format.date/1 and adopt in member components`.

---

## Self-Review
**Spec coverage:** Phase A → Task 1 (manageable_member?/assignable_roles + rewire). Phase B → Tasks 2–3 (macro + 5 modules + thin router). Phase C → Task 4 (context full-coverage fix + flash + test flip + context test). Phase D → Task 5 (badge + Format.date + adopt). Deferred Minor (c) not folded (optional; DB TOTP check already the real proof) — noted, not required.
**Placeholder scan:** extraction steps say "move the verbatim body" (faithful relocation, the implementer reads + relocates) with exact new signatures + exact delegation lines given; all NEW code (macro, predicate, validation fix, badge, Format.date, tests) is spelled out. No TODO/TBD.
**Type consistency:** module names `Members.{Invites,JoinRequests,TwoFactor,Roster,Removal}` and their `fn(socket, params)` shape match the delegation lines in Tasks 2–3; `manageable_member?/2` (Task 1) is consumed by Roster/Removal (Task 3); `assignable_roles/0` (Task 1) consumed by Invites/Roster; `:incomplete_reassignment` produced by `delete_membership` (Task 4 context) is matched in `Removal.remove_member` (Task 4 handler); `<.badge>`/`Format.date/1` (Task 5) consumed in member_components.
**Behavior-preservation gate:** Tasks 1,2,3,5 assert the FULL suite stays green (no characterization test changes); only Task 4 edits a test (the deliberate flip) + adds a context test.

## Unresolved questions
- None blocking. One contingency flagged inline (Task 4 Step 3): if the nested `Repo.ensure_org_context` misbehaves, fall back to an inline sole-owned query — the added context test surfaces it immediately.
