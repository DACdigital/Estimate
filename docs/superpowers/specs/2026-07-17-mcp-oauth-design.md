# MCP OAuth Authorization Server — Design

**Date:** 2026-07-17
**Status:** Approved (brainstorm), pending implementation plan

## Goal

Let claude.ai custom connectors (web/Desktop/mobile/Cowork — "Individual sign-in") connect to the EstiMate MCP server: each member signs into EstiMate, picks an org, and Claude gets tokens that inherit exactly that member's RLS privileges. Port-agnostic loopback support additionally lets Claude Code use OAuth instead of pasted keys.

## Decisions (from brainstorm)

| Question | Decision |
|---|---|
| Consent/org model | Org picker on consent screen (MCP-enabled orgs the user belongs to); token bound to one `(user, org)` like API keys |
| Token policy | Access 1h + refresh 30d with rotation on every use; reuse of a rotated refresh revokes the token family |
| Approach | Hand-rolled minimal AS (no deps); boruta and `oauth_anthropic_creds` rejected |
| Coexistence | Personal `est_` API keys unchanged; validator accepts both |
| Client model | Public clients only (DCR, `token_endpoint_auth_method: "none"`); no client secrets |
| Static-headers beta | Rejected — org-shared credential breaks per-user RLS |

## Verified external contract (claude.com/docs/connectors/building/authentication + MCP auth spec 2025-06-18)

- Discovery: 401 from `/mcp` should carry `WWW-Authenticate: Bearer resource_metadata="…"`; Claude also probes `/.well-known/oauth-protected-resource[/mcp]` on the origin as fallback.
- Protected-resource metadata `resource` MUST equal the MCP URL exactly as users type it (`https://<host>/mcp`); `authorization_servers` first entry wins.
- AS metadata (RFC 8414) at `/.well-known/oauth-authorization-server`; MUST advertise `code_challenge_methods_supported: ["S256"]`; `token_endpoint_auth_methods_supported: ["none"]`; advertise `offline_access` in `scopes_supported` so Claude requests a refresh token.
- DCR (RFC 7591): `registration_endpoint`, JSON body; Claude registers a fresh client per connection (volume fine internally; CIMD = follow-up).
- Redirects: hosted surfaces use exactly `https://claude.ai/api/mcp/auth_callback`; Claude Code uses loopback `http://localhost:<ephemeral>/callback` + `http://127.0.0.1:<…>/callback` — port-agnostic matching required for both loopback hosts.
- PKCE S256 on every authorization request; token + refresh requests are `application/x-www-form-urlencoded`; DCR is JSON.
- Refresh: rotate for public clients, return new refresh in the same response; errors must be RFC-6749 codes (`invalid_grant`). Claude refreshes reactively on 401 + ~5min proactively.
- Latency budget: 10s discovery/register/token, 30s refresh (ours: ms).
- Anthropic egress `160.79.104.0/21` (WAF note only).

## New HTTP surface (all same host)

| Endpoint | Pipeline | Behavior |
|---|---|---|
| `GET /.well-known/oauth-authorization-server` | none/api | RFC 8414 JSON, runtime URLs (issuer = root URL): authorize/token/registration endpoints, `response_types: ["code"]`, `grant_types: ["authorization_code","refresh_token"]`, `code_challenge_methods_supported: ["S256"]`, `token_endpoint_auth_methods_supported: ["none"]`, `scopes_supported: ["mcp:read","offline_access"]` |
| `GET /.well-known/oauth-protected-resource` | none/api | RFC 9728 JSON: `resource` = exact `url(~p"/mcp")`, `authorization_servers: [root url]`, `scopes_supported: ["mcp:read"]`, `bearer_methods_supported: ["header"]` |
| `POST /oauth/register` | api (JSON) | RFC 7591: store public client `{client_name, redirect_uris}`; respond `client_id` (uuid) + echoed metadata; no secret |
| `GET /oauth/authorize` | browser + `require_authenticated_user` | validate client_id, redirect_uri (matching rules below), `response_type=code`, `code_challenge` present + `code_challenge_method=S256`, `resource` == MCP URL; render consent: client name, redirect host (always shown; warning styling for loopback), org picker (user's MCP-enabled orgs; none ⇒ explanatory error page) |
| `POST /oauth/authorize` | browser (same) | consent approve ⇒ mint code (120s TTL, single-use, hash-stored, binds client/user/org/redirect_uri/code_challenge/resource) ⇒ 302 `redirect_uri?code&state`; deny ⇒ 302 `error=access_denied&state` |
| `POST /oauth/token` | api (form-urlencoded) | `grant_type=authorization_code`: code unused+unexpired, client_id + redirect_uri + resource match, PKCE `S256(verifier) == challenge` (constant-time) ⇒ mark code used, issue access (1h) + refresh (30d) in new family. `grant_type=refresh_token`: valid+unrevoked ⇒ rotate (revoke old row, insert new, same family), sliding refresh expiry capped at 30d from rotation. Rotated-refresh reuse ⇒ revoke family, `invalid_grant`. All errors RFC 6749 JSON. `Cache-Control: no-store` |

Error rule for authorize: invalid client_id or unmatchable redirect_uri ⇒ render error page (never redirect); other validation failures redirect with `error=` per RFC when the redirect is valid.

Redirect matching: byte-exact against the client's registered URIs, EXCEPT `http://localhost/...` and `http://127.0.0.1/...` registered URIs match any port (path still exact). No other http allowed; everything else must be https.

## Data model (3 tables; house patterns: binary_id, hash-only secrets, `timestamps(type: :utc_datetime)`)

- `oauth_clients`: `id` (uuid PK = client_id), `name :string`, `redirect_uris {:array, :string}`, timestamps. No RLS (inert public data, no org/user linkage); insert via DCR only.
- `oauth_codes`: `code_hash :binary` (unique), `redirect_uri`, `code_challenge`, `resource`, `expires_at`, `used_at`, FKs `client_id`, `user_id`, `organization_id` (delete_all cascades), timestamps. RLS own-user policy; verification path uses `Repo.without_rls`.
- `oauth_tokens`: `access_token_hash :binary` (unique), `refresh_token_hash :binary` (unique), `family_id :binary_id`, `access_expires_at`, `refresh_expires_at`, `revoked_at`, `last_used_at`, FKs `client_id`, `user_id`, `organization_id` (delete_all), timestamps. RLS own-user policy; verification via `without_rls`.

Token formats: access `est_at_` + 32B base64url; refresh `est_rt_` + 32B base64url; code `est_ac_` + 32B base64url. All stored as sha256 only, shown/returned once.

## Verification integration

`Estimate.MCP.verify_bearer/1` becomes the validator entry point:
- `"est_at_" <> _` ⇒ oauth_tokens lookup (hash; unexpired, unrevoked) joined to org + membership: reject when org `mcp_enabled` false / membership gone (same taxonomy as keys; add `:token_expired` ⇒ 401 so Claude's reactive refresh triggers), touch `last_used_at` (same 300s throttle).
- `"est_" <> _` ⇒ existing `verify_api_key/1` path unchanged.
`Estimate.MCP.KeyValidator` calls `verify_bearer/1`; claims shape unchanged (`sub`/`org_id`/`role`/`aud`) — tools and RLS bridge untouched.

Kill switch: org toggle off ⇒ both token types 401 on next request. Membership removal: extend the `delete_membership` Multi (P4 pattern) to also delete/revoke the member's `oauth_tokens` + pending `oauth_codes` for that org.

anubis config nuance: `authorization:` opts are compile-time with URN placeholders today. At plan time, check whether the config accepts runtime values (child-spec opts or config callback). If yes: set real `resource`/`authorization_servers` so the 401's `resource_metadata` pointer is correct. If no: keep URNs internally (aud minting unaffected) and rely on Claude's documented origin-probe fallback to our correctly-served root metadata. Either path is spec-compliant; prefer the first.

## Consent page

Browser page (auth layout, controller + HEEx template — no LiveView needed): client name, full redirect host display (spec requirement; warning callout when redirect is loopback-only), org picker (radio list of the user's MCP-enabled orgs; auto-selected when exactly one), Approve / Deny. Logged-out users hit the existing login flow and return (`request_path` return-to).

## Settings UI touch

Settings → MCP page: add a "Connect from claude.ai" block — connector URL to paste + "sign in when prompted; no key needed" — beside the existing key snippet (Code/Cursor headers still supported).

## Security requirements (binding)

- PKCE S256 mandatory; `plain` rejected; verifier check constant-time (`Plug.Crypto.secure_compare/2` on hashes).
- Codes single-use + 120s; replay after use ⇒ `invalid_grant` AND revoke tokens already issued from that code.
- Refresh rotation with family reuse-detection (revoke family on reuse).
- Hash-only storage for code/access/refresh; nothing secret in URLs; `no-store` on token responses.
- Open DCR is acceptable: clients are inert without a logged-in user consenting; consent shows redirect host.
- `resource` parameter validated on authorize AND token (RFC 8707).
- `state` passed through untouched, never stored beyond the redirect.

## Testing

- Unit: PKCE (RFC 7636 appendix vector), redirect matcher (exact; loopback any-port; rejects `localhost.evil.com`, https-only otherwise), code single-use/expiry/replay-revocation, rotation + family revocation, `verify_bearer` both types incl. disabled-org, removed-membership, expired access.
- Integration (ConnCase): full flow register → authorize (real session, org pick) → token → Bearer `tools/call` against `/mcp` through the anubis plug (RLS-scoped data asserted) → refresh rotation → old-refresh reuse ⇒ family dead. Anonymous authorize ⇒ login redirect and back. Metadata JSON shape tests (S256, exact resource URL).
- Existing suite (388) stays green.

## Out of scope (follow-ups)

CIMD (`client_id_metadata_document_supported`) — preferred by Anthropic for high-traffic DCR churn; connected-clients management UI; RFC 7009 revocation endpoint; expired clients/codes/tokens pruning job; enterprise managed auth (SSO identity assertions).
