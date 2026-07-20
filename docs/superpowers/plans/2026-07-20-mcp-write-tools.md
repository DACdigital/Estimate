# MCP Write Tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 13 granular MCP write tools (7 create + 6 edit) so a member can build and edit the customer→project→estimation→roles→epics→tasks→per-role-hours chain conversationally through Claude, gated by a default-off org write toggle.

**Architecture:** New `component(...)`s on the existing `EstimateWeb.MCPServer` (`/mcp`), reusing Bearer/OAuth auth and the `Scope.with_scope/2` RLS bridge. All mutations call existing `Estimate.*` context functions. A shared `EstimateWeb.MCP.Write` orchestrator enforces the write kill-switch + a per-tool authorization gate and renders a uniform response (entity + deep-link URL on success, readable error otherwise). Authorization mirrors the web app; since RLS is org-only, project-collaborator gating lives in code (`EstimateWeb.MCP.Authz`).

**Tech Stack:** Elixir, Phoenix 1.8 LiveView, Ecto/Postgres (RLS), `anubis_mcp ~> 1.8` (Peri-based tool schemas), ExUnit.

## Global Constraints

- All write tools register on `EstimateWeb.MCPServer`; each runs inside `EstimateWeb.MCP.Scope.with_scope/2` and passes three gates: server enabled (already enforced at auth), `org.mcp_write_enabled` (checked per tool), per-action role.
- `org.mcp_write_enabled` defaults to `false`. Read tools never check it.
- Authorization mirrors the web app: customer create/edit = org admin/owner; project create = any member; project edit + all estimation writes = org-admin OR project `owner`/`editor` collaborator.
- `organization_id` is never caller-settable — a BEFORE INSERT trigger derives it (customer→project→estimation); child tables are scoped via parent RLS. Tools never put `organization_id` in attrs.
- Currency is always passed as a **code** (e.g. `"EUR"`), resolved via `Estimate.Organizations.Currencies.get_currency_by_code/2`; unknown code → error naming it.
- Every create/update response includes a `url` deep link built from `EstimateWeb.MCPServer.base_url()`.
- Anubis tool name = snake_case of the module suffix (`CreateCustomer` → `create_customer`).
- Tests: `use Estimate.DataCase, async: false` (RLS pdict is process-global). Call `Tool.execute(params, frame)` directly. `frame = mcp_frame(user, org, role)`; `role` is the org role claim. Default fixtures auto-seed 8 role templates (BA/UX/MO/BE/FE/DO/AI/SA) and 4 currencies (USD main, EUR/GBP/PLN).
- TDD; commit after every task.

---

## File Structure

**New backend:**
- `priv/repo/migrations/<ts>_add_mcp_write_enabled_to_organizations.exs`
- `lib/estimate_web/mcp/authz.ex` — write authz gates + parent-project resolution
- `lib/estimate_web/mcp/write.ex` — shared tool orchestrator + `resolve_currency/2`
- `lib/estimate_web/mcp/tools/{create,update}_{customer,project,estimation}.ex`
- `lib/estimate_web/mcp/tools/{add,update}_{estimation_role,epic,task}.ex`
- `lib/estimate_web/mcp/tools/set_task_effort.ex`

**Modified backend:**
- `lib/estimate/accounts/organization.ex` — field + `mcp_write_settings_changeset/2`
- `lib/estimate/organizations.ex` — `update_mcp_write_settings/2`, `mcp_write_enabled?/1`
- `lib/estimate/organizations/currencies.ex` — `get_currency_by_code/2`
- `lib/estimate/estimation_engine.ex` + `.../estimations.ex` — `get_estimation_project_id/2`
- `lib/estimate/estimation_engine.ex` + `.../tasks.ex` — `create_task_with_estimates/3`
- `lib/estimate_web/mcp/serializers.ex` — `changeset_errors/1`, `*_url/…` helpers
- `lib/estimate_web/mcp_server.ex` — 13 `component(...)` registrations
- `lib/estimate_web/live/settings_live/mcp.ex` — write toggle + handler
- `test/support/fixtures/mcp_fixtures.ex` — `enable_mcp_write/1`

**Tests:** one file per tool group under `test/estimate_web/mcp/tools/`, plus context + authz + settings-LV + catalog/integration updates.

---

### Task 1: Org `mcp_write_enabled` column, changeset, context

**Files:**
- Create: `priv/repo/migrations/<ts>_add_mcp_write_enabled_to_organizations.exs`
- Modify: `lib/estimate/accounts/organization.ex`
- Modify: `lib/estimate/organizations.ex`
- Modify: `test/support/fixtures/mcp_fixtures.ex`
- Test: `test/estimate/organizations_mcp_write_settings_test.exs`

**Interfaces:**
- Produces: `Organizations.update_mcp_write_settings(%Organization{}, attrs) :: {:ok, org} | {:error, changeset}`; `Organizations.mcp_write_enabled?(org_id :: binary) :: boolean`; `Estimate.MCPFixtures.enable_mcp_write(org) :: org`

- [ ] **Step 1: Generate the migration**

Run: `mix ecto.gen.migration add_mcp_write_enabled_to_organizations`
Then set its body:

```elixir
defmodule Estimate.Repo.Migrations.AddMcpWriteEnabledToOrganizations do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :mcp_write_enabled, :boolean, null: false, default: false
    end
  end
end
```

- [ ] **Step 2: Run the migration**

Run: `mix ecto.migrate`
Expected: `create/alter` succeeds; `mix ecto.rollback --step 1 && mix ecto.migrate` round-trips clean.

- [ ] **Step 3: Add field + changeset to the schema**

In `lib/estimate/accounts/organization.ex`, add the field beside `mcp_enabled`:

```elixir
    field :mcp_write_enabled, :boolean, default: false
```

Add the changeset (next to `mcp_settings_changeset/2`):

```elixir
  def mcp_write_settings_changeset(organization, attrs) do
    organization
    |> cast(attrs, [:mcp_write_enabled])
    |> validate_required([:mcp_write_enabled])
  end
```

- [ ] **Step 4: Write the failing context test**

Create `test/estimate/organizations_mcp_write_settings_test.exs`:

```elixir
defmodule Estimate.OrganizationsMcpWriteSettingsTest do
  use Estimate.DataCase, async: false

  import Estimate.AccountsFixtures
  alias Estimate.Organizations

  setup do
    %{organization: org} = user_with_organization_fixture()
    %{org: org}
  end

  test "defaults to false", %{org: org} do
    refute org.mcp_write_enabled
    refute Organizations.mcp_write_enabled?(org.id)
  end

  test "update_mcp_write_settings flips it and mcp_write_enabled? reflects it", %{org: org} do
    assert {:ok, org} = Organizations.update_mcp_write_settings(org, %{mcp_write_enabled: true})
    assert org.mcp_write_enabled
    assert Organizations.mcp_write_enabled?(org.id)
  end

  test "mcp_write_enabled? is false for unknown org" do
    refute Organizations.mcp_write_enabled?(Ecto.UUID.generate())
  end
end
```

- [ ] **Step 5: Run it to verify it fails**

Run: `mix test test/estimate/organizations_mcp_write_settings_test.exs`
Expected: FAIL — `update_mcp_write_settings/2` and `mcp_write_enabled?/1` undefined.

- [ ] **Step 6: Implement the context functions**

In `lib/estimate/organizations.ex` (ensure `import Ecto.Query` and `alias Estimate.Accounts.Organization` are present — they are used by neighbours), add:

```elixir
  def update_mcp_write_settings(%Organization{} = org, attrs) do
    org
    |> Organization.mcp_write_settings_changeset(attrs)
    |> Repo.update()
  end

  def mcp_write_enabled?(org_id) when is_binary(org_id) do
    Repo.ensure_org_context(fn ->
      from(o in Organization, where: o.id == ^org_id, select: o.mcp_write_enabled)
      |> Repo.one()
    end) == true
  end
```

- [ ] **Step 7: Add the fixture helper**

In `test/support/fixtures/mcp_fixtures.ex`, add:

```elixir
  @doc "Turns on write access for the org and returns the updated struct."
  def enable_mcp_write(organization) do
    {:ok, org} =
      Estimate.Organizations.update_mcp_write_settings(organization, %{mcp_write_enabled: true})

    org
  end
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `mix test test/estimate/organizations_mcp_write_settings_test.exs`
Expected: PASS (3 tests).

- [ ] **Step 9: Commit**

```bash
git add priv/repo/migrations lib/estimate/accounts/organization.ex lib/estimate/organizations.ex test/support/fixtures/mcp_fixtures.ex test/estimate/organizations_mcp_write_settings_test.exs
git commit -m "feat: org mcp_write_enabled toggle (default off)"
```

---

### Task 2: `Currencies.get_currency_by_code/2`

**Files:**
- Modify: `lib/estimate/organizations/currencies.ex`
- Test: `test/estimate/organizations/currencies_by_code_test.exs`

**Interfaces:**
- Produces: `Currencies.get_currency_by_code(org_id, code) :: %Currency{} | nil` (case-insensitive on code)

- [ ] **Step 1: Write the failing test**

Create `test/estimate/organizations/currencies_by_code_test.exs`:

```elixir
defmodule Estimate.Organizations.CurrenciesByCodeTest do
  use Estimate.DataCase, async: false

  import Estimate.AccountsFixtures
  alias Estimate.Organizations.Currencies

  setup do
    %{organization: org} = user_with_organization_fixture()
    %{org: org}
  end

  test "finds a seeded currency by code, case-insensitively", %{org: org} do
    assert %{code: "EUR"} = Currencies.get_currency_by_code(org.id, "EUR")
    assert %{code: "EUR"} = Currencies.get_currency_by_code(org.id, "eur")
  end

  test "returns nil for an unknown code", %{org: org} do
    assert Currencies.get_currency_by_code(org.id, "ZZZ") == nil
  end

  test "does not leak another org's currency", %{org: org} do
    %{organization: other} = user_with_organization_fixture()
    {:ok, _} = Currencies.create_currency(other.id, %{"code" => "CHF", "name" => "Swiss Franc", "symbol" => "CHF", "exchange_rate" => "0.9", "is_main" => false})
    assert Currencies.get_currency_by_code(org.id, "CHF") == nil
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/estimate/organizations/currencies_by_code_test.exs`
Expected: FAIL — `get_currency_by_code/2` undefined.

- [ ] **Step 3: Implement**

In `lib/estimate/organizations/currencies.ex` add:

```elixir
  def get_currency_by_code(org_id, code) when is_binary(code) do
    upcased = String.upcase(code)

    Repo.ensure_org_context(fn ->
      from(c in Currency,
        where: c.organization_id == ^org_id and fragment("upper(?)", c.code) == ^upcased
      )
      |> Repo.one()
    end)
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/estimate/organizations/currencies_by_code_test.exs`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/estimate/organizations/currencies.ex test/estimate/organizations/currencies_by_code_test.exs
git commit -m "feat: Currencies.get_currency_by_code/2"
```

---

### Task 3: `EstimationEngine.get_estimation_project_id/2`

Lightweight parent-project resolver used by write authz (avoids the heavy `get_estimation!` tree preload).

**Files:**
- Modify: `lib/estimate/estimation_engine/estimations.ex`
- Modify: `lib/estimate/estimation_engine.ex`
- Test: `test/estimate/estimation_engine/get_estimation_project_id_test.exs`

**Interfaces:**
- Produces: `EstimationEngine.get_estimation_project_id(estimation_id, org_id) :: binary | nil`

- [ ] **Step 1: Write the failing test**

Create `test/estimate/estimation_engine/get_estimation_project_id_test.exs`:

```elixir
defmodule Estimate.EstimationEngine.GetEstimationProjectIdTest do
  use Estimate.DataCase, async: false

  import Estimate.{AccountsFixtures, PortfolioFixtures, EstimationEngineFixtures}
  alias Estimate.EstimationEngine

  test "returns the owning project id" do
    %{user: user, organization: org} = user_with_organization_fixture()
    project = project_fixture(nil, user)
    estimation = estimation_fixture(project)

    assert EstimationEngine.get_estimation_project_id(estimation.id, org.id) == project.id
  end

  test "returns nil for a foreign-org estimation" do
    est = estimation_fixture()
    %{organization: other} = user_with_organization_fixture()
    assert EstimationEngine.get_estimation_project_id(est.id, other.id) == nil
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/estimate/estimation_engine/get_estimation_project_id_test.exs`
Expected: FAIL — function undefined.

- [ ] **Step 3: Implement**

In `lib/estimate/estimation_engine/estimations.ex` add:

```elixir
  def get_estimation_project_id(id, org_id) do
    Repo.ensure_org_context(fn ->
      from(e in Estimation,
        where: e.id == ^id and e.organization_id == ^org_id and is_nil(e.deleted_at),
        select: e.project_id
      )
      |> Repo.one()
    end)
  end
```

In `lib/estimate/estimation_engine.ex`, add under `## Estimations`:

```elixir
  defdelegate get_estimation_project_id(id, org_id), to: Estimations
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/estimate/estimation_engine/get_estimation_project_id_test.exs`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/estimate/estimation_engine/estimations.ex lib/estimate/estimation_engine.ex test/estimate/estimation_engine/get_estimation_project_id_test.exs
git commit -m "feat: EstimationEngine.get_estimation_project_id/2"
```

---

### Task 4: `EstimateWeb.MCP.Authz`

**Files:**
- Create: `lib/estimate_web/mcp/authz.ex`
- Test: `test/estimate_web/mcp/authz_test.exs`

**Interfaces:**
- Consumes: `Organizations.mcp_write_enabled?/1`; `Portfolio.get_collaborator/2`; `EstimationEngine.get_estimation_project_id/2`, `get_epic!/2`, `get_task!/2`, `get_role!/2`; `Portfolio.get_project!/2`.
- Produces:
  - `require_write_enabled(claims) :: :ok | {:error, :write_disabled}`
  - `require_org_admin(claims) :: :ok | {:error, :unauthorized}`
  - `require_can_edit_project(project_id, claims) :: :ok | {:error, :unauthorized}`
  - `ensure_project(project_id, org_id) :: {:ok, project_id} | {:error, :not_found}`
  - `project_id_for(:estimation | :epic | :task | :role, id, org_id) :: {:ok, project_id} | {:error, :not_found}`
  - where `claims` = `%{user_id, org_id, role}` (from `Scope.claims/1`).

- [ ] **Step 1: Write the failing test**

Create `test/estimate_web/mcp/authz_test.exs`:

```elixir
defmodule EstimateWeb.MCP.AuthzTest do
  use Estimate.DataCase, async: false

  import Estimate.{AccountsFixtures, PortfolioFixtures, EstimationEngineFixtures, MCPFixtures}
  alias EstimateWeb.MCP.{Authz, Scope}

  defp claims(user, org, role), do: Scope.claims(mcp_frame(user, org, role))

  setup do
    %{user: owner, organization: org} = user_with_organization_fixture()
    %{owner: owner, org: org}
  end

  describe "require_write_enabled" do
    test "off by default, on after enable", %{owner: owner, org: org} do
      assert Authz.require_write_enabled(claims(owner, org, "owner")) == {:error, :write_disabled}
      enable_mcp_write(org)
      assert Authz.require_write_enabled(claims(owner, org, "owner")) == :ok
    end
  end

  describe "require_org_admin" do
    test "owner/admin pass, member fails", %{owner: owner, org: org} do
      assert Authz.require_org_admin(claims(owner, org, "owner")) == :ok
      assert Authz.require_org_admin(claims(owner, org, "admin")) == :ok
      assert Authz.require_org_admin(claims(owner, org, "member")) == {:error, :unauthorized}
    end
  end

  describe "require_can_edit_project" do
    setup %{owner: owner} do
      project = project_fixture(nil, owner)
      %{project: project}
    end

    test "org admin always passes", %{owner: owner, org: org, project: project} do
      assert Authz.require_can_edit_project(project.id, claims(owner, org, "admin")) == :ok
    end

    test "member who is owner/editor collaborator passes; viewer/non-collaborator fails",
         %{org: org, project: project} do
      %{user: member} = member = build_member(org)
      member = member.user

      # non-collaborator member
      assert Authz.require_can_edit_project(project.id, claims(member, org, "member")) ==
               {:error, :unauthorized}

      {:ok, _} = Estimate.Portfolio.add_collaborator(project.id, member.id, "viewer")
      assert Authz.require_can_edit_project(project.id, claims(member, org, "member")) ==
               {:error, :unauthorized}

      collab = Estimate.Portfolio.get_collaborator(project.id, member.id)
      {:ok, _} = Estimate.Portfolio.update_collaborator_role(collab, "editor")
      assert Authz.require_can_edit_project(project.id, claims(member, org, "member")) == :ok
    end
  end

  describe "project_id_for / ensure_project" do
    test "resolves estimation/epic/task/role to project; foreign → not_found",
         %{owner: owner, org: org} do
      project = project_fixture(nil, owner)
      est = estimation_fixture(project)
      epic = epic_fixture(est)
      task = task_fixture(epic)

      assert Authz.ensure_project(project.id, org.id) == {:ok, project.id}
      assert Authz.project_id_for(:estimation, est.id, org.id) == {:ok, project.id}
      assert Authz.project_id_for(:epic, epic.id, org.id) == {:ok, project.id}
      assert Authz.project_id_for(:task, task.id, org.id) == {:ok, project.id}

      %{organization: other} = user_with_organization_fixture()
      assert Authz.project_id_for(:estimation, est.id, other.id) == {:error, :not_found}
      assert Authz.ensure_project(project.id, other.id) == {:error, :not_found}
      assert Authz.project_id_for(:task, "not-a-uuid", org.id) == {:error, :not_found}
    end
  end

  # Adds a second user as an org member (role "member") and returns %{user: user}.
  defp build_member(org) do
    user = user_fixture()
    _ = membership_fixture(user, org, "member")
    %{user: user}
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/estimate_web/mcp/authz_test.exs`
Expected: FAIL — `EstimateWeb.MCP.Authz` undefined.

- [ ] **Step 3: Implement**

Create `lib/estimate_web/mcp/authz.ex`:

```elixir
defmodule EstimateWeb.MCP.Authz do
  @moduledoc """
  Write-side authorization for MCP tools. RLS scopes rows to the org only,
  so these gates add the app's role + project-collaborator rules, mirroring
  the web app. All functions run inside `Scope.with_scope/2` (RLS context set).
  """

  alias Estimate.{Organizations, Portfolio, EstimationEngine}

  @admin_roles ~w(owner admin)
  @editor_collab_roles ~w(owner editor)

  def require_write_enabled(%{org_id: org_id}) do
    if Organizations.mcp_write_enabled?(org_id), do: :ok, else: {:error, :write_disabled}
  end

  def require_org_admin(%{role: role}) when role in @admin_roles, do: :ok
  def require_org_admin(_), do: {:error, :unauthorized}

  def require_can_edit_project(project_id, %{role: role, user_id: user_id}) do
    cond do
      role in @admin_roles -> :ok
      collaborator_role(project_id, user_id) in @editor_collab_roles -> :ok
      true -> {:error, :unauthorized}
    end
  end

  def ensure_project(project_id, org_id) do
    Portfolio.get_project!(project_id, org_id)
    {:ok, project_id}
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
    Ecto.Query.CastError -> {:error, :not_found}
  end

  def project_id_for(kind, id, org_id) do
    case do_resolve(kind, id, org_id) do
      nil -> {:error, :not_found}
      project_id -> {:ok, project_id}
    end
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
    Ecto.Query.CastError -> {:error, :not_found}
  end

  defp do_resolve(:estimation, id, org_id),
    do: EstimationEngine.get_estimation_project_id(id, org_id)

  defp do_resolve(:epic, id, org_id),
    do: EstimationEngine.get_estimation_project_id(EstimationEngine.get_epic!(id, org_id).estimation_id, org_id)

  defp do_resolve(:role, id, org_id),
    do: EstimationEngine.get_estimation_project_id(EstimationEngine.get_role!(id, org_id).estimation_id, org_id)

  defp do_resolve(:task, id, org_id) do
    epic_id = EstimationEngine.get_task!(id, org_id).epic_id
    EstimationEngine.get_estimation_project_id(EstimationEngine.get_epic!(epic_id, org_id).estimation_id, org_id)
  end

  defp collaborator_role(project_id, user_id) do
    case Portfolio.get_collaborator(project_id, user_id) do
      %{role: role} -> role
      _ -> nil
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/estimate_web/mcp/authz_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/estimate_web/mcp/authz.ex test/estimate_web/mcp/authz_test.exs
git commit -m "feat: MCP.Authz write gates + parent-project resolution"
```

---

### Task 5: Serializers helpers + `EstimateWeb.MCP.Write`

**Files:**
- Modify: `lib/estimate_web/mcp/serializers.ex`
- Create: `lib/estimate_web/mcp/write.ex`
- Test: `test/estimate_web/mcp/serializers_write_test.exs`

**Interfaces:**
- Produces:
  - `Serializers.changeset_errors(%Ecto.Changeset{}) :: String.t()`
  - `Serializers.customer_url(org_id, id)`, `project_url(org_id, id)`, `estimation_url(org_id, project_id, id) :: String.t()`
  - `Write.execute(frame, gate_fun, run_fun) :: {:reply, %Anubis.Server.Response{}, frame}` where `gate_fun :: (claims -> :ok | {:error, reason})` and `run_fun :: (claims -> {:ok, map} | {:error, changeset | reason})`
  - `Write.resolve_currency(code_or_nil, org_id) :: {:ok, currency_id | nil} | {:error, String.t()}`

- [ ] **Step 1: Write the failing test**

Create `test/estimate_web/mcp/serializers_write_test.exs`:

```elixir
defmodule EstimateWeb.MCP.SerializersWriteTest do
  use Estimate.DataCase, async: false

  import Estimate.AccountsFixtures
  alias EstimateWeb.MCP.{Serializers, Write}

  test "changeset_errors renders readable messages" do
    cs = Estimate.CRM.Customer.changeset(%Estimate.CRM.Customer{}, %{"name" => ""})
    msg = Serializers.changeset_errors(cs)
    assert msg =~ "key:"
    assert msg =~ "name:"
  end

  test "url helpers embed org + ids" do
    assert Serializers.customer_url("O", "C") =~ "/org/O/customers/C"
    assert Serializers.project_url("O", "P") =~ "/org/O/projects/P"
    assert Serializers.estimation_url("O", "P", "E") =~ "/org/O/projects/P/estimations/E/estimator"
  end

  test "resolve_currency: nil passes through, unknown errors, known resolves" do
    %{organization: org} = user_with_organization_fixture()
    assert Write.resolve_currency(nil, org.id) == {:ok, nil}
    assert Write.resolve_currency("", org.id) == {:ok, nil}
    assert {:error, msg} = Write.resolve_currency("ZZZ", org.id)
    assert msg =~ "ZZZ"
    assert {:ok, id} = Write.resolve_currency("EUR", org.id)
    assert is_binary(id)
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/estimate_web/mcp/serializers_write_test.exs`
Expected: FAIL — undefined functions.

- [ ] **Step 3: Add Serializers helpers**

Append to `lib/estimate_web/mcp/serializers.ex`:

```elixir
  def changeset_errors(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)
    |> Enum.join("; ")
  end

  def customer_url(org_id, id), do: url_for(org_id, "/customers/#{id}")
  def project_url(org_id, id), do: url_for(org_id, "/projects/#{id}")

  def estimation_url(org_id, project_id, id),
    do: url_for(org_id, "/projects/#{project_id}/estimations/#{id}/estimator")

  defp url_for(org_id, rest),
    do: EstimateWeb.MCPServer.base_url() <> "/org/#{org_id}" <> rest
```

- [ ] **Step 4: Implement Write**

Create `lib/estimate_web/mcp/write.ex`:

```elixir
defmodule EstimateWeb.MCP.Write do
  @moduledoc """
  Shared orchestration for write tools: sets RLS scope, enforces the org
  write kill-switch and a per-tool authorization gate, runs the mutation,
  and renders a uniform Anubis response. `run_fun` returns the ready
  JSON-native success map (entity + `:url`) or an error.
  """

  alias Anubis.Server.Response
  alias EstimateWeb.MCP.{Authz, Scope, Serializers}
  alias Estimate.Organizations.Currencies

  def execute(frame, gate_fun, run_fun)
      when is_function(gate_fun, 1) and is_function(run_fun, 1) do
    result =
      Scope.with_scope(frame, fn claims ->
        with :ok <- Authz.require_write_enabled(claims),
             :ok <- gate_fun.(claims) do
          safe_run(run_fun, claims)
        end
      end)

    {:reply, render(result), frame}
  end

  def resolve_currency(code, _org_id) when code in [nil, ""], do: {:ok, nil}

  def resolve_currency(code, org_id) when is_binary(code) do
    case Currencies.get_currency_by_code(org_id, code) do
      nil -> {:error, "unknown currency code: #{code}"}
      currency -> {:ok, currency.id}
    end
  end

  defp safe_run(run_fun, claims) do
    run_fun.(claims)
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
    Ecto.Query.CastError -> {:error, :not_found}
  end

  defp render({:ok, map}) when is_map(map), do: Response.json(Response.tool(), map)

  defp render({:error, %Ecto.Changeset{} = cs}),
    do: Response.error(Response.tool(), Serializers.changeset_errors(cs))

  defp render({:error, :write_disabled}),
    do: Response.error(Response.tool(), "MCP writes are disabled for this organization")

  defp render({:error, :unauthorized}), do: Response.error(Response.tool(), "not authorized")
  defp render({:error, :not_found}), do: Response.error(Response.tool(), "not found")
  defp render({:error, msg}) when is_binary(msg), do: Response.error(Response.tool(), msg)
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `mix test test/estimate_web/mcp/serializers_write_test.exs`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/estimate_web/mcp/serializers.ex lib/estimate_web/mcp/write.ex test/estimate_web/mcp/serializers_write_test.exs
git commit -m "feat: MCP.Write orchestrator + serializer write helpers"
```

---

### Task 6: `create_customer` tool

**Files:**
- Create: `lib/estimate_web/mcp/tools/create_customer.ex`
- Modify: `lib/estimate_web/mcp_server.ex`
- Test: `test/estimate_web/mcp/tools/write_customers_test.exs`

**Interfaces:**
- Consumes: `Write.execute/3`, `Write.resolve_currency/2`, `Authz.require_org_admin/1`, `CRM.create_customer/2`, `CRM.get_customer!/2`, `Serializers.customer/1` + `customer_url/2`.
- Produces: tool `create_customer`.

- [ ] **Step 1: Write the failing test**

Create `test/estimate_web/mcp/tools/write_customers_test.exs`:

```elixir
defmodule EstimateWeb.MCP.Tools.WriteCustomersTest do
  use Estimate.DataCase, async: false

  import Estimate.{AccountsFixtures, CRMFixtures, MCPFixtures}
  alias Anubis.Server.Response
  alias EstimateWeb.MCP.Tools.CreateCustomer

  setup do
    %{user: owner, organization: org} = user_with_organization_fixture()
    enable_mcp_write(org)
    %{owner: owner, org: org}
  end

  defp frame(user, org, role \\ "owner"), do: mcp_frame(user, org, role)

  test "admin creates a customer; response carries id + url", %{owner: owner, org: org} do
    assert {:reply, resp, _} =
             CreateCustomer.execute(%{key: "acme", name: "Acme Corp", currency: "EUR"}, frame(owner, org))

    refute resp.isError
    body = json_content(resp)
    assert body["key"] == "ACME"
    assert body["name"] == "Acme Corp"
    assert body["currency"] == "EUR"
    assert body["url"] =~ "/org/#{org.id}/customers/#{body["id"]}"
  end

  test "member is not authorized", %{org: org} do
    member = user_fixture()
    _ = membership_fixture(member, org, "member")

    assert {:reply, %Response{isError: true} = resp, _} =
             CreateCustomer.execute(%{key: "ACME", name: "Acme"}, frame(member, org, "member"))

    assert json_error(resp) =~ "not authorized"
  end

  test "writes disabled → rejected", %{owner: owner} do
    %{user: owner2, organization: org2} = user_with_organization_fixture()
    # org2 write NOT enabled
    assert {:reply, %Response{isError: true} = resp, _} =
             CreateCustomer.execute(%{key: "ACME", name: "Acme"}, frame(owner2, org2))

    assert json_error(resp) =~ "writes are disabled"
  end

  test "duplicate key → readable changeset error", %{owner: owner, org: org} do
    customer_fixture(org, %{"key" => "ACME", "name" => "Acme"})

    assert {:reply, %Response{isError: true} = resp, _} =
             CreateCustomer.execute(%{key: "ACME", name: "Acme Two"}, frame(owner, org))

    assert json_error(resp) =~ "key:"
  end
end
```

Add a shared error decoder used by all write-tool tests — append to `test/support/mcp_test_helpers.ex`:

```elixir
  @doc "The error text of an Anubis tool error response."
  def json_error(%Anubis.Server.Response{content: [%{"type" => "text", "text" => text}]}), do: text
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/estimate_web/mcp/tools/write_customers_test.exs`
Expected: FAIL — `CreateCustomer` undefined.

- [ ] **Step 3: Implement the tool**

Create `lib/estimate_web/mcp/tools/create_customer.ex`:

```elixir
defmodule EstimateWeb.MCP.Tools.CreateCustomer do
  @moduledoc "Create a customer in the caller's organization (org admins only). Requires a unique key and a name."

  use Anubis.Server.Component, type: :tool

  alias Estimate.CRM
  alias EstimateWeb.MCP.{Authz, Serializers, Write}

  schema do
    field :key, :string, required: true, description: "Short unique key, 2–20 chars (e.g. ACME). Uppercased."
    field :name, :string, required: true
    field :country, :string, description: "2-letter ISO code, e.g. US, DE"
    field :website_url, :string, description: "http(s):// URL"
    field :description, :string
    field :currency, :string, description: "Default currency code, e.g. EUR"
  end

  @impl true
  def execute(params, frame) do
    Write.execute(frame, &Authz.require_org_admin/1, fn %{org_id: org_id} ->
      with {:ok, currency_id} <- Write.resolve_currency(params[:currency], org_id),
           {:ok, customer} <- CRM.create_customer(org_id, attrs(params, currency_id)) do
        customer = CRM.get_customer!(customer.id, org_id)

        {:ok,
         Serializers.customer(customer)
         |> Map.put(:url, Serializers.customer_url(org_id, customer.id))}
      end
    end)
  end

  defp attrs(params, currency_id) do
    %{
      "key" => params.key,
      "name" => params.name,
      "country" => params[:country],
      "website_url" => params[:website_url],
      "description" => params[:description],
      "default_currency_id" => currency_id
    }
  end
end
```

- [ ] **Step 4: Register the tool**

In `lib/estimate_web/mcp_server.ex`, add after the read-tool `component(...)` block:

```elixir
  # --- Write tools ---
  component(EstimateWeb.MCP.Tools.CreateCustomer)
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `mix test test/estimate_web/mcp/tools/write_customers_test.exs`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/estimate_web/mcp/tools/create_customer.ex lib/estimate_web/mcp_server.ex test/estimate_web/mcp/tools/write_customers_test.exs test/support/mcp_test_helpers.ex
git commit -m "feat: create_customer MCP tool"
```

---

### Task 7: `update_customer` tool

**Files:**
- Create: `lib/estimate_web/mcp/tools/update_customer.ex`
- Modify: `lib/estimate_web/mcp_server.ex`
- Test: append to `test/estimate_web/mcp/tools/write_customers_test.exs`

**Interfaces:**
- Consumes: `CRM.get_customer!/2`, `CRM.update_customer/2`.
- Produces: tool `update_customer`.

- [ ] **Step 1: Write the failing test**

Append inside `WriteCustomersTest`:

```elixir
  test "admin updates a customer's name + currency", %{owner: owner, org: org} do
    customer = customer_fixture(org, %{"key" => "ACME", "name" => "Acme"})

    assert {:reply, resp, _} =
             EstimateWeb.MCP.Tools.UpdateCustomer.execute(
               %{id: customer.id, name: "Acme Renamed", currency: "GBP"},
               frame(owner, org)
             )

    refute resp.isError
    body = json_content(resp)
    assert body["name"] == "Acme Renamed"
    assert body["currency"] == "GBP"
    assert body["url"] =~ "/customers/#{customer.id}"
  end

  test "update foreign-org customer → not found", %{owner: owner, org: org} do
    %{organization: other} = user_with_organization_fixture()
    foreign = customer_fixture(other, %{"key" => "FGN", "name" => "Foreign"})

    assert {:reply, %Response{isError: true} = resp, _} =
             EstimateWeb.MCP.Tools.UpdateCustomer.execute(%{id: foreign.id, name: "x"}, frame(owner, org))

    assert json_error(resp) =~ "not found"
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/estimate_web/mcp/tools/write_customers_test.exs`
Expected: FAIL — `UpdateCustomer` undefined.

- [ ] **Step 3: Implement the tool**

Create `lib/estimate_web/mcp/tools/update_customer.ex`:

```elixir
defmodule EstimateWeb.MCP.Tools.UpdateCustomer do
  @moduledoc "Update a customer (org admins only). Only the fields you pass are changed."

  use Anubis.Server.Component, type: :tool

  alias Estimate.CRM
  alias EstimateWeb.MCP.{Authz, Serializers, Write}

  schema do
    field :id, :string, required: true, description: "Customer UUID"
    field :key, :string
    field :name, :string
    field :country, :string
    field :website_url, :string
    field :description, :string
    field :currency, :string, description: "Default currency code, e.g. EUR"
  end

  @impl true
  def execute(params, frame) do
    Write.execute(frame, &Authz.require_org_admin/1, fn %{org_id: org_id} ->
      customer = CRM.get_customer!(params.id, org_id)

      with {:ok, attrs} <- change_attrs(params, org_id),
           {:ok, updated} <- CRM.update_customer(customer, attrs) do
        updated = CRM.get_customer!(updated.id, org_id)

        {:ok,
         Serializers.customer(updated)
         |> Map.put(:url, Serializers.customer_url(org_id, updated.id))}
      end
    end)
  end

  defp change_attrs(params, org_id) do
    with {:ok, currency_id} <- currency_change(params, org_id) do
      base =
        params
        |> Map.take([:key, :name, :country, :website_url, :description])
        |> Map.new(fn {k, v} -> {to_string(k), v} end)

      {:ok, Map.merge(base, currency_id)}
    end
  end

  defp currency_change(params, org_id) do
    case Map.fetch(params, :currency) do
      :error -> {:ok, %{}}
      {:ok, code} -> with {:ok, id} <- Write.resolve_currency(code, org_id), do: {:ok, %{"default_currency_id" => id}}
    end
  end
end
```

- [ ] **Step 4: Register the tool**

In `lib/estimate_web/mcp_server.ex`, under the write block:

```elixir
  component(EstimateWeb.MCP.Tools.UpdateCustomer)
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `mix test test/estimate_web/mcp/tools/write_customers_test.exs`
Expected: PASS (6 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/estimate_web/mcp/tools/update_customer.ex lib/estimate_web/mcp_server.ex test/estimate_web/mcp/tools/write_customers_test.exs
git commit -m "feat: update_customer MCP tool"
```

---

### Task 8: `create_project` tool

**Files:**
- Create: `lib/estimate_web/mcp/tools/create_project.ex`
- Modify: `lib/estimate_web/mcp_server.ex`
- Test: `test/estimate_web/mcp/tools/write_projects_test.exs`

**Interfaces:**
- Consumes: `Portfolio.create_project/4`, `Serializers.project/1` + `project_url/2`.
- Produces: tool `create_project`. Gate: any member (`fn _ -> :ok end`).

- [ ] **Step 1: Write the failing test**

Create `test/estimate_web/mcp/tools/write_projects_test.exs`:

```elixir
defmodule EstimateWeb.MCP.Tools.WriteProjectsTest do
  use Estimate.DataCase, async: false

  import Estimate.{AccountsFixtures, CRMFixtures, PortfolioFixtures, MCPFixtures}
  alias Anubis.Server.Response
  alias EstimateWeb.MCP.Tools.{CreateProject, UpdateProject}

  setup do
    %{user: owner, organization: org} = user_with_organization_fixture()
    enable_mcp_write(org)
    customer = customer_fixture(org, %{"key" => "ACME", "name" => "Acme"})
    %{owner: owner, org: org, customer: customer}
  end

  defp frame(user, org, role \\ "owner"), do: mcp_frame(user, org, role)

  test "member can create a project (becomes owner)", %{org: org, customer: customer} do
    member = user_fixture()
    _ = membership_fixture(member, org, "member")

    assert {:reply, resp, _} =
             CreateProject.execute(
               %{customer_id: customer.id, name: "Website", key: "WEB"},
               frame(member, org, "member")
             )

    refute resp.isError
    body = json_content(resp)
    assert body["name"] == "Website"
    assert body["url"] =~ "/projects/#{body["id"]}"
  end

  test "bad customer id → not found", %{owner: owner, org: org} do
    assert {:reply, %Response{isError: true} = resp, _} =
             CreateProject.execute(%{customer_id: Ecto.UUID.generate(), name: "X"}, frame(owner, org))

    assert json_error(resp) =~ "not found"
  end

  test "writes disabled → rejected", %{customer: _customer} do
    %{user: owner2, organization: org2} = user_with_organization_fixture()
    c2 = customer_fixture(org2, %{"key" => "BETA", "name" => "Beta"})

    assert {:reply, %Response{isError: true} = resp, _} =
             CreateProject.execute(%{customer_id: c2.id, name: "X"}, frame(owner2, org2))

    assert json_error(resp) =~ "writes are disabled"
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/estimate_web/mcp/tools/write_projects_test.exs`
Expected: FAIL — `CreateProject` undefined.

- [ ] **Step 3: Implement the tool**

Create `lib/estimate_web/mcp/tools/create_project.ex`:

```elixir
defmodule EstimateWeb.MCP.Tools.CreateProject do
  @moduledoc "Create a project under a customer. Any org member may create one and becomes its owner. Currency defaults to the customer's default."

  use Anubis.Server.Component, type: :tool

  alias Estimate.Portfolio
  alias EstimateWeb.MCP.{Serializers, Write}

  schema do
    field :customer_id, :string, required: true, description: "Owning customer UUID"
    field :name, :string, required: true
    field :key, :string, description: "2–10 uppercase letters/numbers, unique per customer"
    field :short_description, :string
    field :detailed_description, :string
    field :repository_url, :string, description: "http(s):// URL"
    field :status, :enum, values: ["active", "archived", "completed"], default: "active"
    field :currency, :string, description: "Currency code; omit to inherit the customer default"
  end

  @impl true
  def execute(params, frame) do
    Write.execute(frame, fn _claims -> :ok end, fn %{org_id: org_id, user_id: user_id} ->
      with {:ok, currency_id} <- Write.resolve_currency(params[:currency], org_id),
           {:ok, project} <-
             Portfolio.create_project(attrs(params, currency_id), params.customer_id, user_id, org_id) do
        {:ok,
         Serializers.project(project)
         |> Map.put(:url, Serializers.project_url(org_id, project.id))}
      end
    end)
  end

  defp attrs(params, currency_id) do
    %{
      "name" => params.name,
      "key" => params[:key],
      "short_description" => params[:short_description],
      "detailed_description" => params[:detailed_description],
      "repository_url" => params[:repository_url],
      "status" => params[:status] || "active",
      "currency_id" => currency_id
    }
  end
end
```

Note: `Portfolio.create_project/4` calls `CRM.get_customer!/2` for the customer, which raises `Ecto.NoResultsError` for a bad/foreign id — `Write.safe_run` converts it to `{:error, :not_found}`.

- [ ] **Step 4: Register the tool**

`lib/estimate_web/mcp_server.ex`:

```elixir
  component(EstimateWeb.MCP.Tools.CreateProject)
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `mix test test/estimate_web/mcp/tools/write_projects_test.exs`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/estimate_web/mcp/tools/create_project.ex lib/estimate_web/mcp_server.ex test/estimate_web/mcp/tools/write_projects_test.exs
git commit -m "feat: create_project MCP tool"
```

---

### Task 9: `update_project` tool

**Files:**
- Create: `lib/estimate_web/mcp/tools/update_project.ex`
- Modify: `lib/estimate_web/mcp_server.ex`
- Test: append to `test/estimate_web/mcp/tools/write_projects_test.exs`

**Interfaces:**
- Consumes: `Authz.ensure_project/2` + `require_can_edit_project/2`, `Portfolio.get_project!/2`, `Portfolio.update_project/2`.
- Produces: tool `update_project`. Gate: `ensure_project` then `require_can_edit_project` (org-admin OR owner/editor).

- [ ] **Step 1: Write the failing test**

Append inside `WriteProjectsTest`:

```elixir
  test "owner edits; viewer collaborator is denied", %{owner: owner, org: org, customer: customer} do
    project = project_fixture(customer, owner, %{"name" => "Site"})

    assert {:reply, resp, _} =
             UpdateProject.execute(%{id: project.id, name: "Site v2"}, frame(owner, org))

    refute resp.isError
    assert json_content(resp)["name"] == "Site v2"

    viewer = user_fixture()
    _ = membership_fixture(viewer, org, "member")
    {:ok, _} = Portfolio.add_collaborator(project.id, viewer.id, "viewer")

    assert {:reply, %Response{isError: true} = denied, _} =
             UpdateProject.execute(%{id: project.id, name: "Nope"}, frame(viewer, org, "member"))

    assert json_error(denied) =~ "not authorized"
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/estimate_web/mcp/tools/write_projects_test.exs`
Expected: FAIL — `UpdateProject` undefined.

- [ ] **Step 3: Implement the tool**

Create `lib/estimate_web/mcp/tools/update_project.ex`:

```elixir
defmodule EstimateWeb.MCP.Tools.UpdateProject do
  @moduledoc "Update a project (org admin or project owner/editor). Only the fields you pass are changed."

  use Anubis.Server.Component, type: :tool

  alias Estimate.Portfolio
  alias EstimateWeb.MCP.{Authz, Serializers, Write}

  schema do
    field :id, :string, required: true, description: "Project UUID"
    field :name, :string
    field :key, :string
    field :short_description, :string
    field :detailed_description, :string
    field :repository_url, :string
    field :status, :enum, values: ["active", "archived", "completed"]
    field :currency, :string, description: "Currency code"
  end

  @impl true
  def execute(params, frame) do
    gate = fn claims ->
      with {:ok, pid} <- Authz.ensure_project(params.id, claims.org_id) do
        Authz.require_can_edit_project(pid, claims)
      end
    end

    Write.execute(frame, gate, fn %{org_id: org_id} ->
      project = Portfolio.get_project!(params.id, org_id)

      with {:ok, attrs} <- change_attrs(params, org_id),
           {:ok, updated} <- Portfolio.update_project(project, attrs) do
        {:ok,
         Serializers.project(updated)
         |> Map.put(:url, Serializers.project_url(org_id, updated.id))}
      end
    end)
  end

  defp change_attrs(params, org_id) do
    with {:ok, currency} <- currency_change(params, org_id) do
      base =
        params
        |> Map.take([:name, :key, :short_description, :detailed_description, :repository_url, :status])
        |> Map.new(fn {k, v} -> {to_string(k), v} end)

      {:ok, Map.merge(base, currency)}
    end
  end

  defp currency_change(params, org_id) do
    case Map.fetch(params, :currency) do
      :error -> {:ok, %{}}
      {:ok, code} -> with {:ok, id} <- Write.resolve_currency(code, org_id), do: {:ok, %{"currency_id" => id}}
    end
  end
end
```

- [ ] **Step 4: Register the tool**

`lib/estimate_web/mcp_server.ex`:

```elixir
  component(EstimateWeb.MCP.Tools.UpdateProject)
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `mix test test/estimate_web/mcp/tools/write_projects_test.exs`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/estimate_web/mcp/tools/update_project.ex lib/estimate_web/mcp_server.ex test/estimate_web/mcp/tools/write_projects_test.exs
git commit -m "feat: update_project MCP tool"
```

---

### Task 10: `create_estimation` tool (inline roles + template seeding)

**Files:**
- Create: `lib/estimate_web/mcp/tools/create_estimation.ex`
- Modify: `lib/estimate_web/mcp_server.ex`
- Test: `test/estimate_web/mcp/tools/write_estimations_test.exs`

**Interfaces:**
- Consumes: `Authz.ensure_project/2` + `require_can_edit_project/2`, `EstimationEngine.create_estimation_from_templates/2`, `EstimationEngine.get_estimation!/2`, `Accounts.list_role_templates/1`, `Portfolio.get_project!/2`, `Serializers.estimation_tree/1` + `estimation_url/3`.
- Produces: tool `create_estimation`. Role-attrs maps use ATOM keys `%{name, abbreviation, hourly_rate, pm_overhead, qa_overhead, risk_buffer}` (consumed by `Roles.insert_roles_from_attrs/2`, which reads `attrs.name` etc. and defaults each `nil` numeric to `Decimal.new(0)`).

- [ ] **Step 1: Write the failing test**

Create `test/estimate_web/mcp/tools/write_estimations_test.exs`:

```elixir
defmodule EstimateWeb.MCP.Tools.WriteEstimationsTest do
  use Estimate.DataCase, async: false

  import Estimate.{AccountsFixtures, PortfolioFixtures, EstimationEngineFixtures, MCPFixtures}
  alias Anubis.Server.Response
  alias EstimateWeb.MCP.Tools.{CreateEstimation, UpdateEstimation}

  setup do
    %{user: owner, organization: org} = user_with_organization_fixture()
    enable_mcp_write(org)
    project = project_fixture(nil, owner)
    %{owner: owner, org: org, project: project}
  end

  defp frame(user, org, role \\ "owner"), do: mcp_frame(user, org, role)

  test "inline roles are created; response has tree totals + url", %{owner: owner, org: org, project: project} do
    params = %{
      project_id: project.id,
      name: "MVP",
      currency: "EUR",
      roles: [
        %{name: "Backend", abbreviation: "BE", hourly_rate: 90.0},
        %{name: "Frontend", abbreviation: "FE", hourly_rate: 80.0}
      ]
    }

    assert {:reply, resp, _} = CreateEstimation.execute(params, frame(owner, org))
    refute resp.isError
    body = json_content(resp)
    assert body["name"] == "MVP"
    assert Enum.map(body["roles"], & &1["abbreviation"]) |> Enum.sort() == ["BE", "FE"]
    assert body["url"] =~ "/projects/#{project.id}/estimations/#{body["id"]}/estimator"
  end

  test "omitting roles seeds the org role templates", %{owner: owner, org: org, project: project} do
    assert {:reply, resp, _} =
             CreateEstimation.execute(%{project_id: project.id, name: "Seeded"}, frame(owner, org))

    refute resp.isError
    # user_with_organization_fixture seeds 8 default role templates
    assert length(json_content(resp)["roles"]) == 8
  end

  test "org member who is not a collaborator is denied", %{org: org, project: project} do
    member = user_fixture()
    _ = membership_fixture(member, org, "member")

    assert {:reply, %Response{isError: true} = resp, _} =
             CreateEstimation.execute(%{project_id: project.id, name: "Nope"}, frame(member, org, "member"))

    assert json_error(resp) =~ "not authorized"
  end

  test "unknown project → not found", %{owner: owner, org: org} do
    assert {:reply, %Response{isError: true} = resp, _} =
             CreateEstimation.execute(%{project_id: Ecto.UUID.generate(), name: "x"}, frame(owner, org))

    assert json_error(resp) =~ "not found"
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/estimate_web/mcp/tools/write_estimations_test.exs`
Expected: FAIL — `CreateEstimation` undefined.

- [ ] **Step 3: Implement the tool**

Create `lib/estimate_web/mcp/tools/create_estimation.ex`:

```elixir
defmodule EstimateWeb.MCP.Tools.CreateEstimation do
  @moduledoc """
  Create an estimation on a project (org admin or project owner/editor).
  Pass `roles` to define the team explicitly, or omit it to seed the
  organization's role templates (like the app's "new estimation" modal).
  Currency defaults to the project's currency.
  """

  use Anubis.Server.Component, type: :tool

  alias Estimate.{Accounts, EstimationEngine, Portfolio}
  alias EstimateWeb.MCP.{Authz, Serializers, Write}

  schema do
    field :project_id, :string, required: true, description: "Owning project UUID"
    field :name, :string, required: true
    field :description, :string
    field :currency, :string, description: "Currency code; omit to inherit the project currency"

    embeds_many :roles, description: "Team roles; omit to seed org role templates" do
      field :name, :string, required: true
      field :abbreviation, :string, required: true, description: "1–5 chars; referenced by task efforts"
      field :hourly_rate, :float
      field :pm_overhead, :float, description: "0–100 (%)"
      field :qa_overhead, :float, description: "0–100 (%)"
      field :risk_buffer, :float, description: "0–100 (%)"
    end
  end

  @impl true
  def execute(params, frame) do
    gate = fn claims ->
      with {:ok, pid} <- Authz.ensure_project(params.project_id, claims.org_id) do
        Authz.require_can_edit_project(pid, claims)
      end
    end

    Write.execute(frame, gate, fn %{org_id: org_id} ->
      with {:ok, currency_id} <- currency_id(params, org_id),
           attrs = base_attrs(params, currency_id),
           role_attrs = role_attrs(params, org_id, currency_id),
           {:ok, est} <- EstimationEngine.create_estimation_from_templates(attrs, role_attrs) do
        est = EstimationEngine.get_estimation!(est.id, org_id)

        {:ok,
         Serializers.estimation_tree(est)
         |> Map.put(:url, Serializers.estimation_url(org_id, est.project_id, est.id))}
      end
    end)
  end

  defp base_attrs(params, currency_id) do
    %{"name" => params.name, "description" => params[:description], "project_id" => params.project_id, "currency_id" => currency_id}
  end

  defp currency_id(params, org_id) do
    case Write.resolve_currency(params[:currency], org_id) do
      {:ok, nil} -> {:ok, Portfolio.get_project!(params.project_id, org_id).currency_id}
      other -> other
    end
  end

  defp role_attrs(%{roles: [_ | _] = roles}, _org_id, _currency_id) do
    Enum.map(roles, fn r ->
      %{
        name: r.name,
        abbreviation: r.abbreviation,
        hourly_rate: to_decimal(r[:hourly_rate]),
        pm_overhead: to_decimal(r[:pm_overhead]),
        qa_overhead: to_decimal(r[:qa_overhead]),
        risk_buffer: to_decimal(r[:risk_buffer])
      }
    end)
  end

  defp role_attrs(_params, org_id, currency_id) do
    org_id
    |> Accounts.list_role_templates()
    |> Enum.map(fn t ->
      rate = Enum.find(t.rates, &(&1.currency_id == currency_id))

      %{
        name: t.name,
        abbreviation: t.abbreviation,
        hourly_rate: (rate && rate.hourly_rate) || Decimal.new(0),
        pm_overhead: t.pm_overhead,
        qa_overhead: t.qa_overhead,
        risk_buffer: t.risk_buffer
      }
    end)
  end

  defp to_decimal(nil), do: nil
  defp to_decimal(%Decimal{} = d), do: d
  defp to_decimal(n) when is_integer(n) or is_float(n), do: Decimal.new(to_string(n))
  defp to_decimal(s) when is_binary(s), do: Decimal.new(s)
end
```

Note: `params.roles` is `[]` when the client omits it (Peri default for `embeds_many`), so the second `role_attrs/3` clause (template seeding) matches. `Roles.insert_roles_from_attrs/2` reads `attrs.hourly_rate || Decimal.new(0)` etc., so `nil` numerics become `0`.

- [ ] **Step 4: Register the tool**

`lib/estimate_web/mcp_server.ex`:

```elixir
  component(EstimateWeb.MCP.Tools.CreateEstimation)
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `mix test test/estimate_web/mcp/tools/write_estimations_test.exs`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/estimate_web/mcp/tools/create_estimation.ex lib/estimate_web/mcp_server.ex test/estimate_web/mcp/tools/write_estimations_test.exs
git commit -m "feat: create_estimation MCP tool (inline roles + template seeding)"
```

---

### Task 11: `update_estimation` tool

**Files:**
- Create: `lib/estimate_web/mcp/tools/update_estimation.ex`
- Modify: `lib/estimate_web/mcp_server.ex`
- Test: append to `test/estimate_web/mcp/tools/write_estimations_test.exs`

**Interfaces:**
- Consumes: `Authz.project_id_for(:estimation, id, org_id)` + `require_can_edit_project/2`, `EstimationEngine.get_estimation!/2`, `EstimationEngine.update_estimation/2`.
- Produces: tool `update_estimation`.

- [ ] **Step 1: Write the failing test**

Append inside `WriteEstimationsTest`:

```elixir
  test "owner updates estimation name + currency", %{owner: owner, org: org, project: project} do
    est = estimation_fixture(project)

    assert {:reply, resp, _} =
             UpdateEstimation.execute(%{id: est.id, name: "Renamed", currency: "GBP"}, frame(owner, org))

    refute resp.isError
    body = json_content(resp)
    assert body["name"] == "Renamed"
    assert body["currency"] == "GBP"
    assert body["url"] =~ "/estimations/#{est.id}/estimator"
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/estimate_web/mcp/tools/write_estimations_test.exs`
Expected: FAIL — `UpdateEstimation` undefined.

- [ ] **Step 3: Implement the tool**

Create `lib/estimate_web/mcp/tools/update_estimation.ex`:

```elixir
defmodule EstimateWeb.MCP.Tools.UpdateEstimation do
  @moduledoc "Update an estimation's name/description/currency (org admin or project owner/editor)."

  use Anubis.Server.Component, type: :tool

  alias Estimate.EstimationEngine
  alias EstimateWeb.MCP.{Authz, Serializers, Write}

  schema do
    field :id, :string, required: true, description: "Estimation UUID"
    field :name, :string
    field :description, :string
    field :currency, :string, description: "Currency code"
  end

  @impl true
  def execute(params, frame) do
    gate = fn claims ->
      with {:ok, pid} <- Authz.project_id_for(:estimation, params.id, claims.org_id) do
        Authz.require_can_edit_project(pid, claims)
      end
    end

    Write.execute(frame, gate, fn %{org_id: org_id} ->
      est = EstimationEngine.get_estimation!(params.id, org_id)

      with {:ok, attrs} <- change_attrs(params, org_id),
           {:ok, _updated} <- EstimationEngine.update_estimation(est, attrs) do
        est = EstimationEngine.get_estimation!(params.id, org_id)

        {:ok,
         Serializers.estimation_tree(est)
         |> Map.put(:url, Serializers.estimation_url(org_id, est.project_id, est.id))}
      end
    end)
  end

  defp change_attrs(params, org_id) do
    with {:ok, currency} <- currency_change(params, org_id) do
      base = params |> Map.take([:name, :description]) |> Map.new(fn {k, v} -> {to_string(k), v} end)
      {:ok, Map.merge(base, currency)}
    end
  end

  defp currency_change(params, org_id) do
    case Map.fetch(params, :currency) do
      :error -> {:ok, %{}}
      {:ok, code} -> with {:ok, id} <- Write.resolve_currency(code, org_id), do: {:ok, %{"currency_id" => id}}
    end
  end
end
```

- [ ] **Step 4: Register the tool**

`lib/estimate_web/mcp_server.ex`:

```elixir
  component(EstimateWeb.MCP.Tools.UpdateEstimation)
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `mix test test/estimate_web/mcp/tools/write_estimations_test.exs`
Expected: PASS (5 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/estimate_web/mcp/tools/update_estimation.ex lib/estimate_web/mcp_server.ex test/estimate_web/mcp/tools/write_estimations_test.exs
git commit -m "feat: update_estimation MCP tool"
```

---

### Task 12: `add_estimation_role` + `update_estimation_role` tools

**Files:**
- Create: `lib/estimate_web/mcp/tools/add_estimation_role.ex`, `lib/estimate_web/mcp/tools/update_estimation_role.ex`
- Modify: `lib/estimate_web/mcp_server.ex`
- Test: `test/estimate_web/mcp/tools/write_roles_test.exs`

**Interfaces:**
- Consumes: `Authz.project_id_for(:estimation | :role, …)` + `require_can_edit_project/2`, `EstimationEngine.create_role/1`, `EstimationEngine.get_role!/2`, `EstimationEngine.update_role/2`, `EstimationEngine.get_estimation_project_id/2`, `Serializers.estimation_role/1` + `estimation_url/3`.
- Produces: tools `add_estimation_role`, `update_estimation_role`. `create_role/1` requires attrs key `estimation_id` and inserts at the given `position` (pass a large position or 0 — the app orders by position; use `0` and let the user reorder in-app, matching how child creates elsewhere default position).

- [ ] **Step 1: Write the failing test**

Create `test/estimate_web/mcp/tools/write_roles_test.exs`:

```elixir
defmodule EstimateWeb.MCP.Tools.WriteRolesTest do
  use Estimate.DataCase, async: false

  import Estimate.{AccountsFixtures, PortfolioFixtures, EstimationEngineFixtures, MCPFixtures}
  alias Anubis.Server.Response
  alias EstimateWeb.MCP.Tools.{AddEstimationRole, UpdateEstimationRole}

  setup do
    %{user: owner, organization: org} = user_with_organization_fixture()
    enable_mcp_write(org)
    project = project_fixture(nil, owner)
    est = estimation_fixture(project)
    %{owner: owner, org: org, project: project, est: est}
  end

  defp frame(user, org, role \\ "owner"), do: mcp_frame(user, org, role)

  test "adds a role with rate + overheads", %{owner: owner, org: org, est: est, project: project} do
    assert {:reply, resp, _} =
             AddEstimationRole.execute(
               %{estimation_id: est.id, name: "DevOps", abbreviation: "DO", hourly_rate: 100.0, pm_overhead: 10.0},
               frame(owner, org)
             )

    refute resp.isError
    body = json_content(resp)
    assert body["abbreviation"] == "DO"
    assert body["hourly_rate"] == "100"
    assert body["url"] =~ "/estimations/#{est.id}/estimator"
  end

  test "add rejects abbreviation over 5 chars with readable error", %{owner: owner, org: org, est: est} do
    assert {:reply, %Response{isError: true} = resp, _} =
             AddEstimationRole.execute(%{estimation_id: est.id, name: "X", abbreviation: "TOOLONG"}, frame(owner, org))

    assert json_error(resp) =~ "abbreviation:"
  end

  test "non-collaborator member denied", %{org: org, est: est} do
    member = user_fixture()
    _ = membership_fixture(member, org, "member")

    assert {:reply, %Response{isError: true} = resp, _} =
             AddEstimationRole.execute(%{estimation_id: est.id, name: "X", abbreviation: "X"}, frame(member, org, "member"))

    assert json_error(resp) =~ "not authorized"
  end

  test "updates a role's rate", %{owner: owner, org: org, est: est} do
    {:reply, add, _} =
      AddEstimationRole.execute(%{estimation_id: est.id, name: "BE", abbreviation: "BE", hourly_rate: 90.0}, frame(owner, org))

    role_id = json_content(add)["id"]

    assert {:reply, resp, _} =
             UpdateEstimationRole.execute(%{id: role_id, hourly_rate: 120.0}, frame(owner, org))

    refute resp.isError
    assert json_content(resp)["hourly_rate"] == "120"
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/estimate_web/mcp/tools/write_roles_test.exs`
Expected: FAIL — modules undefined.

- [ ] **Step 3: Implement `add_estimation_role`**

Create `lib/estimate_web/mcp/tools/add_estimation_role.ex`:

```elixir
defmodule EstimateWeb.MCP.Tools.AddEstimationRole do
  @moduledoc "Add a role (with hourly rate + optional PM/QA/risk overheads) to an estimation. Task efforts reference roles by their abbreviation."

  use Anubis.Server.Component, type: :tool

  alias Estimate.EstimationEngine
  alias EstimateWeb.MCP.{Authz, Serializers, Write}

  schema do
    field :estimation_id, :string, required: true
    field :name, :string, required: true
    field :abbreviation, :string, required: true, description: "1–5 chars, referenced by task efforts"
    field :hourly_rate, :float
    field :pm_overhead, :float, description: "0–100 (%)"
    field :qa_overhead, :float, description: "0–100 (%)"
    field :risk_buffer, :float, description: "0–100 (%)"
  end

  @impl true
  def execute(params, frame) do
    gate = fn claims ->
      with {:ok, pid} <- Authz.project_id_for(:estimation, params.estimation_id, claims.org_id) do
        Authz.require_can_edit_project(pid, claims)
      end
    end

    Write.execute(frame, gate, fn %{org_id: org_id} ->
      with {:ok, role} <- EstimationEngine.create_role(attrs(params)) do
        pid = EstimationEngine.get_estimation_project_id(params.estimation_id, org_id)

        {:ok,
         Serializers.estimation_role(role)
         |> Map.put(:url, Serializers.estimation_url(org_id, pid, params.estimation_id))}
      end
    end)
  end

  defp attrs(params) do
    %{
      "estimation_id" => params.estimation_id,
      "name" => params.name,
      "abbreviation" => params.abbreviation,
      "hourly_rate" => num(params[:hourly_rate]),
      "pm_overhead" => num(params[:pm_overhead]),
      "qa_overhead" => num(params[:qa_overhead]),
      "risk_buffer" => num(params[:risk_buffer]),
      "position" => 0
    }
  end

  defp num(nil), do: nil
  defp num(n), do: to_string(n)
end
```

- [ ] **Step 4: Implement `update_estimation_role`**

Create `lib/estimate_web/mcp/tools/update_estimation_role.ex`:

```elixir
defmodule EstimateWeb.MCP.Tools.UpdateEstimationRole do
  @moduledoc "Update an estimation role's name/abbreviation/rate/overheads (org admin or project owner/editor)."

  use Anubis.Server.Component, type: :tool

  alias Estimate.EstimationEngine
  alias EstimateWeb.MCP.{Authz, Serializers, Write}

  schema do
    field :id, :string, required: true, description: "Estimation role UUID"
    field :name, :string
    field :abbreviation, :string
    field :hourly_rate, :float
    field :pm_overhead, :float
    field :qa_overhead, :float
    field :risk_buffer, :float
  end

  @impl true
  def execute(params, frame) do
    gate = fn claims ->
      with {:ok, pid} <- Authz.project_id_for(:role, params.id, claims.org_id) do
        Authz.require_can_edit_project(pid, claims)
      end
    end

    Write.execute(frame, gate, fn %{org_id: org_id} ->
      role = EstimationEngine.get_role!(params.id, org_id)

      with {:ok, updated} <- EstimationEngine.update_role(role, attrs(params)) do
        pid = EstimationEngine.get_estimation_project_id(updated.estimation_id, org_id)

        {:ok,
         Serializers.estimation_role(updated)
         |> Map.put(:url, Serializers.estimation_url(org_id, pid, updated.estimation_id))}
      end
    end)
  end

  defp attrs(params) do
    params
    |> Map.take([:name, :abbreviation, :hourly_rate, :pm_overhead, :qa_overhead, :risk_buffer])
    |> Map.new(fn
      {k, v} when k in [:hourly_rate, :pm_overhead, :qa_overhead, :risk_buffer] -> {to_string(k), to_string(v)}
      {k, v} -> {to_string(k), v}
    end)
  end
end
```

- [ ] **Step 5: Register both tools**

`lib/estimate_web/mcp_server.ex`:

```elixir
  component(EstimateWeb.MCP.Tools.AddEstimationRole)
  component(EstimateWeb.MCP.Tools.UpdateEstimationRole)
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `mix test test/estimate_web/mcp/tools/write_roles_test.exs`
Expected: PASS (4 tests).

- [ ] **Step 7: Commit**

```bash
git add lib/estimate_web/mcp/tools/add_estimation_role.ex lib/estimate_web/mcp/tools/update_estimation_role.ex lib/estimate_web/mcp_server.ex test/estimate_web/mcp/tools/write_roles_test.exs
git commit -m "feat: add/update_estimation_role MCP tools"
```

---

### Task 13: `add_epic` + `update_epic` tools

**Files:**
- Create: `lib/estimate_web/mcp/tools/add_epic.ex`, `lib/estimate_web/mcp/tools/update_epic.ex`
- Modify: `lib/estimate_web/mcp_server.ex`
- Test: `test/estimate_web/mcp/tools/write_epics_test.exs`

**Interfaces:**
- Consumes: `Authz.project_id_for(:estimation | :epic, …)` + `require_can_edit_project/2`, `EstimationEngine.create_epic/1`, `get_epic!/2`, `update_epic/2`, `get_estimation_project_id/2`, `Serializers.epic/1` + `estimation_url/3`.
- Produces: tools `add_epic`, `update_epic`. `Serializers.epic/1` reads `e.tasks`; `create_epic/1` returns an epic without tasks loaded, so map the response manually (id/name/description/position) rather than calling `Serializers.epic/1` on the fresh epic.

- [ ] **Step 1: Write the failing test**

Create `test/estimate_web/mcp/tools/write_epics_test.exs`:

```elixir
defmodule EstimateWeb.MCP.Tools.WriteEpicsTest do
  use Estimate.DataCase, async: false

  import Estimate.{AccountsFixtures, PortfolioFixtures, EstimationEngineFixtures, MCPFixtures}
  alias Anubis.Server.Response
  alias EstimateWeb.MCP.Tools.{AddEpic, UpdateEpic}

  setup do
    %{user: owner, organization: org} = user_with_organization_fixture()
    enable_mcp_write(org)
    est = estimation_fixture(project_fixture(nil, owner))
    %{owner: owner, org: org, est: est}
  end

  defp frame(user, org, role \\ "owner"), do: mcp_frame(user, org, role)

  test "adds an epic", %{owner: owner, org: org, est: est} do
    assert {:reply, resp, _} =
             AddEpic.execute(%{estimation_id: est.id, name: "Backend", description: "APIs"}, frame(owner, org))

    refute resp.isError
    body = json_content(resp)
    assert body["name"] == "Backend"
    assert body["url"] =~ "/estimations/#{est.id}/estimator"
  end

  test "non-collaborator denied", %{org: org, est: est} do
    member = user_fixture()
    _ = membership_fixture(member, org, "member")

    assert {:reply, %Response{isError: true} = resp, _} =
             AddEpic.execute(%{estimation_id: est.id, name: "X"}, frame(member, org, "member"))

    assert json_error(resp) =~ "not authorized"
  end

  test "updates an epic name", %{owner: owner, org: org, est: est} do
    {:reply, add, _} = AddEpic.execute(%{estimation_id: est.id, name: "Old"}, frame(owner, org))
    epic_id = json_content(add)["id"]

    assert {:reply, resp, _} = UpdateEpic.execute(%{id: epic_id, name: "New"}, frame(owner, org))
    refute resp.isError
    assert json_content(resp)["name"] == "New"
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/estimate_web/mcp/tools/write_epics_test.exs`
Expected: FAIL — modules undefined.

- [ ] **Step 3: Implement `add_epic`**

Create `lib/estimate_web/mcp/tools/add_epic.ex`:

```elixir
defmodule EstimateWeb.MCP.Tools.AddEpic do
  @moduledoc "Add an epic (workstream) to an estimation (org admin or project owner/editor)."

  use Anubis.Server.Component, type: :tool

  alias Estimate.EstimationEngine
  alias EstimateWeb.MCP.{Authz, Serializers, Write}

  schema do
    field :estimation_id, :string, required: true
    field :name, :string, required: true
    field :description, :string
    field :position, :integer, min: 0, description: "Sort order; defaults to 0"
  end

  @impl true
  def execute(params, frame) do
    gate = fn claims ->
      with {:ok, pid} <- Authz.project_id_for(:estimation, params.estimation_id, claims.org_id) do
        Authz.require_can_edit_project(pid, claims)
      end
    end

    Write.execute(frame, gate, fn %{org_id: org_id} ->
      attrs = %{
        "estimation_id" => params.estimation_id,
        "name" => params.name,
        "description" => params[:description],
        "position" => params[:position] || 0
      }

      with {:ok, epic} <- EstimationEngine.create_epic(attrs) do
        pid = EstimationEngine.get_estimation_project_id(params.estimation_id, org_id)

        {:ok,
         %{id: epic.id, name: epic.name, description: epic.description, position: epic.position, url: Serializers.estimation_url(org_id, pid, params.estimation_id)}}
      end
    end)
  end
end
```

- [ ] **Step 4: Implement `update_epic`**

Create `lib/estimate_web/mcp/tools/update_epic.ex`:

```elixir
defmodule EstimateWeb.MCP.Tools.UpdateEpic do
  @moduledoc "Update an epic's name/description (org admin or project owner/editor)."

  use Anubis.Server.Component, type: :tool

  alias Estimate.EstimationEngine
  alias EstimateWeb.MCP.{Authz, Serializers, Write}

  schema do
    field :id, :string, required: true, description: "Epic UUID"
    field :name, :string
    field :description, :string
  end

  @impl true
  def execute(params, frame) do
    gate = fn claims ->
      with {:ok, pid} <- Authz.project_id_for(:epic, params.id, claims.org_id) do
        Authz.require_can_edit_project(pid, claims)
      end
    end

    Write.execute(frame, gate, fn %{org_id: org_id} ->
      epic = EstimationEngine.get_epic!(params.id, org_id)
      attrs = params |> Map.take([:name, :description]) |> Map.new(fn {k, v} -> {to_string(k), v} end)

      with {:ok, updated} <- EstimationEngine.update_epic(epic, attrs) do
        pid = EstimationEngine.get_estimation_project_id(updated.estimation_id, org_id)

        {:ok,
         %{id: updated.id, name: updated.name, description: updated.description, position: updated.position, url: Serializers.estimation_url(org_id, pid, updated.estimation_id)}}
      end
    end)
  end
end
```

- [ ] **Step 5: Register both tools**

`lib/estimate_web/mcp_server.ex`:

```elixir
  component(EstimateWeb.MCP.Tools.AddEpic)
  component(EstimateWeb.MCP.Tools.UpdateEpic)
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `mix test test/estimate_web/mcp/tools/write_epics_test.exs`
Expected: PASS (3 tests).

- [ ] **Step 7: Commit**

```bash
git add lib/estimate_web/mcp/tools/add_epic.ex lib/estimate_web/mcp/tools/update_epic.ex lib/estimate_web/mcp_server.ex test/estimate_web/mcp/tools/write_epics_test.exs
git commit -m "feat: add/update_epic MCP tools"
```

---

### Task 14: `create_task_with_estimates/3` context function

Atomic task-plus-efforts insert used by `add_task`. Lives in the context so the transaction and broadcast stay out of the web layer.

**Files:**
- Modify: `lib/estimate/estimation_engine/tasks.ex`
- Modify: `lib/estimate/estimation_engine.ex`
- Test: `test/estimate/estimation_engine/create_task_with_estimates_test.exs`

**Interfaces:**
- Produces: `EstimationEngine.create_task_with_estimates(epic_id, task_attrs :: map, effort_by_role_id :: %{role_id => number}) :: {:ok, %Task{estimates: [...]}} | {:error, changeset}`. Atomic: on any failure nothing is inserted.

- [ ] **Step 1: Write the failing test**

Create `test/estimate/estimation_engine/create_task_with_estimates_test.exs`:

```elixir
defmodule Estimate.EstimationEngine.CreateTaskWithEstimatesTest do
  use Estimate.DataCase, async: false

  import Estimate.{AccountsFixtures, PortfolioFixtures, EstimationEngineFixtures}
  alias Estimate.EstimationEngine

  setup do
    %{user: user} = user_with_organization_fixture()
    est = estimation_fixture(project_fixture(nil, user))
    epic = epic_fixture(est)
    {:ok, be} = EstimationEngine.create_role(%{"estimation_id" => est.id, "name" => "BE", "abbreviation" => "BE"})
    %{epic: epic, be: be}
  end

  test "creates task and its estimates atomically", %{epic: epic, be: be} do
    assert {:ok, task} =
             EstimationEngine.create_task_with_estimates(epic.id, %{"name" => "Login"}, %{be.id => 8})

    assert task.name == "Login"
    assert [%{estimation_role_id: rid, hours: hours}] = task.estimates
    assert rid == be.id
    assert Decimal.equal?(hours, Decimal.new(8))
  end

  test "empty efforts creates just the task", %{epic: epic} do
    assert {:ok, task} = EstimationEngine.create_task_with_estimates(epic.id, %{"name" => "Skeleton"}, %{})
    assert task.estimates == []
  end

  test "a bad estimate rolls the whole thing back", %{epic: epic} do
    assert {:error, _cs} =
             EstimationEngine.create_task_with_estimates(epic.id, %{"name" => "X"}, %{Ecto.UUID.generate() => 8})

    assert Estimate.Repo.aggregate(
             from(t in Estimate.EstimationEngine.Task, where: t.name == "X"),
             :count
           ) == 0
  end
end
```

(Add `import Ecto.Query` at the top of the test.)

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/estimate/estimation_engine/create_task_with_estimates_test.exs`
Expected: FAIL — function undefined.

- [ ] **Step 3: Implement**

In `lib/estimate/estimation_engine/tasks.ex`, add (ensure `alias Estimate.EstimationEngine.{Task, TaskEstimate}` and `alias Estimate.EstimationEngine` for broadcast; import Ecto.Query already present in siblings):

```elixir
  def create_task_with_estimates(epic_id, task_attrs, effort_by_role_id)
      when is_map(effort_by_role_id) do
    Repo.ensure_org_context(fn ->
      Ecto.Multi.new()
      |> Ecto.Multi.insert(:task, Task.changeset(%Task{}, Map.put(task_attrs, "epic_id", epic_id)))
      |> Ecto.Multi.run(:estimates, fn _repo, %{task: task} ->
        Enum.reduce_while(effort_by_role_id, {:ok, []}, fn {role_id, hours}, {:ok, acc} ->
          %TaskEstimate{}
          |> TaskEstimate.changeset(%{
            "task_id" => task.id,
            "estimation_role_id" => role_id,
            "hours" => to_string(hours)
          })
          |> Repo.insert()
          |> case do
            {:ok, te} -> {:cont, {:ok, [te | acc]}}
            {:error, cs} -> {:halt, {:error, cs}}
          end
        end)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{task: task}} ->
          task = Repo.preload(task, :estimates)
          epic = Repo.get!(Estimate.EstimationEngine.Epic, epic_id)
          Estimate.EstimationEngine.broadcast(epic.estimation_id, {:task_created, task})
          {:ok, task}

        {:error, _op, changeset, _} ->
          {:error, changeset}
      end
    end)
  end
```

In `lib/estimate/estimation_engine.ex`, under `## Tasks`:

```elixir
  defdelegate create_task_with_estimates(epic_id, task_attrs, effort_by_role_id), to: Tasks
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/estimate/estimation_engine/create_task_with_estimates_test.exs`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/estimate/estimation_engine/tasks.ex lib/estimate/estimation_engine.ex test/estimate/estimation_engine/create_task_with_estimates_test.exs
git commit -m "feat: EstimationEngine.create_task_with_estimates/3 (atomic)"
```

---

### Task 15: `add_task` + `update_task` tools

**Files:**
- Create: `lib/estimate_web/mcp/tools/add_task.ex`, `lib/estimate_web/mcp/tools/update_task.ex`
- Modify: `lib/estimate_web/mcp_server.ex`
- Test: `test/estimate_web/mcp/tools/write_tasks_test.exs`

**Interfaces:**
- Consumes: `Authz.project_id_for(:epic | :task, …)` + `require_can_edit_project/2`, `EstimationEngine.get_epic!/2`, `get_estimation!/2` (for role abbrevs), `create_task_with_estimates/3`, `get_task!/2`, `update_task/2`, `Serializers.task/1` + `estimation_url/3`.
- Produces: tools `add_task`, `update_task`. `efforts` is an object `{abbrev → hours}` resolved against the estimation's role abbreviations; unknown abbrev → error listing valid ones (no task created).

- [ ] **Step 1: Write the failing test**

Create `test/estimate_web/mcp/tools/write_tasks_test.exs`:

```elixir
defmodule EstimateWeb.MCP.Tools.WriteTasksTest do
  use Estimate.DataCase, async: false

  import Estimate.{AccountsFixtures, PortfolioFixtures, EstimationEngineFixtures, MCPFixtures}
  alias Anubis.Server.Response
  alias Estimate.EstimationEngine
  alias EstimateWeb.MCP.Tools.{AddTask, UpdateTask}

  setup do
    %{user: owner, organization: org} = user_with_organization_fixture()
    enable_mcp_write(org)
    est = estimation_fixture(project_fixture(nil, owner))
    epic = epic_fixture(est)
    {:ok, _be} = EstimationEngine.create_role(%{"estimation_id" => est.id, "name" => "BE", "abbreviation" => "BE"})
    %{owner: owner, org: org, est: est, epic: epic}
  end

  defp frame(user, org, role \\ "owner"), do: mcp_frame(user, org, role)

  test "adds a task with inline efforts", %{owner: owner, org: org, epic: epic, est: est} do
    assert {:reply, resp, _} =
             AddTask.execute(
               %{epic_id: epic.id, name: "Login", priority: "must", efforts: %{"BE" => 8.0}},
               frame(owner, org)
             )

    refute resp.isError
    body = json_content(resp)
    assert body["name"] == "Login"
    assert [%{"hours" => "8"}] = body["estimates"]
    assert body["url"] =~ "/estimations/#{est.id}/estimator"
  end

  test "adds a skeleton task with no efforts (priority defaults to must)", %{owner: owner, org: org, epic: epic} do
    assert {:reply, resp, _} = AddTask.execute(%{epic_id: epic.id, name: "Later"}, frame(owner, org))
    refute resp.isError
    body = json_content(resp)
    assert body["priority"] == "must"
    assert body["estimates"] == []
  end

  test "unknown effort abbreviation → error listing valid ones, no task created", %{owner: owner, org: org, epic: epic} do
    assert {:reply, %Response{isError: true} = resp, _} =
             AddTask.execute(%{epic_id: epic.id, name: "Bad", efforts: %{"ZZ" => 3.0}}, frame(owner, org))

    err = json_error(resp)
    assert err =~ "ZZ"
    assert err =~ "BE"
    assert Repo.aggregate(from(t in Estimate.EstimationEngine.Task, where: t.name == "Bad"), :count) == 0
  end

  test "non-collaborator denied", %{org: org, epic: epic} do
    member = user_fixture()
    _ = membership_fixture(member, org, "member")

    assert {:reply, %Response{isError: true} = resp, _} =
             AddTask.execute(%{epic_id: epic.id, name: "X"}, frame(member, org, "member"))

    assert json_error(resp) =~ "not authorized"
  end

  test "updates a task priority", %{owner: owner, org: org, epic: epic} do
    {:reply, add, _} = AddTask.execute(%{epic_id: epic.id, name: "T"}, frame(owner, org))
    task_id = json_content(add)["id"]

    assert {:reply, resp, _} = UpdateTask.execute(%{id: task_id, priority: "could"}, frame(owner, org))
    refute resp.isError
    assert json_content(resp)["priority"] == "could"
  end
end
```

(Add `import Ecto.Query` at the top of the test.)

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/estimate_web/mcp/tools/write_tasks_test.exs`
Expected: FAIL — modules undefined.

- [ ] **Step 3: Implement `add_task`**

Create `lib/estimate_web/mcp/tools/add_task.ex`:

```elixir
defmodule EstimateWeb.MCP.Tools.AddTask do
  @moduledoc """
  Add a task to an epic (org admin or project owner/editor). Optionally pass
  `efforts` — an object mapping role abbreviations to hours (e.g.
  {"BE": 8, "FE": 4}) — to seed per-role hours in the same call. Omit it to
  create a skeleton and fill hours later in the app or via set_task_effort.
  """

  use Anubis.Server.Component, type: :tool

  alias Estimate.EstimationEngine
  alias EstimateWeb.MCP.{Authz, Serializers, Write}

  schema do
    field :epic_id, :string, required: true
    field :name, :string, required: true
    field :description, :string
    field :priority, :enum, values: ["must", "should", "could", "wont"], default: "must"
    field :position, :integer, min: 0
    field :efforts, {:map, :string, :float}, description: ~s(Role abbreviation → hours, e.g. {"BE": 8, "FE": 4})
  end

  @impl true
  def execute(params, frame) do
    gate = fn claims ->
      with {:ok, pid} <- Authz.project_id_for(:epic, params.epic_id, claims.org_id) do
        Authz.require_can_edit_project(pid, claims)
      end
    end

    Write.execute(frame, gate, fn %{org_id: org_id} ->
      epic = EstimationEngine.get_epic!(params.epic_id, org_id)
      estimation = EstimationEngine.get_estimation!(epic.estimation_id, org_id)
      roles_by_abbrev = Map.new(estimation.roles, &{&1.abbreviation, &1.id})

      with {:ok, effort_by_role_id} <- resolve_efforts(params[:efforts] || %{}, roles_by_abbrev),
           {:ok, task} <-
             EstimationEngine.create_task_with_estimates(params.epic_id, task_attrs(params), effort_by_role_id) do
        {:ok,
         Serializers.task(task)
         |> Map.put(:url, Serializers.estimation_url(org_id, estimation.project_id, estimation.id))}
      end
    end)
  end

  defp task_attrs(params) do
    %{
      "name" => params.name,
      "description" => params[:description],
      "priority" => params[:priority] || "must",
      "position" => params[:position] || 0
    }
  end

  defp resolve_efforts(efforts, roles_by_abbrev) do
    Enum.reduce_while(efforts, {:ok, %{}}, fn {abbrev, hours}, {:ok, acc} ->
      case Map.fetch(roles_by_abbrev, abbrev) do
        {:ok, role_id} -> {:cont, {:ok, Map.put(acc, role_id, hours)}}
        :error -> {:halt, {:error, unknown_abbrev_msg(abbrev, roles_by_abbrev)}}
      end
    end)
  end

  defp unknown_abbrev_msg(abbrev, roles_by_abbrev) do
    valid = roles_by_abbrev |> Map.keys() |> Enum.sort() |> Enum.join(", ")
    "unknown role abbreviation \"#{abbrev}\". Valid abbreviations: #{valid}"
  end
end
```

- [ ] **Step 4: Implement `update_task`**

Create `lib/estimate_web/mcp/tools/update_task.ex`:

```elixir
defmodule EstimateWeb.MCP.Tools.UpdateTask do
  @moduledoc "Update a task's name/description/priority (org admin or project owner/editor). Use set_task_effort to change hours."

  use Anubis.Server.Component, type: :tool

  alias Estimate.EstimationEngine
  alias EstimateWeb.MCP.{Authz, Serializers, Write}

  schema do
    field :id, :string, required: true, description: "Task UUID"
    field :name, :string
    field :description, :string
    field :priority, :enum, values: ["must", "should", "could", "wont"]
  end

  @impl true
  def execute(params, frame) do
    gate = fn claims ->
      with {:ok, pid} <- Authz.project_id_for(:task, params.id, claims.org_id) do
        Authz.require_can_edit_project(pid, claims)
      end
    end

    Write.execute(frame, gate, fn %{org_id: org_id} ->
      task = EstimationEngine.get_task!(params.id, org_id)
      attrs = params |> Map.take([:name, :description, :priority]) |> Map.new(fn {k, v} -> {to_string(k), v} end)

      with {:ok, updated} <- EstimationEngine.update_task(task, attrs) do
        updated = Estimate.Repo.preload(updated, :estimates)
        epic = EstimationEngine.get_epic!(updated.epic_id, org_id)
        pid = EstimationEngine.get_estimation_project_id(epic.estimation_id, org_id)

        {:ok,
         Serializers.task(updated)
         |> Map.put(:url, Serializers.estimation_url(org_id, pid, epic.estimation_id))}
      end
    end)
  end
end
```

- [ ] **Step 5: Register both tools**

`lib/estimate_web/mcp_server.ex`:

```elixir
  component(EstimateWeb.MCP.Tools.AddTask)
  component(EstimateWeb.MCP.Tools.UpdateTask)
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `mix test test/estimate_web/mcp/tools/write_tasks_test.exs`
Expected: PASS (5 tests).

- [ ] **Step 7: Commit**

```bash
git add lib/estimate_web/mcp/tools/add_task.ex lib/estimate_web/mcp/tools/update_task.ex lib/estimate_web/mcp_server.ex test/estimate_web/mcp/tools/write_tasks_test.exs
git commit -m "feat: add/update_task MCP tools (inline efforts by abbrev)"
```

---

### Task 16: `set_task_effort` tool

**Files:**
- Create: `lib/estimate_web/mcp/tools/set_task_effort.ex`
- Modify: `lib/estimate_web/mcp_server.ex`
- Test: `test/estimate_web/mcp/tools/set_task_effort_test.exs`

**Interfaces:**
- Consumes: `Authz.project_id_for(:task, …)` + `require_can_edit_project/2`, `EstimationEngine.get_task!/2`, `get_epic!/2`, `get_estimation!/2`, `upsert_task_estimate/4`, `get_estimation_project_id/2`.
- Produces: tool `set_task_effort`. `role` accepts a role abbreviation OR an estimation-role UUID (both resolved against the task's estimation).

- [ ] **Step 1: Write the failing test**

Create `test/estimate_web/mcp/tools/set_task_effort_test.exs`:

```elixir
defmodule EstimateWeb.MCP.Tools.SetTaskEffortTest do
  use Estimate.DataCase, async: false

  import Estimate.{AccountsFixtures, PortfolioFixtures, EstimationEngineFixtures, MCPFixtures}
  alias Anubis.Server.Response
  alias Estimate.EstimationEngine
  alias EstimateWeb.MCP.Tools.SetTaskEffort

  setup do
    %{user: owner, organization: org} = user_with_organization_fixture()
    enable_mcp_write(org)
    est = estimation_fixture(project_fixture(nil, owner))
    epic = epic_fixture(est)
    task = task_fixture(epic)
    {:ok, be} = EstimationEngine.create_role(%{"estimation_id" => est.id, "name" => "BE", "abbreviation" => "BE"})
    %{owner: owner, org: org, task: task, be: be}
  end

  defp frame(user, org, role \\ "owner"), do: mcp_frame(user, org, role)

  test "sets effort by abbreviation, then overwrites (upsert)", %{owner: owner, org: org, task: task} do
    assert {:reply, resp, _} =
             SetTaskEffort.execute(%{task_id: task.id, role: "BE", hours: 5.0}, frame(owner, org))

    refute resp.isError
    assert json_content(resp)["hours"] == "5"

    assert {:reply, resp2, _} =
             SetTaskEffort.execute(%{task_id: task.id, role: "BE", hours: 9.0}, frame(owner, org))

    assert json_content(resp2)["hours"] == "9"
  end

  test "sets effort by role id", %{owner: owner, org: org, task: task, be: be} do
    assert {:reply, resp, _} =
             SetTaskEffort.execute(%{task_id: task.id, role: be.id, hours: 3.0}, frame(owner, org))

    refute resp.isError
    assert json_content(resp)["role_id"] == be.id
  end

  test "unknown role → error", %{owner: owner, org: org, task: task} do
    assert {:reply, %Response{isError: true} = resp, _} =
             SetTaskEffort.execute(%{task_id: task.id, role: "ZZ", hours: 1.0}, frame(owner, org))

    assert json_error(resp) =~ "ZZ"
  end

  test "non-collaborator denied", %{org: org, task: task} do
    member = user_fixture()
    _ = membership_fixture(member, org, "member")

    assert {:reply, %Response{isError: true} = resp, _} =
             SetTaskEffort.execute(%{task_id: task.id, role: "BE", hours: 1.0}, frame(member, org, "member"))

    assert json_error(resp) =~ "not authorized"
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/estimate_web/mcp/tools/set_task_effort_test.exs`
Expected: FAIL — `SetTaskEffort` undefined.

- [ ] **Step 3: Implement**

Create `lib/estimate_web/mcp/tools/set_task_effort.ex`:

```elixir
defmodule EstimateWeb.MCP.Tools.SetTaskEffort do
  @moduledoc "Set (or overwrite) the hours a role spends on a task (org admin or project owner/editor). `role` is a role abbreviation or an estimation-role UUID."

  use Anubis.Server.Component, type: :tool

  alias Estimate.EstimationEngine
  alias EstimateWeb.MCP.{Authz, Serializers, Write}

  schema do
    field :task_id, :string, required: true
    field :role, :string, required: true, description: "Role abbreviation (e.g. BE) or estimation-role UUID"
    field :hours, :float, required: true, description: "Hours (>= 0)"
  end

  @impl true
  def execute(params, frame) do
    gate = fn claims ->
      with {:ok, pid} <- Authz.project_id_for(:task, params.task_id, claims.org_id) do
        Authz.require_can_edit_project(pid, claims)
      end
    end

    Write.execute(frame, gate, fn %{org_id: org_id} ->
      task = EstimationEngine.get_task!(params.task_id, org_id)
      epic = EstimationEngine.get_epic!(task.epic_id, org_id)
      estimation = EstimationEngine.get_estimation!(epic.estimation_id, org_id)

      with {:ok, role} <- find_role(estimation.roles, params.role),
           {:ok, te} <-
             EstimationEngine.upsert_task_estimate(task.id, role.id, %{"hours" => to_string(params.hours)}, estimation.id) do
        {:ok,
         %{
           task_id: task.id,
           role_id: role.id,
           abbreviation: role.abbreviation,
           hours: Serializers.decimal(te.hours),
           url: Serializers.estimation_url(org_id, estimation.project_id, estimation.id)
         }}
      end
    end)
  end

  defp find_role(roles, ref) do
    case Enum.find(roles, &(&1.abbreviation == ref or &1.id == ref)) do
      nil ->
        valid = roles |> Enum.map(& &1.abbreviation) |> Enum.sort() |> Enum.join(", ")
        {:error, ~s(unknown role "#{ref}". Valid abbreviations: #{valid})}

      role ->
        {:ok, role}
    end
  end
end
```

Note: `upsert_task_estimate/4` returns `{:ok, %TaskEstimate{}}`; confirm its return shape while implementing and unwrap accordingly (it upserts on the `[task_id, estimation_role_id]` unique constraint).

- [ ] **Step 4: Register the tool**

`lib/estimate_web/mcp_server.ex`:

```elixir
  component(EstimateWeb.MCP.Tools.SetTaskEffort)
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `mix test test/estimate_web/mcp/tools/set_task_effort_test.exs`
Expected: PASS (4 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/estimate_web/mcp/tools/set_task_effort.ex lib/estimate_web/mcp_server.ex test/estimate_web/mcp/tools/set_task_effort_test.exs
git commit -m "feat: set_task_effort MCP tool"
```

---

### Task 17: Settings UI — write-access toggle

**Files:**
- Modify: `lib/estimate_web/live/settings_live/mcp.ex`
- Test: `test/estimate_web/live/settings_live/mcp_test.exs`

**Interfaces:**
- Consumes: `Organizations.update_mcp_write_settings/2`, `admin?/1`, `require_admin/2`.
- Produces: `phx-click="toggle_mcp_write"` handler; write-access sub-block inside `#mcp-server-card`.

- [ ] **Step 1: Write the failing test**

Append to `test/estimate_web/live/settings_live/mcp_test.exs` (mirror the existing `toggle_mcp` test's login + navigation; use the file's existing setup helpers):

```elixir
  test "admin toggles write access on and off", %{conn: conn, org: org, admin: admin} do
    {:ok, _} = Estimate.Organizations.update_mcp_settings(org, %{mcp_enabled: true})

    {:ok, lv, _html} =
      conn |> log_in_user(admin) |> live(~p"/org/#{org.id}/settings/mcp")

    assert lv |> element("button[phx-click=toggle_mcp_write]") |> render_click() =~ "writes enabled"
    assert Estimate.Organizations.mcp_write_enabled?(org.id)

    assert lv |> element("button[phx-click=toggle_mcp_write]") |> render_click() =~ "writes disabled"
    refute Estimate.Organizations.mcp_write_enabled?(org.id)
  end
```

(Adapt `%{conn, org, admin}` and `log_in_user` to the file's existing setup — reuse whatever the current `toggle_mcp` test uses.)

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/estimate_web/live/settings_live/mcp_test.exs`
Expected: FAIL — no `toggle_mcp_write` button / handler.

- [ ] **Step 3: Add the markup**

In `lib/estimate_web/live/settings_live/mcp.ex`, inside `#mcp-server-card`, immediately before its closing `</div>` (after the enable/disable row, ~line 47), add:

```heex
        <div :if={@current_organization.mcp_enabled} class="mt-4 pt-4 border-t border-base-300 flex items-center justify-between">
          <div>
            <h3 class="text-sm font-medium text-base-content">
              {if @current_organization.mcp_write_enabled, do: "Write access is enabled", else: "Write access is disabled"}
            </h3>
            <p class="mt-1 text-sm text-base-content/60">
              Lets connected clients create and modify customers, projects, and estimations. Off by default.
            </p>
          </div>
          <button
            phx-click="toggle_mcp_write"
            class={[
              "px-4 py-1.5 text-sm rounded-md font-medium transition-colors",
              if(@current_organization.mcp_write_enabled,
                do: "bg-error/10 text-error hover:bg-error/20",
                else: "bg-neutral text-neutral-content hover:bg-neutral/90"
              )
            ]}
          >
            {if @current_organization.mcp_write_enabled, do: "Disable writes", else: "Enable writes"}
          </button>
        </div>
```

- [ ] **Step 4: Add the handler**

Next to `handle_event("toggle_mcp", …)` add:

```elixir
  def handle_event("toggle_mcp_write", _params, socket) do
    require_admin(socket, fn ->
      org = socket.assigns.current_organization

      case Organizations.update_mcp_write_settings(org, %{mcp_write_enabled: !org.mcp_write_enabled}) do
        {:ok, updated} ->
          {:noreply,
           socket
           |> assign(:current_organization, updated)
           |> put_flash(:info, if(updated.mcp_write_enabled, do: "MCP writes enabled", else: "MCP writes disabled"))}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Could not update write setting")}
      end
    end)
  end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `mix test test/estimate_web/live/settings_live/mcp_test.exs`
Expected: PASS.

- [ ] **Step 6: Verify in the browser**

Start the dev server (preview_start `{name: "..."}` from `.claude/launch.json`), sign in as an admin, open `/org/<id>/settings/mcp`, enable the server, confirm the "Write access" toggle appears and flips with a flash. Screenshot for proof.

- [ ] **Step 7: Commit**

```bash
git add lib/estimate_web/live/settings_live/mcp.ex test/estimate_web/live/settings_live/mcp_test.exs
git commit -m "feat: MCP settings write-access toggle"
```

---

### Task 18: Catalog + end-to-end integration

**Files:**
- Modify: `test/estimate_web/mcp_server_integration_test.exs`
- Test: `test/estimate_web/mcp/tools/write_catalog_test.exs`

**Interfaces:**
- Consumes: `MCPTestHelpers.post_mcp/2`, `init_body/0`, `mcp_api_key_fixture/2`, `enable_mcp_write/1`.

- [ ] **Step 1: Update the tools/list count assertion**

In `test/estimate_web/mcp_server_integration_test.exs`, the test "tools/list exposes the 11-tool catalog" asserts a count. Change it to 24 (11 read + 13 write) and rename the test. Read the assertion and update the expected number to match the actual registered count.

- [ ] **Step 2: Write the failing catalog test**

Create `test/estimate_web/mcp/tools/write_catalog_test.exs`:

```elixir
defmodule EstimateWeb.MCP.Tools.WriteCatalogTest do
  use Estimate.DataCase, async: false

  import Estimate.{AccountsFixtures, MCPFixtures, MCPTestHelpers}

  @write_tools ~w(create_customer update_customer create_project update_project
                  create_estimation update_estimation add_estimation_role update_estimation_role
                  add_epic update_epic add_task update_task set_task_effort)

  setup do
    %{user: user, organization: org} = user_with_organization_fixture()
    {key, _k, org} = mcp_api_key_fixture(user, org)
    _ = enable_mcp_write(org)
    %{key: key, org: org, user: user}
  end

  test "tools/list exposes all 13 write tools", %{key: key} do
    conn = post_mcp(init_body(), [{"authorization", "Bearer " <> key}])
    session_id = Plug.Conn.get_resp_header(conn, "mcp-session-id") |> List.first()

    post_mcp(
      %{"jsonrpc" => "2.0", "method" => "notifications/initialized"},
      [{"authorization", "Bearer " <> key}, {"mcp-session-id", session_id}]
    )

    conn =
      post_mcp(
        %{"jsonrpc" => "2.0", "id" => 2, "method" => "tools/list", "params" => %{}},
        [{"authorization", "Bearer " <> key}, {"mcp-session-id", session_id}]
      )

    names = tool_names(conn)
    for t <- @write_tools, do: assert(t in names, "missing tool #{t}")
  end

  # Extract tool names from the SSE/JSON tools/list response body.
  defp tool_names(conn) do
    conn.resp_body
    |> String.split("\n", trim: true)
    |> Enum.flat_map(fn line ->
      line = String.replace_prefix(line, "data: ", "")

      case Jason.decode(line) do
        {:ok, %{"result" => %{"tools" => tools}}} -> Enum.map(tools, & &1["name"])
        _ -> []
      end
    end)
  end
end
```

Note while implementing: confirm how `post_mcp` returns the session id and body shape by reading the existing integration test's `initialize_session/1`; reuse its exact extraction if this differs.

- [ ] **Step 3: Run it to verify it fails, then passes**

Run: `mix test test/estimate_web/mcp/tools/write_catalog_test.exs`
Expected: initially may FAIL on extraction shape; align `tool_names/1` + session extraction with the existing integration test until PASS.

- [ ] **Step 4: Add an end-to-end write call**

Append to `test/estimate_web/mcp_server_integration_test.exs` a test that, with `enable_mcp_write(org)`, initializes a session and issues `tools/call` `create_customer` (reuse the file's `initialize_session/1` + `call_tool/3` helpers), asserting a non-error result and that the customer exists via `Estimate.CRM.list_customers(org.id)`.

```elixir
  test "tools/call create_customer writes through the plug", %{user: user, org: org} do
    org = enable_mcp_write(org)
    {key, _k, org} = mcp_api_key_fixture(user, org)
    session_id = initialize_session(key)

    conn =
      call_tool(session_id, key, "create_customer", %{"key" => "ACME", "name" => "Acme Corp"})

    refute conn.resp_body =~ ~s("isError":true)
    assert Enum.any?(Estimate.CRM.list_customers(org.id), &(&1.key == "ACME"))
  end
```

(Adapt to the file's existing `initialize_session/1` and tool-call helper signatures.)

- [ ] **Step 5: Run the MCP suite**

Run: `mix test test/estimate_web/mcp_server_integration_test.exs test/estimate_web/mcp/`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add test/estimate_web/mcp_server_integration_test.exs test/estimate_web/mcp/tools/write_catalog_test.exs
git commit -m "test: MCP write-tool catalog + e2e create_customer through the plug"
```

---

### Task 19: Full verification + docs

**Files:**
- Modify: `test` (only if failures surface)
- Modify: `docs/superpowers/specs/2026-07-20-mcp-write-tools-design.md` (status → shipped notes, optional)

- [ ] **Step 1: Run the whole suite**

Run: `mix test`
Expected: all green. Fix any regressions (watch for the async:false RLS interaction and the `tools/list` count).

- [ ] **Step 2: Run formatter + any credo/dialyzer the repo uses**

Run: `mix format && mix format --check-formatted`
Expected: clean. If the repo runs `mix credo`/`mix dialyzer` in CI, run them and resolve findings.

- [ ] **Step 3: Manual smoke via a real MCP client (optional but recommended)**

With the dev server running, org `mcp_enabled` + `mcp_write_enabled` on, and a personal key, use `claude mcp` or curl to `tools/call create_customer` → `create_project` → `create_estimation` → `add_epic` → `add_task` (with efforts), then open the returned estimation `url` in the app and confirm the tree + hours rendered.

- [ ] **Step 4: Update the design doc status**

Add a short "Shipped" note (branch, commit, test count) to the top of `docs/superpowers/specs/2026-07-20-mcp-write-tools-design.md`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "docs: mark MCP write tools shipped"
```

---

## Self-Review

**Spec coverage:**
- 3 gates → Tasks 1 (write toggle), 4 (Authz), 6+ (per-tool gate wiring). ✓
- 13 tools → Tasks 6–16. ✓
- Currency by code → Task 2, used by create/update customer/project/estimation. ✓
- Deep links → Serializers `*_url` (Task 5) + every tool response. ✓
- `create_estimation` role-mimic (inline or seed templates) → Task 10. ✓
- `add_task` optional inline efforts by abbrev + atomicity → Tasks 14–15. ✓
- `set_task_effort` upsert by abbrev/id → Task 16. ✓
- Settings write toggle (admin, shown when server on) → Task 17. ✓
- `organization_id` never caller-set → relies on existing triggers; tools never pass it (verified in tool attrs). ✓
- RLS-is-org-only → project-collaborator gating in code (Authz, Task 4; exercised in Tasks 9/10/12/13/15/16). ✓
- Catalog/e2e → Task 18. ✓
- Unresolved Q1 (exact abbrev match + list valid) → Task 15/16 implement it. Q2 (update_project owner/editor) → Task 9. Q3 (server-off leaves write flag) → no coupling added; auth gate makes writes moot. ✓

**Placeholder scan:** No TBD/TODO. Two "confirm-while-implementing" notes (Task 16 `upsert_task_estimate` return shape; Task 18 session extraction) point at reading an existing, named source — not gaps in the code shown.

**Type consistency:** `Write.execute/3` `(frame, gate_fun, run_fun)` and `run_fun` returning `{:ok, map} | {:error, …}` used uniformly by all tools. `Authz.project_id_for/3`, `ensure_project/2`, `require_can_edit_project/2`, `require_org_admin/1`, `require_write_enabled/1` signatures match every call site. `resolve_currency/2`, `changeset_errors/1`, `*_url` helpers consistent. Tool names = module snake_case, matched in Task 18's `@write_tools`.
