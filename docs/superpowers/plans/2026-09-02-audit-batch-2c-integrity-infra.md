# Audit Batch 2c — Integrity + Infra Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enforce cross-org integrity at the database (composite FKs, NOT NULLs), turn constraint violations into changeset errors, whitelist currency field edits, give `without_rls` a dedicated BYPASSRLS role, ship an enforced Content Security Policy with a report-only escape hatch, move the AI call to `start_async`, and close the batch-1 leftovers.

**Architecture:** One additive integrity migration (backfill → NOT NULL → unique `(id, organization_id)` → composite FKs). `Repo.without_rls/1` switches to `estimate_system` and asserts `rolbypassrls`. A `:browser`-pipeline plug generates a per-request nonce, sets the CSP header (or report-only when configured) and the root layout stamps the nonce on its one inline script. Everything else is small, local changes with DB-backed tests.

**Tech Stack:** Elixir 1.18 / Phoenix 1.8.3 / LiveView 1.1 / Ecto 3.13 / Postgres 17.

**Spec:** `docs/superpowers/specs/2026-09-02-audit-batch-2-security-design.md`, section "2c. Integrity + infra".

## Global Constraints

- Additive migrations only: backfills, `SET NOT NULL` (defaults already exist), new unique indexes, new FKs, new role/grants. No drops of existing constraints/columns.
- TDD per task; `mix test <file>` runs one file (the alias migrates first).
- Diverge-then-assert tests: forbidden state in place → rejection → DB unchanged.
- CSP is ENFORCED by default; `CSP_REPORT_ONLY=true` switches the header name to `content-security-policy-report-only`. Policy string (exact, directives separated by `; `): `default-src 'self'; script-src 'self' 'nonce-<nonce>'; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com data:; img-src 'self' data: blob:; connect-src 'self' ws: wss:; frame-ancestors 'none'; base-uri 'self'; form-action 'self'`.
- Exact copy: "Not authorized", "is used by estimations", "another estimation is already current", "AI request failed".
- Commit signing uses 1Password; on a signing error wait 30 s and retry up to 3 times.
- Finish with `mix precommit` green.

---

### Task 1: Integrity migration — NOT NULLs, composite unique indexes, composite FKs

**Files:**
- Create: `priv/repo/migrations/20260902150000_tighten_integrity_constraints.exs`
- Test: `test/estimate/integrity_constraints_test.exs` (create)

**Interfaces:**
- DB: `NOT NULL` on `estimations.is_current`, `tasks.priority`, `{estimation_roles,project_roles,role_templates}.{pm_overhead,qa_overhead,risk_buffer}`, `role_templates.position`, `project_roles.position`, `estimation_template_epics.position`, `estimation_template_tasks.position`, `estimation_template_tasks.priority`; unique indexes `customers_id_organization_id_index`, `projects_id_organization_id_index`; FKs `projects_customer_org_fkey (customer_id, organization_id) → customers(id, organization_id) ON DELETE CASCADE`, `estimations_project_org_fkey (project_id, organization_id) → projects(id, organization_id) ON DELETE CASCADE`.

- [ ] **Step 1: Failing test**

```elixir
defmodule Estimate.IntegrityConstraintsTest do
  use Estimate.DataCase, async: true

  import Estimate.{AccountsFixtures, CRMFixtures, PortfolioFixtures}
  alias Estimate.Repo

  @not_null [
    {"estimations", "is_current"}, {"tasks", "priority"},
    {"estimation_roles", "pm_overhead"}, {"estimation_roles", "qa_overhead"}, {"estimation_roles", "risk_buffer"},
    {"project_roles", "pm_overhead"}, {"project_roles", "qa_overhead"}, {"project_roles", "risk_buffer"}, {"project_roles", "position"},
    {"role_templates", "pm_overhead"}, {"role_templates", "qa_overhead"}, {"role_templates", "risk_buffer"}, {"role_templates", "position"},
    {"estimation_template_epics", "position"}, {"estimation_template_tasks", "position"}, {"estimation_template_tasks", "priority"}
  ]

  test "previously nullable columns are NOT NULL" do
    for {t, c} <- @not_null do
      %{rows: [[nullable]]} =
        Repo.query!("SELECT is_nullable FROM information_schema.columns WHERE table_name = $1 AND column_name = $2", [t, c])
      assert nullable == "NO", "#{t}.#{c} should be NOT NULL"
    end
  end

  test "composite FKs exist" do
    for name <- ~w(projects_customer_org_fkey estimations_project_org_fkey) do
      assert Repo.exists?(from(c in "pg_constraint", where: c.conname == ^name, select: 1)), name
    end
  end

  test "a project cannot point at another org's customer even with RLS bypassed" do
    %{user: owner_a, organization: org_a} = user_with_organization_fixture()
    %{organization: org_b} = user_with_organization_fixture()
    customer_b = customer_fixture(org_b)
    project_a = project_fixture(nil, owner_a)

    assert_raise Postgrex.Error, ~r/projects_customer_org_fkey/, fn ->
      Repo.query!("UPDATE projects SET customer_id = $1 WHERE id = $2", [Ecto.UUID.dump!(customer_b.id), Ecto.UUID.dump!(project_a.id)])
    end

    assert Repo.reload!(project_a).customer_id == project_a.customer_id
    _ = org_a
  end
end
```

- [ ] **Step 2: Run to verify failure** — `mix test test/estimate/integrity_constraints_test.exs` → NOT NULL assertions and FK lookups fail.

- [ ] **Step 3: Migration**

```elixir
defmodule Estimate.Repo.Migrations.TightenIntegrityConstraints do
  use Ecto.Migration

  @overhead_tables ~w(estimation_roles project_roles role_templates)a

  def up do
    # 1. backfill NULLs with the column defaults
    execute "UPDATE estimations SET is_current = false WHERE is_current IS NULL"
    execute "UPDATE tasks SET priority = 'must' WHERE priority IS NULL"
    for t <- @overhead_tables, c <- ~w(pm_overhead qa_overhead risk_buffer) do
      execute "UPDATE #{t} SET #{c} = 0 WHERE #{c} IS NULL"
    end
    for t <- ~w(role_templates project_roles estimation_template_epics estimation_template_tasks) do
      execute "UPDATE #{t} SET position = 0 WHERE position IS NULL"
    end
    execute "UPDATE estimation_template_tasks SET priority = 'must' WHERE priority IS NULL"

    # 2. NOT NULL (defaults already exist on every column)
    alter table(:estimations), do: modify(:is_current, :boolean, null: false, default: false)
    alter table(:tasks), do: modify(:priority, :string, null: false, default: "must")
    for t <- @overhead_tables do
      alter table(t) do
        modify :pm_overhead, :decimal, precision: 5, scale: 2, null: false, default: 0
        modify :qa_overhead, :decimal, precision: 5, scale: 2, null: false, default: 0
        modify :risk_buffer, :decimal, precision: 5, scale: 2, null: false, default: 0
      end
    end
    for t <- ~w(role_templates project_roles estimation_template_epics estimation_template_tasks)a do
      alter table(t), do: modify(:position, :integer, null: false, default: 0)
    end
    alter table(:estimation_template_tasks), do: modify(:priority, :string, null: false, default: "must")

    # 3. composite uniqueness so the composite FKs below are valid targets
    create unique_index(:customers, [:id, :organization_id])
    create unique_index(:projects, [:id, :organization_id])

    # 4. cross-org linkage becomes impossible at the DB
    execute """
    ALTER TABLE projects ADD CONSTRAINT projects_customer_org_fkey
      FOREIGN KEY (customer_id, organization_id) REFERENCES customers (id, organization_id) ON DELETE CASCADE
    """
    execute """
    ALTER TABLE estimations ADD CONSTRAINT estimations_project_org_fkey
      FOREIGN KEY (project_id, organization_id) REFERENCES projects (id, organization_id) ON DELETE CASCADE
    """
  end

  def down do
    execute "ALTER TABLE estimations DROP CONSTRAINT estimations_project_org_fkey"
    execute "ALTER TABLE projects DROP CONSTRAINT projects_customer_org_fkey"
    drop unique_index(:projects, [:id, :organization_id])
    drop unique_index(:customers, [:id, :organization_id])
    alter table(:estimation_template_tasks), do: modify(:priority, :string, null: true, default: "must")
    for t <- ~w(role_templates project_roles estimation_template_epics estimation_template_tasks)a do
      alter table(t), do: modify(:position, :integer, null: true, default: 0)
    end
    for t <- @overhead_tables do
      alter table(t) do
        modify :pm_overhead, :decimal, precision: 5, scale: 2, null: true, default: 0
        modify :qa_overhead, :decimal, precision: 5, scale: 2, null: true, default: 0
        modify :risk_buffer, :decimal, precision: 5, scale: 2, null: true, default: 0
      end
    end
    alter table(:tasks), do: modify(:priority, :string, null: true, default: "must")
    alter table(:estimations), do: modify(:is_current, :boolean, null: true, default: false)
  end
end
```
Note: `projects.customer_id` is nullable (`nilify_all` history) — a composite FK with a NULL component is not checked, which is fine. `estimations.organization_id`/`projects.organization_id` are set by BEFORE INSERT triggers (see `20260207131323`), so inserts still satisfy the FK.

- [ ] **Step 4: Run, commit** — `mix test test/estimate/integrity_constraints_test.exs test/estimate/` (the whole `test/estimate` tree must stay green: fixtures insert through the triggers).
```bash
git add priv/repo/migrations/20260902150000_tighten_integrity_constraints.exs test/estimate/integrity_constraints_test.exs
git commit -m "fix(db): NOT NULL backfills, composite (id, organization_id) uniqueness and cross-org-proof FKs"
```

---

### Task 2: Constraint errors as changeset errors; currency field whitelist

**Files:**
- Modify: `lib/estimate/organizations/currencies.ex` (`delete_currency/1`), `lib/estimate/accounts/currency.ex` (add `delete_changeset/1`), `lib/estimate/estimation_engine/estimation.ex` (both changesets), `lib/estimate_web/live/settings_live/currencies.ex` (`delete_currency` + `update_field` handlers)
- Test: `test/estimate/organizations_currencies_test.exs` (append), `test/estimate/estimation_engine/estimations_current_test.exs` (create), `test/estimate_web/live/settings_live/currencies_test.exs` (create)

**Interfaces:**
- `Currencies.delete_currency/1` → `{:ok, c} | {:error, :is_main_currency} | {:error, %Ecto.Changeset{}}` (FK violations become changeset errors on `:id` with message "is used by estimations" / "is used by projects" / "is used by customers").
- `Estimation.changeset/2` and `update_changeset/2` carry `unique_constraint(:is_current, name: :estimations_unique_current_per_project, message: "another estimation is already current")`.
- Currency `update_field` accepts only `field in ~w(code name symbol)`; else flash "Not authorized".

- [ ] **Step 1: Failing tests**

`organizations_currencies_test.exs` (append; check its imports — needs `AccountsFixtures`, `PortfolioFixtures`, `EstimationEngineFixtures`):
```elixir
  test "deleting a currency used by an estimation returns a changeset error, not a crash" do
    %{user: owner, organization: org} = user_with_organization_fixture()
    [_main, eur | _] = Estimate.Organizations.Currencies.list_currencies(org.id)
    project = project_fixture(nil, owner)
    _est = estimation_fixture(project, %{"currency_id" => eur.id})

    assert {:error, %Ecto.Changeset{} = cs} = Estimate.Organizations.Currencies.delete_currency(eur)
    assert %{id: ["is used by estimations"]} = errors_on(cs)
    assert Repo.get(Estimate.Accounts.Currency, eur.id)
  end
```

`estimations_current_test.exs`:
```elixir
defmodule Estimate.EstimationEngine.EstimationsCurrentTest do
  use Estimate.DataCase, async: true
  import Estimate.{AccountsFixtures, PortfolioFixtures, EstimationEngineFixtures}
  alias Estimate.EstimationEngine.Estimation
  alias Estimate.Repo

  test "a second current estimation on one project is a changeset error" do
    %{user: owner} = user_with_organization_fixture()
    project = project_fixture(nil, owner)
    first = estimation_fixture(project)
    assert Repo.reload!(first).is_current
    second = estimation_fixture(project)
    refute Repo.reload!(second).is_current

    assert {:error, cs} = second |> Estimation.changeset(%{is_current: true}) |> Repo.update()
    assert %{is_current: ["another estimation is already current"]} = errors_on(cs)
  end
end
```
(The first estimation of a project is made current by `prepare_estimation_attrs`; verify by reading `estimations.ex` and adapt if the fixture path differs.)

`settings_live/currencies_test.exs`:
```elixir
defmodule EstimateWeb.SettingsLive.CurrenciesTest do
  use EstimateWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Estimate.{AccountsFixtures, PortfolioFixtures, EstimationEngineFixtures}
  alias Estimate.Organizations.Currencies

  setup :register_and_log_in_org_owner

  test "update_field refuses non-whitelisted fields", %{conn: conn, org: org} do
    [_main, eur | _] = Currencies.list_currencies(org.id)
    {:ok, lv, _} = live(conn, ~p"/org/#{org.id}/settings/currencies")
    html = render_click(lv, "update_field", %{"id" => eur.id, "field" => "is_main", "value" => "true"})
    assert html =~ "Not authorized"
    refute Repo.reload!(eur).is_main
    html = render_click(lv, "update_field", %{"id" => eur.id, "field" => "exchange_rate", "value" => "0"})
    assert html =~ "Not authorized"
  end

  test "update_field still edits a whitelisted field", %{conn: conn, org: org} do
    [_main, eur | _] = Currencies.list_currencies(org.id)
    {:ok, lv, _} = live(conn, ~p"/org/#{org.id}/settings/currencies")
    render_click(lv, "update_field", %{"id" => eur.id, "field" => "name", "value" => "Euro (EU)"})
    assert Repo.reload!(eur).name == "Euro (EU)"
  end

  test "deleting a currency in use flashes the reason", %{conn: conn, org: org, user: owner} do
    [_main, eur | _] = Currencies.list_currencies(org.id)
    project = project_fixture(nil, owner)
    _ = estimation_fixture(project, %{"currency_id" => eur.id})
    {:ok, lv, _} = live(conn, ~p"/org/#{org.id}/settings/currencies")
    render_click(lv, "confirm_delete", %{"id" => eur.id})
    html = render_click(lv, "delete_currency", %{})
    assert html =~ "is used by estimations"
    assert Repo.get(Estimate.Accounts.Currency, eur.id)
  end
end
```
(`Repo` alias: add `alias Estimate.Repo`.)

- [ ] **Step 2: Run to verify failure** — the three files; expect crashes (`Ecto.ConstraintError`) / no flash / wrong flash.

- [ ] **Step 3: Implement**

`currency.ex`:
```elixir
  @doc "Changeset used for deletes so FK violations surface as errors instead of raising."
  def delete_changeset(currency) do
    currency
    |> change()
    |> foreign_key_constraint(:id, name: :estimations_currency_id_fkey, message: "is used by estimations")
    |> foreign_key_constraint(:id, name: :projects_currency_id_fkey, message: "is used by projects")
    |> foreign_key_constraint(:id, name: :customers_default_currency_id_fkey, message: "is used by customers")
    |> foreign_key_constraint(:id, name: :role_template_rates_currency_id_fkey, message: "is used by role rates")
  end
```
Check the real constraint names with `\d` semantics: `SELECT conname FROM pg_constraint WHERE conname LIKE '%currency_id_fkey'` via `Repo.query!` in an `iex -S mix` or a throwaway test, and use exactly those names (only `estimations` is `on_delete: :restrict`; the others nilify/cascade and will not raise — keep only constraints that can actually fire, i.e. `estimations_currency_id_fkey`, and any other `:restrict` you find).

`currencies.ex` `delete_currency/1`: `Repo.delete(Currency.delete_changeset(currency))` instead of `Repo.delete(currency)`.

`estimation.ex`: add to both `changeset/2` and `update_changeset/2`:
```elixir
    |> unique_constraint(:is_current, name: :estimations_unique_current_per_project, message: "another estimation is already current")
```

`settings_live/currencies.ex`:
```elixir
  @editable_fields ~w(code name symbol)

  def handle_event("update_field", %{"id" => id, "field" => field, "value" => value}, socket)
      when field in @editable_fields do
    ... existing body ...
  end

  def handle_event("update_field", _params, socket),
    do: {:noreply, put_flash(socket, :error, "Not authorized")}
```
and in `delete_currency`: add
```elixir
        {:error, %Ecto.Changeset{} = cs} ->
          msg = cs |> errors_on_id() # extract the :id error message
          {:noreply, socket |> put_flash(:error, "Cannot delete currency: #{msg}") |> assign(:deleting_currency, nil)}
```
Implement `errors_on_id/1` as `Ecto.Changeset.traverse_errors(cs, fn {m, _} -> m end) |> Map.get(:id, ["in use"]) |> List.first()`.

- [ ] **Step 4: Run, commit** — `mix test test/estimate/organizations_currencies_test.exs test/estimate/estimation_engine/ test/estimate_web/live/settings_live/currencies_test.exs test/estimate_web/live/org_scoped_smoke_test.exs`.
```bash
git add lib/estimate/organizations/currencies.ex lib/estimate/accounts/currency.ex lib/estimate/estimation_engine/estimation.ex lib/estimate_web/live/settings_live/currencies.ex test/estimate/organizations_currencies_test.exs test/estimate/estimation_engine/estimations_current_test.exs test/estimate_web/live/settings_live/currencies_test.exs
git commit -m "fix(integrity): constraint violations surface as changeset errors; currency edits whitelisted"
```

---

### Task 3: `estimate_system` BYPASSRLS role for `without_rls`

**Files:**
- Create: `priv/repo/migrations/20260902151000_create_estimate_system_role.exs`
- Modify: `lib/estimate/repo.ex` (`without_rls/1`), `README.md`
- Test: `test/estimate/repo_without_rls_test.exs` (extend)

**Interfaces:**
- Role `estimate_system` (`NOLOGIN BYPASSRLS NOSUPERUSER`), granted `SELECT, INSERT, UPDATE, DELETE ON ALL TABLES`, `USAGE, SELECT ON ALL SEQUENCES`, `EXECUTE ON ALL FUNCTIONS`, matching default privileges; `GRANT estimate_system TO <current login role>`.
- `Repo.without_rls/1` executes `SET ROLE estimate_system`, asserts `SELECT rolbypassrls FROM pg_roles WHERE rolname = current_user` is `true` (raise `RuntimeError` "without_rls: role estimate_system lacks BYPASSRLS" otherwise), then restores as today.

- [ ] **Step 1: Failing test** (append to `repo_without_rls_test.exs`)
```elixir
    test "runs fun as estimate_system, which bypasses RLS" do
      Repo.assume_app_role()

      assert Repo.without_rls(fn -> current_user_role() end) == "estimate_system"

      %{rows: [[bypass]]} =
        Repo.query!("SELECT rolbypassrls FROM pg_roles WHERE rolname = 'estimate_system'", [])
      assert bypass
      assert current_user_role() == "estimate_app"
    end
```

- [ ] **Step 2: Run to verify failure** — role does not exist.

- [ ] **Step 3: Migration**
```elixir
defmodule Estimate.Repo.Migrations.CreateEstimateSystemRole do
  use Ecto.Migration

  # System-level escape hatch for Repo.without_rls/1: a NOLOGIN role that
  # bypasses RLS without being a superuser. Granted to whatever role runs
  # migrations (the DATABASE_URL role) so the app can SET ROLE into it.
  def up do
    execute """
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'estimate_system') THEN
        CREATE ROLE estimate_system NOLOGIN BYPASSRLS NOSUPERUSER NOCREATEDB NOCREATEROLE;
      END IF;
    END
    $$
    """
    execute "GRANT USAGE ON SCHEMA public TO estimate_system"
    execute "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO estimate_system"
    execute "GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO estimate_system"
    execute "GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO estimate_system"
    execute "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO estimate_system"
    execute "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO estimate_system"
    execute "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO estimate_system"
    execute "GRANT estimate_system TO current_user"
  end

  def down do
    execute "REVOKE estimate_system FROM current_user"
    execute "ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM estimate_system"
    execute "ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE USAGE, SELECT ON SEQUENCES FROM estimate_system"
    execute "ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE SELECT, INSERT, UPDATE, DELETE ON TABLES FROM estimate_system"
    execute "REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM estimate_system"
    execute "REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM estimate_system"
    execute "REVOKE ALL ON ALL TABLES IN SCHEMA public FROM estimate_system"
    execute "REVOKE USAGE ON SCHEMA public FROM estimate_system"
    execute "DROP ROLE IF EXISTS estimate_system"
  end
end
```
`GRANT estimate_system TO current_user` — `current_user` is a valid role reference in GRANT ROLE (evaluates to the migrating role; superusers do not need it but harmless).

- [ ] **Step 4: `without_rls/1`**
Replace `query!("RESET ROLE", [])` with:
```elixir
      query!("SET ROLE estimate_system", [])

      %{rows: [[bypass]]} =
        query!("SELECT rolbypassrls FROM pg_roles WHERE rolname = current_user", [])

      unless bypass, do: raise("without_rls: role estimate_system lacks BYPASSRLS")
```
Keep the `after` restore untouched. Update the `@doc` ("Checks out a connection and switches to the estimate_system role, which bypasses RLS…"). README: update the sentence about `without_rls` "resets to the login role" and add `estimate_system` to the RLS section; note the DATABASE_URL role must be able to `SET ROLE estimate_system` (granted by the migration to whichever role ran it).

- [ ] **Step 5: Run, commit** — `mix test test/estimate/repo_without_rls_test.exs test/estimate/mcp/ test/estimate/accounts_test.exs test/estimate/search_test.exs` (every `without_rls` caller), then full suite.
```bash
git add priv/repo/migrations/20260902151000_create_estimate_system_role.exs lib/estimate/repo.ex README.md test/estimate/repo_without_rls_test.exs
git commit -m "fix(rls): without_rls uses a dedicated BYPASSRLS role and asserts it"
```

---

### Task 4: Content Security Policy

**Files:**
- Create: `lib/estimate_web/plugs/content_security_policy.ex`
- Modify: `lib/estimate_web/router.ex` (`:browser` pipeline), `lib/estimate_web/components/layouts/root.html.heex`, `config/config.exs`, `config/runtime.exs`, `README.md`
- Test: `test/estimate_web/plugs/content_security_policy_test.exs` (create), `test/estimate_web/csp_routes_test.exs` (create)

**Interfaces:**
- `EstimateWeb.Plugs.ContentSecurityPolicy` — `init/1` no-op; `call/2` generates `nonce = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)`, `assign(conn, :csp_nonce, nonce)`, sets header `content-security-policy` (or `content-security-policy-report-only` when `Application.get_env(:estimate, EstimateWeb.Plugs.ContentSecurityPolicy, [])[:report_only]`) to the Global-Constraints policy with the nonce substituted. `policy(nonce) :: String.t()` public for tests.
- Root layout: `<script nonce={assigns[:csp_nonce]}>` on the theme bootstrap; remove the `" · Phoenix Framework"` suffix from `<.live_title>`.
- Dev-only LiveDashboard (if mounted in the router): add `csp_nonce_assign_key: :csp_nonce`.

- [ ] **Step 1: Failing tests**

`content_security_policy_test.exs`:
```elixir
defmodule EstimateWeb.Plugs.ContentSecurityPolicyTest do
  use EstimateWeb.ConnCase, async: false
  alias EstimateWeb.Plugs.ContentSecurityPolicy, as: CSP

  test "browser routes get an enforced CSP with a per-request nonce", %{conn: conn} do
    c1 = get(conn, ~p"/users/log_in")
    [h1] = get_resp_header(c1, "content-security-policy")
    assert get_resp_header(c1, "content-security-policy-report-only") == []
    assert h1 =~ "default-src 'self'; script-src 'self' 'nonce-"
    assert h1 =~ "frame-ancestors 'none'"
    [nonce] = Regex.run(~r/'nonce-([A-Za-z0-9_-]+)'/, h1, capture: :all_but_first)
    assert html_response(c1, 200) =~ ~s(<script nonce="#{nonce}">)

    c2 = get(build_conn(), ~p"/users/log_in")
    [h2] = get_resp_header(c2, "content-security-policy")
    refute h1 == h2
  end

  test "policy string is exact", _ do
    assert CSP.policy("abc") ==
             "default-src 'self'; script-src 'self' 'nonce-abc'; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com data:; img-src 'self' data: blob:; connect-src 'self' ws: wss:; frame-ancestors 'none'; base-uri 'self'; form-action 'self'"
  end

  test "JSON endpoints carry no CSP", %{conn: conn} do
    conn = get(conn, ~p"/healthz")
    assert get_resp_header(conn, "content-security-policy") == []
  end

  test "report-only flag switches the header name", %{conn: conn} do
    prev = Application.get_env(:estimate, CSP, [])
    Application.put_env(:estimate, CSP, Keyword.put(prev, :report_only, true))
    on_exit(fn -> Application.put_env(:estimate, CSP, prev) end)

    conn = get(conn, ~p"/users/log_in")
    assert [_] = get_resp_header(conn, "content-security-policy-report-only")
    assert get_resp_header(conn, "content-security-policy") == []
  end
end
```

`csp_routes_test.exs` — every inline script on every browser-rendered page carries the nonce:
```elixir
defmodule EstimateWeb.CspRoutesTest do
  use EstimateWeb.ConnCase, async: true
  import Estimate.{CRMFixtures, PortfolioFixtures, EstimationEngineFixtures, TemplatesFixtures}

  setup :register_and_log_in_org_owner

  test "no inline script without the request nonce on any org page", %{conn: conn, org: org, user: user} do
    customer = customer_fixture(org)
    project = project_fixture(nil, user)
    estimation = estimation_fixture(project)
    template = template_fixture(org)

    paths = [
      ~p"/organizations", ~p"/account", ~p"/account/two-factor/setup",
      ~p"/org/#{org.id}", ~p"/org/#{org.id}/roles", ~p"/org/#{org.id}/templates", ~p"/org/#{org.id}/templates/#{template.id}",
      ~p"/org/#{org.id}/settings", ~p"/org/#{org.id}/settings/members", ~p"/org/#{org.id}/settings/currencies",
      ~p"/org/#{org.id}/settings/ai", ~p"/org/#{org.id}/settings/email", ~p"/org/#{org.id}/settings/mcp", ~p"/org/#{org.id}/settings/trash",
      ~p"/org/#{org.id}/customers", ~p"/org/#{org.id}/customers/#{customer.id}", ~p"/org/#{org.id}/projects", ~p"/org/#{org.id}/projects/#{project.id}",
      ~p"/org/#{org.id}/projects/#{project.id}/estimations/#{estimation.id}/estimator"
    ]

    for path <- paths do
      resp = get(conn, path)
      assert resp.status == 200, "#{path} -> #{resp.status}"
      [header] = get_resp_header(resp, "content-security-policy")
      [nonce] = Regex.run(~r/'nonce-([A-Za-z0-9_-]+)'/, header, capture: :all_but_first)
      html = resp.resp_body

      inline_scripts = Regex.scan(~r/<script(?![^>]*\bsrc=)[^>]*>/, html) |> List.flatten()
      for tag <- inline_scripts do
        assert tag =~ ~s(nonce="#{nonce}"), "#{path}: inline script without nonce: #{tag}"
      end
    end
  end
end
```
(Dead-simple HTTP GETs; the initial render of a LiveView route goes through the root layout, which is where the only inline script lives.)

- [ ] **Step 2: Run to verify failure** — no header today.

- [ ] **Step 3: Implement**

```elixir
defmodule EstimateWeb.Plugs.ContentSecurityPolicy do
  @moduledoc """
  Per-request Content Security Policy with a script nonce. Enforced by default;
  `config :estimate, EstimateWeb.Plugs.ContentSecurityPolicy, report_only: true`
  (env `CSP_REPORT_ONLY=true`) switches to the report-only header for a soak.
  Any inline `<script>` must carry `nonce={@csp_nonce}`; external assets must be
  allow-listed here.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    nonce = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
    header = if report_only?(), do: "content-security-policy-report-only", else: "content-security-policy"

    conn
    |> assign(:csp_nonce, nonce)
    |> put_resp_header(header, policy(nonce))
  end

  @spec policy(String.t()) :: String.t()
  def policy(nonce) do
    Enum.join(
      [
        "default-src 'self'",
        "script-src 'self' 'nonce-#{nonce}'",
        "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
        "font-src 'self' https://fonts.gstatic.com data:",
        "img-src 'self' data: blob:",
        "connect-src 'self' ws: wss:",
        "frame-ancestors 'none'",
        "base-uri 'self'",
        "form-action 'self'"
      ],
      "; "
    )
  end

  defp report_only?, do: Application.get_env(:estimate, __MODULE__, [])[:report_only] == true
end
```
Router `:browser` pipeline: `plug EstimateWeb.Plugs.ContentSecurityPolicy` right after `plug :put_secure_browser_headers`. Root layout: `<script nonce={assigns[:csp_nonce]}>` and `<.live_title default="Estimate">` (drop the suffix). `config/config.exs`: `config :estimate, EstimateWeb.Plugs.ContentSecurityPolicy, report_only: false`. `config/runtime.exs` prod block: `report_only: System.get_env("CSP_REPORT_ONLY") == "true"`. README env row `CSP_REPORT_ONLY` + a bullet in deploy notes ("CSP is enforced; flip `CSP_REPORT_ONLY=true` and restart if a page breaks; add hosts to the policy in the plug"). If `live_dashboard` is mounted for dev in `router.ex`, pass `csp_nonce_assign_key: :csp_nonce`.

Check in the browser-less way: `mix test` covers pages; additionally run `mix phx.server` is NOT required.

- [ ] **Step 4: Run, commit** — `mix test test/estimate_web/plugs/ test/estimate_web/csp_routes_test.exs test/estimate_web/live/ test/estimate_web/controllers/`.
```bash
git add lib/estimate_web/plugs/content_security_policy.ex lib/estimate_web/router.ex lib/estimate_web/components/layouts/root.html.heex config/config.exs config/runtime.exs README.md test/estimate_web/plugs/content_security_policy_test.exs test/estimate_web/csp_routes_test.exs
git commit -m "feat(security): enforced Content Security Policy with per-request script nonce (CSP_REPORT_ONLY escape hatch)"
```

---

### Task 5: AI enhance via `start_async`

**Files:**
- Modify: `lib/estimate_web/live/estimator_live/index.ex` (`ai_enhance_description` handler, remove `handle_info({:ai_result, ...})` clauses, add `handle_async/3`)
- Test: `test/estimate_web/live/estimator_live/ai_enhance_test.exs` (create)

**Interfaces:**
- `start_async(socket, {:ai_enhance, target}, fn -> OpenRouter.enhance_description(...) end)`; `handle_async({:ai_enhance, target}, {:ok, {:ok, text}}, socket)` applies the result the way the old `handle_info` did; `{:ok, {:error, _}}` and `{:exit, _}` → flash "AI request failed", `ai_loading: nil`.
- Provider seam for tests: `Application.get_env(:estimate, :ai_enhancer, Estimate.AI.OpenRouter)` module implementing `enhance_description/5`; the test sets a stub module.

- [ ] **Step 1: Failing test**
```elixir
defmodule EstimateWeb.EstimatorLive.AiEnhanceTest do
  use EstimateWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import Estimate.{AccountsFixtures, PortfolioFixtures, EstimationEngineFixtures}

  defmodule StubAI do
    def enhance_description(_key, _model, _prompt, _name, desc), do: {:ok, String.upcase(desc)}
  end

  defmodule FailingAI do
    def enhance_description(_, _, _, _, _), do: raise("boom")
  end

  defp assigns(lv), do: :sys.get_state(lv.pid).socket.assigns

  setup %{conn: conn} do
    %{user: owner, organization: org} = user_with_organization_fixture()
    {:ok, org} = Estimate.Organizations.update_ai_settings(org, %{"openrouter_api_key" => "sk-or-test-key-123456"})
    project = project_fixture(nil, owner)
    est = estimation_fixture(project)
    prev = Application.get_env(:estimate, :ai_enhancer)
    on_exit(fn -> Application.put_env(:estimate, :ai_enhancer, prev) end)
    %{conn: log_in_user(conn, owner), org: org, project: project, est: est}
  end

  test "result arrives via handle_async and clears loading", ctx do
    Application.put_env(:estimate, :ai_enhancer, StubAI)
    {:ok, lv, _} = live(ctx.conn, ~p"/org/#{ctx.org.id}/projects/#{ctx.project.id}/estimations/#{ctx.est.id}/estimator")
    render_click(lv, "add_epic", %{})
    render_click(lv, "ai_enhance_description", %{"description" => "hello", "name" => "E", "target" => "epic"})
    assert assigns(lv).ai_loading == "epic"
    html = render_async(lv)
    assert assigns(lv).ai_loading == nil
    assert html =~ "HELLO"
  end

  test "a crashing provider flashes AI request failed", ctx do
    Application.put_env(:estimate, :ai_enhancer, FailingAI)
    {:ok, lv, _} = live(ctx.conn, ~p"/org/#{ctx.org.id}/projects/#{ctx.project.id}/estimations/#{ctx.est.id}/estimator")
    render_click(lv, "add_epic", %{})
    render_click(lv, "ai_enhance_description", %{"description" => "hello", "name" => "E", "target" => "epic"})
    html = render_async(lv)
    assert html =~ "AI request failed"
    assert assigns(lv).ai_loading == nil
  end
end
```
Read the existing `handle_info({:ai_result, target, {:ok, enhanced}}, socket)` clauses (index.ex ~740-760) to see how the result is applied (which form assign/field per `target`) and mirror that in `handle_async`; the "HELLO" assertion may need to check the form field value instead of the rendered HTML — adapt honestly.

- [ ] **Step 2: Run to verify failure** — `render_async` has nothing to await / result still arrives via `handle_info`.

- [ ] **Step 3: Implement**
```elixir
      if api_key do
        model = org.openrouter_model || "openai/gpt-4o-mini"
        system_prompt = org.openrouter_system_prompt
        enhancer = Application.get_env(:estimate, :ai_enhancer, Estimate.AI.OpenRouter)

        {:noreply,
         socket
         |> assign(:ai_loading, target)
         |> start_async({:ai_enhance, target}, fn ->
           enhancer.enhance_description(api_key, model, system_prompt, name, desc)
         end)}
      else
```
```elixir
  @impl true
  def handle_async({:ai_enhance, target}, {:ok, {:ok, enhanced}}, socket) do
    # same body as the former handle_info({:ai_result, target, {:ok, enhanced}})
  end

  def handle_async({:ai_enhance, _target}, _failure, socket) do
    {:noreply, socket |> assign(:ai_loading, nil) |> put_flash(:error, "AI request failed")}
  end
```
Delete the `handle_info({:ai_result, ...})` clauses.

- [ ] **Step 4: Run, commit** — `mix test test/estimate_web/live/estimator_live/`.
```bash
git add lib/estimate_web/live/estimator_live/index.ex test/estimate_web/live/estimator_live/ai_enhance_test.exs
git commit -m "fix(estimator): AI enhance runs under start_async with failure handling"
```

---

### Task 6: Batch-1 leftovers

**Files:**
- Modify: `lib/estimate/portfolio/project_collaborator.ex` (`edit_roles/0`), `lib/estimate_web/auth_helpers.ex`, `lib/estimate_web/mcp/authz.ex`, `lib/estimate/portfolio.ex` (`create_project/4`), `lib/estimate_web/live/customer_live/show.ex` (`@impl true`)
- Test: `test/estimate/portfolio/project_collaborator_test.exs` (create)

- [ ] **Step 1: Failing test**
```elixir
defmodule Estimate.Portfolio.ProjectCollaboratorTest do
  use ExUnit.Case, async: true
  alias Estimate.Portfolio.ProjectCollaborator

  test "edit_roles is the single source for editing collaborator roles" do
    assert ProjectCollaborator.edit_roles() == ["owner", "editor"]
    assert Enum.all?(ProjectCollaborator.edit_roles(), &(&1 in ProjectCollaborator.roles()))
  end
end
```

- [ ] **Step 2: Run to verify failure** — undefined function.

- [ ] **Step 3: Implement**
`project_collaborator.ex`: `@edit_roles ~w(owner editor)` + `def edit_roles, do: @edit_roles`. `auth_helpers.ex`: drop `@edit_roles`, use `collaborator.role in ProjectCollaborator.edit_roles()` (alias). `mcp/authz.ex`: drop `@admin_roles`/`@editor_collab_roles`; use `Membership.admin_roles()` and `ProjectCollaborator.edit_roles()` (guards cannot call functions: rewrite `require_org_admin/1` as `def require_org_admin(%{role: role}), do: if role in Membership.admin_roles(), do: :ok, else: {:error, :unauthorized}`). `portfolio.ex` `create_project/4`: delete the `validate_org_reference(:customer_id, ...)` line at ~177 (unreachable: `CRM.get_customer!/2` raises first) and leave a one-line comment. `customer_live/show.ex`: add `@impl true` before the first `handle_event` clause only (Elixir warns on repeated `@impl` per clause group? — one `@impl true` before the first clause of the group is the convention; check that the three flagged handlers are in the same group as the first one; if they are separated by other functions, add `@impl true` before each separated group).

- [ ] **Step 4: Run, commit** — `mix test test/estimate/portfolio/project_collaborator_test.exs test/estimate_web/mcp/ test/estimate_web/live/project_live/ test/estimate_web/live/customer_live/ test/estimate/`.
```bash
git add lib/estimate/portfolio/project_collaborator.ex lib/estimate_web/auth_helpers.ex lib/estimate_web/mcp/authz.ex lib/estimate/portfolio.ex lib/estimate_web/live/customer_live/show.ex test/estimate/portfolio/project_collaborator_test.exs
git commit -m "refactor: single source for collaborator edit roles; drop dead org check; @impl hygiene"
```

---

### Task 7: Full verification

- [ ] `mix precommit` green.
- [ ] Confirm new tests exist and pass: `integrity_constraints_test.exs`, `estimations_current_test.exs`, `settings_live/currencies_test.exs`, `repo_without_rls_test.exs` (extended), `plugs/content_security_policy_test.exs`, `csp_routes_test.exs`, `estimator_live/ai_enhance_test.exs`, `project_collaborator_test.exs`.
- [ ] Commit formatter output if any.
