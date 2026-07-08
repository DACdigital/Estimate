# Web-Layer Code-Quality Overhaul — Phase 1 (Structure)

Date: 2026-06-30
Status: Design approved (pending spec review)
Owner: Krzysztof Radecki

## 1. Context

`Estimate` is a Phoenix 1.8 LiveView app (multi-tenant: organizations / memberships)
for project estimation and quoting. The domain/context layer is reasonable; the
**web layer has accumulated systemic convention debt and structural decay**. This is
the first of several planned quality steps. It targets the web layer only.

A prior `vibeguard-reports/` pass covered security/ops/reliability/production-readiness.
That track is separate and out of scope here.

This is **Phase 1 = structure** of a two-phase intent. Phase 2 (a later, separate
effort) is visual/UX polish on the cleaned components.

## 2. Goals & non-goals

**Goals**
- Eliminate the "god LiveViews"; give components clean event/state ownership.
- Remove systemic AGENTS.md convention debt (forms, formatting, layouts, streams).
- DRY the confirmed duplication; consolidate the shared web surface.
- Consolidate authorization into a single, consistent, testable policy surface.
- Build the **missing UI test suite** as a first-class deliverable.
- Fix the estimator-grid performance problem.

**Non-goals (this phase)**
- Visual / UX redesign (Phase 2).
- DB schema or migration changes (see §3).
- Re-doing the vibeguard security/ops findings.
- Fixing non-atomic register-then-join onboarding (we *pin* current behavior; the fix
  is data-layer).

## 3. Constraints & resolved decisions

| # | Decision | Resolution |
|---|---|---|
| Scope | What "UI/UX" means this step | **Web-layer code quality** (structure). Visual polish = later Phase 2. |
| Tests | Safety net | **Test heavily.** Characterization tests pin behavior *before* risky changes; full new UI suite is a deliverable. |
| Appetite | Size | **Full web-layer sweep** (every LiveView + components + foundation). |
| Event pattern | Fixing leaky boundaries / god LiveViews | **Function components + per-feature handler-delegation modules.** No new LiveComponents. |
| Authz | Context API changes | **In scope.** Context *function signatures* may change (e.g. push org-scoping in). |
| Risk items | Streams + grid perf | **Included**, behind characterization tests. |
| 1.8 layout | `<Layouts.app>` / `current_scope` | **Migrate** app-wide. |
| Grid perf | Phase 6 target | **Hard requirement:** editing one cell must not re-render the whole table. |
| Changeset dup | 3 template schema files | **Mechanical extraction allowed** (helper). |
| `current_scope` shape | scope plumbing | **Single `%Scope{}` struct** wrapping user + membership + org + role. |
| Streams empty-state | list screens / grid | **Hybrid:** AGENTS.md `hidden only:block` pattern; add a count assign only where a number is displayed. |
| Coverage bar | test deliverable | **Qualitative:** every module has a test file + every security flow pinned (no brittle hard `%`). |
| Handler-module shape | god-LV decomposition | **Explicit delegation:** `Mod.handle_event(event, params, socket) :: {:noreply, socket}` called from the LiveView. |

**Data-model constraint (clarified):** "No data model" means **no database schema or
migration changes** — no new/changed columns, tables, indexes, or associations at the
DB level. Behavior-preserving *code* refactors of schema modules (e.g. deduplicating
changeset validation into a helper) are permitted as long as the DB structure is
untouched.

**Overarching rule:** every change is **behavior-preserving**. When done, each screen
looks and works identically. Refactors land only against a green test suite.

**Per-phase gate:** `mix precommit` (compile + format + the full new test suite) must
pass before a cluster's PR merges.

**Ship cadence:** one PR per cluster.

## 4. Findings (evidence baseline)

### 4.1 God LiveViews (confirmed)
| File | LOC | Concerns |
|---|---|---|
| `project_live/show.ex` | 1568 | 40 `handle_event`s across project edit/delete · estimation-modal CRUD · trash/restore · collaborators; two ~200-line inline `~H` tabs |
| `estimator_live/index.ex` | 820 | ~30 events across epic/task/rate/settings/priority/AI; full-grid re-render per keystroke |
| `templates_live/show.ex` | 604 | ~310-line `render`; epic & task modals ~90% identical |
| `settings_live/members.ex` | 565 | 7 concerns; reassignment state-machine; authz rule duplicated 4× |

### 4.2 Leaky component boundaries
Components render UI but the parent LiveView owns all their events + state:
`collaborators_tab`, `new_estimation_modal`, `estimation_dashboard` → `show.ex`;
`reassignment_modal` → `members.ex`; `estimation_table`/`estimate_cell`/`cost_breakdown`
→ `estimator_live/index.ex`. This is the root cause of the god modules.

### 4.3 Systemic convention debt (AGENTS.md)
- **`<.input>` near-zero adoption** — ~28+ raw `<input>/<select>/<textarea>` across nearly
  every form; `<.input>` is missing `radio`; non-idiomatic `FormClasses` macro injects
  style attrs in 2 modules.
- **Formatting helpers scattered/duplicated** — `format_hours` vs `format_hours_h`,
  `format_number`, `parse_decimal` (×2: `estimator_live/helpers.ex:107` &
  `project_live/show.ex:1557`), `format_cost`/`rate`/`percent`/`usd`; three parallel
  string→badge-class mappers (`project_status_class`, `priority_class`, `type_badge_class`).
  Canonical set wrongly homed in `EstimatorLive.Helpers` (already cross-imported — proof
  it is de-facto shared).
- **Duplicated chrome** — page headers, empty-states, cards, breadcrumbs, primary buttons,
  auth fields copy-pasted; `app.html.heex` ≈ `app_account.html.heex` (~70% identical);
  `active_tab`/`settings_page` set by hand in 15 LiveViews.
- **No LiveView streams anywhere** — all collections are plain assigns. Low practical risk
  for small org-scoped lists; **real** problem for the estimator grid.

### 4.4 Confirmed duplication
`handle_params/3` 100% identical (`project_live/index.ex:305` ↔ `show.ex:697`) · project
form near-identical (index↔show) · currency `update_*` handlers ×4 near-identical ·
customer `save` :new/:edit clauses · template epic/task modals ~90% · changeset/2 across
3 template schemas (72–74%).

### 4.5 Authorization smells (security-adjacent — handle with care)
- Membership org-scoping lives in the **LiveView, not the context**:
  `Organizations.update_membership_role/2` & `delete_membership/2` take a bare
  `%Membership{}`; LiveView compensates via `Enum.find(socket.assigns.members, …)` +
  `require_admin`. Safe today, fragile to any new caller.
- "admin ∧ not-owner ∧ not-self" rule hand-written **4×** (3 server guards + 1 template).
- Estimator `with_edit_auth` applied to most but **not all** mutating events
  (confirm/cancel-delete skip it).
- Dead authz-ish privates flagged by scan (`can_edit`, `belongs_to_estimation`) were
  **false positives** (the real fns are `can_edit?`/`belongs_to_estimation?`, in use).

### 4.6 Dead code — almost none
All "unused component" scan flags were **false positives** (HEEx `<.foo>` call sites).
Genuinely removable (verify zero call sites first): `core_components.header/1` (0 uses),
`simple_form/1` (scaffold leftover, 1 use), `get_epic_for_task` (tasks.ex:93),
`skip_after_connect` (repo.ex:23), `enforcement_blocks` (org_auth.ex:99). `days_remaining`
(layouts.ex:14) — verify before removing.

### 4.7 Foundation specifics
- `core_components`: `<.button>` used 4× vs 143 raw `<button>` (variants too thin);
  `<.input>` 9× vs 28 raw; `header/1` dead; `time_ago/1` & `project_status_class/1` are
  formatters mis-placed as components.
- Only one true LiveComponent (`SearchComponent`) — justified, keep. `JsonImportComponent`
  is already a function component — correct.
- Router/`live_session` segmentation is clean; `OrgAuth.on_mount` centralizes
  org/membership. `active_tab` glue is the high-value DRY target.

### 4.8 Tests
6 test files (~657 LOC), all domain/context. **Zero LiveView tests.** Highest-value
targets: auth flows + membership authorization.

## 5. Target architecture (new shared surface)

- **`EstimateWeb.Format`** — single home for `format_cost/rate/hours/percent/usd/number`,
  `parse_decimal`, `time_ago`, `days_remaining`. Imported app-wide via `estimate_web.ex`
  `html_helpers`. Replaces the scattered/duplicated formatters; removes them from
  `EstimatorLive.Helpers`.
- **`core_components` corrected & expanded**
  - Complete `<.input>` (add `radio`); **delete `FormClasses` macro** (fold styling in).
  - New: `<.badge>` (unifies the 3 status/priority/type mappers), `<.page_header>`,
    `<.empty_state>`, `<.breadcrumb>`, `<.settings_card>` + `<.settings_header>`,
    `<.auth_input>` (or an auth variant of `<.input>`).
  - Expand `<.button>` (primary/destructive/ghost + sizes) and adopt it.
  - Delete dead `header/1`, `simple_form/1`. Move `time_ago`/`project_status_class` to
    `Format`/`<.badge>`.
- **`<.app_shell>`** layout component — sidebar + topbar + user section + flash + main;
  dedupes `app.html.heex` ≈ `app_account.html.heex`. Centralize the `"EstiMate"` logo.
- **Shared `on_mount`** in the `:org_scoped` live_session sets `active_tab`/`settings_page`
  from the route → removes manual assigns from 15 LiveViews.
- **`current_scope`** — a single `%Scope{}` struct (user + membership + org + role), set in
  on_mount; adopt `<Layouts.app current_scope={@current_scope} flash={@flash}>` per template,
  read `@current_scope.*` instead of `@current_user`/`@org_id`/`@current_membership`.
- **Authorization policy surface** — `can_manage_membership?/2`, project
  `can_edit?/can_delete?/can_manage_collaborators?`, uniform estimator `with_edit_auth`;
  **org-scoping enforced in the `Organizations` context** (signature changes allowed).
- **Per-feature handler-delegation modules** (function components stay; events route to
  focused modules via explicit `Mod.handle_event(event, params, socket) :: {:noreply, socket}`
  calls — the LiveView stays a readable routing index), e.g.:
  - `ProjectLive.{ProjectEvents, EstimationModalEvents, CollaboratorEvents, EstimationsEvents, Authorization}`
  - `EstimatorLive.{EpicActions, TaskActions, RoleActions, GridEditing, PriorityFilter}` +
    in-memory mutators pushed down to `EstimationEngine`.
  - `SettingsLive.Members.Reassignment` (plain state module for the reassignment machine).
- **Merge** `live_helpers.ex` → `auth_helpers.ex` (two one-fn modules → one).

## 6. Testing strategy (first-class deliverable)

1. **Infrastructure** — `LiveViewCase`/conn helpers; login helpers; fixtures for user, org,
   membership/roles, customer, project, estimation, template, currency, role_template.
2. **Security characterization FIRST** — pin before touching the code:
   - forgot-password user-enumeration safety (identical response either way)
   - `safe_return_to` open-redirect guard (reject `//evil`, `/\evil`, absolute URLs;
     round-trip valid local path)
   - invite email-binding + email-mismatch rejection
   - TOTP enable/disable (incl. `clear_2fa_deadlines_for_user` side-effect, backup-code path)
   - pending-2FA gate (TotpVerification reachable only via `:require_pending_2fa`)
   - reset-token validity (invalid/expired → redirect "/")
   - oauth-vs-password branch (set_user_password vs update_user_password)
   - membership authorization denials (non-admin, owner-target, self-target)
   - registration invite-code atomicity — document current behavior
3. **Per-LiveView** — smoke (key elements present by DOM id) + interaction (validate/submit,
   modal open/close, CRUD round-trips via `render_change`/`render_submit`) + authz-denied +
   flash assertions. Reference existing DOM ids (`#customer-form`, `#org-form`,
   `#ai-settings-form`, `#delete-template-modal`, `#epics-container`, …).
4. **Context tests** wherever a signature changes (authz org-scoping especially).
5. **Bar:** every LiveView and every extracted handler/`Format`/component module has tests;
   every security-sensitive flow has an explicit characterization test.

## 7. Phased plan

Phases 0–1 are global and first. Phases 2–5 then run **cluster by cluster** so each file is
touched once and each cluster ships as one reviewable PR. Phase 6 is cross-cutting, last.

Cluster order: **auth → settings → project → estimator → misc** (templates/customer/roles/
dashboard/organization).

### Phase 0 — Test foundation & safety net
- Test infra (§6.1).
- Security characterization tests (§6.2).
- Smoke tests for every LiveView screen.
- **Acceptance:** new suite green; security behaviors pinned; CI runs LiveView tests.

### Phase 1 — Shared foundation (global)
- `EstimateWeb.Format` + app-wide import.
- `<.input>` completion (+radio); delete `FormClasses`.
- `<.badge>`, `<.page_header>`, `<.empty_state>`, `<.breadcrumb>`, `<.settings_card>`/
  `<.settings_header>`, `<.auth_input>`; expand & adopt `<.button>`.
- Dead-code purge (verify-then-remove).
- Merge `live_helpers` → `auth_helpers`.
- Shared `on_mount` for `active_tab`/`settings_page`.
- `<.app_shell>` layout component; `current_scope` plumbing (assign + on_mount).
- **Acceptance:** foundation modules unit-tested; app compiles; all Phase-0 tests still green;
  no visual diff.

### Phase 2 — Layout/scope migration (per cluster)
- Adopt `<Layouts.app current_scope=.. flash=..>`; read `@current_scope.*`.
- **Acceptance:** per-cluster smoke tests green; no behavior/visual change.

### Phase 3 — Convention & DRY sweep (per cluster)
- `<.input>` + `to_form` everywhere; apply shared primitives & `<.badge>`.
- Dedupe: `handle_params/3`, project form (`ProjectFormFields`), currency `update_*`
  (`with_currency_update/3`), customer save clauses, template epic/task modals
  (`<.template_item_modal>`), changeset validation (`validate_named/1` helper — no DB change).
- **Acceptance:** per-cluster tests green; raw form-control count → 0 in touched files.

### Phase 4 — Decompose god LiveViews (per cluster)
- `show.ex`, `estimator_live/index.ex`, `members.ex`, `templates_live/show.ex` → thin shells
  + per-feature handler modules; move events into their components; push in-memory mutators
  to `EstimationEngine`.
- **Acceptance:** each god file substantially reduced; handler modules unit-tested; behavior
  identical under the characterization suite.

### Phase 5 — Authorization consolidation (per cluster)
- Push org-scoping into `Organizations` context (e.g.
  `update_membership_role(org_id, membership_id, role)`, `delete_membership(org_id, id)`).
- Single `can_manage_membership?/2`; project authz helper; uniform estimator `with_edit_auth`
  on every mutating event.
- **Acceptance:** authz denial tests green; no membership/role mutation path bypasses org
  scope; predicate defined once.

### Phase 6 — Streams & estimator-grid perf (cross-cutting, last)
- Convert list screens to LiveView streams (start: customer/index, templates/index,
  roles/index).
- Rework the estimator grid: epics/tasks as streams + per-row isolation so a single-cell
  edit updates only that cell + affected subtotal/footer/grand-total. Memoize Calculator
  passes. **Hard requirement: no full-table re-render on cell edit.**
- **Acceptance:** characterization tests green; a test asserts a single-cell edit does not
  re-render unaffected rows (e.g. via targeted diff/element assertions); empty-state &
  DOM-keying handled per AGENTS.md stream rules.

## 8. Out of scope
DB schema/migrations · visual/UX redesign (Phase 2) · vibeguard security/ops/reliability
findings · non-atomic register-then-join *fix* · converting the justified `SearchComponent`
LiveComponent.

## 9. Risks & mitigations
1. **Estimator-grid streaming (DOM keying)** — highest risk. Mitigation: Phase 6 last,
   behind the fullest characterization suite; explicit no-full-re-render assertion.
2. **`current_scope` migration breadth** — touches every LiveView. Mitigation: Phase-0 smoke
   tests; do it per cluster, not big-bang.
3. **Moving security-critical membership/auth code** — Mitigation: Phase-5 gated by Phase-0
   authz pins; context-level org-scope tests.
4. **Re-touching files across phases** — Mitigation: cluster-by-cluster execution touches
   each file once across phases 2–5.

## 10. Resolved decisions (post-review)
All open questions resolved with the user:
1. **`current_scope` shape** → single `%Scope{}` struct (user + membership + org + role).
2. **Streams empty-state** → hybrid: AGENTS.md `hidden only:block`; count assign only where a
   number is shown.
3. **Coverage bar** → qualitative (every module has a test file + every security flow pinned).
4. **Handler-module shape** → explicit `Mod.handle_event(event, params, socket)` delegation
   from the LiveView.

No outstanding questions. Ready for implementation planning.
