# Members LiveView Decomposition + Orphan-Bug Fix — Design (Increment 2/2)

**Date:** 2026-07-14
**Part of:** web-layer code-quality overhaul (see `docs/superpowers/specs/2026-06-30-web-layer-code-quality-design.md`).
**Increment 1 (characterization) shipped:** master `58bc08a`, 201 tests green, all 24 members events pinned (`test/estimate_web/live/settings_live/members_test.exs` + `members_reassignment_test.exs`).

## Goal
Decompose the ~24-`handle_event` soup of `EstimateWeb.SettingsLive.Members` into a thin router + per-feature handler modules, consolidate the duplicated authorization, **fix the confirmed orphaned-project bug** the characterization pinned, and adopt two reusable view primitives. Behavior-identical except the deliberate bug fix.

## Constraints
- **No DB model changes** (no schema/migrations/columns/indexes). DB-neutral schema-module *code* (e.g. a new `Membership.assignable_roles/0` function) is allowed.
- **Behavior-identical** for the decomposition + convention sweep — the Increment-1 characterization suite (201 green) must stay green after each of those phases. The ONLY intended behavior change is the orphan-bug fix (Phase C), which flips exactly one pinned test.
- No new LiveComponents (locked decision). Handler logic moves to plain modules; the LiveView keeps `handle_event/3` as the Phoenix event entry point and delegates.
- `mix compile --warnings-as-errors --force` clean; `mix precommit` is the per-phase gate.
- Branch off master (`58bc08a`). One cluster = this branch; internally phased into legible commits.

## Locked decisions (from brainstorming)
1. **5 handler modules** (not 4): the reassignment state machine is isolated in its own file.
2. **Context-layer bug fix**: `delete_membership/2` validates full sole-owned coverage; never orphans regardless of caller.
3. **Scope** = decomposition + authz consolidation + bug fix + test updates + convention sweep.
4. **Convention sweep creates both primitives** (`<.badge>`, `Format.date/1`), minimal, in commits separate from the decomposition.

---

## Architecture

### Thin LiveView + 5 handler modules
`members.ex` retains: `mount/3`, `render/1` (unchanged — composes the existing `MemberComponents`/`ReassignmentModal`), the UI module attrs/guards (`@valid_tabs`, `@valid_reassign_tabs`), `switch_tab` (trivial, stays inline), and a slim `handle_event/3` whose clauses are **one-line delegations** to the modules. New modules live under `lib/estimate_web/live/settings_live/members/`:

| Module (`EstimateWeb.SettingsLive.Members.*`) | File | Events / functions |
|---|---|---|
| `Invites` | `members/invites.ex` | send_invite, generate_invite_code, copy_invite_code, dismiss_generated_code, copy_join_link, copy_invite_link, confirm_cancel_invite, dismiss_cancel_invite, cancel_invite (+ private `atomize_keys/1`) |
| `Roster` | `members/roster.ex` | change_member_role |
| `Removal` | `members/removal.ex` | confirm_remove_member, cancel_remove_member, remove_member, switch_reassign_tab, reassign_all, reassign_customer, reassign_project (+ `reset_removal_state/1`, `valid_eligible_member?/2`, `valid_sole_owned_project?/2`, `sole_owned_project_ids_for_customer/2`) |
| `JoinRequests` | `members/join_requests.ex` | approve_request, reject_request |
| `TwoFactor` | `members/two_factor.ex` | confirm_disable_2fa, cancel_disable_2fa, disable_user_2fa |

Each handler is `fn(socket, params) → {:noreply, socket}` — a pure socket transform (`put_flash`/`assign`/`push_event`/`to_form` all operate on the socket, so relocating the body out of the LiveView is behavior-neutral). `mount/3` calls `Removal.reset_removal_state(socket)`.

**Delegation shape** (in `members.ex`):
```elixir
def handle_event("send_invite", p, s), do: Invites.send_invite(s, p)
def handle_event("switch_tab", %{"tab" => tab}, s) when tab in @valid_tabs, do: {:noreply, assign(s, :current_tab, String.to_existing_atom(tab))}
def handle_event("switch_reassign_tab", %{"tab" => t}, s) when t in @valid_reassign_tabs, do: Removal.switch_reassign_tab(s, t)
def handle_event("remove_member", p, s), do: Removal.remove_member(s, p)
# ... one clause per event ...
def handle_event("switch_tab", _p, s), do: {:noreply, s}          # existing catch-alls stay
def handle_event("switch_reassign_tab", _p, s), do: {:noreply, s}
```
Guards (`when tab in @valid_*`) and the two invalid-value catch-alls stay in `members.ex` (the event entry point). Modules receive already-guarded values where a guard exists.

### Shared imports: `use EstimateWeb, :live_handlers`
Add a `:live_handlers` clause to `EstimateWeb` (`lib/estimate_web.ex`) bundling what every handler module needs, so modules start with one line and the convention is reusable for `show.ex`/`estimator`:
```elixir
def live_handlers do
  quote do
    import Phoenix.LiveView          # put_flash, push_event, ...
    import Phoenix.Component         # assign, assign_new, to_form
    import EstimateWeb.AuthHelpers   # require_admin, admin?
    unquote(verified_routes())       # ~p, url
  end
end
```
Each module: `use EstimateWeb, :live_handlers` + its own `alias Estimate.{Organizations, Portfolio, ...}`.

### Authz consolidation
- **"Not owner, not self" predicate** (currently duplicated in `change_member_role`, `confirm_remove_member`, `remove_member`) → single `Organizations.manageable_member?(membership, actor_user_id)`:
  ```elixir
  def manageable_member?(%Membership{} = m, actor_user_id),
    do: m.role != "owner" and m.user_id != actor_user_id
  def manageable_member?(_, _), do: false
  ```
  Call sites use it; the differing flash strings ("Not authorized" in role/confirm, "Cannot remove this member" in remove_member) stay at the call sites → behavior preserved.
- **Assignable-roles constant** (`~w(member admin)`, dup'd in Invites' send/generate + Roster) → `Membership.assignable_roles/0` returning `~w(admin member)` (a DB-neutral schema function alongside the existing `admin_roles/0`/`roles/0`).
- `require_admin/2` stays the shared `AuthHelpers` gate (unchanged), imported via `:live_handlers`.

### Orphan-bug fix (context, full-coverage validation)
`Estimate.Organizations.delete_membership/2` — `validate_reassignments/3` currently short-circuits `:ok` at `map_size == 0` and otherwise validates only the mappings *present*, so an empty **or partial** reassignment map deletes the member and `delete_all`s their sole-ownership rows, orphaning those projects. Fix:
- Remove the `map_size == 0 → :ok` clause.
- In `validate_reassignments`, compute the removed user's sole-owned project ids via `Portfolio.list_sole_owned_projects(removed_user_id, org_id)` (`Organizations` already aliases `Portfolio` schemas; `Portfolio` does not depend on `Organizations`, so no cycle) and add a guard: if any sole-owned id is **not** a key in `reassignments` → `{:error, :incomplete_reassignment}`. Existing `:invalid_project` / `:self_reassignment` / `:invalid_member` checks remain. (Empty map + no sole-owned projects → coverage vacuously holds → `:ok`, preserving that path.)
- `Removal.remove_member` adds `{:error, :incomplete_reassignment}` to its error match → flash **"Reassign all projects before removing."** (The happy path is unaffected: `confirm_remove_member` prefills the map to cover every sole-owned project, and the modal's Remove button is disabled until complete.)

### Convention sweep (new primitives, minimal)
- **`<.badge>` core component** in `core_components.ex`: a small pill matching the existing members styles — `attr :variant` (e.g. `:neutral | :success | :warning`), `attr :class`, `slot :inner_block`; renders the `text-[10px] px-1.5 py-0.5 … rounded-full font-medium` pill. Adopt at the 3 role/status pills in `member_components.ex` (lines ~159/164/168).
- **`Format.date/1`** in `EstimateWeb.Format`: `def date(%{} = d), do: Calendar.strftime(d, "%b %d, %Y")` (nil-safe). Adopt at the 3 `Calendar.strftime(…, "%b %d, %Y")` sites in `member_components.ex` (invite expiry ×2, request date). `time_ago/1` (relative "Active …") is left as-is.

---

## Testing strategy
- **Decomposition + authz consolidation + convention sweep are behavior-identical** → the Increment-1 characterization suite (201) is the safety net; run it after each phase. No new per-module unit tests (the suite already drives every event through the LiveView — the point of characterize-first). Adopting `<.badge>`/`Format.date` must keep the rendered markup equivalent enough that the suite stays green (the pills/dates aren't asserted char-by-char, but a broken render would fail mounts).
- **Bug fix changes behavior** →
  - **Flip** the pinned `CHARACTERIZATION: remove_member with EMPTY reassignments (button bypass)` test in `members_reassignment_test.exs` to assert the corrected outcome: flash "Reassign all projects before removing", the member is **still a member**, and `Portfolio.list_collaborators(proj_a.id)` still shows the leaver (NOT orphaned).
  - **Add** a context test for `Organizations.delete_membership/2`: empty map with sole-owned projects → `{:error, :incomplete_reassignment}` and nothing deleted; partial map → same; complete map → `:ok` (this last is already covered in `accounts_test.exs` — extend rather than duplicate).
- **Deferred Minor from Increment-1's final review** (only one remains — (a),(b),(d) were already applied in `58bc08a`): `disable_user_2fa` doesn't assert the `members` assign refreshed. Optional; fold in if cheap, else leave (DB TOTP check is the real proof).

## Phasing (legible commits within the branch)
- **Phase A — authz consolidation** (prep): add `Organizations.manageable_member?/2` + `Membership.assignable_roles/0`; rewire the current `members.ex` call sites. Behavior-identical, suite green.
- **Phase B — decomposition**: add `:live_handlers` to `estimate_web.ex`; extract the 5 modules; `members.ex` becomes the thin router. Behavior-identical, suite green.
- **Phase C — orphan-bug fix**: context change + `Removal.remove_member` flash + flip the bypass test + add the context test.
- **Phase D — convention sweep**: `<.badge>` + `Format.date/1` + adopt in `member_components.ex`. Behavior-identical, suite green; visual spot-check in the browser.

## Out of scope
- `project_live/show.ex`, `estimator_live/index.ex` (later clusters; they reuse the `:live_handlers` convention + `<.badge>`).
- `current_scope`/`app_shell` migration; streams/estimator-grid perf.
- Broad `Format` adoption beyond members' date sites; broad `<.badge>` rollout beyond members.
- The unpinned `members.ex` error/edge sub-branches noted by Increment-1's review (smtp send_invite path, "Could not …" flashes) — behavior-preserved by the refactor, not newly tested here.

## Risks
- Handler modules must emit byte-identical markup/events — the suite guards this; run it per phase.
- `:live_handlers` touches `estimate_web.ex` (a central file) — additive only.
- Cross-context `Organizations → Portfolio.list_sole_owned_projects/2` — verified safe (no cycle); if the plan finds a problem, fall back to inlining the sole-owned id query in `Organizations` (which already aliases `Project`/`ProjectCollaborator`).
- `<.badge>` is a new shared primitive — keep it minimal and match existing styles so no visual regression.

## Open questions
None — all four design forks resolved during brainstorming.
