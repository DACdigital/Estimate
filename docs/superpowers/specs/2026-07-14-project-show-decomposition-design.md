# ProjectLive.Show Decomposition + Authz Consolidation + Bug Fixes — Design

**Date:** 2026-07-14
**Part of:** web-layer code-quality overhaul (`docs/superpowers/specs/2026-06-30-web-layer-code-quality-design.md`).
**Prerequisite shipped:** ProjectLive.Show **characterization** (master `e5eb954`, `test/estimate_web/live/project_live/show_test.exs`, 280 tests, all 38 events pinned).

## Goal
Turn the god LiveView `EstimateWeb.ProjectLive.Show` (1568 lines, 40 handlers, ~600 lines of inline render markup) into a thin router + per-feature handler modules + extracted markup components; consolidate the duplicated authorization; and fix the highest-value latent bugs the characterization surfaced. Behavior-identical except the deliberate fixes.

## Constraints
- **No DB model changes** (no schema/migrations/columns/indexes). DB-neutral schema/context *code* changes are allowed (e.g. editing `Portfolio.can_remove_collaborator?/4`).
- **Behavior-identical** for the decomposition/markup/authz-consolidation phases → the 280-test characterization suite MUST stay green after each. The intended behavior changes are scoped to the named bug/asymmetry fixes, each covered by a new/updated test.
- No new LiveComponents. Handler logic → plain `:live_handlers` modules; markup → private/function components. `members` template reused (validated sound).
- `mix compile --warnings-as-errors --force` clean; `mix precommit` per phase. Branch off master (`e5eb954`).

## Locked decisions (from brainstorming)
1. **Scope:** handlers + inline markup (full thin router).
2. **Bug fixes this increment:** (a) `set_dashboard_tab` atom-crash, (b) cross-org `get_estimation!` crash, and the **admin/owner asymmetry**. (e)/(f) deferred.
3. **Dead-branch reconciliation (important):** fixing the asymmetry (org admins may remove owners) makes the "Cannot remove the last project owner" branch (d) **reachable and necessary** — it becomes the guard preventing an admin from orphaning a project's last owner. So (d) is **kept and activated**, not removed. (c) `set_current {:error}` is left in place as defensive error-handling consistent with its 5 sibling handlers (removing a lone handler's `{:error}` clause would risk a `CaseClauseError` on any future change to `set_current_estimation/1` — a robustness regression for negligible gain). **Net: no branch deletions; (d) goes live via the asymmetry fix.**

---

## Architecture

### Thin router (`show.ex`)
Retains `mount/3`, `handle_params/3`+`apply_action/3`, `render/1` (composing components), and a slim `handle_event/3` delegating each event one-line to a module. ~200 lines.

### 6 handler modules (`lib/estimate_web/live/project_live/show/`, `use EstimateWeb, :live_handlers`)
Each `fn(socket, params) → {:noreply, socket}`, verbatim relocation. Add a per-module `@moduledoc` line naming the assigns it reads/writes (the assign contract is implicit — opus's suggestion for the bigger LVs).

| Module | Events | Notes |
|---|---|---|
| `Details` | validate, save | project-details form |
| `DangerZone` | confirm_delete_project, cancel_delete_project, validate_delete_confirmation, delete_project | delete-by-name state machine |
| `Dashboard` | set_dashboard_tab | **bug (a) fix lives here** |
| `EstimationModal` | open/close_estimation_modal, set_estimation_source, validate_estimation, add/remove/reorder/reset_modal_role, create_estimation, json_file_uploaded, download_json_schema, copy_agent_prompt (+ private create helpers: dispatch_create, build_estimation_attrs, roles_valid?, collect_role_attrs, build_modal_roles_from_templates, maybe_* currency/copy, parse_decimal, json glue) | the biggest cluster |
| `Estimations` | set_current_estimation, confirm/cancel_delete_estimation, delete_estimation, toggle_trash, restore_estimation, confirm/cancel_permanent_delete, permanent_delete_estimation | list + trash (E+F merged) |
| `Collaborators` | collaborator_form_change, open/close_member_dropdown, select_member, clear_selected_member, add_collaborator, change_collaborator_role, confirm/cancel_remove_collaborator, remove_collaborator (+ `reload_collaborators` helper) | member-picker + add/change/remove |

### 4 markup components (`lib/estimate_web/live/project_live/components/`)
Extract the inline render markup into function components (verbatim markup relocation, same events bubbling to the LiveView — no `phx-target`):
- `OverviewTab` — from `tab_overview/1` (show.ex:225-425: dashboard + project-details form + danger-zone button).
- `EstimationsTab` — from `tab_estimations/1` (show.ex:427-~600: estimations list + trash section).
- `DeleteProjectModal` — from the inline `<.modal>` (show.ex:126-183).
- `RemoveCollaboratorModal` — from the inline `<.modal>` (show.ex:184-223).
`render/1` composes these + the 3 pre-existing components (`new_estimation_modal`, `collaborators_tab`, `estimation_dashboard`). The extracted components declare the `attr`s they need (the assigns they read); events keep bubbling to the LiveView, which delegates to the handler modules.

### Authz consolidation — `EstimateWeb.ProjectLive.Show.Authz`
A small helper module imported by the handler modules (parallel to `AuthHelpers.require_admin/2`), consolidating the 13 inline `"Not authorized"` flashes + 2 dup'd patterns:
- `require_can_edit(socket, fun)` / `require_can_delete(socket, fun)` / `require_can_manage(socket, fun)` — run `fun.()` iff the matching `socket.assigns.can_*` is true, else `{:noreply, put_flash(socket, :error, "Not authorized")}`. Handlers with an *additional* inner gate (e.g. `delete_project`'s name-match, `change_collaborator_role`'s `can_change_role?`, `remove_collaborator`'s cond) keep that inner logic; the helper replaces only the outer `can_*` check + flash.
- `fetch_authorized_estimation(socket, id) :: {:ok, %Estimation{}} | {:error, :not_found} | {:error, :wrong_project}` — one place that does `get_estimation!/2` **rescuing `Ecto.NoResultsError`** (⇒ **bug (b) fix**) and the cross-tenant `estimation.project_id == project.id` check (dedups 3 sites: set_current, delete_estimation, dispatch_create copy). Callers map `:not_found`/`:wrong_project` → the existing flash strings ("Could not …"/"Not authorized") so external behavior is unchanged for same-org ids and *graceful (not a crash)* for cross-org ids.
- `find_deleted_estimation(socket, id) :: {:ok, e} | :error` — the `Enum.find(deleted_estimations, …)` + not-found lookup (dedups restore + permanent_delete; keeps the "Estimation not found" flash).

### Bug fixes
- **(a) `Dashboard.set_dashboard_tab`** — replace `String.to_existing_atom(tab)` with an explicit map:
  ```elixir
  @dashboard_tabs %{"by_role" => :by_role, "by_epic" => :by_epic, "by_priority" => :by_priority}
  def set_dashboard_tab(socket, %{"tab" => tab}) do
    case @dashboard_tabs do
      %{^tab => atom} -> {:noreply, assign(socket, :dashboard_tab, atom)}
      _ -> {:noreply, socket}
    end
  end
  ```
  Removes the load-order/atom-exhaustion crash on client input. The existing `@allowed_dashboard_tabs` guard + fallback clause collapse into this. Char test still passes (`by_epic` → `:by_epic`) and no longer needs a seeded estimation to avoid a crash.
- **(b) cross-org crash** — handled centrally by `fetch_authorized_estimation/2`'s rescue (above). Applies to set_current/delete/copy.
- **Asymmetry fix** — `Portfolio.can_remove_collaborator?/4` (portfolio.ex:331-337): change the owner-target branch so an org-admin **or** owner-collaborator may remove an owner:
  ```elixir
  def can_remove_collaborator?(can_manage, current_user, _current_collaborator, collab) do
    cond do
      collab.user_id == current_user.id -> false   # never remove self
      true -> can_manage                            # org-admin OR owner-collab (both set can_manage)
    end
  end
  ```
  (`current_collaborator` becomes unused → `_`-prefixed; keep the 4-arity signature so `collaborators_tab.ex`'s `defdelegate` + call site are untouched.) The `remove_collaborator` handler's cond is UNCHANGED — its existing `collab.role == "owner" && Enum.count(owners) <= 1 -> "Cannot remove the last project owner"` clause now **activates**, preventing an admin from orphaning the last owner. `can_change_role?/3` is already symmetric (uses `can_manage`), so no change there.

---

## Testing strategy
- **Phases A/B/C (authz-consolidation, handler decomposition, markup extraction)** are behavior-identical → the 280 characterization suite is the safety net; run it after each. (Authz consolidation via `fetch_authorized_estimation` also lands bug (b) — see below.)
- **Bug (b)** (cross-org → graceful, lands in Phase A): ADD tests — cross-org `source_estimation_id` on copy → "Could not create estimation" (not a crash); cross-org id on set_current/delete → "Not authorized"/graceful. (The characterization deliberately did NOT pin the crash, so nothing flips; these are new tests of the fixed behavior.)
- **Bug (a)** (Phase D): the existing dashboard test stays green; ADD a test that `by_epic`/`by_priority` work on a project with NO current estimation (proving the atom-map removed the load-order crash).
- **Asymmetry fix** (Phase E, behavior change): UPDATE/ADD collaborator tests — an org-admin (non-collaborator) removes a NON-last owner → "Collaborator removed" (newly allowed); an org-admin removes the SOLE owner → "Cannot remove the last project owner" (newly reachable guard); the self-removal + owner-collab paths stay as pinned. The `collaborators_tab` render now shows the remove button to org-admins on owner rows.
- No new per-module unit tests for the pure relocation — the characterization suite exercises every event through the LiveView (the value of characterize-first).

## Phasing (legible commits)
- **Phase A — authz consolidation (+ bug b):** add `Show.Authz` (`require_can_*`, `fetch_authorized_estimation` w/ cross-org rescue, `find_deleted_estimation`); rewire the current `show.ex` sites. Behavior-identical except cross-org ids now graceful; add the bug-(b) tests. Suite green.
- **Phase B — handler decomposition:** extract the 6 modules; `show.ex` handle_event → delegations. Behavior-identical. Suite green.
- **Phase C — markup extraction:** extract the 4 components; `render/1` composes. Behavior-identical (markup byte-equivalent). Suite green.
- **Phase D — bug (a):** `Dashboard` atom-map; add the no-crash test. Suite green.
- **Phase E — asymmetry fix:** `Portfolio.can_remove_collaborator?/4`; update/add collaborator tests. Behavior change, suite green with the updated tests.

## Out of scope
- Latent items (e) [no independent RLS on `update_collaborator_role`] and (f) [permission assigns cached at mount, not invalidated on concurrent change] — architectural/concurrency; a later focused security/concurrency pass.
- `estimator_live/index.ex` (next cluster; streams + grid perf).
- Broad `Format`/`<.badge>` adoption beyond what already fits.

## Risks
- **Markup extraction must stay byte-equivalent** — the 280 suite asserts events/flashes/assigns/DOM ids, not full markup, so a class reshuffle is fine but a dropped `:if`/event would fail a test; run the suite per component.
- **`fetch_authorized_estimation` must preserve the exact external flash mapping** for same-org ids (only the cross-org path changes from crash→graceful) — pin with the existing + new tests.
- **Asymmetry fix changes `can_remove_collaborator?`**, consumed by both the handler AND `collaborators_tab.ex` render (button visibility) — the render change (admins see the remove button on owner rows) is intended; verify no characterization test asserts its absence.
- The `EstimationModal` cluster is large (~13 events + many private helpers) — extract carefully; the suite covers all its events.

## Open questions
- None blocking. The (c) "leave defensive branch" refinement is flagged in Locked-decision 3 for your review; say if you'd rather delete it.
