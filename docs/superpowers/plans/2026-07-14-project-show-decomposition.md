# ProjectLive.Show Decomposition — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Before editing Elixir invoke `elixir-phoenix-guide:elixir-essentials`; before HEEx/components `elixir-phoenix-guide:phoenix-liveview-essentials`. Steps use checkbox (`- [ ]`).

**Goal:** Turn `EstimateWeb.ProjectLive.Show` (1568 lines, 40 handlers, ~600 inline-markup lines) into a thin router + 6 handler modules + 4 markup components, consolidate authorization, and fix bugs (a)/(b) + the admin/owner asymmetry. Behavior-identical except the named fixes.

**Design:** `docs/superpowers/specs/2026-07-14-project-show-decomposition-design.md`.

## Global Constraints
- **No DB model changes** (schema/migrations). DB-neutral context/schema *code* edits OK (e.g. `Portfolio.can_remove_collaborator?/4`).
- **Behavior-identical** for Tasks 2–6 → the 280-test characterization suite (`test/estimate_web/live/project_live/show_test.exs`) MUST stay green after each. Intended behavior changes: Task 1 (cross-org ids now graceful, bug b), Task 6 (bug a — still green, adds a test), Task 7 (asymmetry — updates/adds tests). Never edit a characterization test except where a task explicitly says to.
- No new LiveComponents. Handlers → `use EstimateWeb, :live_handlers` modules; markup → function components; events bubble to the LiveView (no `phx-target`).
- `mix format` (scope to changed files); `mix compile --warnings-as-errors --force` clean; full `mix test` green per task. Commit trailer: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- Branch `refactor/project-show-decompose` (spec committed at `71c10cd`).
- **1Password re-locks often** — if a `git commit` fails ("failed to write commit object" / "failed to fill whole buffer"), STOP and report BLOCKED (do NOT `--no-gpg-sign`; never kill the app). The controller will get it unlocked.

---

### Task 1 (Phase A): `Show.Authz` consolidation + cross-org fetch fix (bug b)

**Files:**
- Create `lib/estimate_web/live/project_live/show/authz.ex`
- Modify `lib/estimate_web/live/project_live/show.ex` (rewire the 13 `"Not authorized"` sites + 3 estimation-fetch guards + 2 not-found lookups)
- Modify `test/estimate_web/live/project_live/show_test.exs` (ADD cross-org graceful tests)

**Interfaces (produced):**
- `EstimateWeb.ProjectLive.Show.Authz.require_can_edit(socket, (-> {:noreply, socket})) :: {:noreply, socket}` (+ `require_can_delete/2`, `require_can_manage/2`) — runs the fun iff the matching `can_*` assign is true, else `{:noreply, put_flash(socket, :error, "Not authorized")}`.
- `fetch_authorized_estimation(socket, id) :: {:ok, %Estimation{}} | {:error, :wrong_project} | {:error, :not_found}` — `get_estimation!/2` **rescuing `Ecto.NoResultsError`** + cross-tenant `project_id` check.
- `find_deleted_estimation(socket, id) :: {:ok, e} | :error`.

- [ ] **Step 0:** Invoke `elixir-phoenix-guide:elixir-essentials`.
- [ ] **Step 1: Create `show/authz.ex`:**
```elixir
defmodule EstimateWeb.ProjectLive.Show.Authz do
  @moduledoc "Authorization + estimation-fetch helpers for ProjectLive.Show handler modules."
  import Phoenix.LiveView, only: [put_flash: 3]
  alias Estimate.EstimationEngine

  def require_can_edit(socket, fun), do: gate(socket.assigns.can_edit_project, socket, fun)
  def require_can_delete(socket, fun), do: gate(socket.assigns.can_delete_project, socket, fun)
  def require_can_manage(socket, fun), do: gate(socket.assigns.can_manage_collaborators, socket, fun)

  defp gate(true, _socket, fun), do: fun.()
  defp gate(_false, socket, _fun), do: {:noreply, put_flash(socket, :error, "Not authorized")}

  @doc "Fetch an estimation by id (rescuing a cross-org NoResultsError) and verify it belongs to the current project."
  def fetch_authorized_estimation(socket, id) do
    est = EstimationEngine.get_estimation!(id, socket.assigns.org_id)

    if est.project_id == socket.assigns.project.id,
      do: {:ok, est},
      else: {:error, :wrong_project}
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
  end

  def find_deleted_estimation(socket, id) do
    case Enum.find(socket.assigns.deleted_estimations, &(&1.id == id)) do
      nil -> :error
      est -> {:ok, est}
    end
  end
end
```
- [ ] **Step 2: Rewire `show.ex` to use the helpers** (add `import EstimateWeb.ProjectLive.Show.Authz`). Behavior-identical for same-org ids; cross-org ids become graceful. Per site:
  - Each handler whose OUTER gate is `if socket.assigns.can_edit_project do … else "Not authorized"` → wrap the body in `require_can_edit(socket, fn -> … end)` (drop the inline `else "Not authorized"`). Same for `can_delete_project`→`require_can_delete`, `can_manage_collaborators`→`require_can_manage`. Handlers: `save` (can_edit), `delete_project` (can_delete — keep the inner name-match), `create_estimation` (can_edit — keep inner roles/dispatch), `set_current_estimation`/`delete_estimation` (can_edit/can_delete), `restore_estimation`/`permanent_delete_estimation` (can_delete), `add_collaborator`/`change_collaborator_role` (can_manage — keep inner predicates), `copy_agent_prompt` etc. — read each and preserve inner logic; the helper replaces only the outer `can_*` + flash.
  - **`set_current_estimation`** — replace the inline `estimation = get_estimation!(id, org_id); if estimation.project_id != project.id do "Not authorized" else case set_current…` with:
```elixir
    require_can_edit(socket, fn ->
      case fetch_authorized_estimation(socket, id) do
        {:ok, estimation} ->
          case EstimationEngine.set_current_estimation(estimation) do
            {:ok, _} ->
              estimations = EstimationEngine.list_estimations(socket.assigns.project.id)
              current = EstimationEngine.get_estimation!(estimation.id, socket.assigns.org_id)
              {:noreply, socket |> assign(:estimations, estimations) |> assign(:current_estimation, current)}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Could not set current estimation")}
          end

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Not authorized")}
      end
    end)
```
  (Keeps the defensive `{:error, _}` set-current branch — decision (c). `{:error, :wrong_project}` and `{:error, :not_found}` both → "Not authorized", matching the pre-existing same-org guard and making cross-org graceful.)
  - **`delete_estimation`** — replace its `get_estimation!` + `project_id` guard with `fetch_authorized_estimation/2`; keep the `is_current` → "Cannot delete current estimation" and ok → "Estimation moved to trash" branches; `{:error, _}` (wrong_project/not_found) → "Not authorized" (matching the current guard).
  - **`dispatch_create("copy", …)`** — where it fetches the source estimation and checks `source_estimation.project_id == project.id`, route the fetch through `fetch_authorized_estimation/2`; map `{:error, _}` to the existing copy failure (→ "Could not create estimation"). (This is what makes cross-ORG copy graceful instead of crashing.)
  - **`restore_estimation` / `permanent_delete_estimation`** — replace the `Enum.find(deleted_estimations, …)` + not-found with `find_deleted_estimation/2` (`:error` → "Estimation not found").
- [ ] **Step 3: ADD cross-org graceful tests** to `show_test.exs` (new behavior from bug b — nothing flips, these are new):
```elixir
  describe "cross-org estimation ids are handled gracefully (bug b)" do
    setup :setup_project

    test "copy from a foreign-org estimation flashes an error, no crash", %{conn: conn, org: org, owner: owner, project: project} do
      # a second org + project + estimation the owner can't see
      %{user: other} = user_with_organization_fixture()
      other_project = project_fixture(nil, other)
      foreign = estimation_fixture(other_project)

      {:ok, lv, _} = live(log_in_user(conn, owner), project_path(org, project))
      # drive create with source=copy + the foreign id (via the modal or a crafted payload):
      render_click(lv, "open_estimation_modal", %{})
      render_click(lv, "set_estimation_source", %{"source" => "copy"})
      html =
        render_submit(form(lv, ~s(form[phx-submit="create_estimation"]), %{
          "estimation" => %{"name" => "X"},
          "source_estimation_id" => foreign.id
        }))
      assert html =~ "Could not create estimation"
      assert Process.alive?(lv.pid)
    end

    test "set_current with a foreign-org id flashes Not authorized, no crash", %{conn: conn, org: org, owner: owner, project: project} do
      %{user: other} = user_with_organization_fixture()
      other_project = project_fixture(nil, other)
      foreign = estimation_fixture(other_project)
      {:ok, lv, _} = live(log_in_user(conn, owner), project_path(org, project))
      assert render_click(lv, "set_current_estimation", %{"id" => foreign.id}) =~ "Not authorized"
      assert Process.alive?(lv.pid)
    end
  end
```
  (Confirm the exact create payload shape from `new_estimation_modal.ex`; adjust if the modal drives `source_estimation_id` differently. The key assertions: graceful flash + `Process.alive?`.)
- [ ] **Step 4:** `mix format`; full `mix test` — **282** (280 + 2 new), all green; `mix compile --warnings-as-errors --force` clean.
- [ ] **Step 5: Commit** `refactor: consolidate project-show authz into Show.Authz + fix cross-org estimation crash`.

---

### Task 2 (Phase B1): extract `Details` + `DangerZone` + `Dashboard` handler modules

**Files:** Create `show/details.ex`, `show/danger_zone.ex`, `show/dashboard.ex`; modify `show.ex` (delegate).

**Interfaces (produced):** `Details`: `validate/2`, `save/2`. `DangerZone`: `confirm_delete_project/2`, `cancel_delete_project/2`, `validate_delete_confirmation/2`, `delete_project/2`. `Dashboard`: `set_dashboard_tab/2`. Each `(socket, params) → {:noreply, socket}`.

- [ ] **Step 0:** Invoke `elixir-phoenix-guide:phoenix-liveview-essentials`.
- [ ] **Step 1:** Create the 3 modules under `lib/estimate_web/live/project_live/show/`, each `use EstimateWeb, :live_handlers`, `import EstimateWeb.ProjectLive.Show.Authz` (for the `require_can_*` used by `save`/`delete_project`), `alias Estimate.Portfolio`. Move the VERBATIM bodies of the current `handle_event` clauses, renaming `handle_event("<e>", <params>, socket)` → `<e>(socket, <params>)`. (Bodies already use `require_can_*` after Task 1.) Add a `@moduledoc` naming the assigns each reads/writes.
- [ ] **Step 2:** In `show.ex` add `alias EstimateWeb.ProjectLive.Show.{Details, DangerZone, Dashboard}` and replace those clauses with one-line delegations, e.g. `def handle_event("save", p, s), do: Details.save(s, p)`. (Leave the other clusters' clauses for later tasks.)
- [ ] **Step 3:** `mix format`; full `mix test` — 282 green (behavior-identical); compile clean.
- [ ] **Step 4: Commit** `refactor: extract project-show details/danger-zone/dashboard handlers`.

---

### Task 3 (Phase B2): extract `EstimationModal` handler module

**Files:** Create `show/estimation_modal.ex`; modify `show.ex` (delegate).

**Interfaces:** `open_estimation_modal/2`, `close_estimation_modal/2`, `set_estimation_source/2`, `validate_estimation/2`, `add_modal_role/2`, `remove_modal_role/2`, `reorder_modal_roles/2`, `reset_modal_roles/2`, `create_estimation/2`, `json_file_uploaded/2`, `download_json_schema/2`, `copy_agent_prompt/2` — plus the private create/modal helpers move with it (`dispatch_create`, `build_estimation_attrs`, `roles_valid?`, `collect_role_attrs`, `build_modal_roles_from_templates`, `maybe_*`, `parse_decimal`, and the json glue `do_validate_json`/`validate_json` if they're modal-only — confirm each private fn's callers before moving; a helper used by another cluster stays or moves to a shared spot).

- [ ] **Step 0:** Invoke `elixir-phoenix-guide:phoenix-liveview-essentials`.
- [ ] **Step 1:** Create `show/estimation_modal.ex` (`use EstimateWeb, :live_handlers`, `import Show.Authz`, `alias Estimate.{EstimationEngine, Portfolio, Templates}` + whatever the bodies use — trim to what's referenced). Move the VERBATIM bodies + the modal-only private helpers. `create_estimation`'s copy branch already routes its source fetch through `fetch_authorized_estimation/2` (Task 1). **Before moving each private helper, grep its callers** (`grep -n "helper_name" show.ex`) — if only modal handlers call it, move it; if shared, leave it in `show.ex` or note it for a shared module.
- [ ] **Step 2:** Delegate the 12 events in `show.ex`.
- [ ] **Step 3:** `mix format`; full `mix test` — 282 green; compile clean (watch unused aliases).
- [ ] **Step 4: Commit** `refactor: extract project-show estimation-modal handlers`.

---

### Task 4 (Phase B3): extract `Estimations` handler module (list + trash)

**Files:** Create `show/estimations.ex`; modify `show.ex`.

**Interfaces:** `set_current_estimation/2`, `confirm_delete_estimation/2`, `cancel_delete_estimation/2`, `delete_estimation/2`, `toggle_trash/2`, `restore_estimation/2`, `confirm_permanent_delete/2`, `cancel_permanent_delete/2`, `permanent_delete_estimation/2`.

- [ ] **Step 1:** Create `show/estimations.ex` (`use EstimateWeb, :live_handlers`, `import Show.Authz`, `alias Estimate.EstimationEngine`). Move the VERBATIM bodies (they already use `require_can_*`/`fetch_authorized_estimation`/`find_deleted_estimation` from Task 1). `@moduledoc` the assign contract.
- [ ] **Step 2:** Delegate in `show.ex`.
- [ ] **Step 3:** `mix format`; full `mix test` — 282 green; compile clean.
- [ ] **Step 4: Commit** `refactor: extract project-show estimations (list + trash) handlers`.

---

### Task 5 (Phase B4): extract `Collaborators` handler module

**Files:** Create `show/collaborators.ex`; modify `show.ex`.

**Interfaces:** `collaborator_form_change/2`, `open_member_dropdown/2`, `close_member_dropdown/2`, `select_member/2`, `clear_selected_member/2`, `add_collaborator/2`, `change_collaborator_role/2`, `confirm_remove_collaborator/2`, `cancel_remove_collaborator/2`, `remove_collaborator/2` + the private `reload_collaborators/2` helper.

- [ ] **Step 1:** Create `show/collaborators.ex` (`use EstimateWeb, :live_handlers`, `import Show.Authz`, `alias Estimate.Portfolio`). Move the VERBATIM bodies + `reload_collaborators/2` (make it a module-private `defp`). The bodies use `Portfolio.can_change_role?/3` + `can_remove_collaborator?/4` (unchanged in this task) and `require_can_manage`. `@moduledoc` the assign contract.
- [ ] **Step 2:** Delegate in `show.ex`. After this task `show.ex`'s `handle_event/3` is entirely one-line delegations. Report the new line count.
- [ ] **Step 3:** `mix format`; full `mix test` — 282 green; compile clean.
- [ ] **Step 4: Commit** `refactor: extract project-show collaborators handlers`.

---

### Task 6 (Phase C): extract the 4 markup components

**Files:** Create `project_live/components/{overview_tab,estimations_tab,delete_project_modal,remove_collaborator_modal}.ex`; modify `show.ex` (`render/1` composes them; delete the moved `defp tab_overview`/`tab_estimations` + the two inline `<.modal>` blocks).

- [ ] **Step 0:** Invoke `elixir-phoenix-guide:phoenix-liveview-essentials`.
- [ ] **Step 1:** For each, create a function component module (`use EstimateWeb, :html`) with the markup moved VERBATIM and `attr`s declared for every assign it reads. Map:
  - `OverviewTab.overview_tab/1` ← `defp tab_overview` (show.ex:225-425) — reads `project`, `form`, `current_estimation`, `dashboard_tab`, `can_edit_project`, `can_delete_project`, `role_templates`/`currencies` as used, `delete_impact`? (danger-zone button). Declare each `attr`.
  - `EstimationsTab.estimations_tab/1` ← `defp tab_estimations` (show.ex:427-~520) — reads `estimations`, `current_estimation`, `can_edit_project`, `can_delete_project`, `show_trash`, `deleted_estimations`.
  - `DeleteProjectModal.delete_project_modal/1` ← inline modal (show.ex:126-183) — reads `deleting_project`, `delete_impact`, `delete_confirmation_input`, `project`.
  - `RemoveCollaboratorModal.remove_collaborator_modal/1` ← inline modal (show.ex:184-223) — reads `removing_collaborator`.
  Keep every `phx-*`/`:if`/value binding byte-identical (events keep bubbling to the LiveView).
- [ ] **Step 2:** In `show.ex`: `import` the 4 new component modules; replace the `defp tab_overview(...)`/`tab_estimations(...)` definitions AND their call sites with `<.overview_tab .../>`/`<.estimations_tab .../>`; replace the two inline `<.modal>` blocks with `<.delete_project_modal .../>`/`<.remove_collaborator_modal .../>`, passing the assigns each declares. Delete the now-moved `defp`s. `render/1` should drop to ~200 lines.
- [ ] **Step 3:** `mix format`; full `mix test` — 282 green (the suite asserts events/flashes/assigns/DOM ids, not full markup; a dropped `:if`/event would fail — that's the guard). Compile clean.
- [ ] **Step 4 (visual, best-effort):** `preview_start` the dev server; confirm the project show page compiles/renders (no seeded-session screenshot needed — rely on the green suite + byte-equivalent markup). Don't fight the preview.
- [ ] **Step 5: Commit** `refactor: extract project-show overview/estimations tabs + modals into components`.

---

### Task 7 (Phase D+E): bug (a) dashboard atom-map + admin/owner asymmetry fix

**Files:** Modify `show/dashboard.ex` (bug a); `lib/estimate/portfolio.ex` (`can_remove_collaborator?/4`); `test/estimate_web/live/project_live/show_test.exs` (tests).

- [ ] **Step 0:** Invoke `elixir-phoenix-guide:elixir-essentials` and `superpowers:test-driven-development`.
- [ ] **Step 1 (bug a — Dashboard):** In `show/dashboard.ex`, replace the guarded `String.to_existing_atom` handler with the explicit map:
```elixir
  @dashboard_tabs %{"by_role" => :by_role, "by_epic" => :by_epic, "by_priority" => :by_priority}

  def set_dashboard_tab(socket, %{"tab" => tab}) do
    case @dashboard_tabs do
      %{^tab => atom} -> {:noreply, assign(socket, :dashboard_tab, atom)}
      _ -> {:noreply, socket}
    end
  end
```
  (Removes the `@allowed_dashboard_tabs` guard + `to_existing_atom` + the fallback clause — the map handles all cases. If `@allowed_dashboard_tabs` was in `show.ex`, remove it there.)
- [ ] **Step 2 (bug a test):** the existing dashboard test stays green. ADD a test proving no atom-crash without a seeded estimation:
```elixir
    test "set_dashboard_tab handles by_epic/by_priority with no current estimation (no atom crash)", %{conn: conn, org: org, owner: owner, project: project} do
      {:ok, lv, _} = live(log_in_user(conn, owner), project_path(org, project))   # NO estimation seeded
      render_click(lv, "set_dashboard_tab", %{"tab" => "by_epic"})
      assert assigns(lv).dashboard_tab == :by_epic
      assert Process.alive?(lv.pid)
    end
```
  (Also simplify the pre-existing dashboard test if it seeds an estimation solely to avoid the crash — it no longer needs to; keep it green either way.)
- [ ] **Step 3 (asymmetry — Portfolio):** change `can_remove_collaborator?/4` (portfolio.ex:331-337):
```elixir
  def can_remove_collaborator?(can_manage, current_user, _current_collaborator, collab) do
    cond do
      collab.user_id == current_user.id -> false
      true -> can_manage
    end
  end
```
  (`current_collaborator` now unused → `_`-prefixed; 4-arity signature kept so `collaborators_tab.ex`'s `defdelegate`/call site are untouched. The `remove_collaborator` handler's `Enum.count(owners) <= 1 -> "Cannot remove the last project owner"` cond is UNCHANGED and now activates for admins.)
- [ ] **Step 4 (asymmetry tests):** UPDATE/ADD in the collaborators describe:
```elixir
    test "an org admin (non-collaborator) can remove a non-last owner", %{conn: conn, org: org, owner: owner, project: project} do
      # a 2nd owner so removal doesn't hit the last-owner guard
      %{user: owner2} = add_collab(project, org, "owner")
      admin = user_fixture(); _ = membership_fixture(admin, org, "admin")
      {:ok, lv, _} = live(log_in_user(conn, admin), ~p"/org/#{org.id}/projects/#{project.id}/collaborators")
      collab = Enum.find(assigns(lv).collaborators, & &1.user_id == owner2.id)
      render_click(lv, "confirm_remove_collaborator", %{"id" => collab.id})
      html = render_click(lv, "remove_collaborator", %{})
      assert html =~ "Collaborator removed"
      refute owner2.id in Enum.map(Portfolio.list_collaborators(project.id), & &1.user_id)
    end

    test "an org admin removing the SOLE owner is blocked (last-owner guard now live)", %{conn: conn, org: org, owner: owner, project: project} do
      admin = user_fixture(); _ = membership_fixture(admin, org, "admin")
      {:ok, lv, _} = live(log_in_user(conn, admin), ~p"/org/#{org.id}/projects/#{project.id}/collaborators")
      owner_collab = Enum.find(assigns(lv).collaborators, & &1.role == "owner")
      render_click(lv, "confirm_remove_collaborator", %{"id" => owner_collab.id})
      html = render_click(lv, "remove_collaborator", %{})
      assert html =~ "Cannot remove the last project owner"
      assert owner.id in Enum.map(Portfolio.list_collaborators(project.id), & &1.user_id)  # still there
    end
```
  If any EXISTING Task-6 collaborator test asserted that an admin CAN'T remove an owner (the old behavior), UPDATE it to the new behavior + note it. The self-removal test stays.
- [ ] **Step 5:** `mix format`; full `mix test` — all green (282 + the new asymmetry/atom tests, minus any updated); `mix compile --warnings-as-errors --force` clean.
- [ ] **Step 6: Commit** `fix: dashboard tab atom-map + let org admins remove owner collaborators (last-owner guard now active)`.

---

## Self-Review
**Spec coverage:** Phase A→Task 1 (Show.Authz + bug b). Phase B→Tasks 2–5 (6 handler modules). Phase C→Task 6 (4 markup components). Phase D+E→Task 7 (bug a + asymmetry). The reconciliation (keep+activate (d); keep defensive (c)) is realized: no branch deletions; the last-owner cond is untouched and activates via the Task-7 predicate change.
**Placeholder scan:** new code (Show.Authz, atom-map, can_remove_collaborator?) is complete; extractions are "move verbatim + delegate" with exact signatures + delegation examples; tests are concrete. The only "confirm against source" notes are the modal create-payload shape (T1/T3) and per-helper caller checks before moving (T3) — real verification steps, not placeholders.
**Type consistency:** `Show.Authz` fns (require_can_*/fetch_authorized_estimation/find_deleted_estimation) produced in T1, consumed in T1 rewire + T3/T4 modules. Handler-module fns `(socket, params)` match the `show.ex` delegation lines. `can_remove_collaborator?/4` keeps its 4-arity signature (T7) so `collaborators_tab.ex` is untouched.
**Behavior gate:** T2–T6 assert the full suite stays green (no test edits); T1 adds 2 tests (bug b), T7 adds/updates tests (bug a + asymmetry).

## Unresolved questions
- None blocking. Confirm-against-source items are flagged inline (modal create payload; private-helper callers before moving). Decision (c) "keep the defensive set_current {:error} branch" is per the approved spec.
