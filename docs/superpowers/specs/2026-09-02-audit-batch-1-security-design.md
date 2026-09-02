# Audit Batch 1 — Security Fixes — Design

Source: full audit 2026-09-02 (artifact "Estimate Black-Belt Audit"). Roadmap items #1, #2, #3, #5. Item #4 (reset mail / OAuth link guard) deferred until prod SMTP exists.

## Goal

Close the two reproduced authorization bugs and the verified HIGH items that need no data-model change: intra-org IDOR in the estimator, viewer project edit, mass-assignable parent FKs, LOGIN-capable DB role, brute-forceable 2FA and unthrottled auth/OAuth endpoints.

## Constraints

- No schema/data migrations except the role hardening (`ALTER ROLE` / `REVOKE`, no table changes).
- Every fix lands with a diverge-then-assert test (see memory `feedback-characterization-no-tautology`): set up the forbidden state, prove the handler rejects it, prove the DB is unchanged.
- Existing 533 tests stay green; `mix precommit` clean.
- Dep added: `hammer ~> 7.4` only.

## 1. Web authorization

- `EstimateWeb.AuthHelpers.can_edit_project?(membership, collaborator)` → `admin?(membership) or collaborator.role in ["owner", "editor"]`. Replaces private copies in `ProjectLive.Index` (edit action + save), `ProjectLive.Show.init_permissions`, `EstimatorLive.Index.can_edit?`.
- Estimator resolves child records from `@estimation` in memory: `find_epic(estimation, id)`, `find_task(estimation, id)`. Handlers `edit_epic`, `confirm_delete_epic`, `add_task` (epic-id), `edit_task`, `confirm_delete_task` use them; unknown id → `put_flash(:error, "Not found")`, no DB fetch. `delete_epic`/`delete_task` no-op when nothing is pending. All `confirm_*` and `ai_enhance_description` run inside `with_edit_auth`.
- `ProjectLive.Show.DangerZone.confirm_delete_project` gated by `require_can_delete`; `CustomerLive.Show.confirm_delete` gated by `require_admin`.

## 2. Changeset split

- `update_changeset/2` added to `Epic`, `Task`, `Estimation`, `EstimationRole`, `TaskEstimate`; it never casts `estimation_id`, `epic_id`, `project_id`, `task_id`, `estimation_role_id`, `project_role_id`, `is_current`. Contexts' `update_*` use it; estimator edit/validate forms use it.
- Reference FKs stay editable but must belong to the org: `Estimate.ChangesetHelpers.validate_org_reference(changeset, field, schema, org_id)` adds error `"does not belong to this organization"` when the referenced row does not exist with that `organization_id`. Applied: `Portfolio.create_project`/`update_project` (`customer_id`, `currency_id`), `CRM.create_customer`/`update_customer` (`default_currency_id`), `Estimations.update_estimation` (`currency_id`).

## 3. DB role hardening

Migration: `ALTER ROLE estimate_app NOLOGIN`; `REVOKE CREATE ON SCHEMA public FROM estimate_app`. `down` restores `LOGIN` (no password) and the grant.

## 5. Throttling

- `Estimate.RateLimit` (`use Hammer, backend: :ets`), child of `Estimate.Supervisor`, `clean_period: 1 min`. `check(bucket, key) :: {:allow, n} | {:deny, retry_ms}` with limits from `config :estimate, Estimate.RateLimit` (test env raises IP limits to 100_000):

  | bucket | key | window | default limit |
  |---|---|---|---|
  | `:login_email` | downcased email | 60 s | 10 |
  | `:login_ip` | client ip | 60 s | 60 |
  | `:totp_attempt` | pending user id | 15 min | 5 |
  | `:totp_replay` | `{user_id, code}` | 90 s | 1 |
  | `:oauth_ip` | client ip | 60 s | 20 |

- `EstimateWeb.ClientIP.get(conn)`: first `x-forwarded-for` hop if present, else `conn.remote_ip`.
- `POST /users/log_in`: deny → flash "Too many attempts. Try again in N seconds." + redirect to login. Checked before credential lookup.
- `POST /users/two-factor/verify`: attempts counted server-side per pending user; cookie counter removed. 5th failure → clear pending session, redirect login (existing copy). A valid code accepted once per 90 s window (`:totp_replay`).
- `POST /oauth/register`, `POST /oauth/token`: plug `EstimateWeb.Plugs.RateLimit, bucket: :oauth_ip` → 429 `{"error":"too_many_requests"}` with `retry-after` header.

## Out of scope (later batches)

Reset/confirmation mail, OAuth scope model, `broadcast_from`, RLS wrapper collapse, estimator decomposition, composite FKs.
