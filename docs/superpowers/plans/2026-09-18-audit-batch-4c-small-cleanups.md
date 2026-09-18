# Audit Batch 4C — Small Cleanups Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the spec's 4C cleanups (C1–C5) plus the carry-overs that 4A and 4B parked: a shared first-error fold, the `Portfolio.create_project` `:roles` error clause, and the templates LiveView's remaining crash paths.

**Architecture:** Five independent, small changes grouped into four tasks by file cluster. Each is TDD (failing test → minimal code → green) and behaviour-preserving except where a task names the change (the `Portfolio` error clause and the templates LV crash paths turn crashes into error tuples / flashes). No migrations, no HEEx, no changes to `Calculator`, RLS, or MCP.

**Tech Stack:** Elixir 1.18, Phoenix 1.8.3 / LiveView 1.1, Ecto 3.13 / Postgres 17 (RLS), ExUnit.

**Spec:** `docs/superpowers/specs/2026-09-18-audit-batch-4-clean-code-design.md` — section "4C — small cleanups" (C1–C6) plus the 4A/4B carry-overs recorded in the batch memory. Read the 4C section first.

## Global Constraints

- Behaviour-preserving except: (a) `Portfolio.create_project/4` returns `{:error, changeset}` instead of raising `CaseClauseError` when role copying fails; (b) `TemplatesLive.Show` `delete_epic`/`delete_task` with nothing confirmed, and `add_task` without `"epic-id"`, flash `"Not found"` instead of crashing the LiveView. Everything else must keep its return shape and copy.
- `Estimate.Repo.each_ok/2` opens no transaction; callers keep whatever transaction they have.
- Tests never use `Process.sleep`; diverge-then-assert; denial/not-found tests assert flash AND unchanged state. **Gating-test rule:** LiveViewTest never clears flash between events — a flash assertion after an earlier flash on the same LV can pass on the stale flash; make it the first flashing event on a fresh LV or assert unchanged state.
- No migrations. No changes to `Estimate.EstimationEngine.Calculator`, RLS, CSP, `lib/estimate_web/mcp/`, or any HEEx.
- `mix precommit` (format, `--warnings-as-errors`, full suite) green before every commit. Trailer exactly `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Worktree via EnterWorktree then `git reset --hard main`; copy `deps/`, `_build/`, `.env`. If `git commit` fails with "1Password: failed to fill whole buffer", stop and report.

## File structure after 4C

| File | Change |
|---|---|
| `lib/estimate/changeset_helpers.ex` | + `validate_name/2` |
| `lib/estimate/templates/{estimation_template,estimation_template_epic,estimation_template_task}.ex`, `lib/estimate/estimation_engine/{epic,task,estimation}.ex` | name rules via `validate_name/2` |
| `lib/estimate/repo.ex` | + `each_ok/2` |
| `lib/estimate/accounts.ex`, `lib/estimate/templates.ex`, `lib/estimate/estimation_engine/{import,copy}.ex` | folds via `Repo.each_ok/2`; `Accounts.first_error/2` removed |
| `lib/estimate/portfolio.ex` | `create_project/4` handles `{:error, :roles, …}` |
| `lib/estimate_web/live/estimator_live/settings.ex` | roles resolved from `@estimation.roles`; no `get_role!` |
| `lib/estimate_web/live/estimator_live/rows.ex`, `view_state.ex`, `grid.ex`, `export.ex` | `filtered_epics/2` lives in `Rows`; `ViewState` delegates; `Grid.refresh_editing` fallback |
| `lib/estimate_web/live/templates_live/show/{epics,tasks}.ex` | nil `@deleting_*` and missing `"epic-id"` → `not_found` |
| `test/support/estimator_live_helpers.ex` | + `by_order/0` |
| tests | new: `changeset_helpers_test.exs`, `repo_each_ok_test.exs`; edited: four sort-key sites, `settings_test.exs`, `sync_test.exs`, `portfolio_test`, `templates_live/show_test.exs` |

---

### Task 1: `ChangesetHelpers.validate_name/2` (C1)

**Files:**
- Modify: `lib/estimate/changeset_helpers.ex`
- Modify: `lib/estimate/templates/estimation_template.ex:16-21`, `estimation_template_epic.ex:17-22`, `estimation_template_task.ex:18-24`
- Modify: `lib/estimate/estimation_engine/epic.ex:23-28`, `task.ex:27-32`, `estimation.ex:46-51` (`update_changeset/2` only)
- Create: `test/estimate/changeset_helpers_test.exs`

**Interfaces:**
- Produces: `Estimate.ChangesetHelpers.validate_name(Ecto.Changeset.t(), pos_integer()) :: Ecto.Changeset.t()` = `validate_required([:name]) |> validate_length(:name, min: 1, max: max)`.

Rule: only replace a `validate_required([:name]) |> validate_length(:name, min: 1, max: N)` pair where `:name` is the ONLY required field in that `validate_required` call. The template `changeset/2`s require a second field (`organization_id` / `estimation_template_id` / `estimation_template_epic_id`) — split them: `validate_required([:parent_field]) |> validate_name(N)`. The engine `changeset/2`s (create) are left alone (they require parent ids too and are covered by mass-assignment tests); only their `update_changeset/2` clauses adopt.

- [ ] **Step 1: Failing test**

`test/estimate/changeset_helpers_test.exs`:

```elixir
defmodule Estimate.ChangesetHelpersTest do
  use ExUnit.Case, async: true

  import Ecto.Changeset
  alias Estimate.ChangesetHelpers

  defmodule Named do
    use Ecto.Schema

    embedded_schema do
      field :name, :string
    end
  end

  defp cs(attrs), do: cast(%Named{}, attrs, [:name])

  test "requires a name" do
    changeset = ChangesetHelpers.validate_name(cs(%{}), 200)
    assert %{name: ["can't be blank"]} = errors_on(changeset)
  end

  test "rejects an empty name" do
    changeset = ChangesetHelpers.validate_name(cs(%{name: ""}), 200)
    assert %{name: ["can't be blank"]} = errors_on(changeset)
  end

  test "enforces the max length" do
    changeset = ChangesetHelpers.validate_name(cs(%{name: String.duplicate("x", 201)}), 200)
    assert %{name: [msg]} = errors_on(changeset)
    assert msg =~ "at most 200"
    assert ChangesetHelpers.validate_name(cs(%{name: String.duplicate("x", 200)}), 200).valid?
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key -> opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string() end)
    end)
  end
end
```

- [ ] **Step 2: Run to verify it fails** — `mix test test/estimate/changeset_helpers_test.exs` → `validate_name/2` undefined.

- [ ] **Step 3: Implement**

Append to `lib/estimate/changeset_helpers.ex` (inside the module):

```elixir
  @doc """
  The project's standard `:name` rule: required and 1..`max` characters.
  Callers that require other fields call `validate_required/2` for those first.
  """
  @spec validate_name(Ecto.Changeset.t(), pos_integer()) :: Ecto.Changeset.t()
  def validate_name(changeset, max) when is_integer(max) and max > 0 do
    changeset
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: max)
  end
```

Update the moduledoc's first line to "Cross-cutting changeset validations." (the DB qualifier is no longer true for the whole module).

- [ ] **Step 4: Adopt**

`estimation_template.ex`:
```elixir
  def changeset(template, attrs) do
    template
    |> cast(attrs, [:name, :description, :organization_id])
    |> validate_required([:organization_id])
    |> ChangesetHelpers.validate_name(200)
  end
```
(add `alias Estimate.ChangesetHelpers`). Same shape for `estimation_template_epic.ex` (`validate_required([:estimation_template_id])`, 200) and `estimation_template_task.ex` (`validate_required([:estimation_template_epic_id])`, 500; keep `validate_inclusion(:priority, @priorities)` after).

Engine `update_changeset/2`: replace the `validate_required([:name]) |> validate_length(:name, min: 1, max: N)` pair with `ChangesetHelpers.validate_name(N)` in `epic.ex` (200), `task.ex` (500), `estimation.ex` (200). Do not touch their `changeset/2`.

Error-message parity check: `validate_required` before/after produces the same `"can't be blank"`; `validate_length` the same `"should be at most N character(s)"`. Order of errors on `:name` is unchanged because both validations still run in the same order.

- [ ] **Step 5: Covering tests + precommit**

Run: `mix test test/estimate/changeset_helpers_test.exs test/estimate/estimation_engine/update_changeset_test.exs test/estimate_web/live/templates_live test/estimate_web/live/estimator_live` then `mix precommit`.

- [ ] **Step 6: Commit**

```bash
git add lib/estimate/changeset_helpers.ex lib/estimate/templates lib/estimate/estimation_engine/epic.ex lib/estimate/estimation_engine/task.ex lib/estimate/estimation_engine/estimation.ex test/estimate/changeset_helpers_test.exs
git commit -m "refactor(changesets): ChangesetHelpers.validate_name/2 is the one home for the name rule

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: `Repo.each_ok/2` + `Portfolio.create_project` `:roles` clause (4A carry-overs)

**Files:**
- Modify: `lib/estimate/repo.ex` (append after `reorder_children/4`)
- Modify: `lib/estimate/accounts.ex` (`seed_default_role_templates/1`; delete `first_error/2`)
- Modify: `lib/estimate/templates.ex` (`:epics_tasks` fold), `lib/estimate/estimation_engine/import.ex` (`insert_epics_and_tasks/2` fold), `lib/estimate/estimation_engine/copy.ex` (two folds)
- Modify: `lib/estimate/portfolio.ex` (`create_project/4` `case`)
- Create: `test/estimate/repo_each_ok_test.exs`
- Test: `test/estimate/portfolio/create_project_roles_test.exs` (new)

**Interfaces:**
- Produces: `Estimate.Repo.each_ok(Enumerable.t(), (term -> :ok | {:ok, term} | {:error, term})) :: :ok | {:error, term}` — runs `fun` in order, stops at the first `{:error, _}`, returns `:ok` when every call returned `:ok` or `{:ok, _}`.

- [ ] **Step 1: Failing tests**

`test/estimate/repo_each_ok_test.exs`:

```elixir
defmodule Estimate.RepoEachOkTest do
  use ExUnit.Case, async: true

  alias Estimate.Repo

  test "returns :ok when every call succeeds (accepting :ok or {:ok, _})" do
    assert Repo.each_ok([1, 2, 3], fn
             1 -> :ok
             n -> {:ok, n}
           end) == :ok
  end

  test "stops at the first error and returns it" do
    seen = :counters.new(1, [])

    result =
      Repo.each_ok([1, 2, 3], fn n ->
        :counters.add(seen, 1, 1)
        if n == 2, do: {:error, {:bad, n}}, else: :ok
      end)

    assert result == {:error, {:bad, 2}}
    assert :counters.get(seen, 1) == 2
  end

  test "empty input is :ok" do
    assert Repo.each_ok([], fn _ -> flunk("must not be called") end) == :ok
  end
end
```

`test/estimate/portfolio/create_project_roles_test.exs`:

```elixir
defmodule Estimate.Portfolio.CreateProjectRolesTest do
  use Estimate.DataCase, async: true

  import Estimate.{AccountsFixtures, CRMFixtures}
  alias Estimate.{Accounts, Portfolio}
  alias Estimate.Accounts.RoleTemplate

  test "a role template that cannot be copied surfaces as {:error, changeset} instead of raising" do
    %{user: owner, organization: org} = user_with_organization_fixture()
    customer = customer_fixture(org)

    # Diverge: make one seeded template invalid for ProjectRole (abbreviation "" fails
    # ProjectRole validate_required after cast empties it; role_templates has no CHECK on it).
    [tpl | _] = Accounts.list_role_templates(org.id)
    Repo.update_all(from(rt in RoleTemplate, where: rt.id == ^tpl.id), set: [abbreviation: ""])

    result = Portfolio.create_project(%{"name" => "P"}, customer.id, owner.id, org.id)

    assert {:error, %Ecto.Changeset{}} = result
    assert Repo.aggregate(Estimate.Portfolio.Project, :count) == 0
  end
end
```

`ProjectRole.changeset/2` requires `:abbreviation` (`validate_required([:name, :abbreviation, :project_id])`, `min: 1, max: 5`), so the empty abbreviation makes `copy_roles_from_templates/2` return `{:error, cs}`. DataCase already imports `Ecto.Query` and aliases `Repo`.

- [ ] **Step 2: Run to verify they fail** — `each_ok/2` undefined; `create_project` raises `CaseClauseError`.

- [ ] **Step 3: Implement `each_ok/2`**

Append to `lib/estimate/repo.ex` right after `reorder_children/4`:

```elixir
  @doc """
  Runs `fun` over `items` in order and stops at the first `{:error, _}`.
  Returns `:ok` when every call returned `:ok` or `{:ok, _}`. Opens no
  transaction — use inside `transaction/1` or an `Ecto.Multi.run/3` step when
  the calls must roll back together.
  """
  @spec each_ok(Enumerable.t(), (term() -> :ok | {:ok, term()} | {:error, term()})) ::
          :ok | {:error, term()}
  def each_ok(items, fun) when is_function(fun, 1) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      case fun.(item) do
        :ok -> {:cont, :ok}
        {:ok, _} -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end
```

- [ ] **Step 4: Adopt the four folds**

`accounts.ex` `seed_default_role_templates/1` tail:
```elixir
      defaults
      |> Enum.zip(templates)
      |> Repo.each_ok(fn {attrs, template} ->
        maybe_create_template_rate(template, main_currency, attrs.default_rate)
      end)
```
Delete `first_error/2` and its comment.

`templates.ex` `:epics_tasks` step: replace the `Enum.zip(new_epics) |> Enum.reduce_while({:ok, :done}, …)` with
```elixir
          with :ok <-
                 epics
                 |> Enum.zip(new_epics)
                 |> Repo.each_ok(fn {epic, new_epic} -> insert_template_tasks(epic.tasks, new_epic.id) end) do
            {:ok, :done}
          end
```

`import.ex` `insert_epics_and_tasks/2` `{:ok, epics}` branch:
```elixir
      {:ok, epics} ->
        with :ok <-
               epics
               |> Enum.zip(epics_data)
               |> Repo.each_ok(fn {epic, epic_data} -> insert_tasks(epic.id, epic_data.tasks) end) do
          {:ok, epics}
        end
```

`copy.ex` `copy_epics_with_estimates/3` / `copy_tasks_with_estimates/3`: same shape — `with :ok <- old |> Enum.zip(new) |> Repo.each_ok(fn {o, n} -> child_copier(...) end), do: {:ok, new}`.

- [ ] **Step 5: `Portfolio.create_project/4`**

Add the missing clause to the `case`:
```elixir
        {:error, :roles, changeset, _} ->
          {:error, changeset}
```

- [ ] **Step 6: Verify + precommit**

`grep -rn "first_error" lib` → empty. `grep -rn "reduce_while" lib/estimate | grep -v json_import | grep -v repo.ex` → empty. Run: `mix test test/estimate/repo_each_ok_test.exs test/estimate/portfolio test/estimate/accounts_test.exs test/estimate/estimation_engine_test.exs test/estimate_web/live/project_live/show_test.exs test/estimate_web/live/estimator_live/export_test.exs` then `mix precommit`.

- [ ] **Step 7: Commit**

```bash
git add lib/estimate/repo.ex lib/estimate/accounts.ex lib/estimate/templates.ex lib/estimate/estimation_engine/import.ex lib/estimate/estimation_engine/copy.ex lib/estimate/portfolio.ex test/estimate/repo_each_ok_test.exs test/estimate/portfolio/create_project_roles_test.exs
git commit -m "refactor(repo): Repo.each_ok/2 replaces the four first-error children folds; create_project surfaces role-copy failures

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: Estimator cleanups — Settings idiom, `filtered_epics` home, `refresh_editing` fallback, shared sort key (C2–C5)

**Files:**
- Modify: `lib/estimate_web/live/estimator_live/settings.ex` (`save_settings/2` roles loop, `delete_estimation_role/2`)
- Modify: `lib/estimate_web/live/estimator_live/rows.ex` (gains `filtered_epics/2`), `view_state.ex` (`defdelegate`), `grid.ex`, `export.ex` (call `Rows.filtered_epics/2`)
- Modify: `lib/estimate_web/live/estimator_live/grid.ex` (`upsert_task_rows_only/2` fallback)
- Modify: `test/support/estimator_live_helpers.ex` (+ `by_order/0`), `test/estimate_web/live/estimator_live/{epics,tasks,realtime}_test.exs`, `test/estimate/estimation_engine/estimations_current_test.exs`
- Modify: `test/estimate_web/live/estimator_live/sync_test.exs` (+ 1 test), `settings_test.exs` (+ 1 test)

**Interfaces:**
- Produces: `Rows.filtered_epics(estimation, MapSet.t()) :: [epic]` (moved verbatim; `ViewState.filtered_epics/2` becomes `defdelegate filtered_epics(estimation, enabled), to: Rows`); `EstimatorLiveHelpers.by_order/0 :: (map -> {integer, :calendar.datetime, binary})`.
- Consumes: `Authz.belongs_to_estimation?/3`, `Grid.reset/1`, `Rows.for_task/3`.

- [ ] **Step 1: Failing tests**

`settings_test.exs` — add after the existing foreign-role `save_settings` test:

```elixir
  test "save_settings resolves roles from the loaded estimation: a foreign-org role id is denied without a lookup", ctx do
    render_click(ctx.lv, "open_settings", %{})

    html =
      render_submit(ctx.lv, "save_settings", %{
        "name" => "Hijack",
        "currency_id" => ctx.est.currency_id,
        "roles" => %{Ecto.UUID.generate() => role_params(ctx.role, %{"name" => "PWNED"})}
      })

    assert html =~ "Could not update roles"
    assert Process.alive?(ctx.lv.pid)
    assert refetch(ctx.est, ctx.org).name == ctx.est.name
  end
```
(Today `get_role!/2` with an unknown id raises `Ecto.NoResultsError` and crashes the LV — this test fails RED.)

`sync_test.exs` — add:

```elixir
  test "editing a cell whose task is hidden by the priority filter resets the grid instead of no-op", ctx do
    render_click(ctx.lv, "edit_task", %{"id" => ctx.task2.id})
    render_submit(ctx.lv, "save_task", %{"task" => %{"name" => "T-two", "priority" => "wont"}})
    render_click(ctx.lv, "toggle_priority", %{"priority" => "wont"})
    refute render(ctx.lv) =~ ~s(id="task-#{ctx.task2.id}")

    # a stale client could still send an edit key for the hidden task
    render_click(ctx.lv, "edit_estimate", %{"key" => "#{ctx.task2.id}-#{ctx.role.id}"})
    html = render(ctx.lv)
    refute html =~ ~s(id="task-#{ctx.task2.id}")
    assert html =~ ~s(id="task-#{ctx.task1.id}")
    assert Process.alive?(ctx.lv.pid)
  end
```
(This characterizes the outcome — hidden row stays hidden, grid intact — and passes both before and after; keep it as the regression net. Verify it is not tautological by temporarily making `upsert_task_rows_only` append a bogus row; it must fail.)

- [ ] **Step 2: Run** — the settings test fails (crash); the sync test passes (expected — note it).

- [ ] **Step 3: Settings idiom**

In `save_settings/2` replace the roles fold:

```elixir
      roles_result =
        Repo.each_ok(roles_params, fn {role_id, role_attrs} ->
          case Enum.find(estimation.roles, &(&1.id == role_id)) do
            nil ->
              {:error, :unauthorized_role}

            role ->
              case EstimationEngine.update_role(role, %{
                     name: role_attrs["name"] || role.name,
                     abbreviation: role_attrs["abbreviation"] || role.abbreviation,
                     hourly_rate: parse_decimal(role_attrs["hourly_rate"]),
                     pm_overhead: parse_decimal(role_attrs["pm_overhead"]),
                     qa_overhead: parse_decimal(role_attrs["qa_overhead"]),
                     risk_buffer: parse_decimal(role_attrs["risk_buffer"])
                   }) do
                {:ok, _} -> :ok
                {:error, _} -> {:error, :role_update_failed}
              end
          end
        end)
```
(`alias Estimate.Repo` in the module; `org_id` may become unused — remove the binding if the compiler says so.)

`delete_estimation_role/2`:

```elixir
        role_id ->
          case Enum.find(socket.assigns.estimation.roles, &(&1.id == role_id)) do
            nil ->
              {:noreply, put_flash(socket, :error, "Not authorized")}

            role ->
              EstimationEngine.delete_role(role)

              {:noreply,
               socket
               |> reload_estimation()
               |> assign(:deleting_role_id, nil)
               |> put_flash(:info, "Role deleted")}
          end
```

- [ ] **Step 4: `filtered_epics` home**

Move the `filtered_epics/2` body (and its `@doc`) from `view_state.ex` to `rows.ex` as a public function; in `view_state.ex` leave `defdelegate filtered_epics(estimation, enabled_priorities), to: EstimateWeb.EstimatorLive.Rows`. In `rows.ex` remove `alias EstimateWeb.EstimatorLive.ViewState` and call `filtered_epics/2` directly. In `grid.ex` and `export.ex` change `ViewState.filtered_epics` → `Rows.filtered_epics` (adjust aliases; `ViewState` alias in `grid.ex` may become unused).

- [ ] **Step 5: `refresh_editing` fallback**

```elixir
  defp upsert_task_rows_only(socket, task_id) do
    case Rows.for_task(socket.assigns.estimation, Rows.view(socket.assigns), task_id) do
      [] -> reset(socket)
      rows -> Enum.reduce(rows, socket, &stream_insert(&2, :rows, &1))
    end
  end
```
Update `refresh_editing/3`'s `@doc`: "Falls back to `reset/1` for a task that is no longer visible."

- [ ] **Step 6: Shared sort key**

`test/support/estimator_live_helpers.ex`:
```elixir
  @doc "The read-side child order: position, then inserted_at (as an Erlang datetime tuple), then id."
  def by_order, do: &{&1.position, NaiveDateTime.to_erl(&1.inserted_at), &1.id}
```
Replace the four `&{&1.position, &1.inserted_at, &1.id}` lambdas (`epics_test.exs`, `tasks_test.exs`, `realtime_test.exs`, `estimations_current_test.exs` ×3) with `by_order()`; `estimations_current_test.exs` is a `DataCase` — add `import EstimateWeb.EstimatorLiveHelpers, only: [by_order: 0]`. Check `inserted_at` is a `NaiveDateTime` on these schemas (`grep -n timestamps lib/estimate/estimation_engine/epic.ex`); if it is `:utc_datetime`, use `DateTime.to_unix(&1.inserted_at)` instead.

- [ ] **Step 7: Covering tests + precommit**

Run: `mix test test/estimate_web/live/estimator_live test/estimate/estimation_engine/estimations_current_test.exs` then `mix precommit`. `grep -rn "get_role!" lib/estimate_web/live/estimator_live/` → empty. `grep -rn "ViewState.filtered_epics" lib` → only the `defdelegate`'s own module.

- [ ] **Step 8: Commit**

```bash
git add lib/estimate_web/live/estimator_live test/support/estimator_live_helpers.ex test/estimate_web/live/estimator_live test/estimate/estimation_engine/estimations_current_test.exs
git commit -m "refactor(estimator): Settings resolves roles in memory; filtered_epics lives in Rows; refresh_editing resets when hidden; shared test sort key

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: Templates LiveView — no client payload crashes the LV (4B carry-over)

**Files:**
- Modify: `lib/estimate_web/live/templates_live/show/epics.ex` (`delete_epic/2`), `show/tasks.ex` (`delete_task/2`, `add_task/2`)
- Modify: `test/estimate_web/live/templates_live/show_test.exs` (+ 3 tests)

**Interfaces:**
- Consumes: `Show.Authz.not_found/1`, `require_admin/2`.
- Produces (behaviour change): `delete_epic`/`delete_task` with `@deleting_* == nil` → `not_found` flash; `add_task` without `"epic-id"` → `not_found` flash.

- [ ] **Step 1: Failing tests**

Add to `show_test.exs` inside the module (fresh LV per test via `setup_template`, so the flash assertion is the first flashing event):

```elixir
  describe "no client payload crashes the LiveView (4C)" do
    test "delete_epic with nothing confirmed flashes Not found", ctx do
      assert assigns(ctx.lv).deleting_epic == nil
      assert render_click(ctx.lv, "delete_epic", %{}) =~ "Not found"
      assert Process.alive?(ctx.lv.pid)
      assert length(refetch(ctx.template, ctx.org).epics) == 1
    end

    test "delete_task with nothing confirmed flashes Not found", ctx do
      assert assigns(ctx.lv).deleting_task == nil
      assert render_click(ctx.lv, "delete_task", %{}) =~ "Not found"
      assert Process.alive?(ctx.lv.pid)
      [epic] = refetch(ctx.template, ctx.org).epics
      assert length(epic.tasks) == 2
    end

    test "add_task without an epic-id flashes Not found", ctx do
      assert render_click(ctx.lv, "add_task", %{}) =~ "Not found"
      assert assigns(ctx.lv).modal == nil
      assert Process.alive?(ctx.lv.pid)
    end
  end
```

- [ ] **Step 2: Run** — all three fail (the LV exits; the test process receives the EXIT or `render_click` errors).

- [ ] **Step 3: Implement**

`epics.ex` `delete_epic/2`:
```elixir
  def delete_epic(socket, _params) do
    require_admin(socket, fn ->
      case socket.assigns.deleting_epic do
        nil ->
          not_found(socket)

        epic ->
          case Templates.delete_template_epic(epic) do
            {:ok, _} ->
              {:noreply,
               socket |> assign(:deleting_epic, nil) |> reload_template() |> put_flash(:info, "Epic deleted")}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Could not delete epic")}
          end
      end
    end)
  end
```
`tasks.ex` `delete_task/2`: same shape on `deleting_task`. `tasks.ex` `add_task/2`: add a second clause `def add_task(socket, _params), do: require_admin(socket, fn -> not_found(socket) end)` after the `%{"epic-id" => epic_id}` clause.

- [ ] **Step 4: Covering tests + precommit** — `mix test test/estimate_web/live/templates_live` then `mix precommit`.

- [ ] **Step 5: Commit**

```bash
git add lib/estimate_web/live/templates_live/show/epics.ex lib/estimate_web/live/templates_live/show/tasks.ex test/estimate_web/live/templates_live/show_test.exs
git commit -m "fix(templates): delete without confirm and add_task without epic flash Not found instead of crashing the LiveView

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## Done criteria

- `grep -rn "validate_required(\[:name\])" lib` → only inside `ChangesetHelpers.validate_name/2`.
- `grep -rn "reduce_while" lib/estimate | grep -v json_import | grep -v repo.ex` → empty; `Accounts.first_error/2` gone.
- `grep -rn "get_role!" lib/estimate_web/live/estimator_live/` → empty.
- `ViewState.filtered_epics/2` is a `defdelegate` to `Rows`.
- Four new/edited test files green; full suite green; no migrations.

## Unresolved questions

None.
