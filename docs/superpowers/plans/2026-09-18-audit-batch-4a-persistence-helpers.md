# Audit Batch 4A — Persistence Helpers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the 11 hand-rolled `reduce_while` + `Repo.insert` loops with `Repo.insert_each/2`, and the 6 position-reorder implementations with one `Repo.reorder_children/4`, so templates and role templates gain the stale-reorder guard the engine already has.

**Architecture:** Two small functions on `Estimate.Repo` (next to `ensure_org_context/1`). `insert_each/2` is a pure ordered fold over changesets; `reorder_children/4` is the engine's existing helper moved and stripped of its broadcast callback (callers broadcast in a `with`). Adoption is mechanical and behaviour-preserving except for the flagged guard on `templates.ex`/`accounts.ex`, whose LiveView callers gain a flash-and-reload branch.

**Tech Stack:** Elixir 1.18, Ecto 3.13 / Postgres 17 (RLS), ExUnit (`Estimate.DataCase`, `EstimateWeb.ConnCase`).

**Spec:** `docs/superpowers/specs/2026-09-18-audit-batch-4-clean-code-design.md` — section "4A — persistence helpers" (A1, A2). Read it first.

## Global Constraints

- Behaviour-preserving except the named change in A2: `Templates.reorder_template_epics/2`, `Templates.reorder_template_tasks/2`, `Accounts.reorder_role_templates/2` now return `{:error, :stale_reorder}` when the id list length differs from the child count (previously silently reordered a subset). Their LiveView callers flash `"Order changed elsewhere; reloaded"` and reload.
- `insert_each/2` opens no transaction of its own; every adopted site keeps whatever transaction/Multi it has today.
- Every adopted site keeps its return shape exactly (`:ok`, `{:ok, list}`, `{:ok, map}`, `{:error, changeset}`) — the existing suite (791 tests at branch start) is the gate; it may not be edited in this batch except where a task says so.
- Tests never use `Process.sleep`. `mix precommit` (format, `--warnings-as-errors`, full suite) green before every commit. Commit trailer exactly `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- No migrations, no template/component changes, no changes under `lib/estimate_web/mcp/`.
- Worktree via EnterWorktree then `git reset --hard main`; copy `deps/`, `_build/`, `.env`. If `git commit` fails with "1Password: failed to fill whole buffer", stop and report.

## File structure after 4A

| File | Responsibility |
|---|---|
| `lib/estimate/repo.ex` | + `insert_each/2`, `reorder_children/4` |
| `lib/estimate/estimation_engine/helpers.ex` | `reorder_children/5` removed; `with_broadcast/3`, `build_estimation_multi/3` stay |
| `lib/estimate/estimation_engine/{epics,roles,tasks}.ex` | reorders via `Repo.reorder_children/4` + `with :ok <-` broadcast |
| `lib/estimate/{templates,accounts}.ex` | reorders via `Repo.reorder_children/4` (gain guard); seed/create loops via `insert_each` |
| `lib/estimate/portfolio.ex`, `lib/estimate/estimation_engine/{copy,import,estimations,tasks}.ex` | insert loops via `insert_each` |
| `lib/estimate_web/live/templates_live/show.ex`, `lib/estimate_web/live/roles_live/index.ex` | reorder handlers handle `{:error, :stale_reorder}` |
| `test/estimate/repo_insert_each_test.exs`, `test/estimate/repo_reorder_children_test.exs` | unit tests for the two helpers |
| `test/estimate/templates_reorder_test.exs`, `test/estimate/accounts_role_templates_reorder_test.exs` | guard tests for the new adopters |

---

### Task 1: `Repo.insert_each/2` + adoption in the engine

**Files:**
- Modify: `lib/estimate/repo.ex` (append before the `## Test helpers` section / before `set_org_context/1`)
- Modify: `lib/estimate/estimation_engine/estimations.ex` (`create_estimation/1`, ~lines 89-109)
- Modify: `lib/estimate/estimation_engine/roles.ex` (`insert_roles/2`, ~lines 110-126)
- Modify: `lib/estimate/estimation_engine/tasks.ex` (`create_task_with_estimates/3` `:estimates` step, ~lines 36-51)
- Modify: `lib/estimate/estimation_engine/import.ex` (`insert_epics_and_tasks/2`, `insert_tasks/2`, ~lines 66-107)
- Modify: `lib/estimate/estimation_engine/copy.ex` (`:roles` step and the three private copiers)
- Create: `test/estimate/repo_insert_each_test.exs`

**Interfaces:**
- Produces: `Estimate.Repo.insert_each(Enumerable.t(), (term -> Ecto.Changeset.t())) :: {:ok, [struct]} | {:error, Ecto.Changeset.t()}` — ordered, halts on first error, `{:ok, []}` for empty input.

- [ ] **Step 1: Write the failing helper tests**

`test/estimate/repo_insert_each_test.exs`:

```elixir
defmodule Estimate.RepoInsertEachTest do
  use Estimate.DataCase, async: true

  import Estimate.{AccountsFixtures, PortfolioFixtures, EstimationEngineFixtures}

  alias Estimate.EstimationEngine.Epic
  alias Estimate.Repo

  setup do
    %{user: owner} = user_with_organization_fixture()
    project = project_fixture(nil, owner)
    est = estimation_fixture(project)
    %{est: est}
  end

  test "inserts every changeset in order and returns the structs in the same order", %{est: est} do
    names = ~w(A B C)

    assert {:ok, epics} =
             Repo.insert_each(Enum.with_index(names), fn {name, idx} ->
               Epic.changeset(%Epic{}, %{name: name, position: idx, estimation_id: est.id})
             end)

    assert Enum.map(epics, & &1.name) == names
    assert Enum.map(epics, & &1.position) == [0, 1, 2]
    assert Repo.aggregate(from(e in Epic, where: e.estimation_id == ^est.id), :count) == 3
  end

  test "halts on the first invalid changeset, returns it, and inserts nothing after it", %{est: est} do
    names = ["ok-1", "", "never"]

    assert {:error, %Ecto.Changeset{} = cs} =
             Repo.insert_each(names, fn name ->
               Epic.changeset(%Epic{}, %{name: name, estimation_id: est.id})
             end)

    assert %{name: [_ | _]} = errors_on(cs)
    inserted = Repo.all(from(e in Epic, where: e.estimation_id == ^est.id, select: e.name))
    assert inserted == ["ok-1"]
  end

  test "empty input is {:ok, []} and touches nothing" do
    assert Repo.insert_each([], fn _ -> flunk("must not be called") end) == {:ok, []}
  end
end
```

- [ ] **Step 2: Run to verify it fails** — `mix test test/estimate/repo_insert_each_test.exs` → `Repo.insert_each/2` undefined.

- [ ] **Step 3: Implement the helper**

Append to `lib/estimate/repo.ex` immediately before `@doc "Sets RLS org context on current connection. For test helper."`:

```elixir
  # ---------------------------------------------------------------------------
  # Batch persistence helpers
  # ---------------------------------------------------------------------------

  @doc """
  Inserts one changeset per item, in order, halting on the first error.

  Returns `{:ok, [struct]}` in input order, or `{:error, changeset}` for the
  first failing changeset (items after it are not attempted). Opens no
  transaction of its own — call it inside `transaction/1` or an
  `Ecto.Multi.run/3` step when partial inserts must roll back.
  """
  @spec insert_each(Enumerable.t(), (term -> Ecto.Changeset.t())) ::
          {:ok, [struct()]} | {:error, Ecto.Changeset.t()}
  def insert_each(items, changeset_fun) when is_function(changeset_fun, 1) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case insert(changeset_fun.(item)) do
        {:ok, record} -> {:cont, {:ok, [record | acc]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
    |> case do
      {:ok, records} -> {:ok, Enum.reverse(records)}
      error -> error
    end
  end
```

- [ ] **Step 4: Run to verify it passes** — `mix test test/estimate/repo_insert_each_test.exs` → 3 tests green.

- [ ] **Step 5: Adopt in `estimations.ex` `create_estimation/1`**

Replace the `Helpers.build_estimation_multi(attrs, fn estimation -> … end)` callback body with:

```elixir
    Helpers.build_estimation_multi(attrs, fn estimation ->
      EstimationRole.default_roles()
      |> Enum.with_index()
      |> Repo.insert_each(fn {role_attrs, idx} ->
        EstimationRole.changeset(
          %EstimationRole{},
          Map.merge(role_attrs, %{estimation_id: estimation.id, position: idx})
        )
      end)
    end)
```

(Return shape `{:ok, [roles]} | {:error, cs}` is what the old fold produced — the old code returned roles in *reverse* insertion order; `build_estimation_multi` does not read the list, so ordering is not observable. Verify by grepping `build_estimation_multi` in `helpers.ex`.)

- [ ] **Step 6: Adopt in `roles.ex` `insert_roles/2`**

```elixir
  defp insert_roles(items, attrs_fn) do
    items
    |> Enum.with_index()
    |> Repo.insert_each(fn {item, idx} ->
      EstimationRole.changeset(%EstimationRole{}, attrs_fn.(item, idx))
    end)
  end
```

(`insert_each` already returns input order, so the old `Enum.reverse` goes away.)

- [ ] **Step 7: Adopt in `tasks.ex` `create_task_with_estimates/3`**

Replace the `:estimates` Multi step body:

```elixir
      |> Ecto.Multi.run(:estimates, fn _repo, %{task: task} ->
        Repo.insert_each(effort_by_role_id, fn {role_id, hours} ->
          %TaskEstimate{}
          |> TaskEstimate.changeset(%{
            "task_id" => task.id,
            "estimation_role_id" => role_id,
            "hours" => to_string(hours)
          })
          |> Ecto.Changeset.foreign_key_constraint(:estimation_role_id)
        end)
      end)
```

- [ ] **Step 8: Adopt in `import.ex`**

```elixir
  defp insert_epics_and_tasks(estimation_id, epics_data) do
    epics_data
    |> Enum.with_index()
    |> Repo.insert_each(fn {epic_data, epic_idx} ->
      Epic.changeset(%Epic{}, %{
        name: epic_data.name,
        description: epic_data[:description],
        position: epic_data[:position] || epic_idx,
        estimation_id: estimation_id
      })
    end)
    |> case do
      {:ok, epics} ->
        epics
        |> Enum.zip(epics_data)
        |> Enum.reduce_while({:ok, epics}, fn {epic, epic_data}, acc ->
          case insert_tasks(epic.id, epic_data.tasks) do
            {:ok, _} -> {:cont, acc}
            {:error, changeset} -> {:halt, {:error, changeset}}
          end
        end)

      error ->
        error
    end
  end

  defp insert_tasks(epic_id, tasks) do
    tasks
    |> Enum.with_index()
    |> Repo.insert_each(fn {task_data, task_idx} ->
      Task.changeset(%Task{}, %{
        name: task_data.name,
        description: task_data[:description],
        position: task_data[:position] || task_idx,
        priority: task_data[:priority] || "must",
        epic_id: epic_id
      })
    end)
  end
```

Note: the old code inserted each epic's tasks immediately after that epic; the new code inserts all epics first, then tasks. Inside `build_estimation_multi`'s transaction this is unobservable (same final rows, same positions). The `reduce_while` that remains is a *children* fold, not an insert loop — acceptable.

- [ ] **Step 9: Adopt in `copy.ex`**

Replace the `:roles` step and the three private functions:

```elixir
      |> Ecto.Multi.run(:roles, fn _repo, %{estimation: new_estimation} ->
        estimation.roles
        |> Repo.insert_each(fn old_role ->
          EstimationRole.changeset(%EstimationRole{}, %{
            name: old_role.name,
            abbreviation: old_role.abbreviation,
            hourly_rate: old_role.hourly_rate,
            pm_overhead: old_role.pm_overhead,
            qa_overhead: old_role.qa_overhead,
            risk_buffer: old_role.risk_buffer,
            position: old_role.position,
            estimation_id: new_estimation.id
          })
        end)
        |> case do
          {:ok, new_roles} ->
            {:ok, Map.new(Enum.zip(estimation.roles, new_roles), fn {o, n} -> {o.id, n.id} end)}

          error ->
            error
        end
      end)
```

```elixir
  defp copy_epics_with_estimates(epics, estimation_id, role_mapping) do
    with {:ok, new_epics} <-
           Repo.insert_each(epics, fn old_epic ->
             Epic.changeset(%Epic{}, %{
               name: old_epic.name,
               description: old_epic.description,
               position: old_epic.position,
               estimation_id: estimation_id
             })
           end) do
      epics
      |> Enum.zip(new_epics)
      |> Enum.reduce_while({:ok, new_epics}, fn {old_epic, new_epic}, acc ->
        case copy_tasks_with_estimates(old_epic.tasks, new_epic.id, role_mapping) do
          {:ok, _} -> {:cont, acc}
          {:error, changeset} -> {:halt, {:error, changeset}}
        end
      end)
    end
  end

  defp copy_tasks_with_estimates(tasks, epic_id, role_mapping) do
    with {:ok, new_tasks} <-
           Repo.insert_each(tasks, fn old_task ->
             Task.changeset(%Task{}, %{
               name: old_task.name,
               description: old_task.description,
               position: old_task.position,
               epic_id: epic_id
             })
           end) do
      tasks
      |> Enum.zip(new_tasks)
      |> Enum.reduce_while({:ok, new_tasks}, fn {old_task, new_task}, acc ->
        case copy_estimates(old_task.estimates, new_task.id, role_mapping) do
          {:ok, _} -> {:cont, acc}
          {:error, changeset} -> {:halt, {:error, changeset}}
        end
      end)
    end
  end

  # Estimates whose role was not copied (no mapping) are skipped, as before.
  defp copy_estimates(estimates, new_task_id, role_mapping) do
    estimates
    |> Enum.filter(&Map.has_key?(role_mapping, &1.estimation_role_id))
    |> Repo.insert_each(fn old_estimate ->
      TaskEstimate.changeset(%TaskEstimate{}, %{
        hours: old_estimate.hours,
        task_id: new_task_id,
        estimation_role_id: Map.fetch!(role_mapping, old_estimate.estimation_role_id)
      })
    end)
  end
```

(`copy_estimates` used to return `:ok`; it now returns `{:ok, list}` and its only caller is updated above. Old `{:ok, acc}` lists were reversed; nothing reads them.)

- [ ] **Step 10: Run the covering tests, then precommit**

Run: `mix test test/estimate/estimation_engine_test.exs test/estimate/estimation_engine test/estimate_web/live/project_live/show_test.exs test/estimate_web/live/estimator_live test/estimate_web/mcp`
Expected: green. Then `mix precommit`.

- [ ] **Step 11: Commit**

```bash
git add lib/estimate/repo.ex lib/estimate/estimation_engine test/estimate/repo_insert_each_test.exs
git commit -m "refactor(repo): Repo.insert_each/2 replaces the engine's reduce_while insert loops

Ordered, halt-on-first-error, no own transaction. Adopted in create_estimation,
insert_roles, create_task_with_estimates, Import and Copy.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: `insert_each` adoption in `accounts.ex`, `templates.ex`, `portfolio.ex`

**Files:**
- Modify: `lib/estimate/accounts.ex` (`seed_default_currencies/1`, `seed_default_role_templates/1`, ~lines 472-507)
- Modify: `lib/estimate/templates.ex` (`create_template_with_epics/2` `:epics_tasks` step + `insert_template_tasks/2`, ~lines 181-233)
- Modify: `lib/estimate/portfolio.ex` (`copy_roles_from_templates/2`, ~lines 501-531)

**Interfaces:**
- Consumes: `Repo.insert_each/2` from Task 1.
- Produces: unchanged public return shapes (`:ok | {:error, cs}` for the two seeders and `copy_roles_from_templates/2`; `{:ok, template} | {:error, cs}` for `create_template_with_epics/2`).

- [ ] **Step 1: `accounts.ex`**

```elixir
  def seed_default_currencies(org_id) do
    with {:ok, _} <-
           Repo.insert_each(Currency.default_currencies(), fn attrs ->
             Currency.changeset(%Currency{}, Map.put(attrs, :organization_id, org_id))
           end) do
      :ok
    end
  end

  def seed_default_role_templates(org_id) do
    main_currency = Estimate.Organizations.Currencies.get_main_currency(org_id)
    defaults = RoleTemplate.default_templates()

    with {:ok, templates} <-
           Repo.insert_each(defaults, fn attrs ->
             RoleTemplate.changeset(%RoleTemplate{}, %{
               name: attrs.name,
               abbreviation: attrs.abbreviation,
               position: attrs.position,
               pm_overhead: attrs.pm_overhead,
               qa_overhead: attrs.qa_overhead,
               risk_buffer: attrs.risk_buffer,
               organization_id: org_id
             })
           end) do
      defaults
      |> Enum.zip(templates)
      |> first_error(fn {attrs, template} ->
        maybe_create_template_rate(template, main_currency, attrs.default_rate)
      end)
    end
  end

  # Runs `fun` over `items` until the first non-:ok result; :ok when all pass.
  defp first_error(items, fun) do
    Enum.find_value(items, :ok, fn item ->
      case fun.(item) do
        :ok -> nil
        error -> error
      end
    end)
  end
```

`maybe_create_template_rate/3` stays as is.

- [ ] **Step 2: `templates.ex`**

Replace the `:epics_tasks` step and `insert_template_tasks/2`:

```elixir
      |> Ecto.Multi.run(:epics_tasks, fn _repo, %{template: template} ->
        with {:ok, new_epics} <-
               Repo.insert_each(epics, fn epic ->
                 EstimationTemplateEpic.changeset(%EstimationTemplateEpic{}, %{
                   name: epic.name,
                   description: epic.description,
                   position: Map.get(epic, :position) || 0,
                   estimation_template_id: template.id
                 })
               end) do
          epics
          |> Enum.zip(new_epics)
          |> Enum.reduce_while({:ok, :done}, fn {epic, new_epic}, acc ->
            case insert_template_tasks(epic.tasks, new_epic.id) do
              {:ok, _} -> {:cont, acc}
              {:error, changeset} -> {:halt, {:error, changeset}}
            end
          end)
        end
      end)
```

```elixir
  defp insert_template_tasks(tasks, epic_id) do
    tasks
    |> Enum.with_index()
    |> Repo.insert_each(fn {task, position} ->
      EstimationTemplateTask.changeset(%EstimationTemplateTask{}, %{
        name: task.name,
        description: task.description,
        position: position,
        priority: task.priority,
        estimation_template_epic_id: epic_id
      })
    end)
  end
```

- [ ] **Step 3: `portfolio.ex` `copy_roles_from_templates/2`**

```elixir
  def copy_roles_from_templates(%Project{} = project, org_id) do
    Repo.ensure_org_context(fn ->
      templates = Accounts.list_role_templates(org_id)
      currency_id = project.currency_id

      with {:ok, _} <-
             Repo.insert_each(templates, fn template ->
               rate = Enum.find(template.rates, fn r -> r.currency_id == currency_id end)
               hourly_rate = if rate, do: rate.hourly_rate, else: Decimal.new(0)

               ProjectRole.changeset(%ProjectRole{}, %{
                 name: template.name,
                 abbreviation: template.abbreviation,
                 position: template.position,
                 hourly_rate: hourly_rate,
                 pm_overhead: template.pm_overhead || Decimal.new(0),
                 qa_overhead: template.qa_overhead || Decimal.new(0),
                 risk_buffer: template.risk_buffer || Decimal.new(0),
                 project_id: project.id
               })
             end) do
        :ok
      end
    end)
  end
```

- [ ] **Step 4: Verify no insert loops remain**

Run: `grep -rn "reduce_while" lib/estimate | grep -v json_import`
Expected: only the children folds introduced in Task 1/2 (`import.ex`, `copy.ex` ×2, `templates.ex`) — none of them contains `Repo.insert(`. Then `grep -rn -B6 "Repo.insert()" lib/estimate | grep -c reduce_while` → `0`.

- [ ] **Step 5: Covering tests + precommit**

Run: `mix test test/estimate/accounts_test.exs test/estimate/templates_fixtures_test.exs test/estimate/portfolio test/estimate_web/live/project_live/show_test.exs test/estimate_web/live/estimator_live/export_test.exs` then `mix precommit`.

- [ ] **Step 6: Commit**

```bash
git add lib/estimate/accounts.ex lib/estimate/templates.ex lib/estimate/portfolio.ex
git commit -m "refactor(contexts): seeders, template creation and role copy use Repo.insert_each/2

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: `Repo.reorder_children/4` + engine adoption

**Files:**
- Modify: `lib/estimate/repo.ex` (append after `insert_each/2`)
- Modify: `lib/estimate/estimation_engine/helpers.ex` (delete `reorder_children/5`)
- Modify: `lib/estimate/estimation_engine/epics.ex` (`reorder_epics/2`), `roles.ex` (`reorder_roles/2`), `tasks.ex` (`reorder_tasks/2`)
- Create: `test/estimate/repo_reorder_children_test.exs`

**Interfaces:**
- Produces: `Estimate.Repo.reorder_children(module, atom, binary, [binary]) :: :ok | {:error, :stale_reorder | term}`. Wraps its own `ensure_org_context/1` + `transaction/1` exactly as the old helper did.

- [ ] **Step 1: Write the failing helper tests**

`test/estimate/repo_reorder_children_test.exs`:

```elixir
defmodule Estimate.RepoReorderChildrenTest do
  use Estimate.DataCase, async: true

  import Estimate.{AccountsFixtures, PortfolioFixtures, EstimationEngineFixtures}

  alias Estimate.EstimationEngine.Epic
  alias Estimate.Repo

  setup do
    %{user: owner} = user_with_organization_fixture()
    project = project_fixture(nil, owner)
    est = estimation_fixture(project)
    e1 = epic_fixture(est, %{name: "E1", position: 0})
    e2 = epic_fixture(est, %{name: "E2", position: 1})
    e3 = epic_fixture(est, %{name: "E3", position: 2})
    %{est: est, ids: [e1.id, e2.id, e3.id]}
  end

  defp positions(est_id) do
    Repo.all(from(e in Epic, where: e.estimation_id == ^est_id, order_by: e.position, select: e.id))
  end

  test "assigns positions in list order", %{est: est, ids: [a, b, c]} do
    assert :ok = Repo.reorder_children(Epic, :estimation_id, est.id, [c, a, b])
    assert positions(est.id) == [c, a, b]
  end

  test "a list whose length differs from the child count is rejected untouched", %{est: est, ids: [a, b, _c] = ids} do
    assert {:error, :stale_reorder} = Repo.reorder_children(Epic, :estimation_id, est.id, [b, a])
    assert positions(est.id) == ids
  end

  test "an id from another parent is ignored, not moved", %{est: est, ids: [a, b, c]} do
    %{user: other_owner} = user_with_organization_fixture()
    other = estimation_fixture(project_fixture(nil, other_owner))
    foreign = epic_fixture(other, %{name: "X", position: 0})

    assert :ok = Repo.reorder_children(Epic, :estimation_id, est.id, [foreign.id, c, b])
    # foreign id consumed a slot but touched nothing; a keeps its old position 0 and now ties with c
    assert Repo.get!(Epic, foreign.id).position == 0
    assert Repo.get!(Epic, a.id).position == 0
    assert Repo.get!(Epic, c.id).position == 1
    assert Repo.get!(Epic, b.id).position == 2
  end
end
```

(The third test documents today's semantics — the count check is on length only, not membership — so it is a characterization, not a new guarantee.)

- [ ] **Step 2: Run to verify it fails** — `mix test test/estimate/repo_reorder_children_test.exs` → undefined.

- [ ] **Step 3: Implement**

Append to `lib/estimate/repo.ex` right after `insert_each/2`:

```elixir
  @doc """
  Rewrites `position` for the children of one parent to match `ids` order.

  Guards against a stale client: when `length(ids)` differs from the number
  of children the parent currently has, nothing is written and
  `{:error, :stale_reorder}` is returned. Ids that do not belong to the
  parent are ignored. Runs inside `ensure_org_context/1` and a transaction.
  """
  @spec reorder_children(module(), atom(), binary(), [binary()]) ::
          :ok | {:error, :stale_reorder | term()}
  def reorder_children(schema, parent_field, parent_id, ids) do
    ensure_org_context(fn ->
      actual_count =
        from(s in schema, where: field(s, ^parent_field) == ^parent_id) |> aggregate(:count)

      if length(ids) != actual_count do
        {:error, :stale_reorder}
      else
        transaction(fn ->
          ids
          |> Enum.with_index()
          |> Enum.each(fn {id, position} ->
            from(s in schema, where: s.id == ^id and field(s, ^parent_field) == ^parent_id)
            |> update_all(set: [position: position])
          end)

          :ok
        end)
        |> case do
          {:ok, :ok} -> :ok
          {:error, reason} -> {:error, reason}
        end
      end
    end)
  end
```

`repo.ex` already has `import Ecto.Query` (it uses `from` in `prepare_query/3`); confirm, else add it.

- [ ] **Step 4: Run to verify it passes** — 3 tests green.

- [ ] **Step 5: Engine callers**

`epics.ex`:

```elixir
  def reorder_epics(estimation_id, epic_ids) do
    with :ok <- Repo.reorder_children(Epic, :estimation_id, estimation_id, epic_ids) do
      Estimate.EstimationEngine.broadcast(estimation_id, {:epics_reordered, epic_ids})
      :ok
    end
  end
```

`roles.ex`:

```elixir
  def reorder_roles(estimation_id, role_ids) do
    with :ok <- Repo.reorder_children(EstimationRole, :estimation_id, estimation_id, role_ids) do
      Estimate.EstimationEngine.broadcast(estimation_id, {:roles_reordered, role_ids})
      :ok
    end
  end
```

`tasks.ex`:

```elixir
  def reorder_tasks(epic_id, task_ids) do
    epic = Repo.ensure_org_context(fn -> Repo.get!(Epic, epic_id) end)

    with :ok <- Repo.reorder_children(Task, :epic_id, epic_id, task_ids) do
      Estimate.EstimationEngine.broadcast(epic.estimation_id, {:tasks_reordered, epic_id, task_ids})
      :ok
    end
  end
```

Remove the three `alias Estimate.EstimationEngine.Helpers` lines that only served the old call (keep any still used). Delete `reorder_children/5` and its `@doc` from `helpers.ex`.

- [ ] **Step 6: Covering tests + precommit**

Run: `mix test test/estimate/estimation_engine_test.exs test/estimate_web/live/estimator_live test/estimate/repo_reorder_children_test.exs` then `mix precommit`. `grep -rn "Helpers.reorder_children" lib` → empty.

- [ ] **Step 7: Commit**

```bash
git add lib/estimate/repo.ex lib/estimate/estimation_engine test/estimate/repo_reorder_children_test.exs
git commit -m "refactor(repo): Repo.reorder_children/4 (moved from EstimationEngine.Helpers); engine callers broadcast in a with

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: Reorder guard for templates and role templates (+ LiveView handling)

**Files:**
- Modify: `lib/estimate/templates.ex` (`reorder_template_epics/2` ~88-101, `reorder_template_tasks/2` ~129-142)
- Modify: `lib/estimate/accounts.ex` (`reorder_role_templates/2` ~408-421)
- Modify: `lib/estimate_web/live/templates_live/show.ex` (`reorder_epics`/`reorder_tasks` handlers ~553-566)
- Modify: `lib/estimate_web/live/roles_live/index.ex` (`reorder_roles` handler ~278-283)
- Create: `test/estimate/templates_reorder_test.exs`, `test/estimate/accounts_role_templates_reorder_test.exs`

**Interfaces:**
- Consumes: `Repo.reorder_children/4`, `Templates.create_template_epic/1`, `Templates.create_template_task/1`, `Templates.get_estimation_template!/2`, `Accounts.create_role_template/2`, `Accounts.list_role_templates/1`, fixtures `template_fixture/2`, `organization_fixture/1`.
- Produces: the three context functions return `:ok | {:error, :stale_reorder | term}` (previously always `:ok`). **This is the batch's one intended behaviour change.**

- [ ] **Step 1: Write the failing context tests**

`test/estimate/templates_reorder_test.exs`:

```elixir
defmodule Estimate.TemplatesReorderTest do
  use Estimate.DataCase, async: true

  import Estimate.{AccountsFixtures, TemplatesFixtures}
  alias Estimate.Templates

  setup do
    org = organization_fixture()
    template = template_fixture(org)

    {:ok, e1} = Templates.create_template_epic(%{"name" => "E1", "position" => 0, "estimation_template_id" => template.id})
    {:ok, e2} = Templates.create_template_epic(%{"name" => "E2", "position" => 1, "estimation_template_id" => template.id})
    {:ok, t1} = Templates.create_template_task(%{"name" => "T1", "position" => 0, "estimation_template_epic_id" => e1.id})
    {:ok, t2} = Templates.create_template_task(%{"name" => "T2", "position" => 1, "estimation_template_epic_id" => e1.id})

    %{org: org, template: template, e1: e1, e2: e2, t1: t1, t2: t2}
  end

  defp epic_ids(template, org), do: Templates.get_estimation_template!(template.id, org.id).epics |> Enum.map(& &1.id)
  defp task_ids(template, org, epic_id) do
    Templates.get_estimation_template!(template.id, org.id).epics
    |> Enum.find(&(&1.id == epic_id))
    |> Map.fetch!(:tasks)
    |> Enum.map(& &1.id)
  end

  test "reorder_template_epics/2 applies the order", ctx do
    assert :ok = Templates.reorder_template_epics(ctx.template.id, [ctx.e2.id, ctx.e1.id])
    assert epic_ids(ctx.template, ctx.org) == [ctx.e2.id, ctx.e1.id]
  end

  test "reorder_template_epics/2 rejects a stale (partial) id list untouched", ctx do
    assert {:error, :stale_reorder} = Templates.reorder_template_epics(ctx.template.id, [ctx.e2.id])
    assert epic_ids(ctx.template, ctx.org) == [ctx.e1.id, ctx.e2.id]
  end

  test "reorder_template_tasks/2 applies the order and rejects a stale list", ctx do
    assert :ok = Templates.reorder_template_tasks(ctx.e1.id, [ctx.t2.id, ctx.t1.id])
    assert task_ids(ctx.template, ctx.org, ctx.e1.id) == [ctx.t2.id, ctx.t1.id]

    assert {:error, :stale_reorder} = Templates.reorder_template_tasks(ctx.e1.id, [ctx.t1.id])
    assert task_ids(ctx.template, ctx.org, ctx.e1.id) == [ctx.t2.id, ctx.t1.id]
  end
end
```

`test/estimate/accounts_role_templates_reorder_test.exs`:

```elixir
defmodule Estimate.AccountsRoleTemplatesReorderTest do
  use Estimate.DataCase, async: true

  import Estimate.AccountsFixtures
  alias Estimate.Accounts

  setup do
    %{organization: org} = user_with_organization_fixture()
    # orgs are seeded with default role templates
    ids = Accounts.list_role_templates(org.id) |> Enum.map(& &1.id)
    assert length(ids) >= 2
    %{org: org, ids: ids}
  end

  test "reorder_role_templates/2 applies the order", %{org: org, ids: [a, b | rest]} do
    new_order = [b, a | rest]
    assert :ok = Accounts.reorder_role_templates(org.id, new_order)
    assert Accounts.list_role_templates(org.id) |> Enum.map(& &1.id) == new_order
  end

  test "reorder_role_templates/2 rejects a stale (partial) id list untouched", %{org: org, ids: [a, b | _] = ids} do
    assert {:error, :stale_reorder} = Accounts.reorder_role_templates(org.id, [b, a])
    assert Accounts.list_role_templates(org.id) |> Enum.map(& &1.id) == ids
  end
end
```

If `Accounts.list_role_templates/1` does not order by `position`, order the assertion by fetching positions instead (`Enum.sort_by(&1.position)`) — check the function first.

- [ ] **Step 2: Run to verify the stale tests fail** — `mix test test/estimate/templates_reorder_test.exs test/estimate/accounts_role_templates_reorder_test.exs` → the "stale" assertions fail (today returns `:ok` and reorders the subset).

- [ ] **Step 3: Adopt in the contexts**

`templates.ex`:

```elixir
  def reorder_template_epics(template_id, epic_ids),
    do: Repo.reorder_children(EstimationTemplateEpic, :estimation_template_id, template_id, epic_ids)

  def reorder_template_tasks(epic_id, task_ids),
    do: Repo.reorder_children(EstimationTemplateTask, :estimation_template_epic_id, epic_id, task_ids)
```

`accounts.ex`:

```elixir
  def reorder_role_templates(org_id, ids),
    do: Repo.reorder_children(RoleTemplate, :organization_id, org_id, ids)
```

- [ ] **Step 4: LiveView callers handle the guard**

`templates_live/show.ex` — both handlers:

```elixir
  def handle_event("reorder_epics", %{"ids" => ids}, socket) do
    require_admin(socket, fn ->
      socket.assigns.template.id
      |> Templates.reorder_template_epics(ids)
      |> after_reorder(socket)
    end)
  end

  def handle_event("reorder_tasks", %{"epic_id" => epic_id, "ids" => ids}, socket) do
    require_admin(socket, fn ->
      epic_id
      |> Templates.reorder_template_tasks(ids)
      |> after_reorder(socket)
    end)
  end
```

and a private helper next to `reload_template/1`:

```elixir
  defp after_reorder(:ok, socket), do: {:noreply, reload_template(socket)}

  defp after_reorder({:error, :stale_reorder}, socket),
    do: {:noreply, socket |> reload_template() |> put_flash(:error, "Order changed elsewhere; reloaded")}

  defp after_reorder({:error, _}, socket),
    do: {:noreply, socket |> reload_template() |> put_flash(:error, "Could not reorder")}
```

`roles_live/index.ex`:

```elixir
  def handle_event("reorder_roles", %{"ids" => ids}, socket) do
    require_admin(socket, fn ->
      case Accounts.reorder_role_templates(socket.assigns.org_id, ids) do
        :ok ->
          {:noreply, reload_templates(socket)}

        {:error, :stale_reorder} ->
          {:noreply, socket |> reload_templates() |> put_flash(:error, "Order changed elsewhere; reloaded")}

        {:error, _} ->
          {:noreply, socket |> reload_templates() |> put_flash(:error, "Could not reorder")}
      end
    end)
  end
```

- [ ] **Step 5: LV test for the flash (templates)**

Append to `test/estimate/templates_reorder_test.exs`? No — it is a DataCase. Create the one LiveView assertion in a new `test/estimate_web/live/templates_live/show_reorder_test.exs` (4B will fold it into the full characterization suite):

```elixir
defmodule EstimateWeb.TemplatesLive.ShowReorderTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Estimate.TemplatesFixtures
  alias Estimate.Templates

  setup :register_and_log_in_org_owner

  test "a stale reorder flashes and reloads instead of silently reordering a subset", %{conn: conn, org: org} do
    template = template_fixture(org)
    {:ok, e1} = Templates.create_template_epic(%{"name" => "E1", "position" => 0, "estimation_template_id" => template.id})
    {:ok, e2} = Templates.create_template_epic(%{"name" => "E2", "position" => 1, "estimation_template_id" => template.id})

    {:ok, lv, _} = live(conn, ~p"/org/#{org.id}/templates/#{template.id}")

    html = render_click(lv, "reorder_epics", %{"ids" => [e2.id]})
    assert html =~ "Order changed elsewhere; reloaded"

    ids = Templates.get_estimation_template!(template.id, org.id).epics |> Enum.map(& &1.id)
    assert ids == [e1.id, e2.id]
  end
end
```

Confirm the templates route with `grep -n "templates" lib/estimate_web/router.ex` and adjust the `~p` path if it differs.

- [ ] **Step 6: Covering tests + precommit**

Run: `mix test test/estimate/templates_reorder_test.exs test/estimate/accounts_role_templates_reorder_test.exs test/estimate_web/live/templates_live test/estimate_web/live/org_scoped_smoke_test.exs` then `mix precommit`.

- [ ] **Step 7: Commit**

```bash
git add lib/estimate/templates.ex lib/estimate/accounts.ex lib/estimate_web/live/templates_live/show.ex lib/estimate_web/live/roles_live/index.ex test/estimate/templates_reorder_test.exs test/estimate/accounts_role_templates_reorder_test.exs test/estimate_web/live/templates_live/show_reorder_test.exs
git commit -m "fix(reorder): templates and role templates gain the stale-reorder guard via Repo.reorder_children/4

Behaviour change: a partial id list is rejected ({:error, :stale_reorder}) instead of
silently reordering a subset; the LiveViews flash and reload.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## Done criteria

- `grep -rn -B6 "Repo.insert()" lib/estimate | grep -c reduce_while` → 0; `grep -rn "reorder_children" lib` shows only `repo.ex` and the six callers.
- `EstimationEngine.Helpers.reorder_children/5` gone.
- New tests: 3 + 3 + 3 + 2 + 1; full suite green; three LV callers handle `{:error, :stale_reorder}`.

## Unresolved questions

None.
