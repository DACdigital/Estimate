# Audit Batch 3B — Estimator Decomposition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the 899-line god LiveView `EstimateWeb.EstimatorLive.Index` into focused handler modules with zero behaviour change, protected by a characterization suite written first.

**Architecture:** Mirror `EstimateWeb.ProjectLive.Show`: `Index` keeps `mount/3`, `render/1`, one-line `handle_event` delegations, `handle_info` and `handle_async` delegations; each feature cluster becomes a module under `lib/estimate_web/live/estimator_live/` using `use EstimateWeb, :live_handlers` with the contract `(socket, params) -> {:noreply, socket}`. Shared authorization/lookup helpers live in `EstimatorLive.Authz`. Templates and components are untouched. Tests come first (Task 1) and must stay green after every move.

**Tech Stack:** Elixir 1.18, Phoenix 1.8.3, Phoenix LiveView 1.1 (`Phoenix.LiveViewTest`), Ecto 3.13 / Postgres 17 with RLS, ExUnit.

**Spec:** `docs/superpowers/specs/2026-09-16-audit-batch-3-followups-decomposition-perf-design.md` — section "3B — estimator decomposition (behaviour-preserving)" (B1 characterization suite, B2 module map, B3 gates). Read it first.

## Global Constraints

- **Behaviour-preserving.** No new features, no changed copy, no changed assigns, no template edits except import lines. Every task ends with the whole estimator suite + `mix precommit` green.
- Tests never use `Process.sleep`. Characterization tests **diverge an assign from its mount default before asserting a handler sets it** (e.g. open a modal before testing `close_modal`).
- Handler modules: `use EstimateWeb, :live_handlers`; functions are `(socket, params) -> {:noreply, socket}`; a `@moduledoc` with `Reads:` / `Writes:` lines listing the assigns touched (see `EstimateWeb.ProjectLive.Show.Estimations` for the convention).
- `Index` keeps `@impl true` on the first clause of each callback group (`handle_event`, `handle_info`, `handle_async`).
- `mix precommit` (format, `--warnings-as-errors`, full suite) green before every commit. Commit trailer exactly `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- No migrations, no changes under `lib/estimate/` (contexts), no changes to `components/*.ex` or `helpers.ex`.
- Work on the batch branch (worktree via EnterWorktree, then `git reset --hard main`; copy `deps/`, `_build/`, `.env` from the main checkout). If `git commit` fails with "1Password: failed to fill whole buffer", stop and report; never retry in a loop.

## File structure after 3B

| File | Responsibility |
|---|---|
| `lib/estimate_web/live/estimator_live/index.ex` | `mount/3`, `render/1`, delegations, `handle_info` (full reload), `handle_async` delegations, `reload_estimation/1` (shared, public `@doc false` in `Authz` — see Task 2) |
| `lib/estimate_web/live/estimator_live/authz.ex` | `with_edit_auth/2`, `not_found/1`, `find_epic/2`, `find_task/2`, `belongs_to_estimation?/3`, `reload_estimation/1`, `display_roles/2` |
| `lib/estimate_web/live/estimator_live/epics.ex` | add/edit/save/confirm_delete/cancel_delete/delete/reorder epics |
| `lib/estimate_web/live/estimator_live/tasks.ex` | add/edit/validate/save/confirm_delete/cancel_delete/delete/reorder tasks |
| `lib/estimate_web/live/estimator_live/estimates.ex` | edit_estimate, save_estimate, cancel_edit, edit_rate, save_rate + in-memory updaters |
| `lib/estimate_web/live/estimator_live/settings.ex` | open_settings, save_settings, add_estimation_role, confirm/cancel/delete role, reorder_roles |
| `lib/estimate_web/live/estimator_live/view_state.ex` | toggle_breakdown / all_in_rates / descriptions / priority, restore_priorities, close_modal, `filtered_epics/2` |
| `lib/estimate_web/live/estimator_live/export.ex` | copy_json, open_save_as_template, save_as_template |
| `lib/estimate_web/live/estimator_live/ai.ex` | ai_enhance_description + the three `handle_async` bodies |
| `test/support/estimator_live_helpers.ex` | shared LV test setup for the estimator |
| `test/estimate_web/live/estimator_live/{mount,epics,tasks,estimates,settings,view_state,export,realtime}_test.exs` | characterization suite |

Existing `test/estimate_web/live/estimator_live/index_authz_test.exs` and `ai_enhance_test.exs` stay as they are.

---

### Task 1: Characterization suite (B1)

**Files:**
- Create: `test/support/estimator_live_helpers.ex`
- Create: `test/estimate_web/live/estimator_live/mount_test.exs`
- Create: `test/estimate_web/live/estimator_live/epics_test.exs`
- Create: `test/estimate_web/live/estimator_live/tasks_test.exs`
- Create: `test/estimate_web/live/estimator_live/estimates_test.exs`
- Create: `test/estimate_web/live/estimator_live/settings_test.exs`
- Create: `test/estimate_web/live/estimator_live/view_state_test.exs`
- Create: `test/estimate_web/live/estimator_live/export_test.exs`
- Create: `test/estimate_web/live/estimator_live/realtime_test.exs`

**Interfaces:**
- Consumes: the current `EstimateWeb.EstimatorLive.Index` (unchanged in this task); fixtures `Estimate.AccountsFixtures.{user_with_organization_fixture/0, user_fixture/0, membership_fixture/3}`, `Estimate.PortfolioFixtures.project_fixture/2`, `Estimate.EstimationEngineFixtures.{estimation_fixture/1, epic_fixture/2, task_fixture/2}`; `EstimateWeb.ConnCase.log_in_user/2`; `Estimate.Portfolio.add_collaborator/3`; `Estimate.EstimationEngine.get_estimation!/2`; `Estimate.Organizations.Currencies.create_currency/2` (string-keyed attrs); `Estimate.Templates.list_estimation_templates/1`.
- Produces: `EstimateWeb.EstimatorLiveHelpers` with `setup_estimator/1` (ExUnit setup callback), `assigns/1`, `estimator_path/3`, `refetch/2`; the eight test files that every later task must keep green.

These tests describe **today's** behaviour. If a test fails against the unmodified `Index`, the test is wrong (or you found a real bug — then report it as a concern; do not "fix" the LV in this task).

- [ ] **Step 1: Create the shared helper**

`test/support/estimator_live_helpers.ex`:

```elixir
defmodule EstimateWeb.EstimatorLiveHelpers do
  @moduledoc """
  Shared setup for EstimatorLive characterization tests.

  `setup_estimator/1` builds: org + owner, one project, one estimation with
  the default roles, one epic with two tasks, and mounts the estimator as
  the owner. Returns everything a test needs to drive handlers directly.
  """
  import Phoenix.LiveViewTest
  import Phoenix.ConnTest, only: [build_conn: 0]
  import Estimate.{AccountsFixtures, PortfolioFixtures, EstimationEngineFixtures}

  alias Estimate.EstimationEngine

  @endpoint EstimateWeb.Endpoint

  def assigns(lv), do: :sys.get_state(lv.pid).socket.assigns

  def estimator_path(org, project, estimation),
    do: "/org/#{org.id}/projects/#{project.id}/estimations/#{estimation.id}/estimator"

  @doc "Re-reads the estimation with roles/epics/tasks/estimates preloaded."
  def refetch(estimation, org), do: EstimationEngine.get_estimation!(estimation.id, org.id)

  def setup_estimator(%{conn: conn}) do
    %{user: owner, organization: org} = user_with_organization_fixture()
    project = project_fixture(nil, owner)
    est = estimation_fixture(project)
    epic = epic_fixture(est, %{name: "Alpha"})
    task1 = task_fixture(epic, %{name: "T-one"})
    task2 = task_fixture(epic, %{name: "T-two"})
    est = refetch(est, org)

    conn = EstimateWeb.ConnCase.log_in_user(conn, owner)
    {:ok, lv, _html} = live(conn, estimator_path(org, project, est))

    %{
      conn: conn,
      org: org,
      owner: owner,
      project: project,
      est: est,
      epic: epic,
      task1: task1,
      task2: task2,
      role: hd(est.roles),
      lv: lv
    }
  end

  @doc "A second project/estimation in the same org, owned by `owner`; returns preloaded estimation."
  def other_estimation(owner, org) do
    other_project = project_fixture(nil, owner)
    other_estimation = estimation_fixture(other_project)
    other_epic = epic_fixture(other_estimation, %{name: "Other-Epic"})
    other_task = task_fixture(other_epic, %{name: "Other-Task"})
    %{estimation: refetch(other_estimation, org), epic: other_epic, task: other_task}
  end

  @doc "Mounts the same estimator as a fresh org member with the given collaborator role (or no collaborator row when role is nil)."
  def mount_as(role, %{org: org, project: project, est: est}) do
    user = user_fixture()
    _ = membership_fixture(user, org, "member")
    if role, do: {:ok, _} = Estimate.Portfolio.add_collaborator(project.id, user.id, role)
    conn = EstimateWeb.ConnCase.log_in_user(build_conn(), user)
    {user, live(conn, estimator_path(org, project, est))}
  end
end
```

Check `test/test_helper.exs`/`mix.exs` already compiles `test/support` (it does — `elixirc_paths(:test)` includes `test/support`).

- [ ] **Step 2: Mount perimeter tests**

`test/estimate_web/live/estimator_live/mount_test.exs`:

```elixir
defmodule EstimateWeb.EstimatorLive.MountTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ExUnit.CaptureLog
  import EstimateWeb.EstimatorLiveHelpers
  import Estimate.AccountsFixtures

  setup :setup_estimator

  test "owner mounts with can_edit and full default view state", ctx do
    a = assigns(ctx.lv)
    assert a.can_edit
    assert a.estimation.id == ctx.est.id
    assert a.project.id == ctx.project.id
    assert a.page_title == "Estimator - #{ctx.est.name}"
    assert a.active_tab == :projects
    assert a.modal == nil and a.editing == nil and a.editing_rate == nil
    assert a.epic_form == nil and a.task_form == nil and a.current_epic_id == nil
    assert a.deleting_epic == nil and a.deleting_task == nil and a.deleting_role_id == nil
    refute a.show_breakdown or a.show_all_in_rates or a.show_descriptions
    assert a.enabled_priorities == MapSet.new(["must", "should", "could", "wont"])
    assert a.ai_loading == nil
    refute a.ai_configured
  end

  test "editor collaborator can edit; viewer cannot", ctx do
    {_u, {:ok, editor_lv, _}} = mount_as("editor", ctx)
    assert assigns(editor_lv).can_edit

    {_u, {:ok, viewer_lv, _}} = mount_as("viewer", ctx)
    refute assigns(viewer_lv).can_edit
  end

  test "org admin who is not a collaborator can edit", ctx do
    admin = user_fixture()
    _ = membership_fixture(admin, ctx.org, "admin")
    {:ok, lv, _} = live(log_in_user(build_conn(), admin), estimator_path(ctx.org, ctx.project, ctx.est))
    assert assigns(lv).can_edit
  end

  test "org member who is not a collaborator is redirected with a flash", ctx do
    {_u, result} = mount_as(nil, ctx)
    assert {:error, {:redirect, %{to: to, flash: flash}}} = result
    assert to == "/org/#{ctx.org.id}/projects"
    assert flash["error"] == "You don't have access to this project."
  end

  test "an estimation from another project under this project's URL raises NoResultsError", ctx do
    %{estimation: other} = other_estimation(ctx.owner, ctx.org)

    # the LV process crashes by design; capture its crash report so test output stays pristine
    capture_log(fn ->
      assert_raise Ecto.NoResultsError, fn ->
        live(ctx.conn, estimator_path(ctx.org, ctx.project, other))
      end
    end)
  end

  test "mount renders the seeded epic and tasks", ctx do
    html = render(ctx.lv)
    assert html =~ "Alpha"
    assert html =~ "T-one"
    assert html =~ "T-two"
  end
end
```

- [ ] **Step 3: Epics tests**

`test/estimate_web/live/estimator_live/epics_test.exs`:

```elixir
defmodule EstimateWeb.EstimatorLive.EpicsTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import EstimateWeb.EstimatorLiveHelpers

  alias Estimate.Repo
  alias Estimate.EstimationEngine.Epic

  setup :setup_estimator

  test "add_epic opens the epic modal with an empty form", ctx do
    render_click(ctx.lv, "add_epic", %{})
    a = assigns(ctx.lv)
    assert a.modal == :epic
    assert a.epic_form.data.id == nil
    assert render(ctx.lv) =~ ~s(id="epic-form")
  end

  test "edit_epic opens the modal with the epic loaded", ctx do
    render_click(ctx.lv, "edit_epic", %{"id" => ctx.epic.id})
    a = assigns(ctx.lv)
    assert a.modal == :epic
    assert a.epic_form.data.id == ctx.epic.id
  end

  test "save_epic creates a new epic, reloads and closes the modal", ctx do
    render_click(ctx.lv, "add_epic", %{})
    render_submit(ctx.lv, "save_epic", %{"epic" => %{"name" => "Beta"}})
    a = assigns(ctx.lv)
    assert a.modal == nil and a.epic_form == nil
    assert Enum.map(a.estimation.epics, & &1.name) == ["Alpha", "Beta"]
    assert Repo.get_by(Epic, estimation_id: ctx.est.id, name: "Beta")
  end

  test "save_epic updates an existing epic", ctx do
    render_click(ctx.lv, "edit_epic", %{"id" => ctx.epic.id})
    render_submit(ctx.lv, "save_epic", %{"epic" => %{"name" => "Alpha-2"}})
    assert Repo.get!(Epic, ctx.epic.id).name == "Alpha-2"
    assert assigns(ctx.lv).modal == nil
  end

  test "save_epic with an invalid name keeps the modal open with errors", ctx do
    render_click(ctx.lv, "add_epic", %{})
    render_submit(ctx.lv, "save_epic", %{"epic" => %{"name" => ""}})
    a = assigns(ctx.lv)
    assert a.modal == :epic
    assert a.epic_form.errors[:name]
    refute Repo.get_by(Epic, estimation_id: ctx.est.id, name: "")
  end

  test "confirm_delete_epic / cancel_delete_epic toggle deleting_epic", ctx do
    render_click(ctx.lv, "confirm_delete_epic", %{"id" => ctx.epic.id})
    assert assigns(ctx.lv).deleting_epic.id == ctx.epic.id
    assert render(ctx.lv) =~ ~s(id="delete-epic-modal")

    render_click(ctx.lv, "cancel_delete_epic", %{})
    assert assigns(ctx.lv).deleting_epic == nil
  end

  test "delete_epic deletes the confirmed epic and reloads", ctx do
    render_click(ctx.lv, "confirm_delete_epic", %{"id" => ctx.epic.id})
    render_click(ctx.lv, "delete_epic", %{})
    a = assigns(ctx.lv)
    assert a.deleting_epic == nil
    assert a.estimation.epics == []
    refute Repo.get(Epic, ctx.epic.id)
  end

  test "delete_epic with nothing confirmed is a no-op", ctx do
    render_click(ctx.lv, "delete_epic", %{})
    assert Repo.get(Epic, ctx.epic.id)
  end

  test "reorder_epics persists the new order and reloads", ctx do
    render_click(ctx.lv, "add_epic", %{})
    render_submit(ctx.lv, "save_epic", %{"epic" => %{"name" => "Beta"}})
    [alpha, beta] = assigns(ctx.lv).estimation.epics

    render_click(ctx.lv, "reorder_epics", %{"ids" => [beta.id, alpha.id]})
    assert Enum.map(assigns(ctx.lv).estimation.epics, & &1.name) == ["Beta", "Alpha"]
    assert Enum.map(refetch(ctx.est, ctx.org).epics, & &1.name) == ["Beta", "Alpha"]
  end

  describe "viewer" do
    setup ctx do
      {_u, {:ok, lv, _}} = mount_as("viewer", ctx)
      %{vlv: lv}
    end

    test "add_epic, edit_epic, save_epic, delete_epic, reorder_epics are denied", ctx do
      for {event, params} <- [
            {"add_epic", %{}},
            {"edit_epic", %{"id" => ctx.epic.id}},
            {"save_epic", %{"epic" => %{"name" => "X"}}},
            {"confirm_delete_epic", %{"id" => ctx.epic.id}},
            {"delete_epic", %{}},
            {"reorder_epics", %{"ids" => [ctx.epic.id]}}
          ] do
        html = render_click(ctx.vlv, event, params)
        assert html =~ "You don&#39;t have edit access", event
      end

      a = assigns(ctx.vlv)
      assert a.modal == nil and a.epic_form == nil and a.deleting_epic == nil
      assert Repo.get(Epic, ctx.epic.id)
    end
  end
end
```

- [ ] **Step 4: Tasks tests**

`test/estimate_web/live/estimator_live/tasks_test.exs`:

```elixir
defmodule EstimateWeb.EstimatorLive.TasksTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import EstimateWeb.EstimatorLiveHelpers

  alias Estimate.Repo
  alias Estimate.EstimationEngine.Task

  setup :setup_estimator

  test "add_task opens the task modal bound to the epic", ctx do
    render_click(ctx.lv, "add_task", %{"epic-id" => ctx.epic.id})
    a = assigns(ctx.lv)
    assert a.modal == :task
    assert a.task_form.data.id == nil
    assert a.current_epic_id == ctx.epic.id
    assert render(ctx.lv) =~ ~s(id="task-form")
  end

  test "edit_task opens the modal with the task loaded", ctx do
    render_click(ctx.lv, "edit_task", %{"id" => ctx.task1.id})
    a = assigns(ctx.lv)
    assert a.modal == :task
    assert a.task_form.data.id == ctx.task1.id
    assert a.current_epic_id == ctx.epic.id
  end

  test "validate_task marks the form as validated with errors", ctx do
    render_click(ctx.lv, "add_task", %{"epic-id" => ctx.epic.id})
    render_change(ctx.lv, "validate_task", %{"task" => %{"name" => ""}})
    form = assigns(ctx.lv).task_form
    assert form.source.action == :validate
    assert form.errors[:name]
  end

  test "save_task creates a task under the current epic and closes the modal", ctx do
    render_click(ctx.lv, "add_task", %{"epic-id" => ctx.epic.id})
    render_submit(ctx.lv, "save_task", %{"task" => %{"name" => "T-three", "priority" => "should"}})
    a = assigns(ctx.lv)
    assert a.modal == nil and a.task_form == nil and a.current_epic_id == nil
    assert Enum.map(hd(a.estimation.epics).tasks, & &1.name) == ["T-one", "T-two", "T-three"]
    assert Repo.get_by(Task, epic_id: ctx.epic.id, name: "T-three")
  end

  test "save_task updates an existing task", ctx do
    render_click(ctx.lv, "edit_task", %{"id" => ctx.task1.id})
    render_submit(ctx.lv, "save_task", %{"task" => %{"name" => "T-one-renamed"}})
    assert Repo.get!(Task, ctx.task1.id).name == "T-one-renamed"
    assert assigns(ctx.lv).modal == nil
  end

  test "save_task with an invalid name keeps the modal open with errors", ctx do
    render_click(ctx.lv, "add_task", %{"epic-id" => ctx.epic.id})
    render_submit(ctx.lv, "save_task", %{"task" => %{"name" => ""}})
    a = assigns(ctx.lv)
    assert a.modal == :task
    assert a.task_form.errors[:name]
  end

  test "save_task for a new task without a current epic flashes Not found", ctx do
    # diverge: open the form, then drop the epic binding the way close_modal would
    render_click(ctx.lv, "add_task", %{"epic-id" => ctx.epic.id})
    :sys.replace_state(ctx.lv.pid, fn state ->
      put_in(state.socket.assigns.current_epic_id, nil)
    end)

    html = render_submit(ctx.lv, "save_task", %{"task" => %{"name" => "Orphan"}})
    assert html =~ "Not found"
    refute Repo.get_by(Task, name: "Orphan")
  end

  test "confirm_delete_task / cancel_delete_task toggle deleting_task", ctx do
    render_click(ctx.lv, "confirm_delete_task", %{"id" => ctx.task2.id})
    assert assigns(ctx.lv).deleting_task.id == ctx.task2.id
    assert render(ctx.lv) =~ ~s(id="delete-task-modal")

    render_click(ctx.lv, "cancel_delete_task", %{})
    assert assigns(ctx.lv).deleting_task == nil
  end

  test "delete_task deletes the confirmed task and reloads", ctx do
    render_click(ctx.lv, "confirm_delete_task", %{"id" => ctx.task2.id})
    render_click(ctx.lv, "delete_task", %{})
    a = assigns(ctx.lv)
    assert a.deleting_task == nil
    assert Enum.map(hd(a.estimation.epics).tasks, & &1.name) == ["T-one"]
    refute Repo.get(Task, ctx.task2.id)
  end

  test "delete_task with nothing confirmed is a no-op", ctx do
    render_click(ctx.lv, "delete_task", %{})
    assert Repo.get(Task, ctx.task2.id)
  end

  test "reorder_tasks persists the new order within the epic", ctx do
    render_click(ctx.lv, "reorder_tasks", %{
      "epic_id" => ctx.epic.id,
      "ids" => [ctx.task2.id, ctx.task1.id]
    })

    assert Enum.map(hd(assigns(ctx.lv).estimation.epics).tasks, & &1.name) == ["T-two", "T-one"]
    assert Enum.map(hd(refetch(ctx.est, ctx.org).epics).tasks, & &1.name) == ["T-two", "T-one"]
  end

  test "reorder_tasks for an epic outside this estimation is ignored", ctx do
    %{epic: other_epic, task: other_task} = other_estimation(ctx.owner, ctx.org)
    before = Repo.get!(Task, other_task.id).position

    render_click(ctx.lv, "reorder_tasks", %{"epic_id" => other_epic.id, "ids" => [other_task.id]})
    assert Repo.get!(Task, other_task.id).position == before
  end

  describe "viewer" do
    setup ctx do
      {_u, {:ok, lv, _}} = mount_as("viewer", ctx)
      %{vlv: lv}
    end

    test "mutating task events are denied", ctx do
      for {event, params} <- [
            {"add_task", %{"epic-id" => ctx.epic.id}},
            {"edit_task", %{"id" => ctx.task1.id}},
            {"save_task", %{"task" => %{"name" => "X"}}},
            {"confirm_delete_task", %{"id" => ctx.task1.id}},
            {"delete_task", %{}},
            {"reorder_tasks", %{"epic_id" => ctx.epic.id, "ids" => [ctx.task2.id, ctx.task1.id]}}
          ] do
        html = render_click(ctx.vlv, event, params)
        assert html =~ "You don&#39;t have edit access", event
      end

      assert assigns(ctx.vlv).modal == nil
      assert Enum.map(hd(refetch(ctx.est, ctx.org).epics).tasks, & &1.name) == ["T-one", "T-two"]
    end
  end
end
```

- [ ] **Step 5: Estimates (cells + rates) tests**

`test/estimate_web/live/estimator_live/estimates_test.exs`:

```elixir
defmodule EstimateWeb.EstimatorLive.EstimatesTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import EstimateWeb.EstimatorLiveHelpers

  alias Estimate.EstimationEngine

  setup :setup_estimator

  defp hours_for(estimation, task_id, role_id) do
    estimation.epics
    |> Enum.flat_map(& &1.tasks)
    |> Enum.find(&(&1.id == task_id))
    |> Map.fetch!(:estimates)
    |> Enum.find(&(&1.role_id == role_id))
    |> case do
      nil -> nil
      est -> est.hours
    end
  end

  test "edit_estimate sets the editing key and renders the input", ctx do
    key = "#{ctx.task1.id}-#{ctx.role.id}"
    render_click(ctx.lv, "edit_estimate", %{"key" => key})
    assert assigns(ctx.lv).editing == key
    assert render(ctx.lv) =~ ~s(id="hours-#{key}")
  end

  test "cancel_edit clears editing and editing_rate", ctx do
    render_click(ctx.lv, "edit_estimate", %{"key" => "#{ctx.task1.id}-#{ctx.role.id}"})
    render_click(ctx.lv, "edit_rate", %{"role-id" => ctx.role.id})
    assert assigns(ctx.lv).editing != nil and assigns(ctx.lv).editing_rate != nil

    render_click(ctx.lv, "cancel_edit", %{})
    a = assigns(ctx.lv)
    assert a.editing == nil and a.editing_rate == nil
  end

  test "save_estimate upserts hours in the DB and in memory without a reload", ctx do
    render_click(ctx.lv, "edit_estimate", %{"key" => "#{ctx.task1.id}-#{ctx.role.id}"})

    render_click(ctx.lv, "save_estimate", %{
      "task-id" => ctx.task1.id,
      "role-id" => ctx.role.id,
      "value" => "12.5"
    })

    a = assigns(ctx.lv)
    assert a.editing == nil
    assert Decimal.equal?(hours_for(a.estimation, ctx.task1.id, ctx.role.id), Decimal.new("12.5"))
    assert Decimal.equal?(hours_for(refetch(ctx.est, ctx.org), ctx.task1.id, ctx.role.id), Decimal.new("12.5"))

    # second save on the same cell replaces, not appends
    render_click(ctx.lv, "save_estimate", %{
      "task-id" => ctx.task1.id,
      "role-id" => ctx.role.id,
      "value" => "3"
    })

    a = assigns(ctx.lv)
    task = a.estimation.epics |> hd() |> Map.fetch!(:tasks) |> Enum.find(&(&1.id == ctx.task1.id))
    assert Enum.count(task.estimates, &(&1.role_id == ctx.role.id)) == 1
    assert Decimal.equal?(hours_for(a.estimation, ctx.task1.id, ctx.role.id), Decimal.new(3))
  end

  test "save_estimate for a task or role outside this estimation is ignored", ctx do
    %{estimation: other, task: other_task} = other_estimation(ctx.owner, ctx.org)
    other_role = hd(other.roles)

    render_click(ctx.lv, "save_estimate", %{
      "task-id" => other_task.id,
      "role-id" => ctx.role.id,
      "value" => "9"
    })

    render_click(ctx.lv, "save_estimate", %{
      "task-id" => ctx.task1.id,
      "role-id" => other_role.id,
      "value" => "9"
    })

    assert assigns(ctx.lv).editing == nil
    assert hours_for(refetch(other, ctx.org), other_task.id, ctx.role.id) == nil
    assert hours_for(refetch(ctx.est, ctx.org), ctx.task1.id, other_role.id) == nil
  end

  test "edit_rate sets editing_rate and renders the rate input", ctx do
    render_click(ctx.lv, "edit_rate", %{"role-id" => ctx.role.id})
    assert assigns(ctx.lv).editing_rate == ctx.role.id
    assert render(ctx.lv) =~ ~s(id="rate-#{ctx.role.id}")
  end

  test "save_rate updates the role in the DB and in memory", ctx do
    render_click(ctx.lv, "edit_rate", %{"role-id" => ctx.role.id})
    render_click(ctx.lv, "save_rate", %{"role-id" => ctx.role.id, "value" => "150"})

    a = assigns(ctx.lv)
    assert a.editing_rate == nil
    in_memory = Enum.find(a.estimation.roles, &(&1.id == ctx.role.id))
    assert Decimal.equal?(in_memory.hourly_rate, Decimal.new(150))
    assert Decimal.equal?(EstimationEngine.get_role!(ctx.role.id, ctx.org.id).hourly_rate, Decimal.new(150))
  end

  test "save_rate for a role outside this estimation is ignored", ctx do
    %{estimation: other} = other_estimation(ctx.owner, ctx.org)
    other_role = hd(other.roles)
    before = EstimationEngine.get_role!(other_role.id, ctx.org.id).hourly_rate

    render_click(ctx.lv, "save_rate", %{"role-id" => other_role.id, "value" => "999"})
    assert assigns(ctx.lv).editing_rate == nil
    assert Decimal.equal?(EstimationEngine.get_role!(other_role.id, ctx.org.id).hourly_rate, before)
  end

  describe "viewer" do
    setup ctx do
      {_u, {:ok, lv, _}} = mount_as("viewer", ctx)
      %{vlv: lv}
    end

    test "save_estimate and save_rate are denied; edit_estimate still only toggles state", ctx do
      html =
        render_click(ctx.vlv, "save_estimate", %{
          "task-id" => ctx.task1.id,
          "role-id" => ctx.role.id,
          "value" => "5"
        })

      assert html =~ "You don&#39;t have edit access"
      assert hours_for(refetch(ctx.est, ctx.org), ctx.task1.id, ctx.role.id) == nil

      html = render_click(ctx.vlv, "save_rate", %{"role-id" => ctx.role.id, "value" => "5"})
      assert html =~ "You don&#39;t have edit access"
    end
  end
end
```

- [ ] **Step 6: Settings (settings modal + roles) tests**

`test/estimate_web/live/estimator_live/settings_test.exs`:

```elixir
defmodule EstimateWeb.EstimatorLive.SettingsTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import EstimateWeb.EstimatorLiveHelpers

  alias Estimate.EstimationEngine
  alias Estimate.Organizations.Currencies

  setup :setup_estimator

  defp role_params(role, overrides) do
    Map.merge(
      %{
        "name" => role.name,
        "abbreviation" => role.abbreviation,
        "hourly_rate" => "100",
        "pm_overhead" => "10",
        "qa_overhead" => "5",
        "risk_buffer" => "0"
      },
      overrides
    )
  end

  test "open_settings opens the settings modal", ctx do
    render_click(ctx.lv, "open_settings", %{})
    assert assigns(ctx.lv).modal == :settings
    assert render(ctx.lv) =~ ~s(id="settings-form")
  end

  test "save_settings updates name, currency and roles, then closes the modal", ctx do
    {:ok, eur} = Currencies.create_currency(ctx.org.id, %{"code" => "EUR", "name" => "Euro", "symbol" => "€"})
    render_click(ctx.lv, "open_settings", %{})

    html =
      render_submit(ctx.lv, "save_settings", %{
        "name" => "Renamed",
        "currency_id" => eur.id,
        "roles" => %{ctx.role.id => role_params(ctx.role, %{"name" => "Lead Dev", "hourly_rate" => "200"})}
      })

    assert html =~ "Settings saved"
    a = assigns(ctx.lv)
    assert a.modal == nil
    assert a.estimation.name == "Renamed"
    assert a.estimation.currency_id == eur.id
    role = Enum.find(a.estimation.roles, &(&1.id == ctx.role.id))
    assert role.name == "Lead Dev"
    assert Decimal.equal?(role.hourly_rate, Decimal.new(200))
    assert Decimal.equal?(role.pm_overhead, Decimal.new(10))
  end

  test "save_settings with a role from another estimation flashes and changes nothing", ctx do
    %{estimation: other} = other_estimation(ctx.owner, ctx.org)
    other_role = hd(other.roles)
    render_click(ctx.lv, "open_settings", %{})

    html =
      render_submit(ctx.lv, "save_settings", %{
        "name" => "Hijack",
        "currency_id" => ctx.est.currency_id,
        "roles" => %{other_role.id => role_params(other_role, %{"name" => "PWNED"})}
      })

    assert html =~ "Could not update roles"
    assert assigns(ctx.lv).modal == :settings
    assert EstimationEngine.get_role!(other_role.id, ctx.org.id).name == other_role.name
    assert refetch(ctx.est, ctx.org).name == ctx.est.name
  end

  test "save_settings with an invalid estimation name flashes Could not save settings", ctx do
    render_click(ctx.lv, "open_settings", %{})

    html =
      render_submit(ctx.lv, "save_settings", %{
        "name" => "",
        "currency_id" => ctx.est.currency_id,
        "roles" => %{}
      })

    assert html =~ "Could not save settings"
    assert assigns(ctx.lv).modal == :settings
    assert refetch(ctx.est, ctx.org).name == ctx.est.name
  end

  test "add_estimation_role appends a zero-rate role with upcased abbreviation", ctx do
    before = length(ctx.est.roles)
    render_click(ctx.lv, "open_settings", %{})

    html =
      render_submit(ctx.lv, "add_estimation_role", %{"new_role_name" => "Designer", "new_role_abbr" => "ux"})

    assert html =~ "Role added"
    roles = assigns(ctx.lv).estimation.roles
    assert length(roles) == before + 1
    new_role = List.last(roles)
    assert new_role.name == "Designer" and new_role.abbreviation == "UX"
    assert new_role.position == before
    assert Decimal.equal?(new_role.hourly_rate, Decimal.new(0))
  end

  test "add_estimation_role with an empty name or abbreviation is a no-op", ctx do
    before = length(ctx.est.roles)
    render_submit(ctx.lv, "add_estimation_role", %{"new_role_name" => "", "new_role_abbr" => "X"})
    render_submit(ctx.lv, "add_estimation_role", %{"new_role_name" => "X", "new_role_abbr" => ""})
    assert length(refetch(ctx.est, ctx.org).roles) == before
  end

  test "confirm_delete_role / cancel_delete_role toggle deleting_role_id", ctx do
    render_click(ctx.lv, "confirm_delete_role", %{"id" => ctx.role.id})
    assert assigns(ctx.lv).deleting_role_id == ctx.role.id

    render_click(ctx.lv, "cancel_delete_role", %{})
    assert assigns(ctx.lv).deleting_role_id == nil
  end

  test "delete_estimation_role deletes the confirmed role and reloads", ctx do
    before = length(ctx.est.roles)
    render_click(ctx.lv, "confirm_delete_role", %{"id" => ctx.role.id})
    html = render_click(ctx.lv, "delete_estimation_role", %{})

    assert html =~ "Role deleted"
    a = assigns(ctx.lv)
    assert a.deleting_role_id == nil
    assert length(a.estimation.roles) == before - 1
    refute Enum.any?(a.estimation.roles, &(&1.id == ctx.role.id))
  end

  test "delete_estimation_role with nothing confirmed is a no-op", ctx do
    before = length(ctx.est.roles)
    render_click(ctx.lv, "delete_estimation_role", %{})
    assert length(refetch(ctx.est, ctx.org).roles) == before
  end

  test "delete_estimation_role for a role from another estimation flashes Not authorized", ctx do
    %{estimation: other} = other_estimation(ctx.owner, ctx.org)
    other_role = hd(other.roles)
    render_click(ctx.lv, "confirm_delete_role", %{"id" => other_role.id})

    html = render_click(ctx.lv, "delete_estimation_role", %{})
    assert html =~ "Not authorized"
    assert EstimationEngine.get_role!(other_role.id, ctx.org.id)
  end

  test "reorder_roles persists the order (no in-memory reload; the broadcast does it)", ctx do
    [r1, r2 | rest] = ctx.est.roles
    ids = Enum.map([r2, r1 | rest], & &1.id)

    render_click(ctx.lv, "reorder_roles", %{"ids" => ids})
    assert Enum.map(refetch(ctx.est, ctx.org).roles, & &1.id) == ids
    # the LV's own broadcast reaches it and reloads
    render(ctx.lv)
    assert Enum.map(assigns(ctx.lv).estimation.roles, & &1.id) == ids
  end

  describe "viewer" do
    setup ctx do
      {_u, {:ok, lv, _}} = mount_as("viewer", ctx)
      %{vlv: lv}
    end

    test "settings and role mutations are denied", ctx do
      for {event, params} <- [
            {"open_settings", %{}},
            {"save_settings", %{"name" => "X", "currency_id" => ctx.est.currency_id, "roles" => %{}}},
            {"add_estimation_role", %{"new_role_name" => "N", "new_role_abbr" => "N"}},
            {"confirm_delete_role", %{"id" => ctx.role.id}},
            {"delete_estimation_role", %{}},
            {"reorder_roles", %{"ids" => Enum.map(ctx.est.roles, & &1.id)}}
          ] do
        html = render_click(ctx.vlv, event, params)
        assert html =~ "You don&#39;t have edit access", event
      end

      assert assigns(ctx.vlv).modal == nil
      assert refetch(ctx.est, ctx.org).name == ctx.est.name
    end
  end
end
```

- [ ] **Step 7: View-state tests**

`test/estimate_web/live/estimator_live/view_state_test.exs`:

```elixir
defmodule EstimateWeb.EstimatorLive.ViewStateTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import EstimateWeb.EstimatorLiveHelpers

  setup :setup_estimator

  test "toggle_breakdown, toggle_all_in_rates, toggle_descriptions flip their flags", ctx do
    for {event, key} <- [
          {"toggle_breakdown", :show_breakdown},
          {"toggle_all_in_rates", :show_all_in_rates},
          {"toggle_descriptions", :show_descriptions}
        ] do
      refute Map.fetch!(assigns(ctx.lv), key)
      render_click(ctx.lv, event, %{})
      assert Map.fetch!(assigns(ctx.lv), key), event
      render_click(ctx.lv, event, %{})
      refute Map.fetch!(assigns(ctx.lv), key), event
    end
  end

  test "toggle_descriptions shows task descriptions in the grid", ctx do
    render_click(ctx.lv, "edit_task", %{"id" => ctx.task1.id})
    render_submit(ctx.lv, "save_task", %{"task" => %{"name" => "T-one", "description" => "hidden-until-toggled"}})
    refute render(ctx.lv) =~ "hidden-until-toggled"

    render_click(ctx.lv, "toggle_descriptions", %{})
    assert render(ctx.lv) =~ "hidden-until-toggled"
  end

  test "toggle_priority removes and re-adds a priority and pushes save_priorities", ctx do
    render_click(ctx.lv, "toggle_priority", %{"priority" => "wont"})
    assert assigns(ctx.lv).enabled_priorities == MapSet.new(["must", "should", "could"])
    assert_push_event(ctx.lv, "save_priorities", %{priorities: list})
    assert Enum.sort(list) == ["could", "must", "should"]

    render_click(ctx.lv, "toggle_priority", %{"priority" => "wont"})
    assert assigns(ctx.lv).enabled_priorities == MapSet.new(["must", "should", "could", "wont"])
  end

  test "toggle_priority never removes the last enabled priority", ctx do
    for p <- ["should", "could", "wont"], do: render_click(ctx.lv, "toggle_priority", %{"priority" => p})
    assert assigns(ctx.lv).enabled_priorities == MapSet.new(["must"])

    render_click(ctx.lv, "toggle_priority", %{"priority" => "must"})
    assert assigns(ctx.lv).enabled_priorities == MapSet.new(["must"])
  end

  test "priority filter hides tasks (and empty epics) from the grid", ctx do
    render_click(ctx.lv, "edit_task", %{"id" => ctx.task2.id})
    render_submit(ctx.lv, "save_task", %{"task" => %{"name" => "T-two", "priority" => "wont"}})
    assert render(ctx.lv) =~ "T-two"

    render_click(ctx.lv, "toggle_priority", %{"priority" => "wont"})
    html = render(ctx.lv)
    assert html =~ "T-one"
    refute html =~ "T-two"

    # hide everything else too -> the epic disappears with its last visible task
    for p <- ["should", "could"], do: render_click(ctx.lv, "toggle_priority", %{"priority" => p})
    render_click(ctx.lv, "toggle_priority", %{"priority" => "wont"})
    render_click(ctx.lv, "toggle_priority", %{"priority" => "must"})
    assert assigns(ctx.lv).enabled_priorities == MapSet.new(["wont"])
    html = render(ctx.lv)
    assert html =~ "T-two"
    refute html =~ "T-one"
  end

  test "restore_priorities applies a valid subset and ignores unknown or empty input", ctx do
    render_click(ctx.lv, "restore_priorities", %{"priorities" => ["must", "bogus"]})
    assert assigns(ctx.lv).enabled_priorities == MapSet.new(["must"])

    render_click(ctx.lv, "restore_priorities", %{"priorities" => ["bogus"]})
    assert assigns(ctx.lv).enabled_priorities == MapSet.new(["must"])

    render_click(ctx.lv, "restore_priorities", %{"priorities" => ["could", "wont"]})
    assert assigns(ctx.lv).enabled_priorities == MapSet.new(["could", "wont"])
  end

  test "close_modal clears modal, forms and current epic", ctx do
    render_click(ctx.lv, "add_task", %{"epic-id" => ctx.epic.id})
    a = assigns(ctx.lv)
    assert a.modal == :task and a.task_form != nil and a.current_epic_id != nil

    render_click(ctx.lv, "close_modal", %{})
    a = assigns(ctx.lv)
    assert a.modal == nil and a.epic_form == nil and a.task_form == nil and a.current_epic_id == nil
  end

  test "viewer can use every view-state toggle", ctx do
    {_u, {:ok, vlv, _}} = mount_as("viewer", ctx)
    render_click(vlv, "toggle_breakdown", %{})
    render_click(vlv, "toggle_all_in_rates", %{})
    render_click(vlv, "toggle_descriptions", %{})
    render_click(vlv, "toggle_priority", %{"priority" => "wont"})
    a = assigns(vlv)
    assert a.show_breakdown and a.show_all_in_rates and a.show_descriptions
    assert a.enabled_priorities == MapSet.new(["must", "should", "could"])
    refute render(vlv) =~ "You don&#39;t have edit access"
  end
end
```

- [ ] **Step 8: Export tests**

`test/estimate_web/live/estimator_live/export_test.exs`:

```elixir
defmodule EstimateWeb.EstimatorLive.ExportTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import EstimateWeb.EstimatorLiveHelpers

  alias Estimate.Templates

  setup :setup_estimator

  test "copy_json pushes the JSON export and flashes Copied!", ctx do
    html = render_click(ctx.lv, "copy_json", %{})
    assert html =~ "Copied!"
    assert_push_event(ctx.lv, "copy_to_clipboard", %{text: json})
    decoded = Jason.decode!(json)
    assert decoded["project"] == ctx.project.name
    assert decoded["estimation"] == ctx.est.name
    [epic] = decoded["epics"]
    assert epic["name"] == "Alpha"
    assert Enum.map(epic["tasks"], & &1["name"]) == ["T-one", "T-two"]
  end

  test "copy_json respects the priority filter", ctx do
    render_click(ctx.lv, "edit_task", %{"id" => ctx.task2.id})
    render_submit(ctx.lv, "save_task", %{"task" => %{"name" => "T-two", "priority" => "wont"}})
    render_click(ctx.lv, "toggle_priority", %{"priority" => "wont"})

    render_click(ctx.lv, "copy_json", %{})
    assert_push_event(ctx.lv, "copy_to_clipboard", %{text: json})
    [epic] = Jason.decode!(json)["epics"]
    assert Enum.map(epic["tasks"], & &1["name"]) == ["T-one"]
  end

  test "open_save_as_template opens the template modal", ctx do
    render_click(ctx.lv, "open_save_as_template", %{})
    assert assigns(ctx.lv).modal == :save_template
    assert render(ctx.lv) =~ ~s(id="template-form")
  end

  test "save_as_template creates a template from the estimation and closes the modal", ctx do
    render_click(ctx.lv, "open_save_as_template", %{})
    html = render_submit(ctx.lv, "save_as_template", %{"template_name" => "From Alpha"})

    assert html =~ "Template saved"
    assert assigns(ctx.lv).modal == nil
    assert [%{name: "From Alpha"}] = Templates.list_estimation_templates(ctx.org.id)
  end

  test "save_as_template with an empty name is a no-op", ctx do
    render_click(ctx.lv, "open_save_as_template", %{})
    render_submit(ctx.lv, "save_as_template", %{"template_name" => ""})
    assert assigns(ctx.lv).modal == :save_template
    assert Templates.list_estimation_templates(ctx.org.id) == []
  end

  test "viewer can copy JSON but cannot save a template", ctx do
    {_u, {:ok, vlv, _}} = mount_as("viewer", ctx)

    assert render_click(vlv, "copy_json", %{}) =~ "Copied!"

    html = render_click(vlv, "open_save_as_template", %{})
    assert html =~ "You don&#39;t have edit access"
    assert assigns(vlv).modal == nil

    render_submit(vlv, "save_as_template", %{"template_name" => "Nope"})
    assert Templates.list_estimation_templates(ctx.org.id) == []
  end
end
```

(Key layout per `EstimateWeb.EstimatorLive.Helpers.build_json_export/4`: top-level `"customer"`, `"project"`, `"estimation"` are name strings; `"epics"` is a list of objects with `"name"` and `"tasks"`.)

- [ ] **Step 9: Realtime (PubSub → reload) tests**

`test/estimate_web/live/estimator_live/realtime_test.exs`:

```elixir
defmodule EstimateWeb.EstimatorLive.RealtimeTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import EstimateWeb.EstimatorLiveHelpers

  alias Estimate.EstimationEngine

  setup :setup_estimator

  test "a context write from outside the LV reaches it via PubSub and reloads the grid", ctx do
    refute render(ctx.lv) =~ "Gamma"
    {:ok, _} = EstimationEngine.create_epic(%{"name" => "Gamma", "estimation_id" => ctx.est.id})
    assert render(ctx.lv) =~ "Gamma"
    assert Enum.map(assigns(ctx.lv).estimation.epics, & &1.name) == ["Alpha", "Gamma"]
  end

  test "every broadcast event triggers a full reload", ctx do
    {:ok, _} = EstimationEngine.update_task(ctx.task1, %{"name" => "T-one-db"})
    # the LV is subscribed; update_task already broadcast. Now send each event shape by hand
    # and prove each one re-reads the DB (the DB name differs from the in-memory one until reload).
    :sys.replace_state(ctx.lv.pid, fn state ->
      update_in(state.socket.assigns.estimation.epics, fn [epic] ->
        [%{epic | tasks: Enum.map(epic.tasks, &%{&1 | name: "STALE"})}]
      end)
    end)

    for event <- [
          {:estimation_updated, nil},
          {:epic_created, nil},
          {:epic_updated, nil},
          {:epic_deleted, nil},
          {:epics_reordered, nil},
          {:task_created, nil},
          {:task_updated, nil},
          {:task_deleted, nil},
          {:estimate_updated, nil},
          {:role_created, nil},
          {:role_updated, nil},
          {:role_deleted, nil},
          {:roles_reordered, nil},
          {:tasks_reordered, ctx.epic.id, []}
        ] do
      :sys.replace_state(ctx.lv.pid, fn state ->
        update_in(state.socket.assigns.estimation.epics, fn [epic] ->
          [%{epic | tasks: Enum.map(epic.tasks, &%{&1 | name: "STALE"})}]
        end)
      end)

      assert Enum.all?(hd(assigns(ctx.lv).estimation.epics).tasks, &(&1.name == "STALE"))
      send(ctx.lv.pid, event)
      render(ctx.lv)
      names = Enum.map(hd(assigns(ctx.lv).estimation.epics).tasks, & &1.name)
      assert names == ["T-one-db", "T-two"], inspect(event)
    end
  end
end
```

- [ ] **Step 10: Run the new suite against the unmodified LV**

Run: `mix test test/estimate_web/live/estimator_live`
Expected: all new tests pass alongside the existing 14 (`index_authz_test`, `ai_enhance_test`). Fix any test that mis-describes current behaviour (adjust the test, never the LV). Then run `mix precommit` (formatting will normalise the new files).

- [ ] **Step 11: Commit**

```bash
git add test/support/estimator_live_helpers.ex test/estimate_web/live/estimator_live
git commit -m "test(estimator): characterization suite for EstimatorLive.Index before decomposition

Shared EstimatorLiveHelpers + 8 files covering mount perimeter, every
handle_event cluster (epics, tasks, estimates/rates, settings/roles, view
state, export) and the PubSub reload path. Diverge-then-assert throughout.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: Extract `EstimatorLive.Authz` (shared helpers)

**Files:**
- Create: `lib/estimate_web/live/estimator_live/authz.ex`
- Modify: `lib/estimate_web/live/estimator_live/index.ex` (remove the private helpers at the bottom: `authorize_edit/1`, `with_edit_auth/2`, `reload_estimation/1`, `find_epic/2`, `find_task/2`, `not_found/1`, `belongs_to_estimation?/3`, `display_roles/2`; add `import EstimateWeb.EstimatorLive.Authz`)

**Interfaces:**
- Produces (all public, used by every later task):
  - `with_edit_auth(socket, (socket -> {:noreply, socket})) :: {:noreply, socket}` — runs `fun` when `socket.assigns.can_edit`, else flashes `"You don't have edit access"`.
  - `not_found(socket) :: {:noreply, socket}` — flashes `"Not found"`.
  - `find_epic(estimation, id) :: %Epic{} | nil`, `find_task(estimation, id) :: %Task{} | nil`.
  - `belongs_to_estimation?(estimation, :task | :role, id) :: boolean`.
  - `reload_estimation(socket) :: socket` — re-reads via `EstimationEngine.get_estimation!(estimation.id, org_id)` into `:estimation`.
  - `display_roles(roles, show_all_in_rates :: boolean) :: [role]`.

- [ ] **Step 1: Create the module**

```elixir
defmodule EstimateWeb.EstimatorLive.Authz do
  @moduledoc """
  Authorization gate and in-memory lookups shared by the EstimatorLive handler modules.

  Every mutating handler goes through `with_edit_auth/2`; every id coming from the
  client is resolved against the in-memory `@estimation` (never a bare
  `get_epic!/get_task!` by id) so a foreign id can never touch another estimation.

  Reads: `:can_edit`, `:estimation`, `:org_id`.
  Writes: `:estimation` (via `reload_estimation/1`), flash.
  """
  import Phoenix.LiveView, only: [put_flash: 3]
  import Phoenix.Component, only: [assign: 3]

  alias Estimate.EstimationEngine
  alias Estimate.EstimationEngine.Calculator

  def with_edit_auth(socket, fun) when is_function(fun, 1) do
    if socket.assigns.can_edit do
      fun.(socket)
    else
      {:noreply, put_flash(socket, :error, "You don't have edit access")}
    end
  end

  def not_found(socket), do: {:noreply, put_flash(socket, :error, "Not found")}

  def find_epic(%{epics: epics}, id), do: Enum.find(epics, &(&1.id == id))

  def find_task(%{epics: epics}, id),
    do: Enum.find_value(epics, fn epic -> Enum.find(epic.tasks, &(&1.id == id)) end)

  def belongs_to_estimation?(estimation, :task, id),
    do: Enum.any?(estimation.epics, fn ep -> Enum.any?(ep.tasks, &(&1.id == id)) end)

  def belongs_to_estimation?(estimation, :role, id),
    do: Enum.any?(estimation.roles, &(&1.id == id))

  def reload_estimation(socket) do
    estimation =
      EstimationEngine.get_estimation!(socket.assigns.estimation.id, socket.assigns.org_id)

    assign(socket, :estimation, estimation)
  end

  def display_roles(roles, true), do: Calculator.roles_with_all_in_rates(roles)
  def display_roles(roles, false), do: roles
end
```

- [ ] **Step 2: Wire it into `Index`**

In `index.ex`: add `import EstimateWeb.EstimatorLive.Authz` under the existing imports; delete the private definitions of `authorize_edit/1`, `with_edit_auth/2`, `reload_estimation/1`, `find_epic/2`, `find_task/2`, `not_found/1`, `belongs_to_estimation?/3`, `display_roles/2` (they were at the bottom of the file, after `filtered_epics/2`). Remove the now-unused `alias Estimate.EstimationEngine.Calculator` from `Index` **only if** the compiler warns it is unused (with `--warnings-as-errors` an unused alias fails the build).

- [ ] **Step 3: Run the estimator suite**

Run: `mix test test/estimate_web/live/estimator_live`
Expected: all pass, no warnings.

- [ ] **Step 4: Precommit and commit**

```bash
git add lib/estimate_web/live/estimator_live/authz.ex lib/estimate_web/live/estimator_live/index.ex
git commit -m "refactor(estimator): extract EstimatorLive.Authz (edit gate, in-memory lookups, reload)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: Extract `EstimatorLive.Epics`

**Files:**
- Create: `lib/estimate_web/live/estimator_live/epics.ex`
- Modify: `lib/estimate_web/live/estimator_live/index.ex` (`handle_event` clauses for `add_epic`, `edit_epic`, `save_epic`, `confirm_delete_epic`, `cancel_delete_epic`, `delete_epic`, `reorder_epics` become one-line delegations)

**Interfaces:**
- Consumes: `EstimatorLive.Authz.{with_edit_auth/2, not_found/1, find_epic/2, reload_estimation/1}`.
- Produces: `Epics.add_epic/2`, `edit_epic/2`, `save_epic/2`, `confirm_delete_epic/2`, `cancel_delete_epic/2`, `delete_epic/2`, `reorder_epics/2`, each `(socket, params) -> {:noreply, socket}`.

- [ ] **Step 1: Create the module** (bodies are the existing clauses, verbatim, with `handle_event("x", params, socket)` → `def x(socket, params)`)

```elixir
defmodule EstimateWeb.EstimatorLive.Epics do
  @moduledoc """
  Epic modal + delete-confirm + reorder handlers.

  Reads: `:estimation`, `:epic_form`, `:deleting_epic`, `:can_edit` (via Authz).
  Writes: `:modal`, `:epic_form`, `:deleting_epic`, `:estimation` (reload).
  """
  use EstimateWeb, :live_handlers

  import EstimateWeb.EstimatorLive.Authz
  alias Estimate.EstimationEngine

  def add_epic(socket, _params) do
    with_edit_auth(socket, fn socket ->
      changeset = EstimationEngine.Epic.changeset(%EstimationEngine.Epic{}, %{})

      {:noreply,
       socket
       |> assign(:modal, :epic)
       |> assign(:epic_form, to_form(changeset))}
    end)
  end

  def edit_epic(socket, %{"id" => id}) do
    with_edit_auth(socket, fn socket ->
      case find_epic(socket.assigns.estimation, id) do
        nil ->
          not_found(socket)

        epic ->
          changeset = EstimationEngine.Epic.update_changeset(epic, %{})

          {:noreply,
           socket
           |> assign(:modal, :epic)
           |> assign(:epic_form, to_form(changeset))}
      end
    end)
  end

  def save_epic(socket, %{"epic" => epic_params}) do
    with_edit_auth(socket, fn socket ->
      case socket.assigns.epic_form do
        nil ->
          not_found(socket)

        epic_form ->
          epic = epic_form.data
          estimation = socket.assigns.estimation

          result =
            if epic.id do
              EstimationEngine.update_epic(epic, epic_params)
            else
              attrs = Map.put(epic_params, "estimation_id", estimation.id)
              EstimationEngine.create_epic(attrs)
            end

          case result do
            {:ok, _epic} ->
              {:noreply,
               socket
               |> reload_estimation()
               |> assign(:modal, nil)
               |> assign(:epic_form, nil)}

            {:error, changeset} ->
              {:noreply, assign(socket, :epic_form, to_form(changeset))}
          end
      end
    end)
  end

  def confirm_delete_epic(socket, %{"id" => id}) do
    with_edit_auth(socket, fn socket ->
      case find_epic(socket.assigns.estimation, id) do
        nil -> not_found(socket)
        epic -> {:noreply, assign(socket, :deleting_epic, epic)}
      end
    end)
  end

  def cancel_delete_epic(socket, _params), do: {:noreply, assign(socket, :deleting_epic, nil)}

  def delete_epic(socket, _params) do
    with_edit_auth(socket, fn socket ->
      case socket.assigns.deleting_epic do
        nil ->
          {:noreply, socket}

        epic ->
          {:ok, _} = EstimationEngine.delete_epic(epic)

          {:noreply,
           socket
           |> reload_estimation()
           |> assign(:deleting_epic, nil)}
      end
    end)
  end

  def reorder_epics(socket, %{"ids" => ids}) do
    with_edit_auth(socket, fn socket ->
      EstimationEngine.reorder_epics(socket.assigns.estimation.id, ids)
      {:noreply, reload_estimation(socket)}
    end)
  end
end
```

- [ ] **Step 2: Replace the clauses in `Index`**

Add `alias EstimateWeb.EstimatorLive.Epics` and replace the seven epic clauses with:

```elixir
  @impl true
  def handle_event("add_epic", params, socket), do: Epics.add_epic(socket, params)
  def handle_event("edit_epic", params, socket), do: Epics.edit_epic(socket, params)
  def handle_event("save_epic", params, socket), do: Epics.save_epic(socket, params)
  def handle_event("confirm_delete_epic", params, socket), do: Epics.confirm_delete_epic(socket, params)
  def handle_event("cancel_delete_epic", params, socket), do: Epics.cancel_delete_epic(socket, params)
  def handle_event("delete_epic", params, socket), do: Epics.delete_epic(socket, params)
  def handle_event("reorder_epics", params, socket), do: Epics.reorder_epics(socket, params)
```

(`@impl true` stays on the first `handle_event` clause of the group — `add_epic` is already the first clause in the file.)

- [ ] **Step 3: Run the estimator suite**

Run: `mix test test/estimate_web/live/estimator_live`
Expected: all pass.

- [ ] **Step 4: Precommit and commit**

```bash
git add lib/estimate_web/live/estimator_live/epics.ex lib/estimate_web/live/estimator_live/index.ex
git commit -m "refactor(estimator): extract EstimatorLive.Epics handlers

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: Extract `EstimatorLive.Tasks`

**Files:**
- Create: `lib/estimate_web/live/estimator_live/tasks.ex`
- Modify: `lib/estimate_web/live/estimator_live/index.ex` (clauses `add_task`, `edit_task`, `validate_task`, `save_task`, `confirm_delete_task`, `cancel_delete_task`, `delete_task`, `reorder_tasks`)

**Interfaces:**
- Consumes: `Authz.{with_edit_auth/2, not_found/1, find_epic/2, find_task/2, reload_estimation/1}`.
- Produces: `Tasks.add_task/2`, `edit_task/2`, `validate_task/2`, `save_task/2`, `confirm_delete_task/2`, `cancel_delete_task/2`, `delete_task/2`, `reorder_tasks/2`.

- [ ] **Step 1: Create the module**

```elixir
defmodule EstimateWeb.EstimatorLive.Tasks do
  @moduledoc """
  Task modal (add/edit/validate/save), delete-confirm and reorder handlers.

  Reads: `:estimation`, `:task_form`, `:current_epic_id`, `:deleting_task`, `:can_edit` (via Authz).
  Writes: `:modal`, `:task_form`, `:current_epic_id`, `:deleting_task`, `:estimation` (reload).
  """
  use EstimateWeb, :live_handlers

  import EstimateWeb.EstimatorLive.Authz
  alias Estimate.EstimationEngine

  def add_task(socket, %{"epic-id" => epic_id}) do
    with_edit_auth(socket, fn socket ->
      case find_epic(socket.assigns.estimation, epic_id) do
        nil ->
          not_found(socket)

        epic ->
          changeset = EstimationEngine.Task.changeset(%EstimationEngine.Task{}, %{})

          {:noreply,
           socket
           |> assign(:modal, :task)
           |> assign(:task_form, to_form(changeset))
           |> assign(:current_epic_id, epic.id)}
      end
    end)
  end

  def edit_task(socket, %{"id" => id}) do
    with_edit_auth(socket, fn socket ->
      case find_task(socket.assigns.estimation, id) do
        nil ->
          not_found(socket)

        task ->
          changeset = EstimationEngine.Task.update_changeset(task, %{})

          {:noreply,
           socket
           |> assign(:modal, :task)
           |> assign(:task_form, to_form(changeset))
           |> assign(:current_epic_id, task.epic_id)}
      end
    end)
  end

  # Not edit-gated today (pure form validation, no write). Preserved as-is.
  def validate_task(socket, %{"task" => task_params}) do
    case socket.assigns.task_form do
      nil ->
        not_found(socket)

      task_form ->
        task = task_form.data

        changeset =
          if task.id,
            do: EstimationEngine.Task.update_changeset(task, task_params),
            else: EstimationEngine.Task.changeset(task, task_params)

        {:noreply,
         assign(socket, :task_form, changeset |> Map.put(:action, :validate) |> to_form())}
    end
  end

  def save_task(socket, %{"task" => task_params}) do
    with_edit_auth(socket, fn socket ->
      task = socket.assigns.task_form && socket.assigns.task_form.data
      epic_id = socket.assigns.current_epic_id

      cond do
        is_nil(task) ->
          not_found(socket)

        is_nil(task.id) and is_nil(epic_id) ->
          not_found(socket)

        true ->
          result =
            if task.id do
              EstimationEngine.update_task(task, task_params)
            else
              attrs = Map.put(task_params, "epic_id", epic_id)
              EstimationEngine.create_task(attrs)
            end

          case result do
            {:ok, _task} ->
              {:noreply,
               socket
               |> reload_estimation()
               |> assign(:modal, nil)
               |> assign(:task_form, nil)
               |> assign(:current_epic_id, nil)}

            {:error, changeset} ->
              {:noreply, assign(socket, :task_form, to_form(changeset))}
          end
      end
    end)
  end

  def confirm_delete_task(socket, %{"id" => id}) do
    with_edit_auth(socket, fn socket ->
      case find_task(socket.assigns.estimation, id) do
        nil -> not_found(socket)
        task -> {:noreply, assign(socket, :deleting_task, task)}
      end
    end)
  end

  def cancel_delete_task(socket, _params), do: {:noreply, assign(socket, :deleting_task, nil)}

  def delete_task(socket, _params) do
    with_edit_auth(socket, fn socket ->
      case socket.assigns.deleting_task do
        nil ->
          {:noreply, socket}

        task ->
          {:ok, _} = EstimationEngine.delete_task(task)

          {:noreply,
           socket
           |> reload_estimation()
           |> assign(:deleting_task, nil)}
      end
    end)
  end

  def reorder_tasks(socket, %{"epic_id" => epic_id, "ids" => ids}) do
    with_edit_auth(socket, fn socket ->
      if Enum.any?(socket.assigns.estimation.epics, &(&1.id == epic_id)) do
        EstimationEngine.reorder_tasks(epic_id, ids)
        {:noreply, reload_estimation(socket)}
      else
        {:noreply, socket}
      end
    end)
  end
end
```

- [ ] **Step 2: Replace the clauses in `Index`**

Add `alias EstimateWeb.EstimatorLive.Tasks` (extend the existing alias line to `alias EstimateWeb.EstimatorLive.{Epics, Tasks}`) and replace the eight task clauses with one-liners in the same style as Task 3 (`def handle_event("add_task", params, socket), do: Tasks.add_task(socket, params)` … through `reorder_tasks`).

- [ ] **Step 3: Run the estimator suite**

Run: `mix test test/estimate_web/live/estimator_live`
Expected: all pass.

- [ ] **Step 4: Precommit and commit**

```bash
git add lib/estimate_web/live/estimator_live/tasks.ex lib/estimate_web/live/estimator_live/index.ex
git commit -m "refactor(estimator): extract EstimatorLive.Tasks handlers

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: Extract `EstimatorLive.Estimates` (cells + rates)

**Files:**
- Create: `lib/estimate_web/live/estimator_live/estimates.ex`
- Modify: `lib/estimate_web/live/estimator_live/index.ex` (clauses `cancel_edit`, `edit_estimate`, `edit_rate`, `save_rate`, `save_estimate`; remove private `update_estimate_in_memory/2` and `update_role_in_memory/2`)

**Interfaces:**
- Consumes: `Authz.{with_edit_auth/2, belongs_to_estimation?/3}`; `EstimateWeb.EstimatorLive.Helpers.parse_decimal/1`.
- Produces: `Estimates.cancel_edit/2`, `edit_estimate/2`, `edit_rate/2`, `save_rate/2`, `save_estimate/2`; `Estimates.update_estimate_in_memory/2` and `update_role_in_memory/2` public `@doc false` (3C will reuse them).

- [ ] **Step 1: Create the module**

```elixir
defmodule EstimateWeb.EstimatorLive.Estimates do
  @moduledoc """
  Inline cell (hours) and rate editing. Successful writes patch `@estimation`
  in memory instead of reloading, so a single cell edit stays cheap.

  Reads: `:estimation`, `:org_id`, `:can_edit` (via Authz).
  Writes: `:editing`, `:editing_rate`, `:estimation` (in-memory patch).
  """
  use EstimateWeb, :live_handlers

  import EstimateWeb.EstimatorLive.Authz
  import EstimateWeb.EstimatorLive.Helpers, only: [parse_decimal: 1]
  alias Estimate.EstimationEngine

  def cancel_edit(socket, _params),
    do: {:noreply, socket |> assign(:editing, nil) |> assign(:editing_rate, nil)}

  def edit_estimate(socket, %{"key" => key}), do: {:noreply, assign(socket, :editing, key)}

  def edit_rate(socket, %{"role-id" => role_id}), do: {:noreply, assign(socket, :editing_rate, role_id)}

  def save_rate(socket, %{"role-id" => role_id, "value" => value}) do
    with_edit_auth(socket, fn socket ->
      estimation = socket.assigns.estimation

      if belongs_to_estimation?(estimation, :role, role_id) do
        role = EstimationEngine.get_role!(role_id, socket.assigns.org_id)
        hourly_rate = parse_decimal(value)

        case EstimationEngine.update_role(role, %{hourly_rate: hourly_rate}) do
          {:ok, updated_role} ->
            {:noreply,
             socket
             |> assign(:estimation, update_role_in_memory(estimation, updated_role))
             |> assign(:editing_rate, nil)}

          {:error, _changeset} ->
            {:noreply, assign(socket, :editing_rate, nil)}
        end
      else
        {:noreply, assign(socket, :editing_rate, nil)}
      end
    end)
  end

  def save_estimate(socket, params) do
    with_edit_auth(socket, fn socket ->
      %{"task-id" => task_id, "role-id" => role_id, "value" => value} = params
      estimation = socket.assigns.estimation

      if belongs_to_estimation?(estimation, :task, task_id) and
           belongs_to_estimation?(estimation, :role, role_id) do
        hours = parse_decimal(value)

        case EstimationEngine.upsert_task_estimate(task_id, role_id, %{hours: hours}, estimation.id) do
          {:ok, updated_estimate} ->
            {:noreply,
             socket
             |> assign(:estimation, update_estimate_in_memory(estimation, updated_estimate))
             |> assign(:editing, nil)}

          {:error, _changeset} ->
            {:noreply, assign(socket, :editing, nil)}
        end
      else
        {:noreply, assign(socket, :editing, nil)}
      end
    end)
  end

  @doc false
  def update_estimate_in_memory(estimation, updated_estimate) do
    epics =
      Enum.map(estimation.epics, fn epic ->
        tasks =
          Enum.map(epic.tasks, fn task ->
            if task.id == updated_estimate.task_id do
              estimates =
                case Enum.find_index(task.estimates, &(&1.id == updated_estimate.id)) do
                  nil -> [updated_estimate | task.estimates]
                  idx -> List.replace_at(task.estimates, idx, updated_estimate)
                end

              %{task | estimates: estimates}
            else
              task
            end
          end)

        %{epic | tasks: tasks}
      end)

    %{estimation | epics: epics}
  end

  @doc false
  def update_role_in_memory(estimation, updated_role) do
    roles =
      Enum.map(estimation.roles, fn role ->
        if role.id == updated_role.id, do: updated_role, else: role
      end)

    %{estimation | roles: roles}
  end
end
```

- [ ] **Step 2: Replace the clauses in `Index`**

Extend the alias to `alias EstimateWeb.EstimatorLive.{Epics, Estimates, Tasks}`; replace `cancel_edit`, `edit_estimate`, `edit_rate`, `save_rate`, `save_estimate` clauses with one-line delegations; delete the private `update_estimate_in_memory/2` and `update_role_in_memory/2` from `Index`. If `import EstimateWeb.EstimatorLive.Helpers` in `Index` now warns as unused for `parse_decimal`, leave the import (it still supplies `build_json_export/4`, `priority_label/1` for render) — only remove it if the compiler reports it unused.

- [ ] **Step 3: Run the estimator suite** — `mix test test/estimate_web/live/estimator_live` → all pass.

- [ ] **Step 4: Precommit and commit**

```bash
git add lib/estimate_web/live/estimator_live/estimates.ex lib/estimate_web/live/estimator_live/index.ex
git commit -m "refactor(estimator): extract EstimatorLive.Estimates (cells, rates, in-memory patch)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: Extract `EstimatorLive.Settings` (settings modal + roles)

**Files:**
- Create: `lib/estimate_web/live/estimator_live/settings.ex`
- Modify: `lib/estimate_web/live/estimator_live/index.ex` (clauses `open_settings`, `add_estimation_role` ×2, `save_settings`, `confirm_delete_role`, `cancel_delete_role`, `delete_estimation_role`, `reorder_roles`)

**Interfaces:**
- Consumes: `Authz.{with_edit_auth/2, reload_estimation/1}`; `Helpers.parse_decimal/1`.
- Produces: `Settings.open_settings/2`, `save_settings/2`, `add_estimation_role/2` (two clauses: the guarded one and the catch-all no-op), `confirm_delete_role/2`, `cancel_delete_role/2`, `delete_estimation_role/2`, `reorder_roles/2`.

- [ ] **Step 1: Create the module**

```elixir
defmodule EstimateWeb.EstimatorLive.Settings do
  @moduledoc """
  Estimation settings modal: name/currency, role rows (rates + overheads),
  add/delete/reorder roles.

  Reads: `:estimation`, `:org_id`, `:deleting_role_id`, `:can_edit` (via Authz).
  Writes: `:modal`, `:deleting_role_id`, `:estimation` (reload), flash.
  """
  use EstimateWeb, :live_handlers

  import EstimateWeb.EstimatorLive.Authz
  import EstimateWeb.EstimatorLive.Helpers, only: [parse_decimal: 1]
  alias Estimate.EstimationEngine

  def open_settings(socket, _params) do
    with_edit_auth(socket, fn socket -> {:noreply, assign(socket, :modal, :settings)} end)
  end

  def add_estimation_role(socket, %{"new_role_name" => name, "new_role_abbr" => abbr})
      when name != "" and abbr != "" do
    with_edit_auth(socket, fn socket ->
      estimation = socket.assigns.estimation

      attrs = %{
        name: name,
        abbreviation: String.upcase(abbr),
        estimation_id: estimation.id,
        position: length(estimation.roles),
        hourly_rate: Decimal.new(0),
        pm_overhead: Decimal.new(0),
        qa_overhead: Decimal.new(0),
        risk_buffer: Decimal.new(0)
      }

      case EstimationEngine.create_role(attrs) do
        {:ok, _role} ->
          {:noreply, reload_estimation(socket) |> put_flash(:info, "Role added")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not add role")}
      end
    end)
  end

  def add_estimation_role(socket, _params), do: {:noreply, socket}

  def save_settings(socket, params) do
    with_edit_auth(socket, fn socket ->
      estimation = socket.assigns.estimation
      org_id = socket.assigns.org_id

      attrs = %{
        "name" => params["name"],
        "currency_id" => params["currency_id"]
      }

      roles_params = params["roles"] || %{}

      roles_result =
        Enum.reduce_while(roles_params, :ok, fn {role_id, role_attrs}, :ok ->
          role = EstimationEngine.get_role!(role_id, org_id)

          if role.estimation_id != estimation.id do
            {:halt, {:error, :unauthorized_role}}
          else
            case EstimationEngine.update_role(role, %{
                   name: role_attrs["name"] || role.name,
                   abbreviation: role_attrs["abbreviation"] || role.abbreviation,
                   hourly_rate: parse_decimal(role_attrs["hourly_rate"]),
                   pm_overhead: parse_decimal(role_attrs["pm_overhead"]),
                   qa_overhead: parse_decimal(role_attrs["qa_overhead"]),
                   risk_buffer: parse_decimal(role_attrs["risk_buffer"])
                 }) do
              {:ok, _} -> {:cont, :ok}
              {:error, _} -> {:halt, {:error, :role_update_failed}}
            end
          end
        end)

      case roles_result do
        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Could not update roles")}

        :ok ->
          case EstimationEngine.update_estimation(estimation, attrs) do
            {:ok, _} ->
              {:noreply,
               socket
               |> reload_estimation()
               |> assign(:modal, nil)
               |> put_flash(:info, "Settings saved")}

            {:error, _changeset} ->
              {:noreply, put_flash(socket, :error, "Could not save settings")}
          end
      end
    end)
  end

  def confirm_delete_role(socket, %{"id" => role_id}) do
    with_edit_auth(socket, fn socket -> {:noreply, assign(socket, :deleting_role_id, role_id)} end)
  end

  def cancel_delete_role(socket, _params), do: {:noreply, assign(socket, :deleting_role_id, nil)}

  def delete_estimation_role(socket, _params) do
    with_edit_auth(socket, fn socket ->
      case socket.assigns.deleting_role_id do
        nil ->
          {:noreply, socket}

        role_id ->
          role = EstimationEngine.get_role!(role_id, socket.assigns.org_id)

          if role.estimation_id != socket.assigns.estimation.id do
            {:noreply, put_flash(socket, :error, "Not authorized")}
          else
            EstimationEngine.delete_role(role)

            {:noreply,
             socket
             |> reload_estimation()
             |> assign(:deleting_role_id, nil)
             |> put_flash(:info, "Role deleted")}
          end
      end
    end)
  end

  def reorder_roles(socket, %{"ids" => ids}) do
    with_edit_auth(socket, fn socket ->
      EstimationEngine.reorder_roles(socket.assigns.estimation.id, ids)
      {:noreply, socket}
    end)
  end
end
```

- [ ] **Step 2: Replace the clauses in `Index`**

Extend the alias with `Settings`; replace the eight clauses (both `add_estimation_role` clauses collapse into one delegation: `def handle_event("add_estimation_role", params, socket), do: Settings.add_estimation_role(socket, params)` — the guard now lives in `Settings`).

- [ ] **Step 3: Run the estimator suite** — all pass.

- [ ] **Step 4: Precommit and commit**

```bash
git add lib/estimate_web/live/estimator_live/settings.ex lib/estimate_web/live/estimator_live/index.ex
git commit -m "refactor(estimator): extract EstimatorLive.Settings (settings modal + roles)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: Extract `EstimatorLive.ViewState` and `EstimatorLive.Export`

Two small modules; batched because both are pure state/UI glue with no engine writes.

**Files:**
- Create: `lib/estimate_web/live/estimator_live/view_state.ex`
- Create: `lib/estimate_web/live/estimator_live/export.ex`
- Modify: `lib/estimate_web/live/estimator_live/index.ex` (clauses `close_modal`, `toggle_breakdown`, `toggle_all_in_rates`, `toggle_descriptions`, `toggle_priority`, `restore_priorities`, `copy_json`, `open_save_as_template`, `save_as_template` ×2; private `filtered_epics/2` moves to `ViewState` and `render/1` calls `ViewState.filtered_epics/2`)

**Interfaces:**
- Consumes: `Authz.{with_edit_auth/2, display_roles/2}`; `Helpers.build_json_export/4`.
- Produces: `ViewState.close_modal/2`, `toggle_breakdown/2`, `toggle_all_in_rates/2`, `toggle_descriptions/2`, `toggle_priority/2`, `restore_priorities/2`, `filtered_epics(estimation, enabled_priorities :: MapSet.t()) :: [epic]`; `Export.copy_json/2`, `open_save_as_template/2`, `save_as_template/2`.

- [ ] **Step 1: Create `ViewState`**

```elixir
defmodule EstimateWeb.EstimatorLive.ViewState do
  @moduledoc """
  Pure view-state toggles: breakdown panel, all-in rates, descriptions,
  MoSCoW priority filter, and closing the generic modal. No engine writes;
  none of these are edit-gated (viewers may use them).

  Reads: `:show_breakdown`, `:show_all_in_rates`, `:show_descriptions`, `:enabled_priorities`.
  Writes: the same four, plus `:modal`, `:epic_form`, `:task_form`, `:current_epic_id` (close_modal).
  """
  use EstimateWeb, :live_handlers

  @all_priorities MapSet.new(["must", "should", "could", "wont"])

  def close_modal(socket, _params) do
    {:noreply,
     socket
     |> assign(:modal, nil)
     |> assign(:epic_form, nil)
     |> assign(:task_form, nil)
     |> assign(:current_epic_id, nil)}
  end

  def toggle_breakdown(socket, _params),
    do: {:noreply, assign(socket, :show_breakdown, !socket.assigns.show_breakdown)}

  def toggle_all_in_rates(socket, _params),
    do: {:noreply, assign(socket, :show_all_in_rates, !socket.assigns.show_all_in_rates)}

  def toggle_descriptions(socket, _params),
    do: {:noreply, assign(socket, :show_descriptions, !socket.assigns.show_descriptions)}

  def toggle_priority(socket, %{"priority" => priority}) do
    current = socket.assigns.enabled_priorities

    updated =
      if MapSet.member?(current, priority) and MapSet.size(current) > 1,
        do: MapSet.delete(current, priority),
        else: MapSet.put(current, priority)

    {:noreply,
     socket
     |> assign(:enabled_priorities, updated)
     |> push_event("save_priorities", %{priorities: MapSet.to_list(updated)})}
  end

  def restore_priorities(socket, %{"priorities" => priorities}) do
    valid = MapSet.intersection(MapSet.new(priorities), @all_priorities)

    if MapSet.size(valid) > 0,
      do: {:noreply, assign(socket, :enabled_priorities, valid)},
      else: {:noreply, socket}
  end

  @doc "Epics with tasks narrowed to the enabled priorities; epics left empty are dropped. Unfiltered when all four are enabled."
  def filtered_epics(estimation, enabled_priorities) do
    if MapSet.size(enabled_priorities) == 4 do
      estimation.epics
    else
      estimation.epics
      |> Enum.map(fn epic ->
        %{
          epic
          | tasks:
              Enum.filter(epic.tasks, &MapSet.member?(enabled_priorities, &1.priority || "must"))
        }
      end)
      |> Enum.reject(&Enum.empty?(&1.tasks))
    end
  end
end
```

- [ ] **Step 2: Create `Export`**

```elixir
defmodule EstimateWeb.EstimatorLive.Export do
  @moduledoc """
  Copy-as-JSON (clipboard push) and save-as-template.

  Reads: `:estimation`, `:show_all_in_rates`, `:enabled_priorities`, `:customer`, `:project`,
  `:org_id`, `:can_edit` (via Authz, template only).
  Writes: `:modal`, flash; pushes `copy_to_clipboard`.
  """
  use EstimateWeb, :live_handlers

  import EstimateWeb.EstimatorLive.Authz
  import EstimateWeb.EstimatorLive.Helpers, only: [build_json_export: 4]
  alias EstimateWeb.EstimatorLive.ViewState

  def copy_json(socket, _params) do
    estimation = socket.assigns.estimation
    dr = display_roles(estimation.roles, socket.assigns.show_all_in_rates)
    filtered = ViewState.filtered_epics(estimation, socket.assigns.enabled_priorities)

    json =
      build_json_export(
        %{estimation | epics: filtered},
        dr,
        socket.assigns.customer,
        socket.assigns.project
      )

    {:noreply,
     socket
     |> push_event("copy_to_clipboard", %{text: json})
     |> put_flash(:info, "Copied!")}
  end

  def open_save_as_template(socket, _params) do
    with_edit_auth(socket, fn socket -> {:noreply, assign(socket, :modal, :save_template)} end)
  end

  def save_as_template(socket, %{"template_name" => name}) when name != "" do
    with_edit_auth(socket, fn socket ->
      estimation = socket.assigns.estimation
      org_id = socket.assigns.org_id

      case Estimate.Templates.create_from_estimation(org_id, name, estimation) do
        {:ok, _template} ->
          {:noreply,
           socket
           |> assign(:modal, nil)
           |> put_flash(:info, "Template saved")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not save template")}
      end
    end)
  end

  def save_as_template(socket, _params), do: {:noreply, socket}
end
```

- [ ] **Step 3: Wire into `Index`**

Extend the alias with `Export, ViewState`; replace the ten clauses with one-line delegations (both `save_as_template` clauses collapse into one delegation); delete the private `filtered_epics/2` and change the first line of `render/1` to `<% epics = ViewState.filtered_epics(@estimation, @enabled_priorities) %>`.

- [ ] **Step 4: Run the estimator suite** — all pass.

- [ ] **Step 5: Precommit and commit**

```bash
git add lib/estimate_web/live/estimator_live/view_state.ex lib/estimate_web/live/estimator_live/export.ex lib/estimate_web/live/estimator_live/index.ex
git commit -m "refactor(estimator): extract EstimatorLive.ViewState and EstimatorLive.Export

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: Extract `EstimatorLive.AI` and finish `Index`

**Files:**
- Create: `lib/estimate_web/live/estimator_live/ai.ex`
- Modify: `lib/estimate_web/live/estimator_live/index.ex` (clause `ai_enhance_description`; the three `handle_async` bodies delegate; final tidy)
- Test: `test/estimate_web/live/estimator_live/ai_enhance_test.exs` (existing async tests stay; one test added for the "AI not configured" branch). `index_authz_test.exs` already covers the viewer denial.

**Interfaces:**
- Consumes: `Authz.with_edit_auth/2`; `Estimate.Organizations.get_decrypted_api_key/1`; `Application.get_env(:estimate, :ai_enhancer, Estimate.AI.OpenRouter)` seam.
- Produces: `AI.enhance_description/2` (handler), `AI.handle_result(target, {:ok, {:ok, text}} | {:ok, {:error, reason}} | {:exit, reason}, socket) :: {:noreply, socket}`.

- [ ] **Step 1: Add the not-configured test**

In `test/estimate_web/live/estimator_live/ai_enhance_test.exs`, append inside the module:

```elixir
  test "ai_enhance_description without an org API key flashes AI not configured", %{conn: conn} do
    # a fresh org: the file's setup configures a key on ctx.org, this one never had one
    %{user: owner, organization: org} = user_with_organization_fixture()
    project = project_fixture(nil, owner)
    est = estimation_fixture(project)

    {:ok, lv, _} =
      live(
        log_in_user(build_conn(), owner),
        ~p"/org/#{org.id}/projects/#{project.id}/estimations/#{est.id}/estimator"
      )

    refute assigns(lv).ai_configured
    render_click(lv, "add_epic", %{})

    html =
      render_click(lv, "ai_enhance_description", %{
        "description" => "hello",
        "name" => "E",
        "target" => "epic"
      })

    assert html =~ "AI not configured"
    assert assigns(lv).ai_loading == nil
  end
```

Run: `mix test test/estimate_web/live/estimator_live/ai_enhance_test.exs` — must pass against the current code (it characterizes the existing `else` branch). The `conn` in this test is unused on purpose (the file's setup logs in ctx's owner); `build_conn/0` and `log_in_user/2` come from `EstimateWeb.ConnCase`.

- [ ] **Step 2: Create the module**

```elixir
defmodule EstimateWeb.EstimatorLive.AI do
  @moduledoc """
  AI description enhancement: kicks off `start_async/3` against the configured
  provider (seam: `Application.get_env(:estimate, :ai_enhancer, Estimate.AI.OpenRouter)`)
  and handles the async result.

  Reads: `:current_organization`, `:can_edit` (via Authz).
  Writes: `:ai_loading`, flash; pushes `ai_set_description`.
  """
  use EstimateWeb, :live_handlers

  import EstimateWeb.EstimatorLive.Authz
  alias Estimate.Organizations

  def enhance_description(socket, %{"description" => desc, "name" => name, "target" => target}) do
    with_edit_auth(socket, fn socket ->
      org = socket.assigns.current_organization
      api_key = Organizations.get_decrypted_api_key(org)

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
        {:noreply, put_flash(socket, :error, "AI not configured")}
      end
    end)
  end

  def handle_result(target, {:ok, {:ok, enhanced}}, socket) do
    {:noreply,
     socket
     |> assign(:ai_loading, nil)
     |> push_event("ai_set_description", %{text: enhanced, target: target})}
  end

  def handle_result(_target, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:ai_loading, nil)
     |> put_flash(:error, "AI error: #{reason}")}
  end

  def handle_result(_target, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:ai_loading, nil)
     |> put_flash(:error, "AI request failed")}
  end
end
```

- [ ] **Step 3: Wire into `Index` and tidy**

- Extend the alias with `AI`; replace the `ai_enhance_description` clause with `def handle_event("ai_enhance_description", params, socket), do: AI.enhance_description(socket, params)`.
- Replace the three `handle_async` clauses with a single delegating clause:

```elixir
  @impl true
  def handle_async({:ai_enhance, target}, result, socket),
    do: AI.handle_result(target, result, socket)
```

- `Index` should now contain only: `use`, aliases/imports, `render/1`, `mount/3`, the `handle_event` delegation block (one line per event, `@impl true` on the first), `handle_async/3`, and the two `handle_info/2` clauses (left as they are — 3C rewrites them). Remove any alias/import the compiler reports unused (`Organizations`, `Calculator`, `Portfolio` stays — used by `mount`). Target size: under 250 lines.
- Confirm no `defp` remains in `Index` (`grep -c "defp" lib/estimate_web/live/estimator_live/index.ex` → `0`).

- [ ] **Step 4: Run the full estimator suite and precommit**

Run: `mix test test/estimate_web/live/estimator_live` then `mix precommit`.
Expected: all green, zero warnings.

- [ ] **Step 5: Commit**

```bash
git add lib/estimate_web/live/estimator_live/ai.ex lib/estimate_web/live/estimator_live/index.ex test/estimate_web/live/estimator_live/ai_enhance_test.exs
git commit -m "refactor(estimator): extract EstimatorLive.AI; Index is now mount/render/delegations only

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## Done criteria

- `lib/estimate_web/live/estimator_live/index.ex` < 250 lines, no `defp`, one delegation line per event.
- Eight new modules under `estimator_live/`, each `use EstimateWeb, :live_handlers` (except `Authz`, which is a plain helper module) with `Reads:`/`Writes:` moduledocs.
- Characterization suite (8 files + helper) green before and after every extraction; `index_authz_test` and `ai_enhance_test` untouched except the one added not-configured test.
- No changes to templates/components/helpers/contexts. `mix precommit` green on every commit.

## Unresolved questions

None.
