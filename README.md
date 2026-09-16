<div align="center">

# EstiMate

**Collaborative software-project estimation, the multiplayer way.**

Spreadsheet-grade estimation grids · MoSCoW scoping · role-based pricing · AI-assisted breakdowns —
with tenant isolation enforced by PostgreSQL itself.

![Elixir](https://img.shields.io/badge/Elixir-1.15%2B-4B275F?logo=elixir&logoColor=white)
![Phoenix](https://img.shields.io/badge/Phoenix-1.8-FD4F00?logo=phoenixframework&logoColor=white)
![LiveView](https://img.shields.io/badge/LiveView-1.1-FD4F00)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-17%20%2B%20RLS-4169E1?logo=postgresql&logoColor=white)
![Tailwind](https://img.shields.io/badge/Tailwind_CSS-v4-38BDF8?logo=tailwindcss&logoColor=white)
![Tests](https://img.shields.io/badge/tests-288%20passing-2EA44F)

[Quickstart](#-quickstart) · [Architecture](#-architecture) · [Multi-tenancy & RLS](#-multi-tenancy-rls-all-the-way-down) · [Estimation math](#-the-estimation-math) · [JSON import](#-json-import-and-the-agent-prompt) · [Deployment](#-deployment) · [Engineering practice](#-testing-and-engineering-practice)

</div>

---

Every agency has lived this meeting: a spreadsheet named `estimate_FINAL_v7_client_edits.xlsx`, three people editing stale copies, a PM asking *"does this include QA?"*, and nobody able to say what the all-in day rate actually is.

**EstiMate** replaces that spreadsheet with a real-time, multi-user estimation workspace. Break work into epics and tasks, price them per role with explicit PM/QA/risk buffers, tag every line with a MoSCoW priority, and watch totals recalculate live for everyone in the room — no refresh button, no merge conflicts, no `_v7`.

It is also, quietly, a reference implementation of things Phoenix people argue about:

- **Row-Level Security as the tenancy backstop** — the app connects to Postgres as a non-superuser role, and `WHERE org_id = ?` mistakes are caught by the database, not code review.
- **Real-time collaboration** with plain `Phoenix.PubSub` — no JS framework, one small `app.js`.
- **God-LiveView decomposition done with characterization tests** — the whole refactor journal ships in [`docs/superpowers/`](docs/superpowers/), including the five real bugs the tests flushed out.

## ✨ Feature tour

| | |
|---|---|
| 🧮 **Estimation grid** | Spreadsheet-like table: epics → tasks as rows, one column per role. Click any cell to edit (`Enter` saves, `Esc` cancels, blur autosaves), drag-and-drop reordering of epics, tasks, and roles, per-epic subtotals and a sticky grand-total footer. |
| 👥 **Multiplayer by default** | Every change — a cell edit, a renamed epic, a reordered role — broadcasts over PubSub and appears instantly for everyone viewing that estimation. |
| 🎯 **MoSCoW scoping** | Every task is `must` / `should` / `could` / `wont`. Filter the grid by priority (persisted per-estimation in `localStorage`) to answer *"what does the MVP cost?"* in one click. |
| 💰 **Honest pricing** | Per-role hourly rates plus independent **PM / QA / risk-buffer percentages**. Toggle between base rates and *all-in* rates; the cost breakdown panel shows exactly where every euro of overhead goes. |
| 🌍 **Multi-currency** | Per-organization currency table with symbol placement and live FX rates from [Frankfurter](https://frankfurter.dev). Switch the main currency and every rate is recomputed. |
| 🤖 **AI assist** | Bring your own [OpenRouter](https://openrouter.ai) key: one-click description enhancement in task/epic modals, plus a searchable live model picker. Keys are AES-256-GCM encrypted at rest. |
| 📥 **JSON import + agent prompt** | Import whole estimation structures from JSON — or click **"Copy agent prompt"**, paste it into your favorite LLM together with meeting notes, and import the JSON it produces. Workshop transcript → priced estimation in minutes. |
| 📋 **Templates** | Save any estimation as a reusable template, or build templates from JSON. New estimations start from blank, a copy, a template, or an import. |
| 🗑️ **Trash, not regret** | Estimations soft-delete into a per-org trash with restore and permanent-delete. Restoring auto-reinstates "current" status when a project has none. |
| 🏢 **True multi-tenancy** | Organizations with `owner` / `admin` / `member` roles, project-level `owner` / `editor` / `viewer` collaborators, invite links, 8-character invite codes (ambiguity-free alphabet), and join-request approval flows. |
| 🔐 **Security that means it** | Argon2 passwords, Google OAuth, TOTP 2FA with QR setup and hashed backup codes, **org-enforced 2FA with grace-period deadlines**, encrypted SMTP credentials, and PostgreSQL RLS underneath it all. |
| 🔎 **Cross-entity search** | Press `/` anywhere: customers, projects, and estimations ranked by `tsvector` weights with trigram-similarity typo tolerance. |
| 🎨 **Two hand-tuned themes** | Phoenix-inspired light and Elixir-inspired dark (oklch, daisyUI), with a system/light/dark toggle applied pre-paint — no flash of wrong theme. |

## 🚀 Quickstart

Prerequisites: **Elixir 1.15+** (released on 1.18 / OTP 28), **Node.js** (only for `npm install` — the bundler itself is esbuild), **Docker** for Postgres.

```bash
git clone git@gitlab.dac.digital:dacdigital/tools/estimate.git && cd estimate

docker compose up -d            # PostgreSQL 17 on 127.0.0.1:5499 (loopback only)
npm install --prefix assets     # sortablejs — the one npm dependency
mix setup                       # deps, DB create + 51 migrations, assets
mix phx.server
```

Open [localhost:4000](http://localhost:4000), register, and you're in. Sign-up emails land in the dev mailbox at [localhost:4000/dev/mailbox](http://localhost:4000/dev/mailbox); LiveDashboard lives at [localhost:4000/dev/dashboard](http://localhost:4000/dev/dashboard).

Google sign-in is optional — drop credentials in a git-ignored `.env` (loaded by [Dotenvy](https://hexdocs.pm/dotenvy) in dev/test only):

```bash
GOOGLE_CLIENT_ID=...
GOOGLE_CLIENT_SECRET=...
```

### Your first estimation, in five minutes

1. **Register** — create your organization (or join one with an invite code). New orgs come pre-seeded with 4 currencies (USD/EUR/GBP/PLN) and 8 role templates — BA, UX, Mobile, Backend, Frontend, DevOps, AI, Architect — each with rates and default overhead buffers.
2. **Add a customer** (`Customers → New`) — a short unique key, country, default currency.
3. **Create a project** for that customer — it inherits the currency and copies your org's role templates into project roles.
4. **New estimation** — start blank, from a template, or paste JSON. The grid opens with your roles as columns.
5. **Estimate** — click cells, add epics/tasks, tag MoSCoW priorities, watch the cost breakdown update live. Open the same URL in a second browser to see the multiplayer part.
6. **Invite the team** — `Settings → Members` issues email invites or shareable codes; project collaborators get `owner`/`editor`/`viewer` rights per project.

## 🏗 Architecture

Boring on purpose: one Phoenix app, one Postgres, no queue, no cache server, no SPA. The supervision tree is six children (`Telemetry`, `Repo`, `DNSCluster`, `PubSub`, a `Task.Supervisor` for async search indexing, `Endpoint`).

```mermaid
flowchart LR
    B["Browser<br/>(LiveView socket)"] <-->|WebSocket| LV["Phoenix LiveView<br/>thin routers + handler modules"]
    LV --> CTX["Domain contexts<br/>Accounts · Portfolio · EstimationEngine<br/>CRM · Templates · Search · Organizations"]
    CTX <--> PS(("Phoenix.PubSub<br/>estimation:{id}"))
    PS <--> LV
    CTX --> REPO["Estimate.Repo<br/>SET ROLE estimate_app<br/>set_config(app.current_org_id)"]
    REPO --> PG[("PostgreSQL 17<br/>Row-Level Security")]
    CTX -.-> OR["OpenRouter<br/>(AI enhance)"]
    CTX -.-> FX["Frankfurter<br/>(FX rates)"]
    CTX -.-> SMTP["Per-org SMTP<br/>(invites, encrypted creds)"]
```

**The web layer is deliberately thin.** After a documented decomposition campaign (see [engineering practice](#-testing-and-engineering-practice)), big LiveViews are *event routers*: each `handle_event` clause is a one-line delegation to a per-feature handler module (`ProjectLive.Show.{Details, Collaborators, Estimations, …}`) wired up with a shared `use EstimateWeb, :live_handlers` macro. Authorization gates live in dedicated modules (`Show.Authz`, `AuthHelpers.require_admin/2`) instead of being sprinkled through event handlers.

**The domain layer owns the rules.** Contexts expose intent-revealing functions (`set_current_estimation/1`, `soft_delete_estimation/1`, `register_user_and_accept_invite/2`) and side effects like PubSub broadcasts and search reindexing happen *inside* the context, so every caller gets them for free.

### Domain map

| Context | Responsibility |
|---|---|
| `Accounts` | Users, organizations, memberships, invites, join requests, session tokens, TOTP 2FA, org defaults seeding |
| `Portfolio` | Projects, per-project collaborator roles, project roles (rates/overheads) synced to estimations |
| `EstimationEngine` | Estimations, epics, tasks, per-role estimates, pure-`Decimal` calculator, deep-copy, soft delete, JSON import |
| `CRM` | Customers with cascade-aware deletion impact reporting |
| `Templates` | Reusable estimation blueprints (from scratch, JSON, or an existing estimation) |
| `Search` | Cross-entity `tsvector` + trigram index, maintained by DB trigger, reindexed async |
| `Organizations` | Org settings: currencies + FX, AI (OpenRouter), SMTP, 2FA enforcement |
| `ExchangeRates` | Behaviour with a pluggable provider (default: Frankfurter over `Req`) |
| `Encryption` | AES-256-GCM at-rest encryption for org secrets, versioned key ring (v1 derived from `SECRET_KEY_BASE`, v2 `ENCRYPTION_KEY`) |

## 🗃 Data model

Everything is UUID-keyed (`Estimate.Schema`), timestamps are `:utc_datetime`, and every tenant-owned row carries or derives an `organization_id` — kept in sync on `projects` and `estimations` by database triggers, because RLS needs it fast.

```mermaid
erDiagram
    ORGANIZATION ||--o{ MEMBERSHIP : "owner/admin/member"
    USER ||--o{ MEMBERSHIP : ""
    ORGANIZATION ||--o{ INVITE : "email or 8-char code"
    ORGANIZATION ||--o{ CURRENCY : "USD/EUR/GBP/PLN + FX"
    ORGANIZATION ||--o{ ROLE_TEMPLATE : "8 defaults"
    ORGANIZATION ||--o{ CUSTOMER : ""
    CUSTOMER ||--o{ PROJECT : "cascade delete"
    PROJECT ||--o{ PROJECT_COLLABORATOR : "owner/editor/viewer"
    USER ||--o{ PROJECT_COLLABORATOR : ""
    PROJECT ||--o{ PROJECT_ROLE : "copied from templates"
    PROJECT ||--o{ ESTIMATION : "one is_current, soft-deletable"
    ESTIMATION ||--o{ ESTIMATION_ROLE : "rate + PM/QA/risk %"
    ESTIMATION ||--o{ EPIC : "position-ordered"
    EPIC ||--o{ TASK : "MoSCoW priority"
    TASK ||--o{ TASK_ESTIMATE : "hours (decimal)"
    ESTIMATION_ROLE ||--o{ TASK_ESTIMATE : ""
```

Details worth knowing:

- **One "current" estimation per project**, enforced by a partial unique index (`WHERE is_current AND deleted_at IS NULL`) — not by hope.
- **`TaskEstimate` is unique per `(task, role)`** and stores a single decimal `hours`; rates and overheads live on the role, so repricing never touches estimates.
- **Role knowledge exists at three levels** — org `RoleTemplate` → project `ProjectRole` → `EstimationRole` — so an org-wide rate change never silently rewrites a sent quote, while `ProjectRole` edits *do* sync forward to linked estimation roles in one `Ecto.Multi`.
- **Soft delete** is a `deleted_at` column plus a real trash UI, with restore and hard delete.

## 🛡 Multi-tenancy: RLS all the way down

Most SaaS codebases enforce tenancy by remembering to add `where: organization_id == ^org_id` to every query. EstiMate does that too — and then assumes somebody will eventually forget, so **PostgreSQL enforces it independently**.

```mermaid
sequenceDiagram
    participant LV as LiveView mount
    participant OA as OrgAuth hook
    participant R as Estimate.Repo
    participant PG as PostgreSQL

    LV->>OA: on_mount :ensure_org_member
    OA->>OA: verify membership (or redirect)
    OA->>R: put_org_id / put_user_id (process dict)
    LV->>R: context fn → Repo.ensure_org_context
    R->>PG: SET ROLE estimate_app
    R->>PG: SELECT set_config('app.current_org_id', …)
    R->>PG: query
    PG-->>R: rows the policies allow — nothing else
```

The moving parts:

- **A dedicated non-superuser DB role.** Every pooled connection runs `SET ROLE estimate_app` in `after_connect` ([`repo.ex`](lib/estimate/repo.ex)). Superusers bypass RLS; `estimate_app` (`NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE`, only ever reached via `SET ROLE`) cannot.
- **Session-scoped tenancy context.** `Repo.ensure_org_context/1` checks out a connection, pins `app.current_org_id` / `app.current_user_id` via `set_config`, and runs the operation on that connection.
- **Policies that walk the ownership chain.** Direct org tables use simple equality; child tables (`task_estimates` → `tasks` → `epics` → `estimations`) prove lineage with `EXISTS`. And it's not just org-level — projects get **row-level authorization**:

  ```sql
  CREATE POLICY project_access ON projects FOR ALL
    USING (
      organization_id = current_org_id()
      AND (
        is_org_admin()
        OR EXISTS (SELECT 1 FROM project_collaborators pc
                   WHERE pc.project_id = id AND pc.user_id = current_user_id())
      )
    )
    WITH CHECK (organization_id = current_org_id());
  ```

  A plain member who isn't a collaborator doesn't get a `403` — the row simply *does not exist* for them.
- **Documented escape hatches.** `memberships` and `invites` deliberately skip RLS (auth flows are inherently cross-org: "list my organizations", "accept this invite token"), and `Repo.without_rls/1` exists for system-level operations (search reindexing, activity timestamps, MCP/OAuth token bookkeeping) that must see across every org. It does `RESET ROLE` back to the `DATABASE_URL` login role — which owns every table, and Postgres exempts table owners from RLS — and **asserts** that this bypass actually holds (the role has the owner's privileges on every RLS-enabled table and none of them `FORCE ROW LEVEL SECURITY`), raising if the database is mis-provisioned. No superuser and no extra role required. Every exception is a conscious, greppable decision.
- **Defense in depth, not instead of depth.** App-level scoping remains everywhere; `Repo.prepare_query/3` can inject org filters as a second belt. RLS is the backstop that turns "we missed a filter" from a data breach into a blank page.
- **Migrations stay privileged.** DDL runs as the login user — the Repo drops its `after_connect` hook during `ecto.*` tasks and when `SKIP_RLS_ROLE=true` (which is how the release entrypoint migrates).

## 🧮 The estimation math

All money math is [`Decimal`](https://hexdocs.pm/decimal) — floats never touch a price. The calculator ([`calculator.ex`](lib/estimate/estimation_engine/calculator.ex)) is a pure module, unit-tested in isolation:

```
task cost            = Σ over roles ( hours × role.hourly_rate )
role all-in rate     = hourly_rate × (1 + (pm% + qa% + risk%) / 100)
epic total (all-in)  = Σ per-role base cost × (1 + that role's overheads)
weighted avg overhead = total overhead / total base cost × 100
```

Each role carries **three independent buffers** — PM coordination, QA, and risk — instead of one fudge factor. The cost-breakdown panel shows base cost and each buffer as separate lines, so the client conversation changes from *"why is this 30% more?"* to *"here is what QA costs on this project."* A toggle switches every displayed rate between base and all-in.

## 📡 Real-time collaboration

No CRDTs, no operational transforms — estimation grids are coarse-grained enough that a well-shaped broadcast does the job:

- Every estimation has a PubSub topic (`"estimation:" <> id`); the grid LiveView subscribes on connect.
- Context modules broadcast **14 domain events** (`:estimate_updated`, `:epic_created`, `:tasks_reordered`, `:role_deleted`, …) *after* successful writes — from the context, so any future caller (an API, a job) broadcasts for free.
- The editor's own cell and rate edits apply **optimistically in memory** — no round-trip re-render; everyone else reloads the estimation on broadcast.
- Logout broadcasts a disconnect to the user's `live_socket_id`, so a stolen tab dies with the session.

## 📥 JSON import and the agent prompt

Estimation *structure* is portable JSON — deliberately hours-free, because scope comes from workshops but pricing is yours:

```json
{
  "estimation": "Mobile Banking MVP",
  "description": "Scoped during the March discovery workshop",
  "currency": "EUR",
  "epics": [
    {
      "name": "Onboarding & KYC",
      "description": "Account creation flow with identity verification",
      "tasks": [
        { "name": "Phone + email registration", "priority": "must" },
        { "name": "Document scanning integration", "priority": "must" },
        { "name": "Biometric login", "priority": "should" }
      ]
    },
    {
      "name": "Payments",
      "tasks": [
        { "name": "SEPA transfers", "priority": "must" },
        { "name": "Scheduled payments", "priority": "could" }
      ]
    }
  ]
}
```

Rules, enforced by [`json_import.ex`](lib/estimate/estimation_engine/json_import.ex): `epics` is a non-empty array; every epic and task needs a `name` (≤ 255 chars); `priority` is optional and defaults to `"must"`; documents are capped at 1 MB. Roles and hours are attached in-app after import.

**The killer workflow** is the built-in *agent prompt*: the import panel's **"Copy agent prompt"** button produces a complete LLM instruction — schema, MoSCoW mapping rules, formatting constraints. Paste it into Claude/ChatGPT/Gemini along with raw meeting notes or a transcript, paste the JSON back (or upload the file), and the panel live-validates: *"4 epics, 23 tasks will be imported."* The same importer feeds both new estimations and reusable templates.

Exports go the other way richer: the grid's **Copy JSON** emits roles, per-task effort maps, hours and cost totals per epic and grand totals — a machine-readable quote for downstream tooling.

## 🤖 AI assist

- **Bring your own key** — each organization configures its own [OpenRouter](https://openrouter.ai) API key (AES-256-GCM encrypted at rest, masked in the UI, balance/usage shown via `assign_async`).
- **Any model** — a search-as-you-type picker over OpenRouter's live catalog (ETS-cached for an hour); defaults to `openai/gpt-4o-mini`. Custom system prompt per org.
- **Enhance in place** — task and epic modals grow a ✨ button when AI is configured. The call runs under LiveView's `start_async`/`handle_async` (the UI never blocks — a spinner does), and the result is written back into the textarea through a `push_event`, form-change semantics intact.

## 🔐 Security posture

| Layer | What's implemented |
|---|---|
| Passwords | Argon2 (`argon2_elixir` 4.x) with a dummy-verify on unknown emails to equalize timing; 8–72 byte length rule |
| 2FA | TOTP (`nimble_totp`) with QR enrollment (`eqrcode`), 10 single-use backup codes stored SHA-256-hashed, **max 5 verify attempts per login**, and **org-wide enforcement** with per-member grace deadlines that lock non-compliant members out of the org until they enroll |
| OAuth | Google via `Assent` (verified-email required); OAuth users get password-less accounts and can set a password later; TOTP still applies |
| Sessions | 60-day DB-backed tokens, session renewal + CSRF token reset on login, signed 60-day remember-me cookie (`SameSite=Lax`), LiveView socket kill on logout |
| Secrets at rest | Org OpenRouter keys, SMTP passwords, and TOTP secrets encrypted with AES-256-GCM (12-byte nonce, 16-byte tag), versioned key ring (v1 PBKDF2-derived from `SECRET_KEY_BASE`, v2 `ENCRYPTION_KEY`); readers lazily re-encrypt to the newest key |
| Tenancy | PostgreSQL RLS under a non-superuser role — see [above](#-multi-tenancy-rls-all-the-way-down) |
| Web | `force_ssl` + HSTS behind `x-forwarded-proto` (health endpoints exempt), CSRF protection, secure browser headers, open-redirect guard on every `return_to` |
| Input hygiene | No `String.to_atom/1` on user input anywhere — client-supplied enums go through explicit whitelist maps; invite codes use an ambiguity-free alphabet; invites expire after 7 days |

> [!NOTE]
> The at-rest encryption key ring is versioned (see `Estimate.Encryption`). Without `ENCRYPTION_KEY` set, `SECRET_KEY_BASE` is still the only key (v1) — rotating it invalidates every stored org secret. Set `ENCRYPTION_KEY` to add a v2 key independent of `SECRET_KEY_BASE`; existing v1 secrets are re-encrypted to v2 lazily on read, or eagerly via `mix estimate.rotate_encryption`.

## ⚙️ Configuration

Runtime config follows the standard Phoenix split: compile-time in `config/*.exs`, everything environment-specific in [`config/runtime.exs`](config/runtime.exs). In dev/test, a git-ignored `.env` is loaded via Dotenvy; in prod only real environment variables count.

| Variable | Scope | Required | Notes |
|---|---|---|---|
| `DATABASE_URL` | prod | **yes** (raises) | `ecto://USER:PASS@HOST/DB` |
| `SECRET_KEY_BASE` | prod | **yes** (raises) | `mix phx.gen.secret` — also derives the v1 at-rest encryption key (see note above) |
| `PHX_HOST` | prod | **yes** (raises) | Public hostname for URL generation |
| `PHX_SERVER` | all | release | Presence starts the HTTP listener (`bin/server` sets it) |
| `PORT` | all | no | Default `4000` |
| `POOL_SIZE` | prod | no | Default `20` |
| `ECTO_IPV6` | prod | no | `true` → IPv6 DB socket |
| `DNS_CLUSTER_QUERY` | prod | no | Headless-service DNS for Erlang clustering |
| `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` | all | no | Enables Google sign-in when both set |
| `DATABASE_ROLE_PASSWORD` | migrations | no | Password set on `estimate_app` at `CREATE ROLE` time (first migration only). `estimate_app` is only ever reached via `SET ROLE` on a connection already authenticated as the `DATABASE_URL` role, so nothing connects with it; optionally have a DBA run `ALTER ROLE estimate_app NOLOGIN` (needs `CREATEROLE` + `ADMIN OPTION` on PG16+, so it is not done by a migration). `bin/migrate` runs as the `DATABASE_URL` role — the **database owner**, no superuser needed — never as `estimate_app`; that's what `SKIP_RLS_ROLE=true` in `migrate_and_server` ensures. |
| `SKIP_RLS_ROLE` | ops | no | Skips `SET ROLE` on connect — used by the release migration wrapper |
| `TRUSTED_PROXY_HOPS` | prod | no | Default `1`. `x-forwarded-for` hops trusted by `EstimateWeb.ClientIP`; set `0` when not behind a proxy |
| `RATE_LIMIT_LOGIN_EMAIL` / `RATE_LIMIT_LOGIN_IP` / `RATE_LIMIT_TOTP_ATTEMPT` / `RATE_LIMIT_OAUTH_IP` | prod | no | Overrides for `Estimate.RateLimit` bucket limits; defaults `10` / `60` / `5` / `20` |
| `OAUTH_JANITOR_INTERVAL_MS` | prod | no | Sweep interval (ms) for `Estimate.MCP.OAuth.Janitor` (expired codes, dead tokens, and orphan dynamically-registered clients older than 24h); default `3600000` (1 hour) |
| `CSP_REPORT_ONLY` | prod | no | `true` → Content-Security-Policy is sent as `Content-Security-Policy-Report-Only` instead of enforced; default enforced |
| `ENCRYPTION_KEY` | prod | no | Base64 of 32 random bytes (`openssl rand -base64 32`); when set, new secrets use it and old ones are re-encrypted on read or via `mix estimate.rotate_encryption`. Once set, `ENCRYPTION_KEY` must never be removed or replaced without first rotating: rows encrypted with it become permanently undecryptable; keep the old `SECRET_KEY_BASE` until `Rotation.run/0` reports nothing left on v1. |

Per-organization settings (SMTP relay, AI key/model/prompt, currencies, 2FA policy) live in the database, not the environment — this is a multi-tenant app; tenants configure themselves.

### MCP access: API keys, OAuth scopes and connected apps

The MCP server (`/mcp`) is reachable two ways, with different access levels:

- **API keys** (per-user, per-org, created under Settings → MCP) — full access to every enabled tool, read and write.
- **OAuth connectors** (e.g. claude.ai) — a client requests `mcp:read` and/or `mcp:write` at connect time; the consent screen shows exactly what's being granted, and if the client didn't ask for write, an opt-in checkbox on that screen can add it anyway. Either way, write tools also require the org's own MCP write toggle (Settings → MCP) — a connector holding `mcp:write` still can't write in an org that has writes disabled.

Users see and revoke their connected apps under **Account → Connected apps**. A grant expires 90 days after consent regardless of use, and changing your password immediately revokes every one of your connectors' tokens.

## 🚢 Deployment

### Docker

The [`Dockerfile`](Dockerfile) is a cache-friendly multi-stage build (Elixir 1.18.4 / OTP 28.3.1 → Debian bookworm-slim) that installs Node 22 solely for `npm ci --prefix assets`, compiles assets, and cuts an OTP release via `mix phx.gen.release`. The runtime image:

- runs as **`USER nobody`**,
- ships a **`HEALTHCHECK`** against `/healthz`,
- boots through `bin/migrate_and_server` — **migrations run automatically** (with `SKIP_RLS_ROLE=true`), then the server starts.

```bash
docker build -t estimate .
docker run -p 4000:4000 \
  -e DATABASE_URL=ecto://postgres:postgres@db/estimate_prod \
  -e SECRET_KEY_BASE=$(mix phx.gen.secret) \
  -e PHX_HOST=estimate.example.com \
  estimate
```

Manual migration control, if you'd rather not auto-migrate:

```bash
docker run --rm -e SKIP_RLS_ROLE=true -e DATABASE_URL=... -e SECRET_KEY_BASE=... -e PHX_HOST=... \
  estimate /app/bin/migrate
```

### Rotating the at-rest encryption key

1. Generate a new key: `openssl rand -base64 32`.
2. Set it as `ENCRYPTION_KEY` and deploy — the key ring now has v2, and every new/lazily-read secret uses it, but existing rows stay on v1 until rotated.
3. Eagerly re-encrypt everything still on v1: `bin/estimate eval 'Estimate.Encryption.Rotation.run() |> IO.inspect()'` (the `mix estimate.rotate_encryption` task is the dev/CI entry point only — it isn't available in a release).
4. Confirm the result shows zero `users_failed` / `organizations_failed`; if either is non-zero, the run still rotated everything it could and logged the reason for each failure (`rotate: could not re-encrypt ...`) — fix and re-run before proceeding.
5. Only once rotation reports nothing left on v1 is it safe to retire the old `SECRET_KEY_BASE`. Removing or replacing `ENCRYPTION_KEY` (or the old `SECRET_KEY_BASE`) before that permanently bricks whatever is still encrypted with it.

### Kubernetes

The app is cluster-ready: stateless nodes, DB-backed sessions, WebSockets pinned per-connection (no sticky sessions needed), and optional Erlang clustering via `dns_cluster`.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: estimate
spec:
  replicas: 2
  selector: { matchLabels: { app: estimate } }
  template:
    metadata: { labels: { app: estimate } }
    spec:
      containers:
        - name: estimate
          image: registry.example.com/estimate:latest   # entrypoint auto-migrates
          ports: [{ containerPort: 4000 }]
          envFrom: [{ secretRef: { name: estimate-env } }]
          livenessProbe:
            httpGet: { path: /healthz, port: 4000 }
            initialDelaySeconds: 10
          readinessProbe:
            httpGet: { path: /readyz, port: 4000 }   # includes a DB round-trip
            periodSeconds: 10
```

Operational notes:

- **Clustering** — set `DNS_CLUSTER_QUERY` to a headless Service (`estimate.default.svc.cluster.local`) and PubSub broadcasts flow across pods, so two users on different replicas still co-edit in real time. Without it, run one replica or pin estimation traffic.
- **Pool sizing** — `POOL_SIZE ≈ total desired DB connections ÷ replicas`.
- **TLS** — `force_ssl` expects an `x-forwarded-proto`-setting ingress; `/health*` paths are exempt so plain-HTTP probes work.
- **Database TLS** — not enabled yet on the Repo (tracked in `runtime.exs`); terminate inside a trusted network or enable `ssl:` when your Postgres has certs.
- **`TRUSTED_PROXY_HOPS`** (default `1`) — how many `x-forwarded-for` hops `EstimateWeb.ClientIP` trusts for rate-limiting; set `0` if the app is ever exposed directly, without a reverse proxy in front of it.
- **Migrations run as the database owner, not a superuser** — the `DATABASE_URL` role must own the database (and therefore every table it creates). `Repo.without_rls/1` relies on that ownership to bypass RLS and asserts it at runtime, so pointing `DATABASE_URL` at a role that does *not* own the tables makes every `without_rls` call raise. Pre-deploy check: `psql "$DATABASE_URL" -tAc "select bool_and(pg_has_role(current_user, relowner, 'USAGE')) from pg_class where relrowsecurity"` must print `t`. Never `FORCE ROW LEVEL SECURITY` on app tables. If a migration fails, `migrate_and_server` exits non-zero (`set -e`) and the pod crash-loops instead of serving a half-migrated schema.
- **Integrity migration locks** — `TightenIntegrityConstraints` takes short `ACCESS EXCLUSIVE` locks per table while adding `NOT NULL`/FK constraints. Fine at current scale; at a much larger table size, split it into `ADD CONSTRAINT ... NOT VALID` followed by a separate `VALIDATE CONSTRAINT` to avoid a long-held lock during validation.
- **Rate limiting is per-node, in-memory ETS state** (`Estimate.RateLimit`): with more than one replica each pod enforces its own limits independently, and all counters reset on every deploy. The TOTP replay guard is DB-backed (`users.totp_last_used_at` + `NimbleTOTP` `:since`), so it is consistent across replicas and survives deploys; the in-memory rate limits remain per-node.
- **CSP is enforced**; flip `CSP_REPORT_ONLY=true` and restart if a page breaks; add hosts to the policy in `EstimateWeb.Plugs.ContentSecurityPolicy`.

### Health endpoints

| Path | Purpose | Behavior |
|---|---|---|
| `GET /healthz`, `GET /health` | Liveness | Always `200 {"status":"ok"}` — no dependencies |
| `GET /readyz` | Readiness | `SELECT 1` with a 2 s timeout; `200` with `checks.database` or **`503`** when the DB is unreachable |

## 🧪 Testing and engineering practice

```bash
mix test        # 288 tests, ~17s (async where possible)
mix precommit   # compile --warnings-as-errors + unused-dep check + format + full suite
```

This codebase went through a documented **web-layer quality overhaul**, and the entire paper trail ships in [`docs/superpowers/`](docs/superpowers/) — [`specs/`](docs/superpowers/specs/) hold the design decisions, [`plans/`](docs/superpowers/plans/) the step-by-step executable plans. Read them in filename (date) order and you get the whole story arc: charter → test safety net → cluster-by-cluster refactor.

The method, in one paragraph: **characterize first, then decompose.** Before touching any "god LiveView", a characterization suite pins its *current* behavior — every event, every authorization path, exact flash messages, exact redirects. Assertions must pass on first run; a red characterization test means you found a latent bug, and the rule is *stop and report, never bend the assertion*. Only then is the module decomposed — thin event-router LiveView, per-feature handler modules, dedicated authz module — with the suite standing guard.

It works. The test base grew from 6 domain test files to 26 files / 288 tests, `ProjectLive.Show` shrank from **1,568 lines and 40 event handlers** to a 428-line router plus 6 handler modules and 4 markup components — and characterization flushed out **five real bugs**, each fixed at the right layer:

1. **Non-atomic registration** — a failed invite/join left an orphaned user row; now a single `Ecto.Multi` across all three onboarding paths.
2. **Orphaned projects on member removal** — incomplete ownership-reassignment maps silently passed validation; fixed in the context so *no* caller can orphan.
3. **Atom-exhaustion vector** — `String.to_existing_atom` on client input replaced by an explicit whitelist map.
4. **Cross-org ID crash** — a foreign estimation ID raised `Ecto.NoResultsError` instead of failing gracefully; now a tenant-safe fetch helper.
5. **Admin/owner asymmetry** — org admins couldn't remove owner-role collaborators; the fix also activated a previously unreachable last-owner guard.

House rules that keep it this way: `mix precommit` before every push, one PR per feature cluster, verify-before-delete for dead code, no schema/migration changes during refactors, and [`AGENTS.md`](AGENTS.md) — the project's standing instructions for AI pair-programmers (this codebase is developed human-with-agent, and the guardrails are versioned).

## 📁 Project structure

```
lib/
├── estimate/                      # Domain layer (contexts)
│   ├── accounts/                  #   users, orgs, memberships, invites, TOTP
│   ├── ai/                        #   OpenRouter client (ETS-cached model list)
│   ├── crm/                       #   customers
│   ├── estimation_engine/         #   estimations, epics, tasks, calculator,
│   │                              #   copy, JSON import, soft delete
│   ├── exchange_rates/            #   Frankfurter provider (behaviour)
│   ├── portfolio/                 #   projects, collaborators, project roles
│   ├── search/                    #   tsvector + trigram search index
│   ├── templates/                 #   reusable estimation templates
│   ├── encryption.ex              #   AES-256-GCM for org secrets
│   ├── repo.ex                    #   RLS-aware Repo (SET ROLE, org context)
│   └── schema.ex                  #   UUID PK / utc_datetime base schema
├── estimate_web/
│   ├── components/                # core components, layouts, themes
│   ├── controllers/               # sessions, Google OAuth, health
│   └── live/                      # LiveViews: thin routers + handler modules
│       ├── estimator_live/        #   the estimation grid + cost breakdown
│       ├── project_live/          #   projects, tabs, collaborators
│       └── settings_live/         #   members, currencies, AI, email, trash
docs/superpowers/                  # design specs + executable refactor plans
priv/repo/migrations/              # 51 migrations: RLS policies, triggers,
                                   # tsvector, check constraints
test/                              # 288 tests incl. characterization suites
```

## 🧭 Design notes & trade-offs

Choices a reviewer would ask about, answered up front:

- **Broadcast-reload over CRDTs.** Concurrent cell edits last-write-win; structural changes reload the grid. For estimation workshops (a handful of concurrent editors) this is the right complexity budget.
- **No LiveView streams yet.** Grids re-render from full assigns; the editor's own keystrokes are already optimistic in-memory updates. Streams + per-row diffing for large grids is the next planned phase (the bar: *editing one cell must not re-render the table*).
- **AI responses are not streamed** — single request/response in a supervised Task. Descriptions are short; a spinner beats streaming plumbing.
- **FX rates refresh on demand**, stamped with `rates_fetched_at` — estimation is not a trading desk; deterministic quotes beat auto-drifting ones.
- **Import ≠ export format.** Imports carry structure only (scope travels between tools); exports carry full pricing (quotes leave the system). Asymmetry is intentional.
- **Custom `current_user`/`current_organization` assigns** rather than Phoenix 1.8's `Scope` struct — the migration to a unified `%Scope{}` is planned as its own cross-cutting change.
- **i18n is wired** (gettext) but only `en` ships today.

## 🗺 Roadmap

- [ ] **Estimator grid performance** — LiveView streams, per-row diffing for very large estimations (the last planned refactor phase)
- [ ] **`%Scope{}` migration** — unify auth assigns into a scope struct + shared `on_mount` plumbing
- [ ] **Focused security/concurrency pass** — RLS coverage for collaborator-role updates, live invalidation of mount-cached permissions
- [ ] **Database TLS** in production
- [ ] **Phase 2: visual/UX polish** — the structural overhaul (Phase 1) is done; the design pass is next

## 🤝 Contributing

1. Read [`AGENTS.md`](AGENTS.md) (humans benefit too) and skim the relevant spec in [`docs/superpowers/specs/`](docs/superpowers/specs/).
2. Refactoring something load-bearing? **Characterize it first** — pin current behavior with exact assertions, then change it.
3. `mix precommit` must pass: zero warnings, formatted, 288+ green.
4. One PR per feature cluster; if you found a latent bug mid-refactor, fix it at the right layer (context, not template) and flip exactly the test that pinned it.

---

<div align="center">

Built with Phoenix LiveView and a healthy distrust of spreadsheets at [dac.digital](https://dac.digital)

*If this README made you want to `git clone` — that was the point.*

</div>
