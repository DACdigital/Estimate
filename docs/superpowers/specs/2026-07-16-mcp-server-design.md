# MCP Server — Design

**Date:** 2026-07-16
**Status:** Approved (brainstorm), pending implementation plan

## Goal

Expose org data via a standard MCP endpoint at `/mcp` so MCP clients (Claude Code/Desktop, Cursor, …) can read it. Org admins enable/disable per org. Each member authenticates with a personal API key that inherits their RLS privileges — MCP sees exactly what the user sees in the UI.

## Decisions (from brainstorm)

| Question | Decision |
|---|---|
| Tool surface | Read-only v1 |
| Key scoping | Per `(user, organization)` membership |
| Keys per membership | 1 active; regenerate = revoke old + issue new; no expiry |
| Toggle level | Org-level (`organizations.mcp_enabled`), editable by owner/admin |
| UI | Single settings page `/settings/mcp` (admin toggle + personal key section) |
| Data scope | All user-visible data (customers, projects, estimations, templates, rates, currencies/FX, search) |
| Protocol impl | `anubis_mcp ~> 1.8` (accepted trade-offs: LGPL-3.0 dep, framework sessions) |

## Architecture

- **Dep:** `{:anubis_mcp, "~> 1.8"}`.
- **Server:** `EstimateWeb.MCPServer` — `use Anubis.Server, name: "Estimate", version: <app vsn>, capabilities: [:tools]`; one `component` per tool module; `authorization` configured with custom validator (below).
- **Supervision:** `{EstimateWeb.MCPServer, transport: :streamable_http}` in `application.ex`.
- **Router:** `forward "/mcp", Anubis.Server.Transport.StreamableHTTP.Plug, server: EstimateWeb.MCPServer` — outside browser pipelines (no session/CSRF). Anubis owns JSON-RPC, version negotiation, sessions, SSE.

## Auth: API key → RLS bridge

### Data

- Table `mcp_api_keys`: `user_id` (FK), `organization_id` (FK), `key_hash` (sha256, unique), `key_prefix` (~12 chars, UI identification), `last_used_at`, timestamps. Unique `(user_id, organization_id)`.
- `organizations.mcp_enabled :boolean, default: false, null: false`.
- Key format: `est_` + 32 random bytes base64url. Shown once at generation; only hash stored.

### Validator

`Estimate.MCP.KeyValidator` implements `Anubis.Server.Authorization.Validator`:

1. sha256 the bearer token → lookup key row via `Repo.without_rls` (verification precedes org context by definition; same escape hatch as search reindexing).
2. Join membership + organization. Reject (→ 401) when: key unknown, membership gone, or `mcp_enabled == false`.
3. Return `{:ok, %{"sub" => user_id, "org_id" => org_id}}` — claims land on the tool `frame`.

Consequences: toggle off, member removal, or key revocation kills access on the next request. No new authorization logic beyond the lookup.

### RLS in tools

Anubis may execute tools outside the HTTP request process → never rely on ambient state. Shared helper:

```elixir
Estimate.MCP.with_scope(frame, fun)
# reads user_id/org_id from frame claims, then:
# Repo.put_user_id(user_id); Repo.with_org_context(org_id, fun)
```

Every tool body runs inside it. Set per-execute ⇒ no leakage even if sessions share a process. DB privileges identical to the user's LiveView session.

### RLS on `mcp_api_keys` itself

Normal org-context policy for user-facing operations (member manages own row; admin visibility optional later). Only the verification lookup bypasses RLS via `without_rls`.

## Tools (v1, read-only)

| Tool | Args | Returns |
|---|---|---|
| `list_customers` | `search?`, `limit?` | id, name, currency, project count |
| `get_customer` | `id` | full customer |
| `list_projects` | `customer_id?`, `search?`, `limit?` | id, name, customer, currency |
| `get_project` | `id` | project + roles + estimation summaries |
| `list_estimations` | `project_id` | summaries |
| `get_estimation` | `id` | full tree: epics → tasks → per-role estimates + totals |
| `list_templates` | `limit?` | template summaries |
| `get_template` | `id` | template + epics + tasks |
| `list_role_templates` | — | roles + rates |
| `list_currencies` | — | org currencies + FX rates |
| `search` | `query` | cross-entity, reuses existing search context |

- Args validated via anubis schema DSL; results as JSON content.
- `limit` default 50, max 200.
- Field shapes decided at implementation, mirroring what LiveViews show (never more).
- Tool modules under `EstimateWeb.MCP.Tools.*`, one module per tool, all delegating to existing context functions.

## Settings UI — `/settings/mcp`

Sidebar entry "MCP" beside AI/Email.

- **Admin block** (owner/admin only, existing settings authz pattern): enable toggle + endpoint URL display.
- **Personal block** (any member; visible only when org enabled): key status (prefix, created, last used) · Generate/Regenerate (confirm → one-time key modal: copy button + ready `claude mcp add --transport http estimate <url>/mcp --header "Authorization: Bearer <key>"` snippet) · Revoke.
- Admin management of other members' keys: **not v1** (toggle-off is the kill switch); follow-up.

## Errors & observability

- Bad/missing/revoked key or disabled org → 401 (anubis shapes the response from validator error).
- Unknown or foreign-org id → MCP tool error "not found". RLS makes cross-org and nonexistent indistinguishable — no existence oracle.
- Unexpected exceptions → anubis internal error handling; logged.
- Telemetry event + Logger metadata (`user_id`, `org_id`, tool name) per tool call.
- `last_used_at` updated at most every 5 minutes per key (no hot writes).

## Testing

- **Context** (`Estimate.MCP`): generate (hash stored, plaintext returned once), regenerate revokes old, revoke, verify paths — unknown key, revoked, org disabled, membership removed. RLS policy on `mcp_api_keys` via `DataCase.setup_rls`.
- **Validator:** unit tests for claim shape + rejection reasons.
- **Integration (ConnCase):** JSON-RPC against `/mcp` — initialize → tools/list → tools/call with a real generated key. **Cross-org isolation:** org A key never reads org B rows (RLS seeding trick from prior work).
- **Settings LV:** toggle visible/editable only for owner/admin; key shown once; regenerate invalidates old key (no-tautology characterization discipline: diverge state before asserting).

## Migrations

1. `add :mcp_enabled` to `organizations`.
2. `create table :mcp_api_keys` + indexes + RLS policy.

## Out of scope v1 (follow-ups)

- OAuth authorization server (required only for claude.ai web connectors; header-capable clients covered).
- Rate limiting on `/mcp`.
- Write tools.
- Admin management of other members' keys.
- MCP resources/prompts (cheap to add later under anubis).

## Open questions

- None blocking. Rate limiting deliberately deferred — revisit if abuse observed.
