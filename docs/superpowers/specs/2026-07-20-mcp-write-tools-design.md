# MCP Write Tools — Design

**Date:** 2026-07-20
**Status:** Implemented on branch `mcp-write-tools` (from `96addc78`), pending final review + merge. 23 commits, 525 tests + 2 doctests green, dev+test compile `--warnings-as-errors` clean. Plan: [2026-07-20-mcp-write-tools.md](../plans/2026-07-20-mcp-write-tools.md).
**Builds on:** [MCP server](2026-07-16-mcp-server-design.md) · [MCP OAuth](2026-07-17-mcp-oauth-design.md)

## Implementation notes (post-build)

- All 13 tools shipped (7 create + 6 edit) + `mcp_write_enabled` toggle + settings UI. Nearly all logic reused existing context fns; new: migration, `get_currency_by_code`, `get_estimation_project_id`, `MCP.Authz`, `MCP.Write`, `create_task_with_estimates` (atomic).
- **Peri `:float` rejects integer JSON** (Jason decodes `8`→integer). All numeric input fields use `{:either, {:float, :integer}}`; verified at the schema layer (the `execute/2` unit tests bypass Peri).
- Non-collaborator members get `not found` (project-level RLS hides the row) rather than `not authorized`; only a viewer-role collaborator (who can see the row) gets `not authorized`. Both deny.
- Fixed in-branch: `Customer.changeset` duplicate-key error now attaches to `:key`; role tools default omitted numerics instead of inserting `nil` into NOT NULL columns; `set_task_effort` uses atom-keyed attrs (mixed keys crashed).
- **Found pre-existing, out-of-scope (chip-flagged):** `Accounts.seed_default_role_templates/1` never applies pm/qa/risk overhead %, so new orgs' default role templates are all 0%.
- **Deferred decision:** estimation-mutating write tools (`add_epic`/`add_task`/`update_*`/`set_task_effort`/`add_estimation_role`) do not reindex search — MCP-created/edited content is stale in search until the next estimation update. Decide reindex-on-write vs follow-up.

## Goal

Let a member drive EstiMate through Claude to **create and edit** the full estimation
chain — customer → project → estimation → roles → epics → tasks → per-role hours —
conversationally, one confirmable tool call at a time. Same `/mcp` server, same
Bearer/OAuth auth, same per-user RLS privileges as today's read-only tools. Writes are
off by default and must be explicitly enabled by an org admin.

Primary use: a member runs the `pricing-agent` skill (or just talks to Claude), then has
Claude scaffold the result into the app step by step. Claude resolves dependencies with
the existing read tools and only mutates on the user's OK.

## Decisions (from brainstorm)

| Question | Decision |
|---|---|
| Architecture | **Granular, conversational tools** (not a monolithic import); reusable for ad-hoc edits |
| Effort entry | `add_task` takes an **optional** inline `efforts` map (`{abbrev → hours}`); omit to create skeleton and fill hours later (in-app or via `set_task_effort`) |
| Dependency wiring | **Explicit IDs**; Claude resolves via read tools + confirms, creates dependency only on approval. No auto resolve-or-create |
| Write gate | **New `org.mcp_write_enabled`, default `false`** (separate from `mcp_enabled`); admin opts in; read unaffected |
| `create_estimation` roles | **Mimic the "new estimation" modal**: optional inline `roles[]`; omit → seed suggested defaults from org role templates (rates for the estimation currency) |
| Project create | Any org member (mirrors web) — becomes `owner` collaborator |
| Deep links | Every create/update response returns an app URL to the entity |
| Deletes | **Deferred** to a fast-follow (create + update + `set_task_effort` only in v1) |

## Architecture

Write tools register as new `component(...)`s on the **existing** `EstimateWeb.MCPServer`
(`/mcp`). No new endpoint, no new auth path. Every tool body runs inside
`EstimateWeb.MCP.Scope.with_scope/2`, which sets the caller's RLS pdict (org_id, user_id)
exactly as `OrgAuth.on_mount` does for a LiveView. All mutations go through **existing
context functions** (see catalog) — the tools are a thin authorization + serialization layer.

Tool components are static/compile-time, so write tools are always advertised in
`tools/list`; execution enforces the gates below (server-off is already impossible to
reach — see gate 1).

## Security & authorization model (the crux)

Three independent gates; **all** must pass before any mutation:

1. **Server enabled** — `org.mcp_enabled`. Already enforced at *auth time*:
   `MCP.verify_api_key/1` and `verify_bearer/1` select `o.mcp_enabled` and reject the whole
   request with `:mcp_disabled` when false. ⇒ `mcp_enabled = false` means no request
   reaches any tool; **no write loophole**, and write tools need not re-check it.
2. **Writes enabled** — `org.mcp_write_enabled`, read **fresh** inside every write tool.
   False ⇒ reply `"MCP writes are disabled for this organization"`. Read tools never check it.
3. **Per-action role**, mirroring the web app:

   | Tool group | Gate |
   |---|---|
   | `create_customer`, `update_customer` | org admin/owner only (`role in ["owner","admin"]`) |
   | `create_project` | any org member (auth already proves membership) |
   | `update_project` | org-admin **OR** project `owner`/`editor` collaborator |
   | `create_estimation` + all estimation children (roles/epics/tasks/efforts) & their updates | org-admin **OR** project `owner`/`editor` collaborator (`can_edit_project`) |

**Why code-level project gating is required:** RLS scopes rows to the *org* only. It does
**not** know project-collaborator roles. So an in-org member who is not an `owner`/`editor`
collaborator on project X must be blocked *in code* from writing X's estimation — even with
a valid `epic_id`/`task_id`. Each estimation-write tool therefore resolves the target up to
its `project_id` and authorizes against the caller's collaborator role.

Note the chain that makes members productive without over-granting: creating a project makes
the creator an `owner` collaborator (existing `create_project` behavior), so they can
immediately create estimations on *that* project and no other.

### `EstimateWeb.MCP.Authz` (new)

Pure functions over `Scope.claims/1` + `org_id`:

- `write_enabled?(org_id)` — `Organizations.mcp_write_enabled?/1` (fresh query).
- `require_org_admin(claims)` — `claims.role in ["owner","admin"]`.
- `require_can_edit_project(project_id, claims)` — org-admin OR
  `Portfolio.get_collaborator(project_id, user_id).role in ["owner","editor"]`.
- `project_id_for(kind, id, org_id)` — resolves `:estimation | :epic | :task | :role` up to
  its `project_id` via the org-scoped getters (`get_estimation!/get_epic!/get_task!/get_role!`),
  so every child tool authorizes against the owning project. `Ecto.NoResultsError` ⇒
  `{:error, :not_found}` (cross-org rows are invisible under RLS → also `:not_found`).

Each write tool: `with_scope` → `write_enabled?` → per-action gate → context call →
serialize (entity + deep link) or `{:error, ...}`.

## Tool catalog (13)

Args marked `?` optional. `currency` is always a **code** (e.g. `"EUR"`), resolved by
`get_currency_by_code/2`; unknown code ⇒ error naming it. All responses include the entity
(reusing/extending `MCP.Serializers`) plus a `url` deep link.

### Create

| Tool | Args | Gate | Context fn |
|---|---|---|---|
| `create_customer` | key, name, country?, website_url?, description?, currency? | org admin | `CRM.create_customer/2` |
| `create_project` | customer_id, name, key?, short_description?, detailed_description?, repository_url?, status?, currency? | member | `Portfolio.create_project/4` (creator→owner, copies role templates, inherits customer currency) |
| `create_estimation` | project_id, name, description?, currency?, roles? `[{name, abbreviation, hourly_rate?, pm_overhead?, qa_overhead?, risk_buffer?}]` | can_edit_project | `EstimationEngine.create_estimation_from_templates/2` — `roles` given → use them; omitted → build from `Accounts.list_role_templates(org_id)` with rate for the currency (currency omitted → inherit project currency) |
| `add_estimation_role` | estimation_id, name, abbreviation, hourly_rate?, pm_overhead?, qa_overhead?, risk_buffer? | can_edit_project (via estimation→project) | `EstimationEngine.create_role/1` (position = end) |
| `add_epic` | estimation_id, name, description?, position? | can_edit_project | `EstimationEngine.create_epic/1` |
| `add_task` | epic_id, name, description?, priority?(default `must`), position?, efforts? `{abbrev → hours}` | can_edit_project (via epic→estimation→project) | **atomic**: `create_task/1` then, per effort, resolve abbrev → estimation role (within the epic's estimation) → `upsert_task_estimate/4`. Unknown abbrev ⇒ rollback + error listing available abbrevs |
| `set_task_effort` | task_id, role (abbrev or role_id), hours | can_edit_project (via task→…→project) | `EstimationEngine.upsert_task_estimate/4` |

### Edit

| Tool | Args | Gate | Context fn |
|---|---|---|---|
| `update_customer` | id + any of key/name/country/website_url/description/currency | org admin | `get_customer!/2` → `CRM.update_customer/2` |
| `update_project` | id + any of name/key/short_description/detailed_description/repository_url/status/currency | can_edit_project | `get_project!/2` → `Portfolio.update_project/2` |
| `update_estimation` | id + any of name/description/currency | can_edit_project | `get_estimation!/2` → `EstimationEngine.update_estimation/2` |
| `update_estimation_role` | id + any of name/abbreviation/hourly_rate/pm_overhead/qa_overhead/risk_buffer | can_edit_project (via role→estimation→project) | `get_role!/2` → `EstimationEngine.update_role/2` |
| `update_epic` | id + any of name/description | can_edit_project | `get_epic!/2` → `EstimationEngine.update_epic/2` |
| `update_task` | id + any of name/description/priority | can_edit_project | `get_task!/2` → `EstimationEngine.update_task/2` |

## Data-flow specifics

- **Currency by code** — new `Estimate.Organizations.Currencies.get_currency_by_code/2`
  (org-scoped; no migration). Tools accept a code, resolve to `currency_id`; unknown ⇒ error.
- **Efforts by abbreviation** — `add_task.efforts` / `set_task_effort.role` keys match the
  estimation's role abbreviations **exactly as stored** (EstimationRole does not upcase).
  Claude reads exact abbrevs via `get_estimation`. Mismatch ⇒ error listing available abbrevs.
  Roles must exist before efforts reference them (create/add roles first).
- **`create_estimation` role-mimic** — conversationally: Claude calls the existing
  `list_role_templates`, shows the suggested set (with per-currency rates), the user
  tweaks, Claude passes the final `roles[]`. Server-side identical to the modal's
  `create_estimation_from_templates(attrs, role_attrs)`.
- **Transactions** — each tool call is its own transaction (partial progress across calls is
  fine in a conversation). `add_task` + its efforts is internally atomic.
- **Deep links** — `MCPServer.base_url()` + path, `org_id` from claims:
  customer `/org/{org}/customers/{id}` · project `/org/{org}/projects/{id}` ·
  estimation `/org/{org}/projects/{pid}/estimations/{id}/estimator`.
- **Changeset errors** — new `Serializers.changeset_errors/1` (Ecto `traverse_errors`) so
  failures return readable messages (e.g. `"key: has already been taken"`).

## New / changed code

1. **Migration (1)** — add `mcp_write_enabled :boolean, null: false, default: false` to
   `organizations`. Up/down clean.
2. **Schema / context**
   - `Organization`: new `mcp_write_settings_changeset/2` casting `[:mcp_write_enabled]`
     (validate_required); field on schema.
   - `Organizations.update_mcp_write_settings/2` + `mcp_write_enabled?/1`.
   - `Currencies.get_currency_by_code/2`.
3. **MCP layer**
   - `EstimateWeb.MCP.Authz` (gates + `project_id_for/3`).
   - `Serializers` additions: `changeset_errors/1`, `*_url/…` deep-link helpers, and any
     missing entity serializers (role/epic/task already exist).
   - 13 tool modules under `lib/estimate_web/mcp/tools/`; register in `mcp_server.ex`.
4. **Settings UI** — second admin toggle in `#mcp-server-card` ("Allow write access — Claude
   can create & modify data", warning styling), shown/enabled only when `mcp_enabled` is on.
   `handle_event("toggle_mcp_write", …)` → `require_admin` → **reload org** →
   `update_mcp_write_settings(!current)` → flash.

## Testing

TDD, following the read-tool test patterns + `Estimate.MCPTestHelpers` + `mcp_api_key_fixture`.

- **Context**: `get_currency_by_code` (hit / miss / wrong-org); `update_mcp_write_settings`
  + changeset; `mcp_write_enabled?`.
- **Authz** (`MCP.Authz`): each gate with real ids — org-admin vs member; collaborator
  `owner`/`editor` allowed vs `viewer`/non-collaborator denied; `project_id_for` resolution.
- **Per tool**: happy path; each authz denial; **write-disabled** denial (actually flip
  `mcp_write_enabled` — no tautology); cross-org isolation (RLS); changeset-error surfacing;
  currency-code + effort-abbrev resolution errors; `add_task` efforts atomicity (bad abbrev
  ⇒ no task created).
- Gating tests use real ids + cleared flash per [[feedback-characterization-tautology]].

## Non-obvious facts / gotchas

- `mcp_enabled` is an **auth-time** gate (both key + OAuth paths) → server-off blocks every
  request; write tools only add the `mcp_write_enabled` check.
- **RLS is org-only**; project-collaborator authorization must be enforced in code.
- `Organization` settings changesets **no-op on stale structs** (plain `cast`) → the settings
  LV must reload the org before toggling, and tests must `Repo.reload!` before asserting.
- Anubis components are compile-time; write tools always appear in `tools/list`.
- Any settings-page code snippet blocks need `phx-no-format` (formatter-wrapped interpolation
  renders literal indent under `whitespace-pre-wrap`) — only relevant if we add snippets.
- `create_project` already: adds creator as `owner` collaborator, copies org role templates
  into project roles, inherits customer default currency. `create_estimation` inherits the
  project currency when none given.
- **`organization_id` is not caller-settable** — a BEFORE INSERT trigger derives it from the
  parent (`set_project_org_id` from customer, `set_estimation_org_id` from project); child
  tables (epics/tasks/estimation_roles/task_estimates) carry no org column and are scoped via
  parent RLS policies. So tools never set org_id, and a caller cannot spoof org through
  `attrs` — the trigger overwrites it and RLS blocks a cross-org parent. (`customers` is a
  direct-org table; `CRM.create_customer` sets org_id in code.)

## Out of scope (v1) / follow-ups

Deletes (`remove_task`/`remove_epic`/`remove_estimation_role`, soft-delete estimation) —
deliberate fast-follow. Also deferred: reorders; project-role & collaborator & template CRUD
via MCP; auto resolve-or-create; a bulk/composite import tool; write rate-limiting.

## Unresolved questions

1. Effort abbrev match — exact/case-sensitive, error lists available? (**assumed yes**)
2. `update_project` gate — stricter `owner`/`editor` (proposed, consistent with estimation
   editing) vs web-index's looser "any collaborator"? (**proposing owner/editor**)
3. On disabling the server, also force `mcp_write_enabled = false`? (**proposing: leave
   independent; writes are moot while server off**)
