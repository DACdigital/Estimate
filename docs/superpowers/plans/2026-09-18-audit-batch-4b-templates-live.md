# Audit Batch 4B — Templates LiveView Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put `EstimateWeb.TemplatesLive.Show` (603 lines, 0 tests) under a characterization suite, split it into handler modules like the estimator, then close its authorization and nil-safety gaps.

**Architecture:** Three phases, each its own commit(s). B1 pins today's behaviour (including its gaps) in `show_test.exs` with a shared `TemplatesLiveHelpers`. B2 moves handler bodies verbatim into `Show.{Authz, Epics, Tasks, Template}` (`use EstimateWeb, :live_handlers`), leaving `Show` as mount/render/delegations — the suite must stay green after every move. B3 is the only behaviour change: admin-gate the modal openers and delete-confirms, make lookups nil-safe with a "Not found" flash, validate `epic_id` on task reorder, flash on template-update failure; the B1 tests that pinned the old gaps are rewritten in that commit.

**Tech Stack:** Elixir 1.18, Phoenix 1.8.3, LiveView 1.1 (`Phoenix.LiveViewTest`), Ecto 3.13 / Postgres 17 (RLS), ExUnit.

**Spec:** `docs/superpowers/specs/2026-09-18-audit-batch-4-clean-code-design.md` — section "4B — `templates_live/show.ex`" (B1, B2, B3). Read it first.

## Global Constraints

- **B1 and B2 are behaviour-preserving** — no copy, assign, event or template change; B2 may change import/alias lines and the single `render/1` call sites only if a moved function needs it (it does not). **B3 is the only behaviour change**, in its own commit, with the affected B1 tests rewritten in that commit and a comment naming B3.
- Tests never use `Process.sleep`; **diverge an assign from its mount default before asserting a handler sets it**; member-denial tests assert the flash AND unchanged state.
- Handler modules `use EstimateWeb, :live_handlers` (`import Phoenix.LiveView`, `Phoenix.Component`, `EstimateWeb.AuthHelpers` → `require_admin/2`, `admin?/1`), functions `(socket, params) -> {:noreply, socket}`, `@moduledoc` with `Reads:`/`Writes:` lines. `Show` keeps `@impl true` on the first `handle_event` clause.
- `Templates.reorder_template_epics/2` / `reorder_template_tasks/2` return `:ok | {:error, :stale_reorder}` (batch 4A); the `after_reorder/2` helper moves with the reorder handlers.
- Flash copy (exact): existing `require_admin/2` → `"Not authorized"`; B3 not-found → `"Not found"`; B3 template save failure → `"Could not save template"`; existing stale reorder → `"Order changed elsewhere; reloaded"`.
- `mix precommit` (format, `--warnings-as-errors`, full suite) green before every commit. Commit trailer exactly `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- No changes under `lib/estimate/` (contexts), no migrations, no HEEx changes.
- Worktree via EnterWorktree then `git reset --hard main`; copy `deps/`, `_build/`, `.env`. If `git commit` fails with "1Password: failed to fill whole buffer", stop and report.

## File structure after 4B

| File | Responsibility |
|---|---|
| `lib/estimate_web/live/templates_live/show.ex` | `mount/3`, `render/1` (HEEx unchanged), one delegation line per event |
| `lib/estimate_web/live/templates_live/show/authz.ex` | `find_epic/2`, `find_task/3` (nil-safe after B3), `not_found/1`, `reload_template/1`, `reload_and_close/1`, `after_reorder/2` |
| `lib/estimate_web/live/templates_live/show/epics.ex` | `add_epic`, `edit_epic`, `save_epic` (create + update clauses), `confirm_delete_epic`, `delete_epic`, `reorder_epics` |
| `lib/estimate_web/live/templates_live/show/tasks.ex` | `add_task`, `edit_task`, `save_task` (create + update clauses), `confirm_delete_task`, `delete_task`, `reorder_tasks` |
| `lib/estimate_web/live/templates_live/show/template.ex` | `update_template`, `close_modal`, `cancel_delete` |
| `test/support/templates_live_helpers.ex` | `setup_template/1`, `assigns/1`, `template_path/2`, `mount_as_member/1`, `refetch/2` |
| `test/estimate_web/live/templates_live/show_test.exs` | characterization suite (B1), rewritten gates (B3) |
| `test/estimate_web/live/templates_live/show_reorder_test.exs` | from 4A; unchanged |

---

### Task 1: Characterization suite (B1)

**Files:**
- Create: `test/support/templates_live_helpers.ex`
- Create: `test/estimate_web/live/templates_live/show_test.exs`

**Interfaces:**
- Consumes: `Estimate.TemplatesFixtures.template_fixture/2`, `Estimate.AccountsFixtures.{user_with_organization_fixture/0, user_fixture/0, membership_fixture/3}`, `EstimateWeb.ConnCase.log_in_user/2`, `Estimate.Templates.{create_template_epic/1, create_template_task/1, get_estimation_template!/2}`. Route: `/org/:org_id/templates/:id` (org-scoped `live_session`).
- Produces: `EstimateWeb.TemplatesLiveHelpers` — `setup_template/1` (ExUnit setup: owner-mounted LV over a template with one epic "Alpha" holding tasks "T-one"/"T-two"; returns `%{conn, org, owner, template, epic, task1, task2, lv}`), `assigns/1`, `template_path/2`, `mount_as_member/1` (fresh non-admin member → `{:ok, lv, html}`), `refetch/2`.

Form contract (from the HEEx): epic modal posts `%{"epic_id" => id | "", "name" => …, "description" => …}` via `save_epic`; task modal posts `%{"task_id" => id | "", "epic_id" => …, "name" => …, "description" => …, "priority" => …}` via `save_task`; `edit_task`/`confirm_delete_task` take `%{"id" => task_id, "epic-id" => epic_id}`; `add_task` takes `%{"epic-id" => …}`; `update_template` is `phx-change` with `%{"name" => …, "description" => …}`. Modals render `id="epic-modal"` / `id="task-modal"`; confirms render `id="delete-epic-modal"` / `id="delete-task-modal"`.

These tests describe **today's** behaviour — including that members can open modals and stage deletes, and that unknown ids crash. Where a test would crash the LV, characterize with `assert_raise`/`catch_exit` as shown. Do not fix the LV in this task.

- [ ] **Step 1: Create the helper**

`test/support/templates_live_helpers.ex`:

```elixir
defmodule EstimateWeb.TemplatesLiveHelpers do
  @moduledoc """
  Shared setup for TemplatesLive.Show characterization tests: org + owner, one
  template with one epic ("Alpha") and two tasks ("T-one", "T-two"), mounted
  as the owner.
  """
  import Phoenix.LiveViewTest
  import Phoenix.ConnTest
  import Estimate.{AccountsFixtures, TemplatesFixtures}

  alias Estimate.Templates

  @endpoint EstimateWeb.Endpoint

  def assigns(lv), do: :sys.get_state(lv.pid).socket.assigns

  def template_path(org, template), do: "/org/#{org.id}/templates/#{template.id}"

  def refetch(template, org), do: Templates.get_estimation_template!(template.id, org.id)

  def setup_template(%{conn: conn}) do
    %{user: owner, organization: org} = user_with_organization_fixture()
    template = template_fixture(org, %{name: "Tpl", description: "Desc"})

    {:ok, epic} =
      Templates.create_template_epic(%{
        "name" => "Alpha",
        "position" => 0,
        "estimation_template_id" => template.id
      })

    {:ok, task1} =
      Templates.create_template_task(%{
        "name" => "T-one",
        "position" => 0,
        "priority" => "must",
        "estimation_template_epic_id" => epic.id
      })

    {:ok, task2} =
      Templates.create_template_task(%{
        "name" => "T-two",
        "position" => 1,
        "priority" => "should",
        "estimation_template_epic_id" => epic.id
      })

    template = refetch(template, org)
    conn = EstimateWeb.ConnCase.log_in_user(conn, owner)
    {:ok, lv, _html} = live(conn, template_path(org, template))

    %{conn: conn, org: org, owner: owner, template: template, epic: epic, task1: task1, task2: task2, lv: lv}
  end

  @doc "Mounts the same template as a fresh non-admin org member."
  def mount_as_member(%{org: org, template: template}) do
    member = user_fixture()
    _ = membership_fixture(member, org, "member")
    live(EstimateWeb.ConnCase.log_in_user(build_conn(), member), template_path(org, template))
  end
end
```

- [ ] **Step 2: Write the suite**

`test/estimate_web/live/templates_live/show_test.exs`:

```elixir
defmodule EstimateWeb.TemplatesLive.ShowTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ExUnit.CaptureLog
  import EstimateWeb.TemplatesLiveHelpers

  alias Estimate.Repo
  alias Estimate.Templates.{EstimationTemplate, EstimationTemplateEpic, EstimationTemplateTask}

  setup :setup_template

  describe "mount" do
    test "owner mounts with is_admin and default view state", ctx do
      a = assigns(ctx.lv)
      assert a.is_admin
      assert a.template.id == ctx.template.id
      assert a.page_title == "Tpl"
      assert a.active_tab == :templates
      assert a.modal == nil and a.current_epic_id == nil and a.current_task_id == nil
      assert a.deleting_epic == nil and a.deleting_task == nil
      html = render(ctx.lv)
      assert html =~ "Alpha" and html =~ "T-one" and html =~ "T-two"
      assert html =~ ~s(phx-change="update_template")
    end

    test "member mounts read-only", ctx do
      {:ok, lv, html} = mount_as_member(ctx)
      refute assigns(lv).is_admin
      refute html =~ ~s(phx-change="update_template")
      refute html =~ ~s(phx-click="add_epic")
    end
  end

  describe "update_template" do
    test "renames and re-describes the template", ctx do
      render_change(ctx.lv, "update_template", %{"name" => "Renamed", "description" => "New"})
      assert assigns(ctx.lv).template.name == "Renamed"
      assert Repo.get!(EstimationTemplate, ctx.template.id).description == "New"
    end

    test "an invalid name is silently ignored (characterizes today: no flash)", ctx do
      html = render_change(ctx.lv, "update_template", %{"name" => "", "description" => "x"})
      refute html =~ "Could not save template"
      assert Repo.get!(EstimationTemplate, ctx.template.id).name == "Tpl"
    end

    test "member is denied", ctx do
      {:ok, lv, _} = mount_as_member(ctx)
      assert render_change(lv, "update_template", %{"name" => "Hijack", "description" => ""}) =~ "Not authorized"
      assert Repo.get!(EstimationTemplate, ctx.template.id).name == "Tpl"
    end
  end

  describe "epics" do
    test "add_epic opens an empty epic modal", ctx do
      render_click(ctx.lv, "add_epic", %{})
      a = assigns(ctx.lv)
      assert a.modal == :epic and a.current_epic_id == nil
      assert a.epic_form[:name].value == ""
      assert render(ctx.lv) =~ ~s(id="epic-modal")
    end

    test "edit_epic opens the modal prefilled", ctx do
      render_click(ctx.lv, "edit_epic", %{"id" => ctx.epic.id})
      a = assigns(ctx.lv)
      assert a.modal == :epic and a.current_epic_id == ctx.epic.id
      assert a.epic_form[:name].value == "Alpha"
    end

    test "save_epic with an empty epic_id creates at the next position and closes", ctx do
      render_click(ctx.lv, "add_epic", %{})
      render_submit(ctx.lv, "save_epic", %{"epic_id" => "", "name" => "Beta", "description" => ""})
      a = assigns(ctx.lv)
      assert a.modal == nil
      assert Enum.map(a.template.epics, &{&1.name, &1.position}) == [{"Alpha", 0}, {"Beta", 1}]
    end

    test "save_epic with an epic_id updates and closes", ctx do
      render_click(ctx.lv, "edit_epic", %{"id" => ctx.epic.id})
      render_submit(ctx.lv, "save_epic", %{"epic_id" => ctx.epic.id, "name" => "Alpha-2", "description" => "d"})
      assert assigns(ctx.lv).modal == nil
      assert Repo.get!(EstimationTemplateEpic, ctx.epic.id).name == "Alpha-2"
    end

    test "save_epic with an empty name flashes and keeps the modal", ctx do
      render_click(ctx.lv, "add_epic", %{})
      html = render_submit(ctx.lv, "save_epic", %{"epic_id" => "", "name" => "", "description" => ""})
      assert html =~ "Could not create epic"
      assert assigns(ctx.lv).modal == :epic
    end

    test "confirm_delete_epic / cancel_delete toggle deleting_epic", ctx do
      render_click(ctx.lv, "confirm_delete_epic", %{"id" => ctx.epic.id})
      assert assigns(ctx.lv).deleting_epic.id == ctx.epic.id
      assert render(ctx.lv) =~ ~s(id="delete-epic-modal")
      render_click(ctx.lv, "cancel_delete", %{})
      assert assigns(ctx.lv).deleting_epic == nil
    end

    test "delete_epic deletes the confirmed epic and its tasks", ctx do
      render_click(ctx.lv, "confirm_delete_epic", %{"id" => ctx.epic.id})
      html = render_click(ctx.lv, "delete_epic", %{})
      assert html =~ "Epic deleted"
      assert assigns(ctx.lv).deleting_epic == nil
      assert assigns(ctx.lv).template.epics == []
      refute Repo.get(EstimationTemplateEpic, ctx.epic.id)
      refute Repo.get(EstimationTemplateTask, ctx.task1.id)
    end

    test "reorder_epics applies the new order", ctx do
      render_click(ctx.lv, "add_epic", %{})
      render_submit(ctx.lv, "save_epic", %{"epic_id" => "", "name" => "Beta", "description" => ""})
      [alpha, beta] = assigns(ctx.lv).template.epics
      render_click(ctx.lv, "reorder_epics", %{"ids" => [beta.id, alpha.id]})
      assert Enum.map(assigns(ctx.lv).template.epics, & &1.name) == ["Beta", "Alpha"]
    end

    test "member can open the epic modal and stage a delete (characterizes today's gap; changed in B3)", ctx do
      {:ok, lv, _} = mount_as_member(ctx)
      render_click(lv, "add_epic", %{})
      assert assigns(lv).modal == :epic
      render_click(lv, "confirm_delete_epic", %{"id" => ctx.epic.id})
      assert assigns(lv).deleting_epic.id == ctx.epic.id
    end

    test "member is denied on save_epic, delete_epic and reorder_epics", ctx do
      {:ok, lv, _} = mount_as_member(ctx)
      assert render_submit(lv, "save_epic", %{"epic_id" => "", "name" => "X", "description" => ""}) =~ "Not authorized"
      render_click(lv, "confirm_delete_epic", %{"id" => ctx.epic.id})
      assert render_click(lv, "delete_epic", %{}) =~ "Not authorized"
      assert render_click(lv, "reorder_epics", %{"ids" => [ctx.epic.id]}) =~ "Not authorized"
      assert Repo.get(EstimationTemplateEpic, ctx.epic.id)
      assert length(refetch(ctx.template, ctx.org).epics) == 1
    end

    test "edit_epic with an unknown id crashes the LiveView (characterizes today's gap; changed in B3)", ctx do
      log =
        capture_log(fn ->
          catch_exit(render_click(ctx.lv, "edit_epic", %{"id" => Ecto.UUID.generate()}))
        end)

      assert log =~ "KeyError" or log =~ "nil"
    end
  end

  describe "tasks" do
    test "add_task opens the task modal bound to the epic", ctx do
      render_click(ctx.lv, "add_task", %{"epic-id" => ctx.epic.id})
      a = assigns(ctx.lv)
      assert a.modal == :task and a.current_epic_id == ctx.epic.id and a.current_task_id == nil
      assert a.task_form[:priority].value == "must"
      assert render(ctx.lv) =~ ~s(id="task-modal")
    end

    test "edit_task opens the modal prefilled", ctx do
      render_click(ctx.lv, "edit_task", %{"id" => ctx.task2.id, "epic-id" => ctx.epic.id})
      a = assigns(ctx.lv)
      assert a.modal == :task and a.current_task_id == ctx.task2.id
      assert a.task_form[:name].value == "T-two" and a.task_form[:priority].value == "should"
    end

    test "save_task with an empty task_id creates at the next position and closes", ctx do
      render_click(ctx.lv, "add_task", %{"epic-id" => ctx.epic.id})
      render_submit(ctx.lv, "save_task", %{"task_id" => "", "epic_id" => ctx.epic.id, "name" => "T-three", "description" => "", "priority" => "could"})
      a = assigns(ctx.lv)
      assert a.modal == nil
      [epic] = a.template.epics
      assert Enum.map(epic.tasks, &{&1.name, &1.position, &1.priority}) == [{"T-one", 0, "must"}, {"T-two", 1, "should"}, {"T-three", 2, "could"}]
    end

    test "save_task with a task_id updates and closes", ctx do
      render_click(ctx.lv, "edit_task", %{"id" => ctx.task1.id, "epic-id" => ctx.epic.id})
      render_submit(ctx.lv, "save_task", %{"task_id" => ctx.task1.id, "epic_id" => ctx.epic.id, "name" => "T-one-2", "description" => "", "priority" => "wont"})
      assert assigns(ctx.lv).modal == nil
      t = Repo.get!(EstimationTemplateTask, ctx.task1.id)
      assert t.name == "T-one-2" and t.priority == "wont"
    end

    test "save_task with an empty name flashes and keeps the modal", ctx do
      render_click(ctx.lv, "add_task", %{"epic-id" => ctx.epic.id})
      html = render_submit(ctx.lv, "save_task", %{"task_id" => "", "epic_id" => ctx.epic.id, "name" => "", "description" => "", "priority" => "must"})
      assert html =~ "Could not create task"
      assert assigns(ctx.lv).modal == :task
    end

    test "confirm_delete_task / cancel_delete toggle deleting_task", ctx do
      render_click(ctx.lv, "confirm_delete_task", %{"id" => ctx.task2.id, "epic-id" => ctx.epic.id})
      assert assigns(ctx.lv).deleting_task.id == ctx.task2.id
      assert render(ctx.lv) =~ ~s(id="delete-task-modal")
      render_click(ctx.lv, "cancel_delete", %{})
      assert assigns(ctx.lv).deleting_task == nil
    end

    test "delete_task deletes the confirmed task", ctx do
      render_click(ctx.lv, "confirm_delete_task", %{"id" => ctx.task2.id, "epic-id" => ctx.epic.id})
      html = render_click(ctx.lv, "delete_task", %{})
      assert html =~ "Task deleted"
      assert assigns(ctx.lv).deleting_task == nil
      refute Repo.get(EstimationTemplateTask, ctx.task2.id)
    end

    test "reorder_tasks applies the new order within the epic", ctx do
      render_click(ctx.lv, "reorder_tasks", %{"epic_id" => ctx.epic.id, "ids" => [ctx.task2.id, ctx.task1.id]})
      [epic] = assigns(ctx.lv).template.epics
      assert Enum.map(epic.tasks, & &1.name) == ["T-two", "T-one"]
    end

    test "member can open the task modal and stage a delete (characterizes today's gap; changed in B3)", ctx do
      {:ok, lv, _} = mount_as_member(ctx)
      render_click(lv, "add_task", %{"epic-id" => ctx.epic.id})
      assert assigns(lv).modal == :task
      render_click(lv, "confirm_delete_task", %{"id" => ctx.task1.id, "epic-id" => ctx.epic.id})
      assert assigns(lv).deleting_task.id == ctx.task1.id
    end

    test "member is denied on save_task, delete_task and reorder_tasks", ctx do
      {:ok, lv, _} = mount_as_member(ctx)
      assert render_submit(lv, "save_task", %{"task_id" => "", "epic_id" => ctx.epic.id, "name" => "X", "description" => "", "priority" => "must"}) =~ "Not authorized"
      render_click(lv, "confirm_delete_task", %{"id" => ctx.task1.id, "epic-id" => ctx.epic.id})
      assert render_click(lv, "delete_task", %{}) =~ "Not authorized"
      assert render_click(lv, "reorder_tasks", %{"epic_id" => ctx.epic.id, "ids" => [ctx.task2.id, ctx.task1.id]}) =~ "Not authorized"
      assert Repo.get(EstimationTemplateTask, ctx.task1.id)
      [epic] = refetch(ctx.template, ctx.org).epics
      assert Enum.map(epic.tasks, & &1.name) == ["T-one", "T-two"]
    end

    test "edit_task with an unknown epic id crashes the LiveView (characterizes today's gap; changed in B3)", ctx do
      log =
        capture_log(fn ->
          catch_exit(render_click(ctx.lv, "edit_task", %{"id" => ctx.task1.id, "epic-id" => Ecto.UUID.generate()}))
        end)

      assert log =~ "nil" or log =~ "KeyError"
    end
  end

  describe "modal / delete housekeeping" do
    test "close_modal clears only the modal", ctx do
      render_click(ctx.lv, "add_task", %{"epic-id" => ctx.epic.id})
      assert assigns(ctx.lv).modal == :task
      render_click(ctx.lv, "close_modal", %{})
      a = assigns(ctx.lv)
      assert a.modal == nil
      # characterizes today: close_modal leaves current_epic_id as it was
      assert a.current_epic_id == ctx.epic.id
    end

    test "cancel_delete clears both deleting assigns", ctx do
      render_click(ctx.lv, "confirm_delete_epic", %{"id" => ctx.epic.id})
      render_click(ctx.lv, "confirm_delete_task", %{"id" => ctx.task1.id, "epic-id" => ctx.epic.id})
      a = assigns(ctx.lv)
      assert a.deleting_epic != nil and a.deleting_task != nil
      render_click(ctx.lv, "cancel_delete", %{})
      a = assigns(ctx.lv)
      assert a.deleting_epic == nil and a.deleting_task == nil
    end
  end
end
```

- [ ] **Step 3: Run the suite against the unmodified LV**

Run: `mix test test/estimate_web/live/templates_live`
Expected: all green (26 new + the 4A reorder test). Where a test mis-describes current behaviour, fix the **test** and note it in the report — never the LV. The two crash-characterization tests may need their log assertion loosened to whatever the crash actually logs (`FunctionClauseError`, `KeyError`, `nil`); keep them as crash characterizations.

- [ ] **Step 4: Precommit and commit**

```bash
git add test/support/templates_live_helpers.ex test/estimate_web/live/templates_live/show_test.exs
git commit -m "test(templates): characterization suite for TemplatesLive.Show before decomposition

Pins mount perimeter, every handler, modal/delete state, member denials, and
today's gaps (members can open modals and stage deletes; unknown ids crash).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: Decompose into `Show.{Authz, Epics, Tasks, Template}` (B2)

**Files:**
- Create: `lib/estimate_web/live/templates_live/show/authz.ex`, `show/epics.ex`, `show/tasks.ex`, `show/template.ex`
- Modify: `lib/estimate_web/live/templates_live/show.ex` (handlers → delegations; private helpers removed)

**Interfaces:**
- Produces:
  - `Show.Authz`: `find_epic(template, id)`, `find_task(template, epic_id, task_id)`, `reload_template(socket)`, `reload_and_close(socket)`, `after_reorder(:ok | {:error, :stale_reorder}, socket) :: {:noreply, socket}`, `not_found(socket) :: {:noreply, socket}` (flash `"Not found"`; unused until B3).
  - `Show.Epics`: `add_epic/2`, `edit_epic/2`, `save_epic/2` (two clauses on `"epic_id" => ""` vs id), `confirm_delete_epic/2`, `delete_epic/2`, `reorder_epics/2`.
  - `Show.Tasks`: `add_task/2`, `edit_task/2`, `save_task/2` (two clauses), `confirm_delete_task/2`, `delete_task/2`, `reorder_tasks/2`.
  - `Show.Template`: `update_template/2`, `close_modal/2`, `cancel_delete/2`.

Bodies are verbatim moves (`handle_event("x", params, socket)` → `def x(socket, params)`); `require_admin/2` is available through `:live_handlers`.

- [ ] **Step 1: `Show.Authz`**

```elixir
defmodule EstimateWeb.TemplatesLive.Show.Authz do
  @moduledoc """
  Lookups and reload helpers shared by the TemplatesLive.Show handler modules.
  Admin gating itself is `EstimateWeb.AuthHelpers.require_admin/2` (via `:live_handlers`).

  Reads: `:template`, `:org_id`. Writes: `:template` (reload), `:modal` (reload_and_close), flash.
  """
  import Phoenix.LiveView, only: [put_flash: 3]
  import Phoenix.Component, only: [assign: 3]

  alias Estimate.Templates

  def find_epic(template, id), do: Enum.find(template.epics, &(&1.id == id))

  def find_task(template, epic_id, task_id) do
    epic = find_epic(template, epic_id)
    Enum.find(epic.tasks, &(&1.id == task_id))
  end

  def not_found(socket), do: {:noreply, put_flash(socket, :error, "Not found")}

  def reload_template(socket) do
    template =
      Templates.get_estimation_template!(socket.assigns.template.id, socket.assigns.org_id)

    assign(socket, :template, template)
  end

  def reload_and_close(socket), do: socket |> reload_template() |> assign(:modal, nil)

  def after_reorder(:ok, socket), do: {:noreply, reload_template(socket)}

  def after_reorder({:error, :stale_reorder}, socket),
    do:
      {:noreply,
       socket |> reload_template() |> put_flash(:error, "Order changed elsewhere; reloaded")}
end
```

(`find_task/3` keeps today's crash on an unknown epic — B3 fixes it.)

- [ ] **Step 2: `Show.Epics`** — move the seven epic clauses verbatim:

```elixir
defmodule EstimateWeb.TemplatesLive.Show.Epics do
  @moduledoc """
  Template epic modal, delete-confirm and reorder handlers.

  Reads: `:template`, `:deleting_epic`, `:current_membership` (via require_admin).
  Writes: `:modal`, `:current_epic_id`, `:epic_form`, `:deleting_epic`, `:template` (reload), flash.
  """
  use EstimateWeb, :live_handlers

  import EstimateWeb.TemplatesLive.Show.Authz
  alias Estimate.Templates

  def add_epic(socket, _params) do
    {:noreply,
     socket
     |> assign(:modal, :epic)
     |> assign(:current_epic_id, nil)
     |> assign(:epic_form, to_form(%{"name" => "", "description" => ""}, as: "epic"))}
  end

  def edit_epic(socket, %{"id" => id}) do
    epic = find_epic(socket.assigns.template, id)

    {:noreply,
     socket
     |> assign(:modal, :epic)
     |> assign(:current_epic_id, id)
     |> assign(
       :epic_form,
       to_form(%{"name" => epic.name, "description" => epic.description || ""}, as: "epic")
     )}
  end

  def save_epic(socket, %{"epic_id" => "", "name" => name} = params) do
    require_admin(socket, fn ->
      position = length(socket.assigns.template.epics)

      attrs = %{
        "name" => name,
        "description" => params["description"],
        "position" => position,
        "estimation_template_id" => socket.assigns.template.id
      }

      case Templates.create_template_epic(attrs) do
        {:ok, _} -> {:noreply, reload_and_close(socket)}
        {:error, _} -> {:noreply, put_flash(socket, :error, "Could not create epic")}
      end
    end)
  end

  def save_epic(socket, %{"epic_id" => id, "name" => name} = params) do
    require_admin(socket, fn ->
      epic = find_epic(socket.assigns.template, id)

      case Templates.update_template_epic(epic, %{
             "name" => name,
             "description" => params["description"]
           }) do
        {:ok, _} -> {:noreply, reload_and_close(socket)}
        {:error, _} -> {:noreply, put_flash(socket, :error, "Could not update epic")}
      end
    end)
  end

  def confirm_delete_epic(socket, %{"id" => id}) do
    epic = find_epic(socket.assigns.template, id)
    {:noreply, assign(socket, :deleting_epic, epic)}
  end

  def delete_epic(socket, _params) do
    require_admin(socket, fn ->
      case Templates.delete_template_epic(socket.assigns.deleting_epic) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(:deleting_epic, nil)
           |> reload_template()
           |> put_flash(:info, "Epic deleted")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not delete epic")}
      end
    end)
  end

  def reorder_epics(socket, %{"ids" => ids}) do
    require_admin(socket, fn ->
      socket.assigns.template.id
      |> Templates.reorder_template_epics(ids)
      |> after_reorder(socket)
    end)
  end
end
```

- [ ] **Step 3: `Show.Tasks`** — the seven task clauses verbatim:

```elixir
defmodule EstimateWeb.TemplatesLive.Show.Tasks do
  @moduledoc """
  Template task modal, delete-confirm and reorder handlers.

  Reads: `:template`, `:deleting_task`, `:current_membership` (via require_admin).
  Writes: `:modal`, `:current_epic_id`, `:current_task_id`, `:task_form`, `:deleting_task`, `:template` (reload), flash.
  """
  use EstimateWeb, :live_handlers

  import EstimateWeb.TemplatesLive.Show.Authz
  alias Estimate.Templates

  def add_task(socket, %{"epic-id" => epic_id}) do
    {:noreply,
     socket
     |> assign(:modal, :task)
     |> assign(:current_epic_id, epic_id)
     |> assign(:current_task_id, nil)
     |> assign(
       :task_form,
       to_form(%{"name" => "", "description" => "", "priority" => "must"}, as: "task")
     )}
  end

  def edit_task(socket, %{"id" => id, "epic-id" => epic_id}) do
    task = find_task(socket.assigns.template, epic_id, id)

    {:noreply,
     socket
     |> assign(:modal, :task)
     |> assign(:current_epic_id, epic_id)
     |> assign(:current_task_id, id)
     |> assign(
       :task_form,
       to_form(
         %{
           "name" => task.name,
           "description" => task.description || "",
           "priority" => task.priority
         },
         as: "task"
       )
     )}
  end

  def save_task(socket, %{"task_id" => "", "epic_id" => epic_id, "name" => name} = params) do
    require_admin(socket, fn ->
      epic = find_epic(socket.assigns.template, epic_id)
      position = length(epic.tasks)

      attrs = %{
        "name" => name,
        "description" => params["description"],
        "priority" => params["priority"] || "must",
        "position" => position,
        "estimation_template_epic_id" => epic_id
      }

      case Templates.create_template_task(attrs) do
        {:ok, _} -> {:noreply, reload_and_close(socket)}
        {:error, _} -> {:noreply, put_flash(socket, :error, "Could not create task")}
      end
    end)
  end

  def save_task(socket, %{"task_id" => id, "epic_id" => epic_id, "name" => name} = params) do
    require_admin(socket, fn ->
      task = find_task(socket.assigns.template, epic_id, id)

      attrs = %{
        "name" => name,
        "description" => params["description"],
        "priority" => params["priority"] || task.priority
      }

      case Templates.update_template_task(task, attrs) do
        {:ok, _} -> {:noreply, reload_and_close(socket)}
        {:error, _} -> {:noreply, put_flash(socket, :error, "Could not update task")}
      end
    end)
  end

  def confirm_delete_task(socket, %{"id" => id, "epic-id" => epic_id}) do
    task = find_task(socket.assigns.template, epic_id, id)
    {:noreply, assign(socket, :deleting_task, task)}
  end

  def delete_task(socket, _params) do
    require_admin(socket, fn ->
      case Templates.delete_template_task(socket.assigns.deleting_task) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(:deleting_task, nil)
           |> reload_template()
           |> put_flash(:info, "Task deleted")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not delete task")}
      end
    end)
  end

  def reorder_tasks(socket, %{"epic_id" => epic_id, "ids" => ids}) do
    require_admin(socket, fn ->
      epic_id
      |> Templates.reorder_template_tasks(ids)
      |> after_reorder(socket)
    end)
  end
end
```

- [ ] **Step 4: `Show.Template`**

```elixir
defmodule EstimateWeb.TemplatesLive.Show.Template do
  @moduledoc """
  Template header (inline name/description) and modal/delete housekeeping.

  Reads: `:template`, `:org_id`. Writes: `:template`, `:modal`, `:deleting_epic`, `:deleting_task`.
  """
  use EstimateWeb, :live_handlers

  alias Estimate.Templates

  def update_template(socket, params) do
    require_admin(socket, fn ->
      attrs = %{"name" => params["name"], "description" => params["description"]}

      case Templates.update_estimation_template(socket.assigns.template, attrs) do
        {:ok, template} ->
          template = Templates.get_estimation_template!(template.id, socket.assigns.org_id)
          {:noreply, assign(socket, :template, template)}

        {:error, _} ->
          {:noreply, socket}
      end
    end)
  end

  def close_modal(socket, _params), do: {:noreply, assign(socket, :modal, nil)}

  def cancel_delete(socket, _params),
    do: {:noreply, socket |> assign(:deleting_epic, nil) |> assign(:deleting_task, nil)}
end
```

- [ ] **Step 5: `Show` becomes delegations**

Replace every `handle_event` clause and the private helpers with:

```elixir
  alias EstimateWeb.TemplatesLive.Show.{Epics, Tasks, Template}

  @impl true
  def handle_event("update_template", params, socket), do: Template.update_template(socket, params)
  def handle_event("add_epic", params, socket), do: Epics.add_epic(socket, params)
  def handle_event("edit_epic", params, socket), do: Epics.edit_epic(socket, params)
  def handle_event("save_epic", params, socket), do: Epics.save_epic(socket, params)
  def handle_event("confirm_delete_epic", params, socket), do: Epics.confirm_delete_epic(socket, params)
  def handle_event("delete_epic", params, socket), do: Epics.delete_epic(socket, params)
  def handle_event("add_task", params, socket), do: Tasks.add_task(socket, params)
  def handle_event("edit_task", params, socket), do: Tasks.edit_task(socket, params)
  def handle_event("save_task", params, socket), do: Tasks.save_task(socket, params)
  def handle_event("confirm_delete_task", params, socket), do: Tasks.confirm_delete_task(socket, params)
  def handle_event("delete_task", params, socket), do: Tasks.delete_task(socket, params)
  def handle_event("reorder_epics", params, socket), do: Epics.reorder_epics(socket, params)
  def handle_event("reorder_tasks", params, socket), do: Tasks.reorder_tasks(socket, params)
  def handle_event("close_modal", params, socket), do: Template.close_modal(socket, params)
  def handle_event("cancel_delete", params, socket), do: Template.cancel_delete(socket, params)
```

Delete `reload_template/1`, `after_reorder/2`, `reload_and_close/1`, `find_epic/2`, `find_task/3` from `Show`; remove aliases the compiler reports unused (`Templates` stays — `mount/3` uses it). `grep -c defp lib/estimate_web/live/templates_live/show.ex` → 0.

- [ ] **Step 6: Suite + precommit** — `mix test test/estimate_web/live/templates_live test/estimate_web/live/org_scoped_smoke_test.exs` green, then `mix precommit`.

- [ ] **Step 7: Commit**

```bash
git add lib/estimate_web/live/templates_live
git commit -m "refactor(templates): decompose TemplatesLive.Show into Authz/Epics/Tasks/Template handler modules

Verbatim moves; Show is mount/render/delegations. Behaviour-preserving (suite unchanged).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: Close the gaps (B3)

**Files:**
- Modify: `lib/estimate_web/live/templates_live/show/authz.ex` (`find_task/3` nil-safe)
- Modify: `show/epics.ex` (`add_epic`, `edit_epic`, `confirm_delete_epic` gated + nil-safe)
- Modify: `show/tasks.ex` (`add_task`, `edit_task`, `confirm_delete_task` gated + nil-safe; `reorder_tasks` validates `epic_id`)
- Modify: `show/template.ex` (`update_template` error flash)
- Modify: `test/estimate_web/live/templates_live/show_test.exs` (rewrite the five "characterizes today's gap" tests; add the reorder validation test)

**Interfaces:**
- Consumes: `Authz.{find_epic/2, find_task/3, not_found/1}`, `require_admin/2`.
- Produces: the behaviour change. Flash copy exact: `"Not authorized"`, `"Not found"`, `"Could not save template"`.

- [ ] **Step 1: Rewrite the gap tests first (they must fail)**

In `show_test.exs`:

Replace `"member can open the epic modal and stage a delete …"` with:

```elixir
    test "member is denied on add_epic, edit_epic and confirm_delete_epic (B3)", ctx do
      {:ok, lv, _} = mount_as_member(ctx)
      assert render_click(lv, "add_epic", %{}) =~ "Not authorized"
      assert render_click(lv, "edit_epic", %{"id" => ctx.epic.id}) =~ "Not authorized"
      assert render_click(lv, "confirm_delete_epic", %{"id" => ctx.epic.id}) =~ "Not authorized"
      a = assigns(lv)
      assert a.modal == nil and a.deleting_epic == nil
    end
```

Replace `"edit_epic with an unknown id crashes …"` with:

```elixir
    test "edit_epic / confirm_delete_epic with an unknown id flash Not found (B3)", ctx do
      assert render_click(ctx.lv, "edit_epic", %{"id" => Ecto.UUID.generate()}) =~ "Not found"
      assert assigns(ctx.lv).modal == nil
      assert render_click(ctx.lv, "confirm_delete_epic", %{"id" => Ecto.UUID.generate()}) =~ "Not found"
      assert assigns(ctx.lv).deleting_epic == nil
      assert Process.alive?(ctx.lv.pid)
    end
```

Replace `"member can open the task modal and stage a delete …"` with:

```elixir
    test "member is denied on add_task, edit_task and confirm_delete_task (B3)", ctx do
      {:ok, lv, _} = mount_as_member(ctx)
      assert render_click(lv, "add_task", %{"epic-id" => ctx.epic.id}) =~ "Not authorized"
      assert render_click(lv, "edit_task", %{"id" => ctx.task1.id, "epic-id" => ctx.epic.id}) =~ "Not authorized"
      assert render_click(lv, "confirm_delete_task", %{"id" => ctx.task1.id, "epic-id" => ctx.epic.id}) =~ "Not authorized"
      a = assigns(lv)
      assert a.modal == nil and a.deleting_task == nil
    end
```

Replace `"edit_task with an unknown epic id crashes …"` with:

```elixir
    test "edit_task / confirm_delete_task with an unknown epic or task id flash Not found (B3)", ctx do
      assert render_click(ctx.lv, "edit_task", %{"id" => ctx.task1.id, "epic-id" => Ecto.UUID.generate()}) =~ "Not found"
      assert render_click(ctx.lv, "edit_task", %{"id" => Ecto.UUID.generate(), "epic-id" => ctx.epic.id}) =~ "Not found"
      assert assigns(ctx.lv).modal == nil
      assert render_click(ctx.lv, "confirm_delete_task", %{"id" => Ecto.UUID.generate(), "epic-id" => ctx.epic.id}) =~ "Not found"
      assert assigns(ctx.lv).deleting_task == nil
      assert Process.alive?(ctx.lv.pid)
    end

    test "reorder_tasks for an epic that is not in this template is rejected (B3)", ctx do
      other = Estimate.TemplatesFixtures.template_fixture(ctx.org)
      {:ok, other_epic} = Estimate.Templates.create_template_epic(%{"name" => "Other", "position" => 0, "estimation_template_id" => other.id})
      {:ok, ot} = Estimate.Templates.create_template_task(%{"name" => "OT", "position" => 0, "estimation_template_epic_id" => other_epic.id})

      assert render_click(ctx.lv, "reorder_tasks", %{"epic_id" => other_epic.id, "ids" => [ot.id]}) =~ "Not found"
      assert Repo.get!(EstimationTemplateTask, ot.id).position == 0
    end
```

Replace `"an invalid name is silently ignored …"` with:

```elixir
    test "an invalid name flashes Could not save template (B3)", ctx do
      html = render_change(ctx.lv, "update_template", %{"name" => "", "description" => "x"})
      assert html =~ "Could not save template"
      assert Repo.get!(EstimationTemplate, ctx.template.id).name == "Tpl"
    end
```

Remove the now-unused `import ExUnit.CaptureLog` if nothing else uses it.

- [ ] **Step 2: Run — expect exactly these six tests to fail** against the B2 code.

- [ ] **Step 3: Implement**

`authz.ex`:

```elixir
  def find_task(template, epic_id, task_id) do
    case find_epic(template, epic_id) do
      nil -> nil
      epic -> Enum.find(epic.tasks, &(&1.id == task_id))
    end
  end
```

`epics.ex`:

```elixir
  def add_epic(socket, _params) do
    require_admin(socket, fn ->
      {:noreply,
       socket
       |> assign(:modal, :epic)
       |> assign(:current_epic_id, nil)
       |> assign(:epic_form, to_form(%{"name" => "", "description" => ""}, as: "epic"))}
    end)
  end

  def edit_epic(socket, %{"id" => id}) do
    require_admin(socket, fn ->
      case find_epic(socket.assigns.template, id) do
        nil ->
          not_found(socket)

        epic ->
          {:noreply,
           socket
           |> assign(:modal, :epic)
           |> assign(:current_epic_id, id)
           |> assign(
             :epic_form,
             to_form(%{"name" => epic.name, "description" => epic.description || ""}, as: "epic")
           )}
      end
    end)
  end

  def confirm_delete_epic(socket, %{"id" => id}) do
    require_admin(socket, fn ->
      case find_epic(socket.assigns.template, id) do
        nil -> not_found(socket)
        epic -> {:noreply, assign(socket, :deleting_epic, epic)}
      end
    end)
  end
```

Also make `save_epic/2`'s update clause nil-safe: `case find_epic(...) do nil -> not_found(socket); epic -> (existing case) end`.

`tasks.ex`: same shape for `add_task` (gate; also `not_found` when `find_epic(template, epic_id)` is nil), `edit_task` (gate + `find_task` nil → `not_found`), `confirm_delete_task` (gate + nil → `not_found`), `save_task/2` update clause nil-safe; and:

```elixir
  def reorder_tasks(socket, %{"epic_id" => epic_id, "ids" => ids}) do
    require_admin(socket, fn ->
      case find_epic(socket.assigns.template, epic_id) do
        nil ->
          not_found(socket)

        _epic ->
          epic_id
          |> Templates.reorder_template_tasks(ids)
          |> after_reorder(socket)
      end
    end)
  end
```

`template.ex` `update_template/2` error branch:

```elixir
        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not save template")}
```

Update each module's `@moduledoc` `Reads:` line to mention `:current_membership` (gate) where added. Update `Authz`'s moduledoc: "`find_*` return `nil` for unknown ids; handlers flash `not_found/1`."

- [ ] **Step 4: Suite + precommit** — `mix test test/estimate_web/live/templates_live` all green (the six rewritten pass; nothing else changed), then `mix precommit`.

- [ ] **Step 5: Commit**

```bash
git add lib/estimate_web/live/templates_live test/estimate_web/live/templates_live/show_test.exs
git commit -m "fix(templates): admin-gate modal openers and delete confirms; nil-safe lookups; validate epic on task reorder

Members could open epic/task modals and stage deletes (saves were denied, but
UI state was wrong); unknown epic/task ids crashed the LiveView; reorder_tasks
trusted a client epic_id; update_template failures were silent.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## Done criteria

- `show.ex`: 0 `defp`, one delegation per event, HEEx unchanged (diff of the `render/1` body vs base is empty).
- Four handler modules with `Reads:`/`Writes:` moduledocs; `after_reorder/2` lives in `Authz`.
- `show_test.exs` ≈ 27 tests: every handler, member denial for every mutating/opening handler, not-found paths, reorder validation; `show_reorder_test.exs` untouched.
- B3 is one commit; B1/B2 introduce no behaviour change.

## Unresolved questions

None.
