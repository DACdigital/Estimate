# Audit batch 3 — small follow-ups, estimator decomposition, perf

Date: 2026-09-16. Follows batch 1 (`2026-09-02-audit-batch-1-security-design.md`) and batch 2 (`2026-09-02-audit-batch-2-security-design.md`). Roadmap items #6–8 (perf), the estimator decomposition, and the small follow-ups carried from batches 2a/2b. Password-reset / email-confirmation / OAuth link-to-confirmed work stays parked.

Three sub-batches, in order, each on its own branch with its own plan, subagent-driven, reviewed, then **merged locally to `main` (not pushed)**:

- **3A** small follow-ups — independent quick wins.
- **3B** estimator decomposition — behaviour-preserving split of the last god LiveView, characterization tests first.
- **3C** perf — `broadcast_from`, `with_org_context` collapse, estimator grid on LiveView streams. Lands on the decomposed modules from 3B.

Test rules from `AGENTS.md` apply throughout: no `Process.sleep`, diverge-then-assert for characterization tests (see memory `feedback-characterization-no-tautology`).

---

## 3A — small follow-ups

### A1. `Estimate.Encryption.Rotation.rotate_field/5` version guard
Today the `Repo.update_all` in `rotate_field` sets ciphertext/nonce/version unconditionally, so it can overwrite a row that the lazy read-path re-encrypt already moved to the current version (last writer wins with a stale plaintext-derived ciphertext — same plaintext, but a wasted write and a theoretical race with a concurrent secret *change*).

- Add `where: field(o, ^ver_f) == ^old_version` to the `update_all` (old version read from the row before decrypt).
- `{0, _}` (no row matched → someone else already rotated or changed the secret) is `:unchanged`, **not** `:failed`; counts stay accurate.
- Test: pre-bump the row's version after loading it, call `rotate_field`, assert `:unchanged` and the row is untouched. Existing rotation tests unchanged.

### A2. `Estimations.maybe_auto_set_current/1` goes through a changeset and is race-free
Today: `Ecto.Changeset.change(is_current: true) |> Repo.update()` — bypasses the schema's `unique_constraint(:is_current, name: :estimations_unique_current_per_project)`; a concurrent auto-set raises `Postgrex.Error`. It is only called from `restore_estimation/1`, inside an `Ecto.Multi` transaction, and its result is discarded (`{:ok, :done}`).

- New `Estimation.set_current_changeset/1`: `change(estimation, is_current: true)` + the same `unique_constraint(:is_current, …)` as `changeset/2` (constraint options extracted to one private helper used by both).
- `maybe_auto_set_current/1` first locks the project row (`from(p in Project, where: p.id == ^estimation.project_id, lock: "FOR UPDATE")`), then runs the exists-check, then `Repo.update(Estimation.set_current_changeset(estimation))`. The lock serialises concurrent auto-sets per project, so the unique index can no longer be hit by a race. Returns `{:ok, %Estimation{}}` (set), `{:ok, :unchanged}` (another estimation is current) or `{:error, changeset}`.
- `restore_estimation/1` uses that return value directly in `Multi.run` — a genuine failure now rolls the restore back instead of being swallowed. (A unique violation inside a transaction aborts the Postgres transaction even though Ecto returns `{:error, changeset}`; that is why the race is removed with a lock rather than "tolerated".)
- Tests: (a) restoring the only estimation of a project makes it current; (b) restoring when another estimation is current leaves both flags unchanged; (c) `Repo.update(Estimation.set_current_changeset(second))` while another current row exists returns `{:error, changeset}` with the `is_current` error, not a raise (outside any transaction).

### A3. `OAuth.Janitor` prunes orphan `oauth_clients`
Dynamic client registration creates one `oauth_clients` row per connector attempt; nothing deletes them.

- Third step in `Janitor.run/0`, after tokens and codes: delete clients where **no `oauth_codes` row and no `oauth_tokens` row reference the client** (`not exists` on both) **and** `inserted_at < now - 24h`.
- Rationale (best-practice lifecycle): a client's life is derived from its children. Tokens/codes are already retained under their own grace windows (`@token_grace_seconds`, `@code_grace_seconds`); once they are gone the client is an orphan. The 24h registration grace protects an in-flight register→authorize flow. A live grant can never be affected: its token row blocks the delete (and the FK `on_delete: :delete_all` from codes/tokens to clients is never reached because the guard excludes any referenced client).
- Result map gains `clients:`. Existing log line includes it.
- Tests: orphan older than 24h deleted; orphan younger kept; client with only a revoked-but-not-yet-pruned token kept; client with a live token kept; run order proves a client whose last token was pruned in the same run is deleted in that run.

### A4. Consent screen: client name demoted, redirect host is the anchor
`consent.html.heex` headline is `Connect {@client.name}` — attacker-chosen text in the most prominent position.

- Headline: `Connect to {@redirect_host}` (host is validated against the registered redirect URIs — the only trustworthy identity we have).
- Body: `An app calling itself “{@client.name}” at <mono>{@redirect_host}</mono> is asking to access your estimation data, acting as you:` — name in quotes, clearly self-declared. HEEx escaping already prevents markup injection; also clamp display with CSS truncation (`max-w-[14rem] truncate`) so a 100-char name cannot push the host off-screen (`max-w-full` on an inline-block inside an unconstrained paragraph does not clamp).
- Loopback warning unchanged. Tests: consent renders host in the `h1`, renders name inside quotes, and a name containing `<b>` is rendered escaped.

---

## 3B — estimator decomposition (behaviour-preserving)

Target: `lib/estimate_web/live/estimator_live/index.ex` (899 lines, 39 `handle_event`, 2 `handle_info` clauses, 3 `handle_async` clauses). Templates/components (`components/*.ex`, `helpers.ex`) are **not** changed in 3B beyond import paths.

### B1. Characterization suite first
`test/estimate_web/live/estimator_live/index_test.exs` (may be split per cluster: `epics_test.exs`, `tasks_test.exs`, …). Covers every handler, `handle_info` reload, modal open/close/cancel state, priority filter/restore, toggles, JSON export, save-as-template, settings/roles CRUD + reorder, rate edit, cell edit. Each test diverges the relevant assign from its mount default **before** asserting the handler sets it; unauthorized paths (`can_edit == false`) assert the flash and unchanged state. Existing `index_authz_test.exs` (12) and `ai_enhance_test.exs` (2) stay. Expected ~60–80 new tests. Suite must be green on the god LV **before** any split (that is the point).

### B2. Module map (mirrors `EstimateWeb.ProjectLive.Show`)
All handler modules take `(socket, params)` and return `{:noreply, socket}`; `Index` keeps `mount/3`, `render/1`, one-line `handle_event` delegations, `handle_info` (rewritten in 3C), `handle_async` delegations.

| Module | Handlers / functions |
|---|---|
| `EstimatorLive.Authz` | `with_edit_auth/2`, `authorize_edit/1`, `find_epic/2`, `find_task/2`, `belongs_to_estimation?/3`, `not_found/1` |
| `EstimatorLive.Epics` | `add_epic`, `edit_epic`, `save_epic`, `confirm_delete_epic`, `cancel_delete_epic`, `delete_epic`, `reorder_epics` |
| `EstimatorLive.Tasks` | `add_task`, `edit_task`, `validate_task`, `save_task`, `confirm_delete_task`, `cancel_delete_task`, `delete_task`, `reorder_tasks` |
| `EstimatorLive.Estimates` | `edit_estimate`, `save_estimate`, `cancel_edit`, `edit_rate`, `save_rate`, `update_estimate_in_memory/2`, `update_role_in_memory/2` |
| `EstimatorLive.Settings` | `open_settings`, `save_settings`, `add_estimation_role`, `confirm_delete_role`, `cancel_delete_role`, `delete_estimation_role`, `reorder_roles` |
| `EstimatorLive.ViewState` | `toggle_breakdown`, `toggle_all_in_rates`, `toggle_descriptions`, `toggle_priority`, `restore_priorities`, `close_modal`, `filtered_epics/2` |
| `EstimatorLive.Export` | `copy_json`, `open_save_as_template`, `save_as_template` (both clauses) |
| `EstimatorLive.AI` | `ai_enhance_description` handler + the three `handle_async({:ai_enhance, _}, …)` bodies (Index keeps the callbacks, delegates) |
| `EstimatorLive.Index` | `mount`, `render`, delegations, `handle_info`, `reload_estimation/1` (moves to `Estimates`/shared helper in 3C) |

Shared helpers (`reload_estimation/1`, `display_roles/2`) live in `EstimatorLive.Authz` or a small `EstimatorLive.State` module — implementer's call, one home, no duplication. Handler modules `use EstimateWeb, :live_handlers` (the macro from the project-show work, see `ProjectLive.Show.Dashboard`).

### B3. Gates
Characterization suite + `index_authz_test` + `ai_enhance_test` + `org_scoped_smoke_test` + `mix precommit` green after every move. No new behaviour. Each cluster move is its own commit.

---

## 3C — perf

### C1. `broadcast_from` (roadmap #6)
`Estimate.EstimationEngine.broadcast/2` → `Phoenix.PubSub.broadcast_from(@pubsub, self(), topic, event)`.

- Contract: context functions are called **inline in the caller's process** (LiveView or MCP request process), so `self()` is the originator. The originating LV must apply its own change locally — every mutating estimator handler already does (`reload_estimation` or `update_*_in_memory`); the plan audits each one. MCP writes originate in a non-LV process, so all LVs still receive them.
- Payload contract (relied on by C3): events carry the full updated struct (`{:task_updated, %Task{}}`, `{:estimate_updated, %TaskEstimate{}}`, …) or the id list for reorders — as today. Documented in `EstimationEngine` moduledoc.
- Tests: two connected LVs on the same estimation; a cell edit in A updates A once (no second reload — assert via a counter on `get_estimation!` through the `:ai_enhancer`-style seam or by asserting A's DOM after a single `render`), and B receives the event and reflects it. MCP-originated update reaches both.

### C2. `Repo.with_org_context/2` collapse (roadmap #7)
Today: 7 statements per call, re-executed when nested.

- Setup collapses to **one** statement: `SELECT set_config('role', 'estimate_app', false), set_config('app.current_org_id', $1, false), set_config('app.current_user_id', $2, false)` (`set_config('role', …)` is `SET ROLE`). Capture stays one statement; restore collapses to one `SELECT set_config(...) × 3`. **7 → 3.**
- Nested idempotency: `checkout/1` pins the connection to the process, so a process-dictionary marker `{:rls_ctx, {org_id, user_id}}` set inside the outermost call lets a nested call with the **same** `{org_id, user_id}` run `fun.()` directly — 0 statements. Different org/user → full path as today (restores the outer context after). Marker is cleared in the outermost `after`. `ensure_org_context/1` benefits automatically.
- `without_rls/1` unchanged (rare path, already asserted).
- Bench: `bench/org_context.exs` (mix run, not a test) timing 1 000 `with_org_context` calls flat and 1 000 nested-same-context calls before/after; numbers go in the plan ledger and the commit message.
- Tests: existing `repo_without_rls_test.exs` state-restoration tests must still pass unchanged (they are the safety net); add: nested same-context call executes no `SET`/`set_config` (assert via `Ecto` telemetry `[:estimate, :repo, :query]` counting queries inside the nested call); nested different-context restores the outer context.

### C3. Estimator grid on LiveView streams (roadmap #8)
Today: `render/1` computes `epics = filtered_epics(...)` at render time, the table is an unkeyed `for` comprehension, and every `Calculator.*` total is recomputed at render (~25 passes). Any change re-diffs the whole grid.

**Row model.** One stream `:rows` on `#epics-container` (`phx-update="stream"`), items are flattened rows in display order, three kinds, dom ids stable:

| kind | dom id | payload |
|---|---|---|
| `:epic_header` | `epic-<id>` | epic, `data-id`, drag handle, edit/delete controls |
| `:task` | `task-<id>` | task, `data-id`, `data-epic-id`, per-role estimates, `total_hours`, `total_cost` |
| `:epic_subtotal` | `epic-<id>-subtotal` | per-role hours, `epic_hours`, `epic_total_cost` |

Built by `EstimatorLive.Rows.build/2` (estimation, view state) — pure, unit-tested. Per-row totals are computed **once at build time** and stored on the row struct. Footer + cost breakdown totals (`role_hours`, `calc_total_hours`, `calc_base_cost`, overheads, grand total, weighted averages) are computed once into a `@totals` assign by `EstimatorLive.Totals.compute/2` whenever the estimation or `show_all_in_rates` changes — never at render.

`@estimation` stays in memory as the source of truth for authz (`find_epic/find_task`) and for building rows; streams hold nothing after render (memory per LV unchanged vs today).

**Update matrix** (the rule: any assign a row reads either re-inserts the rows it affects or resets the stream):

| trigger | action |
|---|---|
| `estimate_updated`, `task_updated` (own or PubSub) | update `@estimation` in memory → `stream_insert` `task-<id>` + `epic-<epic>-subtotal`; recompute `@totals` |
| `epic_updated` | `stream_insert` `epic-<id>` header |
| `role_updated` (rate change) | affects every cost → rebuild `reset: true`; recompute `@totals` |
| `editing` cell change | `stream_insert` previous editing task row (if any) + new one |
| `editing_rate` | header lives outside the stream → plain assign |
| create/delete/reorder of epic/task/role, `estimation_updated`, `roles_reordered` | `reload_estimation` → rebuild `reset: true`; recompute `@totals` |
| `toggle_priority`, `restore_priorities`, `toggle_descriptions`, `toggle_all_in_rates` | rebuild `reset: true` (`toggle_all_in_rates` also `@totals`) |
| `toggle_breakdown`, modals, flashes | outside the stream → nothing |

`handle_info` in `Index` is rewritten as the matrix above (pattern match per event) — this replaces the "every event → full reload" clauses. Unknown/new events fall through to reload + reset (safe default, logged at debug).

**JS.** `Sortable` hook stays on `#epics-container`; selectors already key off `data-id` / `data-epic-id`, which the rows keep. `updated()` re-initialising task sortables per epic still works with stream inserts. Stream `reset` re-renders all rows; `updated()` fires — same as a full re-render today.

**Bench.** `bench/estimator_grid.exs`: seed 100 tasks × 5 roles, measure (a) `render/1` wall time and (b) diff payload size via `Phoenix.LiveViewTest` `render_click` result byte length for one cell edit, before (on 3B's main) and after. Target: cell edit pushes 2 rows (task + subtotal) plus `@totals`, not the grid. Numbers recorded in the plan ledger.

**Tests.** Full 3B characterization suite must stay green (DOM assertions are stream-agnostic). Add: `Rows.build/2` unit tests (order, kinds, ids, filter by priority, descriptions flag); `Totals.compute/2` equals the old render-time `Calculator` calls for a fixture (guards against drift); LV tests asserting after a cell edit the task row and the epic subtotal show new values while an unrelated epic's header element is byte-identical (`element/2 |> render`); PubSub `estimate_updated` from a peer updates the row; priority toggle hides/shows rows.

---

## Non-goals
- No changes to `Calculator` semantics, to any migration/schema, to MCP tools, or to the CSP/security surface.
- No `without_rls` optimisation. No `Task`/`Agent` caching of totals.
- Mail/reset/confirmation work stays parked.

## Risks & mitigations
- **3B is a big mechanical move** — characterization first, one cluster per commit, each gated.
- **`broadcast_from` hides own updates** — the plan audits all 20 mutating handlers for a local update; the two-LV test catches a miss.
- **Nested-context marker leaks** — marker set/cleared in the same `try/after` as the SQL restore; the restoration tests are the net.
- **Streams + Sortable** — DOM shape and data attributes preserved on purpose; manual drag-and-drop verification in the browser is part of the 3C review.
- **Row-reads-assign drift** — the update matrix is the contract; review checks every `@assign` referenced inside a row template against it.
