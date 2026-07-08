# Test Foundation & Safety Net — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the missing LiveView test foundation — login/fixture helpers, a broad smoke-test safety net across every screen, and the pure open-redirect guard pinned — so the rest of the web-layer sweep can refactor against a green suite.

**Architecture:** Extend the existing `EstimateWeb.ConnCase` with `Phoenix.LiveViewTest`-based login helpers. Add one missing fixture (`template_fixture`). Write characterization/smoke tests only — **no production code changes** in this plan. Smoke tests assert each route mounts for an authorized user and redirects an unauthorized one; the only unit test pins `UserAuth.safe_return_to/1`.

**Tech Stack:** Elixir ~> 1.15, Phoenix 1.8, Phoenix.LiveView 1.1, Phoenix.LiveViewTest, ExUnit, Ecto SQL Sandbox, PostgreSQL (with Row-Level Security).

## Global Constraints

- **Behavior-preserving:** this plan adds tests only; it must not change any runtime behavior.
- **No DB schema/migration changes** (no new/changed columns, tables, indexes, associations).
- **`mix precommit` must pass** before merge (`compile --warnings-as-errors`, `deps.unlock --unused`, `format`, `test`).
- **AGENTS.md test rules:** assert with `element/2`/`has_element?/2` or tuple-match on `live/2` — **never** assert against raw HTML strings. Always reference DOM ids where they exist.
- **RLS:** org-scoped pages set their RLS context through the real request path (`OrgAuth.ensure_org_member` on_mount). Fixtures create data via contexts; DB triggers backfill `organization_id`. If a smoke test cannot read seeded data, that is a real RLS finding — surface it, do not paper over it.
- **Ship as one PR:** branch `test/phase0-foundation`.

---

### Task 1: LiveView login helpers in `ConnCase`

**Files:**
- Modify: `test/support/conn_case.ex`
- Test: `test/estimate_web/conn_case_helpers_test.exs` (create)

**Interfaces:**
- Consumes: `Estimate.Accounts.generate_user_session_token/1`; `Estimate.AccountsFixtures.{user_fixture/0,user_with_organization_fixture/0}`.
- Produces (used by every later task and every cluster plan):
  - `log_in_user(conn, user) :: Plug.Conn.t()` — puts a real session token in the conn.
  - `register_and_log_in_user(%{conn: conn}) :: %{conn: conn, user: user}` — ExUnit setup helper.
  - `register_and_log_in_org_owner(%{conn: conn}) :: %{conn: conn, user: user, org: organization}` — ExUnit setup helper; the user is the org owner.

- [ ] **Step 1: Add the helpers to `ConnCase`**

In `test/support/conn_case.ex`, add these functions to the module body (after the `setup` block, before the final `end`):

```elixir
  @doc """
  Logs the given `user` into the `conn` by writing a real session token.
  """
  def log_in_user(conn, user) do
    token = Estimate.Accounts.generate_user_session_token(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end

  @doc """
  ExUnit setup helper: registers a plain user and logs them in.
  """
  def register_and_log_in_user(%{conn: conn}) do
    user = Estimate.AccountsFixtures.user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  @doc """
  ExUnit setup helper: registers a user with a new organization (owner)
  and logs them in. Returns `:conn`, `:user`, and `:org`.
  """
  def register_and_log_in_org_owner(%{conn: conn}) do
    %{user: user, organization: org} =
      Estimate.AccountsFixtures.user_with_organization_fixture()

    %{conn: log_in_user(conn, user), user: user, org: org}
  end
```

- [ ] **Step 2: Write a test that exercises the helpers**

Create `test/estimate_web/conn_case_helpers_test.exs`:

```elixir
defmodule EstimateWeb.ConnCaseHelpersTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "register_and_log_in_org_owner/1" do
    setup :register_and_log_in_org_owner

    test "yields a conn that can load an authenticated org page", %{conn: conn, org: org} do
      assert {:ok, _view, _html} = live(conn, ~p"/org/#{org.id}")
    end

    test "provides user and org in context", %{user: user, org: org} do
      assert user.id
      assert org.id
    end
  end

  describe "register_and_log_in_user/1" do
    setup :register_and_log_in_user

    test "yields a conn that can load the organizations index", %{conn: conn} do
      assert {:ok, _view, _html} = live(conn, ~p"/organizations")
    end
  end
end
```

- [ ] **Step 3: Run the test**

Run: `mix test test/estimate_web/conn_case_helpers_test.exs`
Expected: PASS (3 tests). If `live/2` returns `{:error, {:redirect, ...}}` instead, the login helper or RLS context is wrong — investigate before proceeding (this validates the whole foundation).

- [ ] **Step 4: Commit**

```bash
git add test/support/conn_case.ex test/estimate_web/conn_case_helpers_test.exs
git commit -m "test: add LiveView login helpers to ConnCase

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: `template_fixture` for estimation-template screens

**Files:**
- Create: `test/support/fixtures/templates_fixtures.ex`
- Modify: `test/test_helper.exs` (only if support fixtures are not auto-compiled — verify first)
- Test: `test/estimate/templates_fixtures_test.exs` (create)

**Interfaces:**
- Consumes: `Estimate.Templates.create_estimation_template/?` (verify exact arity/shape in `lib/estimate/templates.ex` before writing), `Estimate.AccountsFixtures.organization_fixture/0`.
- Produces: `Estimate.TemplatesFixtures.template_fixture(organization \\ nil, attrs \\ %{}) :: %EstimationTemplate{}` — used by the `/templates/:id` smoke test (Task 3) and the misc-cluster plan.

- [ ] **Step 1: Confirm the context function signature**

Run: `grep -n "def create_estimation_template" lib/estimate/templates.ex`
Read the matched function to learn the exact argument shape (org id positional? attrs map keys? string vs atom keys?). Mirror the existing fixtures' `stringify_keys` style.

- [ ] **Step 2: Write the fixture**

Create `test/support/fixtures/templates_fixtures.ex` (adapt the `create_estimation_template` call to the signature found in Step 1):

```elixir
defmodule Estimate.TemplatesFixtures do
  @moduledoc """
  Test helpers for creating entities via the `Estimate.Templates` context.
  """

  alias Estimate.AccountsFixtures

  def template_fixture(organization \\ nil, attrs \\ %{}) do
    organization = organization || AccountsFixtures.organization_fixture()
    unique = System.unique_integer([:positive])

    {:ok, template} =
      Estimate.Templates.create_estimation_template(
        organization.id,
        Map.merge(%{"name" => "Test Template #{unique}"}, stringify_keys(attrs))
      )

    template
  end

  defp stringify_keys(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
```

- [ ] **Step 3: Write a test that the fixture inserts**

Create `test/estimate/templates_fixtures_test.exs`:

```elixir
defmodule Estimate.TemplatesFixturesTest do
  use Estimate.DataCase, async: true

  import Estimate.TemplatesFixtures

  test "template_fixture/2 creates a persisted estimation template" do
    template = template_fixture()
    assert template.id
    assert template.name =~ "Test Template"
  end
end
```

- [ ] **Step 4: Run the test**

Run: `mix test test/estimate/templates_fixtures_test.exs`
Expected: PASS. If `create_estimation_template` has a different signature, fix the fixture per Step 1 and re-run.

- [ ] **Step 5: Commit**

```bash
git add test/support/fixtures/templates_fixtures.ex test/estimate/templates_fixtures_test.exs
git commit -m "test: add template_fixture for estimation-template screens

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Pin `UserAuth.safe_return_to/1` (open-redirect guard)

**Files:**
- Test: `test/estimate_web/user_auth_test.exs` (create)

**Interfaces:**
- Consumes: `EstimateWeb.UserAuth.safe_return_to/1` (returns the path for safe local paths, `nil` otherwise).
- Produces: nothing (pure characterization).

This is a pure-function characterization test: it documents and locks the current behavior so the auth-cluster refactor cannot silently weaken the open-redirect guard.

- [ ] **Step 1: Write the characterization test**

Create `test/estimate_web/user_auth_test.exs`:

```elixir
defmodule EstimateWeb.UserAuthTest do
  use ExUnit.Case, async: true

  alias EstimateWeb.UserAuth

  describe "safe_return_to/1" do
    test "accepts simple local paths" do
      assert UserAuth.safe_return_to("/org/123") == "/org/123"
      assert UserAuth.safe_return_to("/projects/abc/estimations") == "/projects/abc/estimations"
    end

    test "rejects protocol-relative URLs (open redirect)" do
      assert UserAuth.safe_return_to("//evil.com") == nil
      assert UserAuth.safe_return_to("/\\evil.com") == nil
    end

    test "rejects absolute URLs with scheme/host" do
      assert UserAuth.safe_return_to("https://evil.com") == nil
      assert UserAuth.safe_return_to("http://evil.com/path") == nil
    end

    test "rejects paths without a leading slash" do
      assert UserAuth.safe_return_to("evil.com") == nil
      assert UserAuth.safe_return_to("javascript:alert(1)") == nil
    end

    test "rejects non-string input" do
      assert UserAuth.safe_return_to(nil) == nil
      assert UserAuth.safe_return_to(%{}) == nil
    end
  end
end
```

- [ ] **Step 2: Run the test**

Run: `mix test test/estimate_web/user_auth_test.exs`
Expected: PASS — it pins current behavior. If any case FAILS, you have found either a guard weakness or a wrong assumption: stop and confirm the intended behavior with the team before changing the assertion.

- [ ] **Step 3: Commit**

```bash
git add test/estimate_web/user_auth_test.exs
git commit -m "test: pin safe_return_to open-redirect guard

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Smoke tests — all org-scoped screens render for the owner

**Files:**
- Test: `test/estimate_web/live/org_scoped_smoke_test.exs` (create)

**Interfaces:**
- Consumes: `register_and_log_in_org_owner/1` (Task 1); `Estimate.{CRMFixtures.customer_fixture/1, PortfolioFixtures.project_fixture/3, EstimationEngineFixtures.estimation_fixture/2, TemplatesFixtures.template_fixture/1}`.
- Produces: nothing (safety net).

Every org screen must mount without crashing or unexpectedly redirecting for an authorized owner. The `{:ok, _, _} = live(...)` match is the assertion: it raises on mount crash or redirect.

- [ ] **Step 1: Write the index/list-route smoke tests**

Create `test/estimate_web/live/org_scoped_smoke_test.exs`:

```elixir
defmodule EstimateWeb.OrgScopedSmokeTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_org_owner

  describe "index/list routes render" do
    test "dashboard", %{conn: conn, org: org} do
      assert {:ok, _view, _html} = live(conn, ~p"/org/#{org.id}")
    end

    test "roles", %{conn: conn, org: org} do
      assert {:ok, _view, _html} = live(conn, ~p"/org/#{org.id}/roles")
    end

    test "templates index", %{conn: conn, org: org} do
      assert {:ok, _view, _html} = live(conn, ~p"/org/#{org.id}/templates")
    end

    test "settings index", %{conn: conn, org: org} do
      assert {:ok, _view, _html} = live(conn, ~p"/org/#{org.id}/settings")
    end

    test "settings members", %{conn: conn, org: org} do
      assert {:ok, _view, _html} = live(conn, ~p"/org/#{org.id}/settings/members")
    end

    test "settings currencies", %{conn: conn, org: org} do
      assert {:ok, _view, _html} = live(conn, ~p"/org/#{org.id}/settings/currencies")
    end

    test "settings ai", %{conn: conn, org: org} do
      assert {:ok, _view, _html} = live(conn, ~p"/org/#{org.id}/settings/ai")
    end

    test "settings email", %{conn: conn, org: org} do
      assert {:ok, _view, _html} = live(conn, ~p"/org/#{org.id}/settings/email")
    end

    test "settings trash", %{conn: conn, org: org} do
      assert {:ok, _view, _html} = live(conn, ~p"/org/#{org.id}/settings/trash")
    end

    test "customers index", %{conn: conn, org: org} do
      assert {:ok, _view, _html} = live(conn, ~p"/org/#{org.id}/customers")
    end

    test "projects index", %{conn: conn, org: org} do
      assert {:ok, _view, _html} = live(conn, ~p"/org/#{org.id}/projects")
    end
  end
```

- [ ] **Step 2: Add the detail-route smoke tests (with fixtures) in the same file**

Append, before the final module `end`:

```elixir
  describe "detail routes render with seeded data" do
    test "customer show", %{conn: conn, org: org} do
      customer = Estimate.CRMFixtures.customer_fixture(org)
      assert {:ok, _view, _html} = live(conn, ~p"/org/#{org.id}/customers/#{customer.id}")
    end

    test "project show", %{conn: conn, org: org, user: user} do
      project = Estimate.PortfolioFixtures.project_fixture(nil, user)
      assert {:ok, _view, _html} = live(conn, ~p"/org/#{org.id}/projects/#{project.id}")
    end

    test "templates show", %{conn: conn, org: org} do
      template = Estimate.TemplatesFixtures.template_fixture(org)
      assert {:ok, _view, _html} = live(conn, ~p"/org/#{org.id}/templates/#{template.id}")
    end

    test "estimator", %{conn: conn, org: org, user: user} do
      project = Estimate.PortfolioFixtures.project_fixture(nil, user)
      estimation = Estimate.EstimationEngineFixtures.estimation_fixture(project)

      assert {:ok, _view, _html} =
               live(
                 conn,
                 ~p"/org/#{org.id}/projects/#{project.id}/estimations/#{estimation.id}/estimator"
               )
    end
  end
end
```

- [ ] **Step 3: Run the smoke suite**

Run: `mix test test/estimate_web/live/org_scoped_smoke_test.exs`
Expected: PASS (15 tests). A failing match `{:ok, _, _}` means that screen crashed on mount or redirected — record which screen and the error; this is exactly the regression signal the safety net exists to catch. If a *detail* route fails on RLS (cannot read seeded row), confirm whether `project_fixture(nil, user)` correctly ties the project to the owner's org; adjust the fixture call, not the screen.

- [ ] **Step 4: Commit**

```bash
git add test/estimate_web/live/org_scoped_smoke_test.exs
git commit -m "test: smoke-test all org-scoped LiveView screens

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Smoke tests — account & anonymous auth screens

**Files:**
- Test: `test/estimate_web/live/account_smoke_test.exs` (create)
- Test: `test/estimate_web/live/auth_smoke_test.exs` (create)

**Interfaces:**
- Consumes: `register_and_log_in_user/1` (Task 1); a plain `conn` for anonymous routes.
- Produces: nothing (safety net).

- [ ] **Step 1: Account screens (authenticated)**

Create `test/estimate_web/live/account_smoke_test.exs`:

```elixir
defmodule EstimateWeb.AccountSmokeTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user

  test "account settings renders", %{conn: conn} do
    assert {:ok, _view, _html} = live(conn, ~p"/account")
  end

  test "totp setup renders", %{conn: conn} do
    assert {:ok, _view, _html} = live(conn, ~p"/account/two-factor/setup")
  end
end
```

- [ ] **Step 2: Anonymous auth screens**

Create `test/estimate_web/live/auth_smoke_test.exs`:

```elixir
defmodule EstimateWeb.AuthSmokeTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "registration renders", %{conn: conn} do
    assert {:ok, _view, _html} = live(conn, ~p"/users/register")
  end

  test "login renders", %{conn: conn} do
    assert {:ok, _view, _html} = live(conn, ~p"/users/log_in")
  end

  test "forgot password renders", %{conn: conn} do
    assert {:ok, _view, _html} = live(conn, ~p"/users/reset_password")
  end
end
```

- [ ] **Step 3: Run both files**

Run: `mix test test/estimate_web/live/account_smoke_test.exs test/estimate_web/live/auth_smoke_test.exs`
Expected: PASS (5 tests).

- [ ] **Step 4: Commit**

```bash
git add test/estimate_web/live/account_smoke_test.exs test/estimate_web/live/auth_smoke_test.exs
git commit -m "test: smoke-test account and anonymous auth screens

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: Authorization smoke tests (unauthorized access is blocked)

**Files:**
- Test: `test/estimate_web/live/authorization_smoke_test.exs` (create)

**Interfaces:**
- Consumes: `Estimate.AccountsFixtures.{user_fixture/0, user_with_organization_fixture/0}`; `log_in_user/2` (Task 1).
- Produces: nothing (safety net for the authorization behavior the Phase-5 work must preserve).

- [ ] **Step 1: Write the authorization tests**

Create `test/estimate_web/live/authorization_smoke_test.exs`:

```elixir
defmodule EstimateWeb.AuthorizationSmokeTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "anonymous user is redirected from an org route to log in", %{conn: conn} do
    %{organization: org} = Estimate.AccountsFixtures.user_with_organization_fixture()

    assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/org/#{org.id}")
    assert to =~ "/users/log_in"
  end

  test "anonymous user is redirected from account to log in", %{conn: conn} do
    assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/account")
    assert to =~ "/users/log_in"
  end

  test "a logged-in non-member cannot load another org's dashboard", %{conn: conn} do
    %{organization: other_org} = Estimate.AccountsFixtures.user_with_organization_fixture()
    outsider = Estimate.AccountsFixtures.user_fixture()
    conn = log_in_user(conn, outsider)

    assert {:error, {:redirect, %{to: _to}}} = live(conn, ~p"/org/#{other_org.id}")
  end
end
```

- [ ] **Step 2: Run the test**

Run: `mix test test/estimate_web/live/authorization_smoke_test.exs`
Expected: PASS (3 tests). The third test pins the org-membership boundary (`OrgAuth.ensure_org_member`). If a non-member is *not* redirected, that is a real authorization hole — stop and report it; do not weaken the test.

- [ ] **Step 3: Commit**

```bash
git add test/estimate_web/live/authorization_smoke_test.exs
git commit -m "test: pin authorization boundaries for org and account routes

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: Green-bar gate

**Files:** none (verification task).

- [ ] **Step 1: Run the full suite**

Run: `mix test`
Expected: all green, including the 6 pre-existing domain test files.

- [ ] **Step 2: Run the precommit gate**

Run: `mix precommit`
Expected: PASS — `compile --warnings-as-errors`, `deps.unlock --unused`, `format`, `test` all clean. Fix any formatting the test files introduced.

- [ ] **Step 3: Open the PR**

```bash
git push -u origin test/phase0-foundation
gh pr create --title "Phase 0: web-layer test foundation & safety net" \
  --body "Adds LiveView login/fixture helpers, smoke-test safety net across every screen, and the safe_return_to open-redirect characterization. Tests only — no runtime changes. Foundation for the web-layer code-quality sweep (docs/superpowers/specs/2026-06-30-web-layer-code-quality-design.md)."
```

---

## Self-Review

**Spec coverage (Phase 0 portion):**
- Test infrastructure → Task 1 (login helpers) + Task 2 (missing fixture). ✓
- Security characterization "first" → `safe_return_to` pinned (Task 3); authorization boundary pinned (Task 6). Deep per-flow characterization (forgot/reset/2FA/invite, membership authz) is **deliberately deferred to the cluster plans**, where it lands in the same PR as the refactor it guards — noted in the spec reconciliation. ✓ (documented deviation, not a gap)
- Smoke tests for all screens → Tasks 4 + 5 cover all 21 LiveView routes. ✓
- CI runs LiveView tests → Task 7 (`mix precommit`). ✓

**Placeholder scan:** Task 2 Step 1 intentionally verifies the `create_estimation_template` signature before writing the fixture (the one place the exact context API was not yet read) — this is a concrete verification step with a fallback, not a placeholder. No "TBD"/"add error handling"/"similar to Task N" present. ✓

**Type consistency:** `log_in_user/2`, `register_and_log_in_user/1`, `register_and_log_in_org_owner/1` defined in Task 1 are used with the same names/shapes in Tasks 4–6. Fixture names match the files read (`customer_fixture/1`, `project_fixture/3`, `estimation_fixture/2`, `template_fixture/1`). ✓
