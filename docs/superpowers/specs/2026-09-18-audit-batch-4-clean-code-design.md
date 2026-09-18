# Audit batch 4 — clean code: persistence helpers, templates LiveView, small cleanups, MCP tools

Date: 2026-09-18. Follows batches 1–3 (`docs/superpowers/specs/2026-09-02-audit-batch-1-security-design.md`, `…-batch-2-security-design.md`, `2026-09-16-audit-batch-3-followups-decomposition-perf-design.md`). Addresses the audit's DRY/clean-code findings and the follow-ups carried from batch 3. Password-reset / email-confirmation work stays parked.

Four sub-batches, in order, each on its own branch with its own plan, subagent-driven, reviewed, then **merged locally to `main` (not pushed)**:

- **4A** persistence helpers — `Repo.insert_each/2`, `Repo.reorder_children/4`, adopted everywhere.
- **4B** `templates_live/show.ex` — characterize (0 tests today) → decompose like the estimator → close the authorization gaps.
- **4C** small cleanups — changeset helper, `Settings` idiom, `filtered_epics` home, `Grid.refresh_editing` fallback, shared test sort helper.
- **4D** MCP tools — `Read` wrapper, `Authz.edit_gate/2`, `Serializers.attrs/2`.

Test rules from `AGENTS.md` apply throughout: no `Process.sleep`, diverge-then-assert for characterization tests. No schema migrations in this batch. Every sub-batch except the named behaviour changes below is behaviour-preserving and gated by the existing suite (791 tests at `8529d80`).

---

## 4A — persistence helpers

### A1. `Estimate.Repo.insert_each/2`

```elixir
@spec insert_each(Enumerable.t(), (term -> Ecto.Changeset.t())) ::
        {:ok, [struct]} | {:error, Ecto.Changeset.t()}
```

Inserts each changeset in order, returns the inserted structs in the same order, halts on the first `{:error, changeset}`. No transaction of its own: callers already run inside `Repo.transaction`/`Ecto.Multi.run` or accept partial inserts today (no behaviour change). Lives on `Estimate.Repo` next to `ensure_org_context/1` — the module already hosts cross-cutting persistence helpers, and every caller aliases `Repo`. (Rejected: a separate `Estimate.Repo.Batch` module — one more alias for two functions.)

**Adoption (11 loops → one call each; the caller's `with` composes children):**

| Site | Today | After |
|---|---|---|
| `accounts.ex` `seed_default_currencies/1` | `reduce_while :ok` | `with {:ok, _} <- Repo.insert_each(defaults, &Currency.changeset(%Currency{}, Map.put(&1, :organization_id, org_id))), do: :ok` |
| `accounts.ex` `seed_default_role_templates/1` | `reduce_while` with nested rate insert | `insert_each` for the templates, then `Enum.zip(defaults, templates)` and `maybe_create_template_rate/3` per pair with `Enum.find_value(pairs, :ok, fn pair -> match?({:error, _}, result = rate.(pair)) && result end)`-style first-error short-circuit (private `first_error/2` in `Accounts`) |
| `templates.ex` `create_template_with_epics/2` (`:epics_tasks` Multi step) + `insert_template_tasks/2` | two `reduce_while` | epics via `insert_each`, then per epic `insert_each` of its tasks inside the same Multi step |
| `portfolio.ex` `copy_roles_from_templates/2` | `reduce_while :ok` | `with {:ok, _} <- Repo.insert_each(...)`, `:ok` |
| `estimation_engine/copy.ex` `:roles` step | `reduce_while` building `old_id => new_id` | `insert_each` then `Map.new(Enum.zip(old_roles, new_roles), fn {o, n} -> {o.id, n.id} end)` |
| `copy.ex` `copy_epics_with_estimates/3`, `copy_tasks_with_estimates/3`, `copy_estimates/3` | three nested `reduce_while` | `insert_each` per level; children in the callback's `with` |
| `estimation_engine/tasks.ex` `create_task_with_estimates` `:estimates` step | `reduce_while` | `insert_each` (keeps the `foreign_key_constraint(:estimation_role_id)` in the changeset fn) |
| `estimation_engine/import.ex` `insert_epics_and_tasks/2`, `insert_tasks/2` | two `reduce_while` | `insert_each` per level |
| `estimation_engine/estimations.ex` `create_estimation/1` default roles | `reduce_while` | `insert_each` over `Enum.with_index(defaults)` |
| `estimation_engine/roles.ex` `insert_roles/2` | `reduce_while` + reverse | `insert_each` (already ordered) |

`json_import.ex`'s `reduce_while` loops are validation, not inserts — untouched.

Tests: `test/estimate/repo_insert_each_test.exs` — ordered success; halt on first failing changeset returns that changeset and inserted nothing after it; empty input → `{:ok, []}`. Existing context/LV tests are the behaviour gate for every adoption.

### A2. `Estimate.Repo.reorder_children/4`

```elixir
@spec reorder_children(module, atom, binary, [binary]) :: :ok | {:error, :stale_reorder | term}
```

Moved from `Estimate.EstimationEngine.Helpers.reorder_children/5` (which is deleted). Semantics unchanged: count check → `{:error, :stale_reorder}`; transactional `update_all` per id scoped to the parent; `:ok`. The broadcast callback argument is dropped — engine callers do `with :ok <- Repo.reorder_children(...) do broadcast; :ok end`.

**Adoption:** `epics.ex`, `roles.ex`, `tasks.ex` (already via the helper); **new:** `templates.ex` `reorder_template_epics/2`, `reorder_template_tasks/2`; `accounts.ex` `reorder_role_templates/2`.

**Behaviour change (intended, flagged):** the three new adopters gain the stale-reorder guard; today a partial id list silently reorders a subset. Their LV callers (`TemplatesLive.Show` reorder handlers, `RolesLive.Index` role-template reorder) handle `{:error, :stale_reorder}` with flash `"Order changed elsewhere; reloaded"` + reload.

Tests: `test/estimate/repo_reorder_children_test.exs` (happy path, stale count, cross-parent id ignored); one test per new adopter proving the guard; the estimator's existing reorder tests are the gate for the engine callers.

---

## 4B — `templates_live/show.ex` (603 lines, 0 tests)

### B1. Characterization first
`test/estimate_web/live/templates_live/show_test.exs` (+ `test/support/templates_live_helpers.ex` mirroring `EstimatorLiveHelpers`: `setup_template/1` seeding one template with one epic and two tasks, mounting as the org owner; `mount_as/2` for a non-admin member). Covers: mount perimeter (admin vs member `is_admin`), every `handle_event` (update_template, add/edit/save-create/save-update/confirm/delete epic; add/edit/save-create/save-update/confirm/delete task; reorder_epics/tasks; close_modal; cancel_delete), modal state, and **today's** gating (member denied on saves/deletes/reorders; member *allowed* to open modals — characterized as-is, changed in B3). Diverge-then-assert. Expected ~35 tests, green on the unmodified LV before any split.

### B2. Decompose (behaviour-preserving)
Mirror `EstimatorLive`: `TemplatesLive.Show.Authz` (`find_epic/2`, `find_task/3`, `reload_template/1`, `reload_and_close/1`, `not_found/1`; `require_admin/2` keeps coming from `AuthHelpers` via `:live_handlers`), `Show.Epics` (add/edit/save ×2/confirm/delete/reorder), `Show.Tasks` (same seven), `Show.Template` (`update_template`, `close_modal`, `cancel_delete`). Handler modules `use EstimateWeb, :live_handlers` with `Reads:`/`Writes:` moduledocs. `Show` = `mount/3`, `render/1` (HEEx unchanged, ~315 lines), delegations. Reorders switch to `Repo.reorder_children/4` via the `Templates` context (4A) with the stale-reorder flash. Gate: B1 suite + precommit after every move.

### B3. Close the gaps (behaviour change, own commit, tests diverged then asserted)
- `require_admin` on `add_epic`, `edit_epic`, `confirm_delete_epic`, `add_task`, `edit_task`, `confirm_delete_task` (today a member can open modals and stage a delete; the save/delete is denied, but the UI state is wrong and `deleting_*` assigns are set). Denial flash: the existing `require_admin` text.
- `find_epic/2` / `find_task/3` return `nil` safely; handlers flash `"Not found"` (today an unknown epic id crashes `find_task` on `nil.tasks`).
- `update_template` error branch flashes `"Could not save template"` instead of silently returning.
- B1 tests that characterized the old gating are updated in this commit with the new expectations (and a comment naming B3).

Rejected: a generic epic/task outline editor shared with the estimator — different schemas and contexts, streams on one side only.

---

## 4C — small cleanups

- **C1** `Estimate.ChangesetHelpers.validate_name(changeset, max)` = `validate_required([:name]) |> validate_length(:name, min: 1, max: max)`; adopted by the three template schemas (`max: 200/200/500`). The engine schemas' `update_changeset/2` clauses (`Epic` 200, `Task` 500, `Estimation` 200: `validate_required([:name])` + `validate_length(:name, min: 1, max: n)`) are byte-identical in effect and adopt it too; their `changeset/2` clauses require extra fields and stay as they are.
- **C2** `EstimatorLive.Settings.save_settings/2` and `delete_estimation_role/2` resolve roles from `@estimation.roles` (`Enum.find` after `Authz.belongs_to_estimation?(estimation, :role, id)`), removing the `EstimationEngine.get_role!/2` round-trip and the `NoResultsError` path for a foreign-org id; denial stays `{:error, :unauthorized_role}` → flash "Could not update roles" / "Not authorized" as today. Existing settings tests (incl. the foreign-role denial) are the gate.
- **C3** `ViewState.filtered_epics/2` moves to `Rows.filtered_epics/2`; `ViewState` keeps a `defdelegate`. Removes the pure-module → handler-module dependency.
- **C4** `Grid.upsert_task_rows_only/2` (used by `refresh_editing/3`) gets the same `[] -> reset(socket)` fallback as `upsert_task/2`; test: editing key for a task hidden by the priority filter resets instead of no-op.
- **C5** `EstimatorLiveHelpers.by_order/0` returns `&{&1.position, NaiveDateTime.to_erl(&1.inserted_at), &1.id}`; the four duplicated sort keys (`epics_test`, `tasks_test`, `realtime_test`, `estimations_current_test`) use it. Test-support only.
- **C6** Dead code: the plugin scanner flagged 11 functions; all are false positives (`?`/`!`-suffixed names, HEEx `<.component>` calls, `plug :atom`). Nothing to delete. Recorded here so the next audit does not re-investigate.

---

## 4D — MCP tools (24 files, 1130 lines; behaviour-preserving)

- **D1** `EstimateWeb.MCP.Read`:
  - `fetch(frame, not_found_label, fun)` — `Scope.fetch/2` + `{:ok, map} → Response.json(Response.tool(), map)`, `{:error, :not_found} → Response.error(Response.tool(), not_found_label)`; returns `{:reply, resp, frame}`. `fun` returns the ready JSON map (tools move their serialization into `fun`).
  - `list(frame, fun)` — `Scope.with_scope/2` + `Response.json`. 
  - Adopted by every read tool (`get_*`, `list_*`, `search`); entity-specific messages (`"customer not found"`, `"project not found"`, …) preserved verbatim.
- **D2** `EstimateWeb.MCP.Authz.edit_gate(kind, id) :: (claims -> :ok | {:error, _})` = the closure `fn claims -> with {:ok, pid} <- project_id_for(kind, id, claims.org_id), do: require_can_edit_project(pid, claims) end`; adopted by the eight write tools that spell it out: `add_task`, `add_estimation_role`, `add_epic`, `set_task_effort`, `update_epic`, `update_estimation_role`, `update_task`, `update_estimation`.
- **D3** `EstimateWeb.MCP.Serializers.attrs(params, keys)` = `params |> Map.take(keys) |> Map.new(fn {k, v} -> {to_string(k), v} end)`; adopted where the idiom appears (`update_epic`, `update_task`, `update_customer`, `update_project`, `update_estimation`).
- Gate: existing MCP tests (`test/estimate_web/mcp/**`, incl. `catalog_test`) unchanged; add `read_test.exs` for `Read.fetch/3` + `Read.list/2` (found / not found / CastError). Target ≈ 850 lines total under `tools/`.

---

## Non-goals
- No changes to `Calculator`, RLS policies, migrations, CSP, or JS.
- No decomposition of the other 400–500-line LiveViews (`project_live/index`, `settings_live/currencies`, `roles_live/index`, `account_settings`) — candidates for a later batch.
- No new MCP tools or response-shape changes.

## Risks & mitigations
- **`insert_each` in Multi steps** — the callback runs on the same connection; no new transaction. Reviewer checks every adopted site still returns the shape its Multi/`with` expects.
- **Stale-reorder guard on templates/role-templates** — intended behaviour change; LV callers handle the error; one test per adopter.
- **4B B3 changes gating** — done in its own commit after the preserving split, with tests updated deliberately.
- **MCP `Read` wrapper** — response bytes must not change; existing tool tests assert on rendered JSON.
