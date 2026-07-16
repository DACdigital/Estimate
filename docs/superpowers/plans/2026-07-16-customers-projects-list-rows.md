# Customers + Projects List Rows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign customers + projects index rows per approved spec — always-present meta line, project-count pill, key columns merged into meta lines, broad entity avatar palette.

**Architecture:** Web-layer only: two LiveView index templates, one pure format helper, one CRM query gaining a LEFT JOIN count into a virtual field, one component palette change. No routes, no schema DDL, no new modules beyond one helper.

**Tech Stack:** Phoenix 1.8.3 LiveView, Ecto, Tailwind/daisyUI tokens, ExUnit (async, existing fixtures).

**Spec:** `docs/superpowers/specs/2026-07-16-customers-projects-list-rows-design.md`

## Global Constraints

- **No DB migrations, no DDL** — `project_count` is `virtual: true` only (data-model constraint).
- No new dependencies; existing Tailwind/daisyUI tokens only.
- Keep `Repo.ensure_org_context`, org filters, ordering (`asc: c.name`), `default_currency` preload, watchtower filters exactly as they are.
- All new tests `async: true`, fixtures from `test/support/fixtures/`, LV structure asserts via `has_element?/2`.
- Row shells (padding, borders, hover, whole-row `navigate` link, admin-only pencil) unchanged.
- Every commit: run `mix format <changed files>` first; message style: extremely concise; end body with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

---

### Task 1: `EstimateWeb.FormatHelpers.domain/1`

**Files:**
- Create: `lib/estimate_web/live/helpers/format_helpers.ex`
- Test: `test/estimate_web/live/helpers/format_helpers_test.exs`

**Interfaces:**
- Consumes: nothing
- Produces: `EstimateWeb.FormatHelpers.domain(url :: String.t() | nil) :: String.t() | nil` — bare host without scheme/`www.`/path; `nil` for nil/empty/host-less input. Task 3 imports it.

- [ ] **Step 1: Write the failing test**

```elixir
defmodule EstimateWeb.FormatHelpersTest do
  use ExUnit.Case, async: true

  import EstimateWeb.FormatHelpers

  doctest EstimateWeb.FormatHelpers

  describe "domain/1" do
    test "strips scheme" do
      assert domain("https://acme.com") == "acme.com"
      assert domain("http://acme.com") == "acme.com"
    end

    test "strips leading www." do
      assert domain("https://www.acme.com") == "acme.com"
    end

    test "keeps non-www subdomains" do
      assert domain("https://app.acme.co.uk") == "app.acme.co.uk"
    end

    test "drops path, query, trailing slash" do
      assert domain("https://acme.com/about?ref=1") == "acme.com"
      assert domain("https://acme.com/") == "acme.com"
    end

    test "nil, empty, and host-less input → nil" do
      assert domain(nil) == nil
      assert domain("") == nil
      assert domain("not a url") == nil
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/estimate_web/live/helpers/format_helpers_test.exs`
Expected: FAIL — `module EstimateWeb.FormatHelpers is not loaded`

- [ ] **Step 3: Write implementation**

```elixir
defmodule EstimateWeb.FormatHelpers do
  @moduledoc """
  Pure formatting helpers for HEEx templates.
  """

  @doc """
  Bare display domain of a URL: host without scheme, leading "www.", or path.

      iex> EstimateWeb.FormatHelpers.domain("https://www.acme.com/about")
      "acme.com"

      iex> EstimateWeb.FormatHelpers.domain(nil)
      nil
  """
  def domain(nil), do: nil

  def domain(url) when is_binary(url) do
    case URI.parse(url).host do
      nil -> nil
      "" -> nil
      host -> String.replace_prefix(host, "www.", "")
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/estimate_web/live/helpers/format_helpers_test.exs`
Expected: PASS (7 tests incl. doctests)

- [ ] **Step 5: Commit**

```bash
mix format lib/estimate_web/live/helpers/format_helpers.ex test/estimate_web/live/helpers/format_helpers_test.exs
git add lib/estimate_web/live/helpers/format_helpers.ex test/estimate_web/live/helpers/format_helpers_test.exs
git commit -m "feat: FormatHelpers.domain/1 for display domains

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: `project_count` on `CRM.list_customers`

**Files:**
- Modify: `lib/estimate/crm/customer.ex` (schema block, after `field :description`)
- Modify: `lib/estimate/crm.ex:11-32` (`list_customers/1,2`)
- Test: `test/estimate/crm_test.exs` (new file)

**Interfaces:**
- Consumes: `Estimate.CRM.Customer` `has_many :projects` (exists)
- Produces: every customer returned by `CRM.list_customers/1,2` has `project_count :: non_neg_integer()` set. Task 3 renders it.

- [ ] **Step 1: Write the failing test**

```elixir
defmodule Estimate.CRMTest do
  use Estimate.DataCase, async: true

  alias Estimate.CRM

  import Estimate.AccountsFixtures
  import Estimate.CRMFixtures
  import Estimate.PortfolioFixtures

  describe "list_customers/1,2 project_count" do
    setup do
      %{user: user, organization: org} = user_with_organization_fixture()
      %{org: org, user: user}
    end

    test "counts projects per customer, 0 when none", %{org: org, user: user} do
      alpha = customer_fixture(org, %{"name" => "Alpha"})
      beta = customer_fixture(org, %{"name" => "Beta"})
      project_fixture(alpha, user)
      project_fixture(alpha, user)

      assert [%{id: alpha_id, project_count: 2}, %{id: beta_id, project_count: 0}] =
               CRM.list_customers(org.id)

      assert alpha_id == alpha.id
      assert beta_id == beta.id
    end

    test "keeps name ordering and default_currency preload", %{org: org} do
      customer_fixture(org, %{"name" => "Zed"})
      customer_fixture(org, %{"name" => "Ann"})

      assert [%{name: "Ann"} = ann, %{name: "Zed"}] = CRM.list_customers(org.id)
      # preload intact (nil default currency loads as nil, not %Ecto.Association.NotLoaded{})
      refute match?(%Ecto.Association.NotLoaded{}, ann.default_currency)
    end

    test "watchtower filter still applies and keeps counts", %{org: org, user: user} do
      no_desc = customer_fixture(org, %{"name" => "NoDesc"})
      customer_fixture(org, %{"name" => "HasDesc", "description" => "desc"})
      project_fixture(no_desc, user)

      assert [%{name: "NoDesc", project_count: 1}] =
               CRM.list_customers(org.id, watchtower: :missing_description)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/estimate/crm_test.exs`
Expected: FAIL — `project_count: 2` doesn't match (field missing / nil)

- [ ] **Step 3: Add virtual field**

In `lib/estimate/crm/customer.ex`, inside `schema "customers" do`, after `field :description, :string`:

```elixir
    field :project_count, :integer, virtual: true
```

- [ ] **Step 4: Rewrite `list_customers`**

Replace both `list_customers` clauses in `lib/estimate/crm.ex` (lines 11-32) with:

```elixir
  def list_customers(org_id), do: list_customers(org_id, [])

  def list_customers(org_id, opts) when is_list(opts) do
    Repo.ensure_org_context(fn ->
      from(c in Customer,
        where: c.organization_id == ^org_id,
        left_join: p in assoc(c, :projects),
        group_by: c.id,
        order_by: [asc: c.name],
        select_merge: %{project_count: count(p.id)},
        preload: [:default_currency]
      )
      |> maybe_filter_watchtower(Keyword.get(opts, :watchtower))
      |> Repo.all()
    end)
  end
```

(Non-join `preload:` runs as a separate query, so `group_by` is unaffected; `order_by c.name` is legal under `group_by: c.id` because `id` is the PK.)

- [ ] **Step 5: Run tests**

Run: `mix test test/estimate/crm_test.exs`
Expected: PASS (3 tests)

- [ ] **Step 6: Commit**

```bash
mix format lib/estimate/crm.ex lib/estimate/crm/customer.ex test/estimate/crm_test.exs
git add lib/estimate/crm.ex lib/estimate/crm/customer.ex test/estimate/crm_test.exs
git commit -m "feat: project_count virtual field on CRM.list_customers

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Customers index row template

**Files:**
- Modify: `lib/estimate_web/live/customer_live/index.ex` (render rows ~54-88; module head; private fns at bottom)
- Test: `test/estimate_web/live/customer_live/index_test.exs` (new file)

**Interfaces:**
- Consumes: `EstimateWeb.FormatHelpers.domain/1` (Task 1), `customer.project_count` (Task 2)
- Produces: nothing downstream

- [ ] **Step 1: Write the failing test**

```elixir
defmodule EstimateWeb.CustomerLive.IndexTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Estimate.AccountsFixtures
  import Estimate.CRMFixtures
  import Estimate.PortfolioFixtures

  defp customers_path(org), do: ~p"/org/#{org.id}/customers"

  defp setup_org(_) do
    %{user: owner, organization: org} = user_with_organization_fixture()
    %{org: org, owner: owner}
  end

  describe "row content" do
    setup :setup_org

    test "no description → meta line with key, country, domain", %{conn: conn, org: org, owner: owner} do
      customer_fixture(org, %{
        "key" => "AVIO",
        "name" => "Avio Areo",
        "country" => "IT",
        "website_url" => "https://www.avioareo.it"
      })

      {:ok, lv, html} = live(log_in_user(conn, owner), customers_path(org))

      assert has_element?(lv, "span.font-mono", "AVIO")
      assert has_element?(lv, "span.font-mono", "IT")
      assert html =~ "avioareo.it"
      refute html =~ "www.avioareo.it"
    end

    test "meta line omits missing country/website", %{conn: conn, org: org, owner: owner} do
      customer = customer_fixture(org, %{"key" => "BRG", "name" => "Brigade"})

      {:ok, lv, _html} = live(log_in_user(conn, owner), customers_path(org))

      assert has_element?(lv, "span.font-mono", "BRG")
      # only the key + count pill for this row; no stray separators
      refute render(lv) =~ "BRG ·"
      assert customer.country == nil
    end

    test "description wins over meta line", %{conn: conn, org: org, owner: owner} do
      customer =
        customer_fixture(org, %{"name" => "Olus", "description" => "UK legal-tech consultancy"})

      {:ok, lv, html} = live(log_in_user(conn, owner), customers_path(org))

      assert has_element?(lv, "p", "UK legal-tech consultancy")
      refute html =~ customer.key
    end

    test "old standalone key column is gone", %{conn: conn, org: org, owner: owner} do
      customer_fixture(org)
      {:ok, lv, _html} = live(log_in_user(conn, owner), customers_path(org))
      refute has_element?(lv, "span.w-12")
    end
  end

  describe "project-count pill" do
    setup :setup_org

    test "0, 1, N projects render pluralized pill", %{conn: conn, org: org, owner: owner} do
      zero = customer_fixture(org, %{"name" => "Alpha"})
      one = customer_fixture(org, %{"name" => "Beta"})
      many = customer_fixture(org, %{"name" => "Gamma"})
      project_fixture(one, owner)
      project_fixture(many, owner)
      project_fixture(many, owner)

      {:ok, lv, _html} = live(log_in_user(conn, owner), customers_path(org))

      assert has_element?(lv, "span.rounded-full", "0 projects")
      assert has_element?(lv, "span.rounded-full", "1 project")
      assert has_element?(lv, "span.rounded-full", "2 projects")
      assert zero.id && one.id && many.id
    end

    test "zero pill is extra muted", %{conn: conn, org: org, owner: owner} do
      customer_fixture(org)
      {:ok, lv, _html} = live(log_in_user(conn, owner), customers_path(org))
      assert has_element?(lv, ~s{span[class*="text-base-content/40"]}, "0 projects")
    end
  end

  describe "permissions" do
    setup :setup_org

    test "member sees rows but no pencil", %{conn: conn, org: org} do
      customer = customer_fixture(org)
      member = user_fixture()
      membership_fixture(member, org, "member")

      {:ok, lv, html} = live(log_in_user(conn, member), customers_path(org))

      assert html =~ customer.name
      refute has_element?(lv, ~s{a[href="/org/#{org.id}/customers/#{customer.id}/edit"]})
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/estimate_web/live/customer_live/index_test.exs`
Expected: FAIL — meta-line/pill assertions (`has_element?` on `"0 projects"` etc.); the `span.w-12` refute also fails while the old column exists

- [ ] **Step 3: Edit module head**

In `lib/estimate_web/live/customer_live/index.ex` after the `alias` lines add:

```elixir
  import EstimateWeb.FormatHelpers, only: [domain: 1]
```

- [ ] **Step 4: Replace the row markup**

Replace the whole `:for={customer <- @customers}` div (currently the block with the `w-12` key span, name/description div, and right-side country/currency/pencil) with:

```heex
          <div
            :for={customer <- @customers}
            class="px-6 py-5 flex items-center gap-4 border-b border-base-content/10 last:border-b-0 hover:bg-base-200 transition-colors"
          >
            <.link
              navigate={~p"/org/#{@org_id}/customers/#{customer.id}"}
              class="flex items-center gap-4 flex-1 min-w-0"
            >
              <.avatar name={customer.name} seed={customer.id} type={:customer} size={:lg} />
              <div class="min-w-0 flex-1">
                <h3 class="text-sm font-medium text-base-content truncate">{customer.name}</h3>
                <p :if={customer.description} class="text-sm text-base-content/60 truncate">
                  {customer.description}
                </p>
                <p :if={!customer.description} class="text-xs text-base-content/50 truncate">
                  <span class="font-mono text-base-content/40">{customer.key}</span>
                  <span :if={customer.country} class="font-mono text-base-content/40">
                    · {customer.country}
                  </span>
                  <span :if={domain(customer.website_url)}>· {domain(customer.website_url)}</span>
                </p>
              </div>
            </.link>
            <div class="flex items-center gap-3 flex-shrink-0">
              <span :if={customer.default_currency} class="text-xs text-base-content/40 font-mono">
                {customer.default_currency.code}
              </span>
              <span class={[
                "text-xs px-2 py-0.5 rounded-full bg-base-200",
                if(customer.project_count == 0,
                  do: "text-base-content/40",
                  else: "text-base-content/60"
                )
              ]}>
                {project_count_label(customer.project_count)}
              </span>
              <.link
                :if={@is_admin}
                patch={~p"/org/#{@org_id}/customers/#{customer.id}/edit"}
                class="text-base-content/40 hover:text-base-content/70 transition-colors"
              >
                <.icon name="hero-pencil" class="w-5 h-5" />
              </.link>
            </div>
          </div>
```

(Deliberately a raw span, not `<.badge>` — the pill must match the projects status pill's `text-xs px-2 py-0.5` size; `<.badge>` is `text-[10px] px-1.5`.)

- [ ] **Step 5: Add pluralization helper**

At the bottom of the module (after `save_customer/3`):

```elixir
  defp project_count_label(1), do: "1 project"
  defp project_count_label(n), do: "#{n} projects"
```

- [ ] **Step 6: Run tests**

Run: `mix test test/estimate_web/live/customer_live/index_test.exs`
Expected: PASS (7 tests)

- [ ] **Step 7: Commit**

```bash
mix format lib/estimate_web/live/customer_live/index.ex test/estimate_web/live/customer_live/index_test.exs
git add lib/estimate_web/live/customer_live/index.ex test/estimate_web/live/customer_live/index_test.exs
git commit -m "feat: customers rows — meta line + project-count pill, drop key column

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Projects index row template

**Files:**
- Modify: `lib/estimate_web/live/project_live/index.ex:57-94` (row block only)
- Test: `test/estimate_web/live/project_live/index_test.exs` (new file)

**Interfaces:**
- Consumes: `Project.composite_key/1` (exists: `lib/estimate/portfolio/project.ex:61`), `list_projects` preloads `[:customer, :currency]` (exists)
- Produces: nothing downstream

- [ ] **Step 1: Write the failing test**

```elixir
defmodule EstimateWeb.ProjectLive.IndexTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Estimate.AccountsFixtures
  import Estimate.CRMFixtures
  import Estimate.PortfolioFixtures

  defp projects_path(org), do: ~p"/org/#{org.id}/projects"

  defp setup_org(_) do
    %{user: owner, organization: org} = user_with_organization_fixture()
    %{org: org, owner: owner}
  end

  describe "row content" do
    setup :setup_org

    test "meta line shows composite key + customer name", %{conn: conn, org: org, owner: owner} do
      customer = customer_fixture(org, %{"key" => "CHA", "name" => "Charite Berlin"})
      project_fixture(customer, owner, %{"key" => "WEB", "name" => "Website Relaunch"})

      {:ok, lv, html} = live(log_in_user(conn, owner), projects_path(org))

      assert has_element?(lv, "span.font-mono", "CHA-WEB")
      assert html =~ "Charite Berlin"
    end

    test "old standalone key column is gone", %{conn: conn, org: org, owner: owner} do
      project_fixture(nil, owner)
      {:ok, lv, _html} = live(log_in_user(conn, owner), projects_path(org))
      refute has_element?(lv, "span.w-20")
    end

    test "status pill still renders", %{conn: conn, org: org, owner: owner} do
      project_fixture(nil, owner)
      {:ok, lv, _html} = live(log_in_user(conn, owner), projects_path(org))
      assert has_element?(lv, "span.rounded-full", "active")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/estimate_web/live/project_live/index_test.exs`
Expected: FAIL — `span.w-20` refute (column still present); composite key currently renders in the `w-20` span so the first test may pass — the refute is the gate

- [ ] **Step 3: Edit the row markup**

In `lib/estimate_web/live/project_live/index.ex`, delete the standalone key span:

```heex
              <span
                :if={project.key && project.customer}
                class="text-xs font-mono text-base-content/40 w-20 flex-shrink-0"
              >
                {Project.composite_key(project)}
              </span>
```

and replace the name/customer div:

```heex
              <div class="min-w-0 flex-1">
                <h3 class="text-sm font-medium text-base-content truncate">{project.name}</h3>
                <p :if={project.customer} class="text-sm text-base-content/60 truncate">
                  {project.customer.name}
                </p>
              </div>
```

with:

```heex
              <div class="min-w-0 flex-1">
                <h3 class="text-sm font-medium text-base-content truncate">{project.name}</h3>
                <p :if={project.customer} class="text-sm text-base-content/60 truncate">
                  <span :if={Project.composite_key(project)} class="font-mono text-xs text-base-content/40">
                    {Project.composite_key(project)} ·
                  </span>
                  {project.customer.name}
                </p>
              </div>
```

Right side (currency, status pill, pencil) stays untouched.

- [ ] **Step 4: Run tests**

Run: `mix test test/estimate_web/live/project_live/index_test.exs`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
mix format lib/estimate_web/live/project_live/index.ex test/estimate_web/live/project_live/index_test.exs
git add lib/estimate_web/live/project_live/index.ex test/estimate_web/live/project_live/index_test.exs
git commit -m "feat: projects rows — composite key into meta line, drop key column

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Entity avatar palette

**Files:**
- Modify: `lib/estimate_web/components/core_components.ex:47-54` (`@customer_gradients` → `@entity_gradients`), `:82-92` (case), `:69-70` (docstring)
- Modify: `lib/estimate_web/live/project_live/index.ex:65`, `lib/estimate_web/live/project_live/show.ex:56` (add `type={:project}`)
- Test: `test/estimate_web/components/core_components_test.exs` (append `describe "avatar/1"`)

**Interfaces:**
- Consumes: nothing
- Produces: `<.avatar type={:project}>` supported; `:customer` + `:project` share `@entity_gradients`; default (user) + `:pending` behavior unchanged

- [ ] **Step 1: Write the failing test**

Append to `test/estimate_web/components/core_components_test.exs`:

```elixir
  describe "avatar/1" do
    test ":customer and :project share the entity palette deterministically" do
      customer =
        render_component(&CoreComponents.avatar/1, %{name: "Acme Corp", seed: "same-seed", type: :customer})

      project =
        render_component(&CoreComponents.avatar/1, %{name: "Acme Corp", seed: "same-seed", type: :project})

      assert customer =~ "bg-gradient-to-br from-"
      assert customer =~ "AC"
      assert customer == project
    end

    test "user avatars keep their own palette" do
      user =
        render_component(&CoreComponents.avatar/1, %{name: "Acme Corp", seed: "same-seed"})

      entity =
        render_component(&CoreComponents.avatar/1, %{name: "Acme Corp", seed: "same-seed", type: :customer})

      assert user =~ "bg-gradient-to-br from-"
      refute user == entity
    end

    test ":pending unchanged" do
      html = render_component(&CoreComponents.avatar/1, %{name: "X", seed: "s", type: :pending})
      assert html =~ "bg-warning/10 text-warning"
    end
  end
```

(`refute user == entity` holds because no gradient string appears in both palettes — see Step 3.)

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/estimate_web/components/core_components_test.exs`
Expected: FAIL — `:project` falls into the default (user) branch, so `customer == project` assertion fails

- [ ] **Step 3: Replace the palette**

In `lib/estimate_web/components/core_components.ex` replace the whole `@customer_gradients [...]` attribute with (12 entries, none identical to a `@user_gradients` entry):

```elixir
  @entity_gradients [
    "bg-gradient-to-br from-sky-500 to-blue-600 text-white",
    "bg-gradient-to-br from-amber-500 to-orange-600 text-white",
    "bg-gradient-to-br from-violet-500 to-purple-600 text-white",
    "bg-gradient-to-br from-emerald-500 to-teal-600 text-white",
    "bg-gradient-to-br from-rose-500 to-pink-600 text-white",
    "bg-gradient-to-br from-cyan-500 to-sky-600 text-white",
    "bg-gradient-to-br from-indigo-500 to-blue-600 text-white",
    "bg-gradient-to-br from-orange-500 to-red-600 text-white",
    "bg-gradient-to-br from-teal-500 to-cyan-600 text-white",
    "bg-gradient-to-br from-fuchsia-500 to-pink-600 text-white",
    "bg-gradient-to-br from-lime-500 to-green-600 text-white",
    "bg-gradient-to-br from-blue-500 to-indigo-600 text-white"
  ]
```

- [ ] **Step 4: Update the case + docstring**

In `avatar/1`, replace the `:customer ->` branch with:

```elixir
        type when type in [:customer, :project] ->
          Enum.at(@entity_gradients, :erlang.phash2(seed, length(@entity_gradients)))
```

In the `@doc` example block (line ~70), replace the customer example with:

```elixir
      <.avatar name="Acme Corp" seed="customer-uuid" type={:customer} size={:xl} />
      <.avatar name="Website Relaunch" seed="project-uuid" type={:project} size={:lg} />
```

- [ ] **Step 5: Tag project call sites**

`lib/estimate_web/live/project_live/index.ex:65`:

```heex
              <.avatar name={project.name} seed={project.id} type={:project} size={:lg} />
```

`lib/estimate_web/live/project_live/show.ex:56`:

```heex
          <.avatar name={@project.name} seed={@project.id} type={:project} size={:xl} />
```

- [ ] **Step 6: Run tests**

Run: `mix test test/estimate_web/components/core_components_test.exs test/estimate_web/live/project_live/`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
mix format lib/estimate_web/components/core_components.ex lib/estimate_web/live/project_live/index.ex lib/estimate_web/live/project_live/show.ex test/estimate_web/components/core_components_test.exs
git add lib/estimate_web/components/core_components.ex lib/estimate_web/live/project_live/index.ex lib/estimate_web/live/project_live/show.ex test/estimate_web/components/core_components_test.exs
git commit -m "feat: broad entity avatar palette for customers+projects

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Full suite + browser verification

**Files:** none (verification only)

- [ ] **Step 1: Full test suite**

Run: `mix test`
Expected: 0 failures (288 pre-existing + ~20 new)

- [ ] **Step 2: Format + compile checks**

Run: `mix format --check-formatted && mix compile --warnings-as-errors`
Expected: clean

- [ ] **Step 3: Browser verification (superpowers:verification-before-completion)**

Start the dev server via the Browser pane (`preview_start`, not Bash). Log in, visit `/org/<org-id>/customers` and `/org/<org-id>/projects`, verify against the approved mockups (`.superpowers/brainstorm/96813-1784181243/content/consistency.html`):

- Every customer row: 2 lines; meta line `KEY · CC · domain` (mono, muted) or description; count pill (`0 projects` extra-muted); currency · pill · pencil order; no key column.
- Every project row: 2 lines; `KEY-PROJ · Customer` meta line; status pill unchanged; no key column.
- Avatars: varied hues on both lists; same entity → same color on index + show pages; user avatars (navbar/members) unchanged purple family.
- Row click navigates to show; pencil (admin) still opens edit modal.

Screenshot both screens as proof.

---

## Self-Review Checklist (run after writing, before execution)

- Spec coverage: anatomy (T3/T4), fallback chain (T3), count pill + muted 0 (T2/T3), country into meta (T3), key columns dropped (T3/T4), entity palette + call sites (T5), no-DDL (T2 virtual), tests incl. domain helper (T1) — all mapped.
- No placeholders; all code complete.
- Type consistency: `domain/1` name used in T3 import + template; `project_count` field name matches T2/T3; `@entity_gradients` only in T5.
