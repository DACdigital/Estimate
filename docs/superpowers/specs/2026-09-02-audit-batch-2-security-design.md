# Audit Batch 2 — Remaining Security Fixes — Design

Source: full audit 2026-09-02 (artifact "Estimate Black-Belt Audit") and the batch-1 final review. Batch 1 (`main@86dd7bc`) closed the reproduced authorization bugs, parent-FK mass assignment, the LOGIN-capable DB role, and added throttling. This spec covers the remaining security items, delivered as three sequential sub-batches, each on its own branch with its own implementation plan and local merge:

- **2a — OAuth hardening**
- **2b — Crypto + membership**
- **2c — Integrity + infra**

**Explicitly excluded until the owner says otherwise:** password-reset mail, email confirmation, and restricting Google OAuth linking to confirmed accounts (audit roadmap #4).

## Global constraints

- Additive migrations are allowed: new columns/indexes/constraints/roles with safe defaults and backfills. No drops, no renames, no type changes.
- Every fix lands with a diverge-then-assert test: put the forbidden state in place, prove rejection, prove the DB is unchanged (see memory `feedback-characterization-no-tautology`).
- `mix precommit` green at every merge (compile --warnings-as-errors, deps.unlock --unused, format, full suite).
- No new runtime dependencies beyond what is named here (none planned).
- Flash/error copy is given verbatim where it matters; everything else follows existing house style ("Not authorized", "Not found").

---

## 2a. OAuth hardening

### Scopes
- Two scopes: `mcp:read`, `mcp:write`. `offline_access` remains accepted and ignored (it is advertised today).
- `/oauth/authorize` reads the optional `scope` param (space-separated). Unknown values → `invalid_scope` error redirect. Absent → `mcp:read`.
- Consent screen (`oauth_authorize_html/consent.html.heex`) lists the requested scopes in plain language: "Read your estimation data" and, when requested, a visually distinct line "Create and edit customers, projects and estimations as you". The "read-only" sentence is removed. The `scope` value is carried through the hidden inputs.
- Persistence: `oauth_codes.scope` and `oauth_tokens.scope` (`:string`, `null: false`, `default: "mcp:read"`); migration backfills existing rows with `mcp:read`. Existing grants therefore stay read-only until the user re-consents (owner decision).
- `OAuth.create_code/1` stores the granted scope; `exchange_code/2` copies it to the token; `refresh_tokens/2` copies it to the rotated token. Token response includes `scope: token.scope`.
- `OAuth.verify_access_token/1` returns `scope` in the auth map; `MCP.verify_api_key/1` returns `"mcp:read mcp:write"` (API keys keep full scope, shown as such on `/settings/mcp`). `KeyValidator` puts `"scope"` into the claims; `Scope.claims/1` exposes `scopes :: [String.t()]`.
- `Write.execute/3` requires `"mcp:write"` in `claims.scopes` before the org toggle: `{:error, :insufficient_scope}` renders "this connection was authorized read-only; reconnect it and grant write access". Read tools are unaffected.
- Metadata: `scopes_supported: ["mcp:read", "mcp:write", "offline_access"]` on both documents. `MCPServer` moduledoc and `/settings/mcp` copy drop "read-only".

### Connected apps
- `OAuth.list_grants(user_id)` returns one entry per active token family: client name, organization name, scope, `granted_at` (originating code `inserted_at`), `last_used_at`, `family_id`. Active = has a token with `revoked_at IS NULL` and `refresh_expires_at > now`.
- `OAuth.revoke_grant(user_id, family_id)` revokes the family only if it belongs to `user_id`; returns `{:ok, n}` or `{:error, :not_found}`.
- `UserLive.AccountSettings` gains a "Connected apps" card listing grants with a Revoke button (confirm modal, house style). Empty state copy: "No connected apps."
- `Accounts.update_user_password/3` and `Accounts.reset_user_password/2` call `OAuth.revoke_all_for_user(user_id)` after commit.

### Lifetime, registration, pruning
- Refresh is refused when the originating code's `inserted_at` is older than 90 days (`{:error, :invalid_grant}`), regardless of the sliding `refresh_expires_at`. No new column.
- `OAuth.Client.registration_changeset/2`: `validate_length(:name, max: 100)`, `validate_length(:redirect_uris, min: 1, max: 5)`, each URI `String.length <= 2048` (error on `:redirect_uris`).
- `Estimate.MCP.OAuth.Janitor` (GenServer under `Estimate.Supervisor`, runs at start + every hour, disabled in test via config): deletes `oauth_codes` with `expires_at < now - 1 hour` and `oauth_tokens` with `revoked_at < now - 7 days` or `refresh_expires_at < now - 7 days`. Runs inside `Repo.without_rls/1`. Logs counts at `:info`.
- API-key expiry stays deferred.

### Tests (2a)
Scope requested/absent/unknown at authorize; consent renders both scope lines; code→token→refresh carry scope; write tool with `mcp:read` token → insufficient_scope; API key → write allowed (with toggle on); backfilled tokens read as `mcp:read`; list/revoke grants incl. cross-user revoke → not_found; password change revokes families; 90-day absolute cap via backdated code; DCR limits; janitor deletes only expired/revoked-old rows.

---

## 2b. Crypto + membership

### TOTP replay across nodes
- Migration: `users.totp_last_used_at :utc_datetime`.
- `Totp.valid_code?/3` becomes `valid_code?(user, secret, code)` → `NimbleTOTP.valid?(secret, code, since: user.totp_last_used_at)`; on success the caller persists `totp_last_used_at = now` (in `Totp.valid_code_or_backup?/3`, which returns `{:ok, user}` / `:error`). `verify_totp` and TOTP setup/disable flows updated to the new return shape.
- The `:totp_replay` rate-limit bucket is removed (RateLimit, config, tests, README note). `:totp_attempt` stays.

### Encryption key rotation
- `ENCRYPTION_KEY` env (base64 of 32 random bytes) in `runtime.exs`; absent → key v1 only (current behaviour).
- `Estimate.Encryption` keeps a key ring `%{1 => derive(secret_key_base), 2 => env_key}` in `:persistent_term` (populated at application start). `encrypt/1` returns `{:ok, nonce, ciphertext, key_version}` using the newest key; `decrypt/3` takes `(nonce, ciphertext, key_version)`.
- Migration: `users.totp_key_version`, `organizations.openrouter_key_version`, `organizations.smtp_key_version` (`:integer`, `null: false`, `default: 1`).
- Call sites (`Totp.enable_totp/3`, `Totp.get_decrypted_secret/1`, `Organizations.update_ai_settings/2`, `update_smtp_settings/2`, `get_decrypted_api_key/1`, `get_decrypted_smtp_password/1`) store and read the version. After a successful decrypt with an older version, the value is re-encrypted with the current key and persisted (lazy rotation) inside `Repo.without_rls/1`-free code paths (they already run in org context).
- `mix estimate.rotate_encryption` re-encrypts every row not on the current version; idempotent; prints counts.

### Membership
- `Invite.generate_code/1` uses `:crypto.strong_rand_bytes` mapped onto the 32-char alphabet.
- `Organizations.invite_acceptance_multi/2` claims the invite atomically: `Ecto.Multi.update_all(:claim, from(i in Invite, where: i.id == ^id and is_nil(i.accepted_at) and i.expires_at > ^now), set: [accepted_at: now])` and fails with `{:error, :invalid_invite}` unless exactly one row was updated. The pre-read `verify_still_valid` step is removed.
- `Organizations.transfer_ownership(org_id, actor_user_id, target_user_id)`: actor must be an owner of the org, target must be a member (any role); in one Multi target → `"owner"`, actor → `"admin"`. Errors: `:not_owner`, `:not_a_member`, `:same_user`.
- `Organizations.leave_organization(user_id, org_id)`: refused with `:sole_owner` if the user is the only owner of the org, `:sole_project_owner` if they are the only `"owner"` collaborator on any project of the org; otherwise `delete_membership/2` with no reassignments. Flash copy: "Transfer ownership before leaving." / "Transfer your projects before leaving."
- `Organizations.update_membership_role/2` and both `Invite` changesets accept only `Membership.assignable_roles()` (`admin`, `member`). Owner is reachable only via organization creation and `transfer_ownership/3`.
- `approve_join_request/2` requires `status == "pending"` (`{:error, :not_pending}`).
- `Portfolio.add_collaborator/3` asserts the user is a member of the project's organization (`{:error, :not_a_member}`).
- UI: members roster row action "Make owner" (visible to owners only, confirm modal) → `transfer_ownership`; org settings General page card "Leave organization" (hidden for sole owners with the explanatory text instead).

### Tests (2b)
Replay of a valid code fails after `totp_last_used_at` is set, across two fresh conns (no ETS involved); encryption round-trip per version, lazy re-encrypt bumps version, mix task rotates and is idempotent, decrypt of v1 data still works when `ENCRYPTION_KEY` set; invite code alphabet/length from CSPRNG (statistical smoke: 1000 codes, all chars in alphabet, no duplicates); concurrent invite acceptance: two Tasks race on one code, exactly one succeeds; transfer ownership happy/`:not_owner`/`:not_a_member`; leave org refused for sole owner and sole project owner; context rejects `"owner"` in `update_membership_role` and invites; approve non-pending refused; `add_collaborator` non-member refused.

---

## 2c. Integrity + infra

### Data integrity migrations (one migration, ordered)
1. Backfill: `UPDATE estimations SET is_current = false WHERE is_current IS NULL`; `tasks.priority` → `'must'`; `pm_overhead/qa_overhead/risk_buffer` → `0` on `estimation_roles`, `project_roles`, `role_templates`; `position` → `0` on `role_templates`, `project_roles`.
2. `ALTER ... SET NOT NULL` (defaults already exist) on those columns.
3. `create unique_index(:customers, [:id, :organization_id])`, `create unique_index(:projects, [:id, :organization_id])`.
4. Composite FKs: `projects (customer_id, organization_id) REFERENCES customers (id, organization_id) ON DELETE CASCADE` (matching the existing single-column cascade) and `estimations (project_id, organization_id) REFERENCES projects (id, organization_id) ON DELETE CASCADE`. Existing single-column FKs stay.
`down` drops the composite FKs and unique indexes and relaxes NOT NULL.

### Constraint errors surface as changeset errors
- `Currencies.delete_currency/1` deletes through a changeset with `foreign_key_constraint(:id, name: :estimations_currency_id_fkey, message: "is used by estimations")` (and the same for projects/customers FKs), returning `{:error, changeset}`; `SettingsLive.Currencies` flashes the message.
- `Estimation.changeset/2` and `update_changeset/2` add `unique_constraint(:is_current, name: :estimations_unique_current_per_project, message: "another estimation is already current")`.
- `SettingsLive.Currencies` `update_field` accepts only `field in ~w(code name symbol)`; anything else → "Not authorized".

### RLS bypass role
- Migration: `CREATE ROLE estimate_system NOLOGIN BYPASSRLS` (idempotent), `GRANT estimate_system TO <current login role>`, grant the same DML/sequence privileges `estimate_app` has.
- `Repo.without_rls/1` executes `SET ROLE estimate_system`, then asserts `SELECT rolbypassrls FROM pg_roles WHERE rolname = current_user` is true (raise otherwise), restores as today. `SKIP_RLS_ROLE` migration flow unchanged (migrations run as the login role).
- Test `repo_without_rls_test.exs` extended: inside `without_rls`, `current_user` is `estimate_system`.

### Content Security Policy
- `EstimateWeb.Plugs.ContentSecurityPolicy` in the `:browser` pipeline after `put_secure_browser_headers`: generates a 16-byte base64 nonce per request, assigns `:csp_nonce`, sets the header.
- Policy (single line, spaces between directives): `default-src 'self'; script-src 'self' 'nonce-<nonce>'; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com data:; img-src 'self' data: blob:; connect-src 'self' ws: wss:; frame-ancestors 'none'; base-uri 'self'; form-action 'self'`.
- `CSP_REPORT_ONLY=true` (runtime env → `config :estimate, EstimateWeb.Plugs.ContentSecurityPolicy, report_only: true`) switches the header name to `content-security-policy-report-only`. Default enforcing.
- `root.html.heex`: the theme bootstrap `<script>` gets `nonce={@csp_nonce}`; `<.live_title>` suffix leftover " · Phoenix Framework" removed while there.
- Tests: header present and exact on a browser route, absent on `/mcp` and `/oauth/token`; nonce differs per request and matches the inline script's attribute; report-only flag switches the header name; a test iterates every `live` route in the router for a logged-in owner and asserts no `<script>` without the nonce is rendered.

### AI enhance off `Task.start`
- `EstimatorLive.Index` `ai_enhance_description` uses `start_async(socket, {:ai_enhance, target}, fn -> ... end)` with `handle_async/3` for `{:ok, result}` and `{:exit, reason}` (flash "AI request failed"). Existing `handle_info({:ai_result, ...})` removed.

### Batch-1 leftovers
- `ProjectCollaborator.edit_roles/0` (`["owner", "editor"]`) used by `AuthHelpers.can_edit_project?/2` and `MCP.Authz.require_can_edit_project/2`; `MCP.Authz` uses `Membership.admin_roles/0` instead of its own list.
- `Portfolio.create_project/4`: drop the unreachable `validate_org_reference(:customer_id, ...)` line; `CRM.get_customer!/2` remains the guard.
- `@impl true` on the three `CustomerLive.Show` handlers.

### Tests (2c)
Migration assertions via `information_schema` (NOT NULL, composite FKs exist); cross-org `customer_id` insert rejected at the DB even with RLS bypassed; currency delete with dependent estimation returns changeset error and LV flashes it; `update_field` with `is_main` refused; `without_rls` asserts role; CSP tests as above; AI enhance via `start_async` renders result and handles exit.

---

## Out of scope (later)
Reset/confirmation mail and OAuth link-to-confirmed (roadmap #4); API-key expiry; performance roadmap (#6-#8); estimator decomposition (#9); DRY pass (#12); CI gates (coverage ratchet, credo/sobelow, Docker waits for CI).
