# Audit Batch 1 — Security Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the reproduced estimator IDOR and viewer project-edit bugs, stop parent-FK mass assignment, harden the RLS DB role, and throttle login/2FA/OAuth endpoints.

**Architecture:** Web-layer authorization is centralised in `EstimateWeb.AuthHelpers`; the estimator resolves children from its in-memory `@estimation` instead of org-scoped DB lookups. Schemas gain `update_changeset/2` without parent FKs; contexts validate org-owned references. A supervised Hammer ETS limiter backs login, 2FA and OAuth throttling.

**Tech Stack:** Elixir 1.18 / Phoenix 1.8.3 / LiveView 1.1 / Ecto 3.13 / Postgres 17 RLS / `hammer ~> 7.4`.

**Spec:** `docs/superpowers/specs/2026-09-02-audit-batch-1-security-design.md`

## Global Constraints

- No table/column migrations. Only the role migration in Task 7.
- Every task: failing test first, then code, then `mix test <file>` green, then commit.
- Tests follow diverge-then-assert: put the forbidden state in place, prove rejection, prove DB unchanged.
- Before the final commit run `mix precommit` (compile --warnings-as-errors, format, full tests).
- Flash copy exactly: `"Not authorized"`, `"Not found"`, `"You don't have edit access"`, `"Too many attempts. Try again in N seconds."`, `"Too many failed attempts. Please log in again."`.
- Test helpers: `EstimateWeb.ConnCase` gives `log_in_user/2`; fixtures `user_with_organization_fixture/0`, `user_fixture/0`, `membership_fixture/3`, `project_fixture/2`, `estimation_fixture/1`, `epic_fixture/2`, `task_fixture/2`, `user_with_totp_fixture/0`, `valid_totp_code/1`. LiveView assigns via `:sys.get_state(lv.pid).socket.assigns`.
- Run a single file with `mix test path/to/file.exs`; the `test` alias also runs `ecto.create`/`ecto.migrate`.

---

### Task 1: Shared `can_edit_project?/2` and the viewer project-edit fix

**Files:**
- Modify: `lib/estimate_web/auth_helpers.ex`
- Modify: `lib/estimate_web/live/project_live/index.ex:319-339` (`apply_action(:edit)`), `:441-461` (`save_project(:edit)`)
- Modify: `lib/estimate_web/live/project_live/show.ex:230-242` (`init_permissions`)
- Modify: `lib/estimate_web/live/estimator_live/index.ex:758-761` (`can_edit?`)
- Modify: `.gitignore` (add `.claude/worktrees/`)
- Test: `test/estimate_web/live/project_live/index_test.exs`

**Interfaces:**
- Produces: `EstimateWeb.AuthHelpers.can_edit_project?(membership :: %{role: String.t()} | nil, collaborator :: %{role: String.t()} | nil) :: boolean()` — imported automatically in every LiveView via `use EstimateWeb, :live_view` (see `lib/estimate_web.ex:55,77,90`).

- [ ] **Step 1: Write the failing tests**

Append to `test/estimate_web/live/project_live/index_test.exs` (keep existing content; add these imports/aliases at the top if missing: `import Phoenix.LiveViewTest`, `import Estimate.{AccountsFixtures, PortfolioFixtures}`, `alias Estimate.{Portfolio, Repo}`):

```elixir
  describe "edit gating" do
    setup do
      %{user: owner, organization: org} = user_with_organization_fixture()
      project = project_fixture(nil, owner)
      viewer = user_fixture()
      _ = membership_fixture(viewer, org, "member")
      {:ok, _} = Portfolio.add_collaborator(project.id, viewer.id, "viewer")
      editor = user_fixture()
      _ = membership_fixture(editor, org, "member")
      {:ok, _} = Portfolio.add_collaborator(project.id, editor.id, "editor")
      %{org: org, project: project, viewer: viewer, editor: editor}
    end

    test "viewer collaborator cannot save project edits", %{conn: conn} = ctx do
      {:ok, lv, _} =
        live(log_in_user(conn, ctx.viewer), ~p"/org/#{ctx.org.id}/projects/#{ctx.project.id}/edit")

      # the edit action itself must bounce a viewer back to the index
      assert_patch(lv, ~p"/org/#{ctx.org.id}/projects")
      assert render(lv) =~ "Not authorized"

      # forged save event even after the bounce
      render_submit(lv, "save", %{"project" => %{"name" => "VIEWER-RENAMED"}})
      assert Repo.get!(Estimate.Portfolio.Project, ctx.project.id).name == ctx.project.name
    end

    test "editor collaborator can save project edits", %{conn: conn} = ctx do
      {:ok, lv, _} =
        live(log_in_user(conn, ctx.editor), ~p"/org/#{ctx.org.id}/projects/#{ctx.project.id}/edit")

      render_submit(lv, "save", %{"project" => %{"name" => "EDITOR-RENAMED"}})
      assert Repo.get!(Estimate.Portfolio.Project, ctx.project.id).name == "EDITOR-RENAMED"
    end
  end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/estimate_web/live/project_live/index_test.exs`
Expected: the viewer test FAILS (no patch happens; name becomes `VIEWER-RENAMED`). The editor test passes already.

- [ ] **Step 3: Add the shared predicate**

In `lib/estimate_web/auth_helpers.ex` add after `admin?/1`:

```elixir
  @edit_roles ["owner", "editor"]

  @doc "True when the membership is org admin/owner or the collaborator row has an editing role."
  def can_edit_project?(membership, collaborator) do
    admin?(membership) or (collaborator != nil and collaborator.role in @edit_roles)
  end
```

- [ ] **Step 4: Use it in ProjectLive.Index**

Replace both gate blocks. `apply_action(:edit)` becomes:

```elixir
  defp apply_action(socket, :edit, %{"id" => id}) do
    collaborator = Portfolio.get_collaborator(id, socket.assigns.current_user.id)

    if can_edit_project?(socket.assigns.current_membership, collaborator) do
      project = Portfolio.get_project!(id, socket.assigns.org_id)
      changeset = Portfolio.change_project(project)
      customer_key = if project.customer, do: project.customer.key

      socket
      |> assign(:page_title, "Edit Project")
      |> assign(:project, project)
      |> assign(:customer_key, customer_key)
      |> assign(:form, to_form(changeset))
    else
      socket
      |> put_flash(:error, "Not authorized")
      |> push_patch(to: ~p"/org/#{socket.assigns.org_id}/projects")
    end
  end
```

`save_project(:edit)` becomes:

```elixir
  defp save_project(socket, :edit, project_params) do
    project = socket.assigns.project
    collaborator = Portfolio.get_collaborator(project.id, socket.assigns.current_user.id)

    if can_edit_project?(socket.assigns.current_membership, collaborator) do
      case Portfolio.update_project(project, project_params) do
        {:ok, project} ->
          {:noreply,
           socket
           |> put_flash(:info, "Project updated successfully")
           |> push_navigate(to: ~p"/org/#{socket.assigns.org_id}/projects/#{project.id}")}

        {:error, changeset} ->
          {:noreply, assign(socket, form: to_form(changeset))}
      end
    else
      {:noreply, put_flash(socket, :error, "Not authorized")}
    end
  end
```

Note: after the viewer bounce, `socket.assigns.project` may be `nil`. Add a clause before the one above:

```elixir
  defp save_project(%{assigns: %{project: nil}} = socket, :edit, _params),
    do: {:noreply, put_flash(socket, :error, "Not authorized")}
```

Check `mount`/`apply_action(:index)` assign `:project` to `nil`; if they do not, add `|> assign(:project, nil)` in `mount`.

- [ ] **Step 5: Use it in ProjectLive.Show and the estimator**

`show.ex` `init_permissions`: replace `assign(:can_edit_project, is_org_admin || collab_role in ["owner", "editor"])` with `assign(:can_edit_project, can_edit_project?(membership, current_collaborator))`.

`estimator_live/index.ex`: delete the private `can_edit?/2` (lines 758-761) and in `mount` replace `can_edit = can_edit?(collaborator, socket.assigns.current_membership)` with `can_edit = can_edit_project?(socket.assigns.current_membership, collaborator)`.

- [ ] **Step 6: Add worktree dir to .gitignore**

Append a line `.claude/worktrees/` to `.gitignore`.

- [ ] **Step 7: Run tests**

Run: `mix test test/estimate_web/live/project_live/index_test.exs test/estimate_web/live/project_live/show_test.exs test/estimate_web/live/org_scoped_smoke_test.exs`
Expected: all PASS.

- [ ] **Step 8: Commit**

```bash
git add .gitignore lib/estimate_web/auth_helpers.ex lib/estimate_web/live/project_live/index.ex lib/estimate_web/live/project_live/show.ex lib/estimate_web/live/estimator_live/index.ex test/estimate_web/live/project_live/index_test.exs
git commit -m "fix(authz): shared can_edit_project?; viewer can no longer edit project via index modal"
```

---

### Task 2: Estimator resolves epics/tasks in memory; gate confirm and AI handlers

**Files:**
- Modify: `lib/estimate_web/live/estimator_live/index.ex` handlers at `:233-291` (epics), `:293-370` (tasks), `:676-702` (AI), helpers near `:786-790`
- Create: `test/estimate_web/live/estimator_live/index_authz_test.exs`

**Interfaces:**
- Consumes: `can_edit_project?/2` from Task 1.
- Produces (private, estimator only): `find_epic(estimation, id) :: %Epic{} | nil`, `find_task(estimation, id) :: %Task{} | nil`.

- [ ] **Step 1: Write the failing tests**

Create `test/estimate_web/live/estimator_live/index_authz_test.exs`:

```elixir
defmodule EstimateWeb.EstimatorLive.IndexAuthzTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Estimate.{AccountsFixtures, PortfolioFixtures, EstimationEngineFixtures}

  alias Estimate.{Portfolio, Repo}
  alias Estimate.EstimationEngine.{Epic, Task}

  defp assigns(lv), do: :sys.get_state(lv.pid).socket.assigns

  defp estimator_path(org, project, estimation),
    do: ~p"/org/#{org.id}/projects/#{project.id}/estimations/#{estimation.id}/estimator"

  # member is EDITOR on project A and VIEWER on project B, both in the same org.
  # B's epic/task are visible to them (RLS allows collaborators) but must not be editable
  # from A's estimator.
  setup %{conn: conn} do
    %{user: owner, organization: org} = user_with_organization_fixture()
    project_a = project_fixture(nil, owner)
    project_b = project_fixture(nil, owner)
    est_a = estimation_fixture(project_a)
    est_b = estimation_fixture(project_b)
    epic_b = epic_fixture(est_b, %{name: "B-EPIC"})
    task_b = task_fixture(epic_b, %{name: "B-TASK"})

    member = user_fixture()
    _ = membership_fixture(member, org, "member")
    {:ok, _} = Portfolio.add_collaborator(project_a.id, member.id, "editor")
    {:ok, _} = Portfolio.add_collaborator(project_b.id, member.id, "viewer")

    viewer = user_fixture()
    _ = membership_fixture(viewer, org, "member")
    {:ok, _} = Portfolio.add_collaborator(project_a.id, viewer.id, "viewer")

    {:ok, lv, _} = live(log_in_user(conn, member), estimator_path(org, project_a, est_a))

    %{conn: conn, org: org, project_a: project_a, est_a: est_a, epic_b: epic_b, task_b: task_b,
      member: member, viewer: viewer, lv: lv}
  end

  describe "foreign estimation ids are rejected in memory" do
    test "confirm_delete_epic + delete_epic", %{lv: lv, epic_b: epic_b} do
      render_click(lv, "confirm_delete_epic", %{"id" => epic_b.id})
      assert assigns(lv).deleting_epic == nil
      assert render(lv) =~ "Not found"

      render_click(lv, "delete_epic", %{})
      assert Repo.get(Epic, epic_b.id)
    end

    test "edit_epic + save_epic", %{lv: lv, epic_b: epic_b} do
      render_click(lv, "edit_epic", %{"id" => epic_b.id})
      assert assigns(lv).epic_form == nil
      assert render(lv) =~ "Not found"

      assert Repo.get!(Epic, epic_b.id).name == "B-EPIC"
    end

    test "add_task into foreign epic", %{lv: lv, epic_b: epic_b} do
      render_click(lv, "add_task", %{"epic-id" => epic_b.id})
      assert assigns(lv).current_epic_id == nil
      assert render(lv) =~ "Not found"

      render_submit(lv, "save_task", %{"task" => %{"name" => "INJECTED"}})
      refute Repo.get_by(Task, epic_id: epic_b.id, name: "INJECTED")
    end

    test "edit_task + confirm_delete_task + delete_task", %{lv: lv, task_b: task_b} do
      render_click(lv, "edit_task", %{"id" => task_b.id})
      assert assigns(lv).task_form == nil

      render_click(lv, "confirm_delete_task", %{"id" => task_b.id})
      assert assigns(lv).deleting_task == nil

      render_click(lv, "delete_task", %{})
      assert Repo.get(Task, task_b.id)
    end
  end

  describe "own estimation still works" do
    test "confirm_delete_epic on own epic sets the assign", %{lv: lv, est_a: est_a} do
      epic_a = epic_fixture(est_a, %{name: "A-EPIC"})
      # LV loaded before the epic existed: reload via the PubSub path the LV listens on
      send(lv.pid, {:epic_created, epic_a})
      render(lv)

      render_click(lv, "confirm_delete_epic", %{"id" => epic_a.id})
      assert assigns(lv).deleting_epic.id == epic_a.id
    end
  end

  describe "viewer on this project" do
    setup %{conn: conn, org: org, project_a: project_a, est_a: est_a, viewer: viewer} do
      epic_a = epic_fixture(est_a, %{name: "A-EPIC"})
      {:ok, lv, _} = live(log_in_user(conn, viewer), estimator_path(org, project_a, est_a))
      %{vlv: lv, epic_a: epic_a}
    end

    test "confirm_delete_epic is denied", %{vlv: lv, epic_a: epic_a} do
      render_click(lv, "confirm_delete_epic", %{"id" => epic_a.id})
      assert assigns(lv).deleting_epic == nil
      assert render(lv) =~ "You don&#39;t have edit access"
    end

    test "ai_enhance_description is denied", %{vlv: lv} do
      render_click(lv, "ai_enhance_description", %{
        "description" => "x", "name" => "y", "target" => "epic"
      })
      assert assigns(lv).ai_loading == nil
      assert render(lv) =~ "You don&#39;t have edit access"
    end
  end
end
```

Check the `handle_info({:epic_created, _}, socket)` clause exists at `index.ex:723-740` (it reloads the estimation); if the clause name differs, use the event name that `Epics.create_epic` broadcasts (`{:epic_created, epic}`).

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/estimate_web/live/estimator_live/index_authz_test.exs`
Expected: foreign-id tests FAIL (assigns set, rows mutated/deleted); viewer tests FAIL on `confirm_delete_epic` (assign set) and `ai_enhance_description` (`ai_loading` set or "AI not configured" flash).

- [ ] **Step 3: Add in-memory finders**

In `estimator_live/index.ex`, next to `belongs_to_estimation?/3`:

```elixir
  defp find_epic(%{epics: epics}, id), do: Enum.find(epics, &(&1.id == id))

  defp find_task(%{epics: epics}, id),
    do: Enum.find_value(epics, fn epic -> Enum.find(epic.tasks, &(&1.id == id)) end)

  defp not_found(socket), do: {:noreply, put_flash(socket, :error, "Not found")}
```

- [ ] **Step 4: Rewrite the epic handlers**

```elixir
  def handle_event("edit_epic", %{"id" => id}, socket) do
    with_edit_auth(socket, fn socket ->
      case find_epic(socket.assigns.estimation, id) do
        nil ->
          not_found(socket)

        epic ->
          changeset = EstimationEngine.Epic.changeset(epic, %{})

          {:noreply,
           socket
           |> assign(:modal, :epic)
           |> assign(:epic_form, to_form(changeset))}
      end
    end)
  end

  def handle_event("confirm_delete_epic", %{"id" => id}, socket) do
    with_edit_auth(socket, fn socket ->
      case find_epic(socket.assigns.estimation, id) do
        nil -> not_found(socket)
        epic -> {:noreply, assign(socket, :deleting_epic, epic)}
      end
    end)
  end

  def handle_event("delete_epic", _params, socket) do
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
```

(Task 5 later switches `Epic.changeset(epic, %{})` to `Epic.update_changeset/2`; leave as is for now.)

- [ ] **Step 5: Rewrite the task handlers**

```elixir
  def handle_event("add_task", %{"epic-id" => epic_id}, socket) do
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

  def handle_event("edit_task", %{"id" => id}, socket) do
    with_edit_auth(socket, fn socket ->
      case find_task(socket.assigns.estimation, id) do
        nil ->
          not_found(socket)

        task ->
          changeset = EstimationEngine.Task.changeset(task, %{})

          {:noreply,
           socket
           |> assign(:modal, :task)
           |> assign(:task_form, to_form(changeset))
           |> assign(:current_epic_id, task.epic_id)}
      end
    end)
  end

  def handle_event("confirm_delete_task", %{"id" => id}, socket) do
    with_edit_auth(socket, fn socket ->
      case find_task(socket.assigns.estimation, id) do
        nil -> not_found(socket)
        task -> {:noreply, assign(socket, :deleting_task, task)}
      end
    end)
  end

  def handle_event("delete_task", _params, socket) do
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
```

`save_task` for a new task reads `socket.assigns.current_epic_id`; after a denied `add_task` it is `nil`. Make the denial explicit at the top of the `save_task` closure:

```elixir
      task = socket.assigns.task_form && socket.assigns.task_form.data
      epic_id = socket.assigns.current_epic_id

      cond do
        is_nil(task) -> not_found(socket)
        is_nil(task.id) and is_nil(epic_id) -> not_found(socket)
        true -> <existing save body using task and epic_id>
      end
```

- [ ] **Step 6: Gate the AI handler**

Wrap the existing `ai_enhance_description` body in `with_edit_auth(socket, fn socket -> ... end)`. Keep `Task.start` for now (moving to `start_async` is a later batch).

- [ ] **Step 7: Run tests**

Run: `mix test test/estimate_web/live/estimator_live/index_authz_test.exs test/estimate_web/live/org_scoped_smoke_test.exs`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/estimate_web/live/estimator_live/index.ex test/estimate_web/live/estimator_live/index_authz_test.exs
git commit -m "fix(estimator): resolve epics/tasks from loaded estimation; gate confirm and AI handlers (closes cross-project IDOR)"
```

---

### Task 3: Gate `confirm_delete_project` and customer `confirm_delete`

**Files:**
- Modify: `lib/estimate_web/live/project_live/show/danger_zone.ex:14-22`
- Modify: `lib/estimate_web/live/customer_live/show.ex:194-202`
- Test: `test/estimate_web/live/project_live/show_test.exs` (append), `test/estimate_web/live/customer_live/show_authz_test.exs` (create)

- [ ] **Step 1: Write failing tests**

Append to `show_test.exs` inside an existing `describe` that has `setup :setup_project` and the `add_collab/3` helper (see `show_test.exs:31-37`):

```elixir
    test "viewer cannot open the delete-project confirmation", %{conn: conn, org: org, project: project} do
      %{user: viewer} = add_collab(project, org, "viewer")
      {:ok, lv, _} = live(log_in_user(conn, viewer), project_path(org, project))

      render_click(lv, "confirm_delete_project", %{})
      refute assigns(lv).deleting_project
      assert render(lv) =~ "Not authorized"
    end
```

Create `test/estimate_web/live/customer_live/show_authz_test.exs`:

```elixir
defmodule EstimateWeb.CustomerLive.ShowAuthzTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Estimate.{AccountsFixtures, CRMFixtures}

  defp assigns(lv), do: :sys.get_state(lv.pid).socket.assigns

  test "non-admin member cannot open the delete confirmation", %{conn: conn} do
    %{user: owner, organization: org} = user_with_organization_fixture()
    customer = customer_fixture(org)
    member = user_fixture()
    _ = membership_fixture(member, org, "member")
    _ = owner

    {:ok, lv, _} = live(log_in_user(conn, member), ~p"/org/#{org.id}/customers/#{customer.id}")
    render_click(lv, "confirm_delete", %{})

    refute assigns(lv).deleting_customer
    assert render(lv) =~ "Not authorized"
  end
end
```

Check `customer_fixture/1` signature in `test/support/fixtures/crm_fixtures.ex` (it may take `org` or `nil`); adjust the call.

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/estimate_web/live/project_live/show_test.exs test/estimate_web/live/customer_live/show_authz_test.exs`
Expected: both new tests FAIL (`deleting_project`/`deleting_customer` become true).

- [ ] **Step 3: Gate DangerZone**

```elixir
  def confirm_delete_project(socket, _params) do
    require_can_delete(socket, [deleting_project: false], fn ->
      impact = Portfolio.deletion_impact(socket.assigns.project)

      {:noreply,
       socket
       |> assign(:deleting_project, true)
       |> assign(:delete_impact, impact)
       |> assign(:delete_confirmation_input, "")}
    end)
  end
```

- [ ] **Step 4: Gate CustomerLive.Show**

```elixir
  def handle_event("confirm_delete", _params, socket) do
    require_admin(socket, fn ->
      impact = CRM.deletion_impact(socket.assigns.customer)

      {:noreply,
       socket
       |> assign(:deleting_customer, true)
       |> assign(:delete_impact, impact)
       |> assign(:delete_confirmation_input, "")}
    end)
  end
```

- [ ] **Step 5: Run tests, commit**

Run: `mix test test/estimate_web/live/project_live/show_test.exs test/estimate_web/live/customer_live/`
Expected: PASS.

```bash
git add lib/estimate_web/live/project_live/show/danger_zone.ex lib/estimate_web/live/customer_live/show.ex test/estimate_web/live/project_live/show_test.exs test/estimate_web/live/customer_live/show_authz_test.exs
git commit -m "fix(authz): gate delete confirmations for project and customer"
```

---

### Task 4: `update_changeset/2` for engine schemas

**Files:**
- Modify: `lib/estimate/estimation_engine/epic.ex`, `task.ex`, `estimation.ex`, `estimation_role.ex`, `task_estimate.ex`
- Modify: `lib/estimate/estimation_engine/epics.ex:24-30`, `tasks.ex:67-72`, `estimations.ex:117-122`, `roles.ex:24-30`, `estimates.ex:41-44`
- Modify: `lib/estimate_web/live/estimator_live/index.ex` (`edit_epic`, `edit_task`, `validate_task` use `update_changeset` when the struct has an id)
- Test: `test/estimate/estimation_engine/update_changeset_test.exs` (create)

**Interfaces:**
- Produces: `Epic.update_changeset/2`, `Task.update_changeset/2`, `Estimation.update_changeset/2`, `EstimationRole.update_changeset/2`, `TaskEstimate.update_changeset/2` — same validations as `changeset/2` minus parent FKs and `is_current`.

- [ ] **Step 1: Write failing tests**

```elixir
defmodule Estimate.EstimationEngine.UpdateChangesetTest do
  use Estimate.DataCase, async: true

  import Estimate.{AccountsFixtures, PortfolioFixtures, EstimationEngineFixtures}
  alias Estimate.EstimationEngine
  alias Estimate.EstimationEngine.{Epic, Task, Estimation, EstimationRole, TaskEstimate}

  setup do
    %{user: owner, organization: org} = user_with_organization_fixture()
    project = project_fixture(nil, owner)
    # estimation_fixture/1 returns a bare Repo.get!; reload with roles preloaded
    est_a = EstimationEngine.get_estimation!(estimation_fixture(project).id, org.id)
    est_b = estimation_fixture(project)
    epic_a = epic_fixture(est_a)
    epic_b = epic_fixture(est_b)
    task_a = task_fixture(epic_a)
    %{est_a: est_a, est_b: est_b, epic_a: epic_a, epic_b: epic_b, task_a: task_a}
  end

  test "update_epic ignores estimation_id", %{epic_a: epic_a, est_b: est_b} do
    {:ok, epic} = EstimationEngine.update_epic(epic_a, %{"name" => "renamed", "estimation_id" => est_b.id})
    assert epic.name == "renamed"
    assert epic.estimation_id == epic_a.estimation_id
  end

  test "update_task ignores epic_id", %{task_a: task_a, epic_b: epic_b} do
    {:ok, task} = EstimationEngine.update_task(task_a, %{"name" => "renamed", "epic_id" => epic_b.id})
    assert task.epic_id == task_a.epic_id
  end

  test "update_estimation ignores project_id and is_current", %{est_a: est_a} do
    {:ok, est} = EstimationEngine.update_estimation(est_a, %{"is_current" => true, "project_id" => Ecto.UUID.generate()})
    assert est.project_id == est_a.project_id
    assert est.is_current == est_a.is_current
  end

  test "update_role ignores estimation_id", %{est_a: est_a, est_b: est_b} do
    [role | _] = est_a.roles
    {:ok, role2} = EstimationEngine.update_role(role, %{"hourly_rate" => "10", "estimation_id" => est_b.id})
    assert role2.estimation_id == est_a.id
  end

  test "schema update_changesets never cast parent keys" do
    refute Map.has_key?(Epic.update_changeset(%Epic{}, %{"estimation_id" => Ecto.UUID.generate()}).changes, :estimation_id)
    refute Map.has_key?(Task.update_changeset(%Task{}, %{"epic_id" => Ecto.UUID.generate()}).changes, :epic_id)
    refute Map.has_key?(Estimation.update_changeset(%Estimation{}, %{"project_id" => Ecto.UUID.generate(), "is_current" => true}).changes, :project_id)
    refute Map.has_key?(EstimationRole.update_changeset(%EstimationRole{}, %{"project_role_id" => Ecto.UUID.generate()}).changes, :project_role_id)
    refute Map.has_key?(TaskEstimate.update_changeset(%TaskEstimate{}, %{"task_id" => Ecto.UUID.generate()}).changes, :task_id)
  end
end
```

`create_estimation/1` seeds default roles, so `est_a.roles` is non-empty after the `get_estimation!` reload.

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/estimate/estimation_engine/update_changeset_test.exs`
Expected: FAIL — `update_changeset/2` undefined; the `ignores` tests show parent ids changing.

- [ ] **Step 3: Add `update_changeset/2` to the five schemas**

`epic.ex`:
```elixir
  def update_changeset(epic, attrs) do
    epic
    |> cast(attrs, [:name, :description, :position])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 200)
  end
```
`task.ex`:
```elixir
  def update_changeset(task, attrs) do
    task
    |> cast(attrs, [:name, :description, :position, :priority])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 500)
    |> validate_inclusion(:priority, @priorities)
  end
```
`estimation.ex`:
```elixir
  def update_changeset(estimation, attrs) do
    estimation
    |> cast(attrs, [:name, :description, :currency_id])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 200)
    |> foreign_key_constraint(:currency_id)
  end
```
`estimation_role.ex`:
```elixir
  def update_changeset(role, attrs) do
    role
    |> cast(attrs, [:name, :abbreviation, :hourly_rate, :position, :pm_overhead, :qa_overhead, :risk_buffer])
    |> validate_required([:name, :abbreviation])
    |> validate_length(:abbreviation, min: 1, max: 5)
    |> validate_number(:hourly_rate, greater_than_or_equal_to: 0)
    |> validate_number(:pm_overhead, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:qa_overhead, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:risk_buffer, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
  end
```
`task_estimate.ex`:
```elixir
  def update_changeset(estimate, attrs) do
    estimate
    |> cast(attrs, [:hours])
    |> validate_number(:hours, greater_than_or_equal_to: 0)
  end
```

- [ ] **Step 4: Switch contexts to `update_changeset`**

`epics.ex` `update_epic`: `Epic.changeset(attrs)` → `Epic.update_changeset(attrs)`. `tasks.ex` `update_task`: `Task.changeset` → `Task.update_changeset`. `estimations.ex` `update_estimation`: `Estimation.changeset` → `Estimation.update_changeset`. `roles.ex` `update_role`: `EstimationRole.changeset` → `EstimationRole.update_changeset`. `estimates.ex` `update_task_estimate`: `TaskEstimate.changeset` → `TaskEstimate.update_changeset`. Leave `set_current_estimation` (`estimations.ex:167`) on `Estimation.changeset` — internal, trusted attrs.

- [ ] **Step 5: Estimator edit forms**

In `estimator_live/index.ex`: `edit_epic` → `Epic.update_changeset(epic, %{})`; `edit_task` → `Task.update_changeset(task, %{})`; `validate_task`:

```elixir
  def handle_event("validate_task", %{"task" => task_params}, socket) do
    task = socket.assigns.task_form.data

    changeset =
      if task.id,
        do: EstimationEngine.Task.update_changeset(task, task_params),
        else: EstimationEngine.Task.changeset(task, task_params)

    {:noreply, assign(socket, :task_form, changeset |> Map.put(:action, :validate) |> to_form())}
  end
```

- [ ] **Step 6: Run tests, commit**

Run: `mix test test/estimate/estimation_engine/ test/estimate_web/live/estimator_live/ test/estimate_web/mcp/tools/`
Expected: PASS (MCP update tools call the same context functions; their tests must stay green).

```bash
git add lib/estimate/estimation_engine/ lib/estimate_web/live/estimator_live/index.ex test/estimate/estimation_engine/update_changeset_test.exs
git commit -m "fix(engine): update_changeset/2 never casts parent keys or is_current"
```

---

### Task 5: Org-owned reference validation for customers, projects, estimations

**Files:**
- Create: `lib/estimate/changeset_helpers.ex`
- Modify: `lib/estimate/portfolio.ex:165-172` (`create_project`), `:219-233` (`update_project`)
- Modify: `lib/estimate/crm.ex:50-66` (`create_customer`), `:69-84` (`update_customer`)
- Modify: `lib/estimate/estimation_engine/estimations.ex:117-122` (`update_estimation`)
- Test: `test/estimate/org_reference_test.exs` (create)

**Interfaces:**
- Produces: `Estimate.ChangesetHelpers.validate_org_reference(changeset, field, schema, org_id) :: Ecto.Changeset.t()`; error message `"does not belong to this organization"`.

- [ ] **Step 1: Write failing tests**

```elixir
defmodule Estimate.OrgReferenceTest do
  use Estimate.DataCase, async: true

  import Estimate.{AccountsFixtures, PortfolioFixtures, CRMFixtures, EstimationEngineFixtures}
  alias Estimate.{Portfolio, CRM, EstimationEngine}
  alias Estimate.Organizations.Currencies

  setup do
    %{user: owner_a, organization: org_a} = user_with_organization_fixture()
    %{organization: org_b} = user_with_organization_fixture()
    customer_b = customer_fixture(org_b)
    [currency_b | _] = Currencies.list_currencies(org_b.id)
    project_a = project_fixture(nil, owner_a)
    %{org_a: org_a, org_b: org_b, owner_a: owner_a, customer_b: customer_b, currency_b: currency_b, project_a: project_a}
  end

  test "update_project rejects a customer from another org", ctx do
    {:error, cs} = Portfolio.update_project(ctx.project_a, %{"customer_id" => ctx.customer_b.id})
    assert %{customer_id: ["does not belong to this organization"]} = errors_on(cs)
  end

  test "update_project rejects a currency from another org", ctx do
    {:error, cs} = Portfolio.update_project(ctx.project_a, %{"currency_id" => ctx.currency_b.id})
    assert %{currency_id: ["does not belong to this organization"]} = errors_on(cs)
  end

  test "create_project rejects a foreign currency", ctx do
    customer_a = customer_fixture(ctx.org_a)
    {:error, cs} =
      Portfolio.create_project(%{"name" => "P", "currency_id" => ctx.currency_b.id}, customer_a.id, ctx.owner_a.id, ctx.org_a.id)
    assert %{currency_id: ["does not belong to this organization"]} = errors_on(cs)
  end

  test "create/update_customer reject a foreign default currency", ctx do
    {:error, cs} = CRM.create_customer(ctx.org_a.id, %{"key" => "AB", "name" => "A", "default_currency_id" => ctx.currency_b.id})
    assert %{default_currency_id: ["does not belong to this organization"]} = errors_on(cs)

    customer_a = customer_fixture(ctx.org_a)
    {:error, cs} = CRM.update_customer(customer_a, %{"default_currency_id" => ctx.currency_b.id})
    assert %{default_currency_id: ["does not belong to this organization"]} = errors_on(cs)
  end

  test "update_estimation rejects a foreign currency", ctx do
    est = estimation_fixture(ctx.project_a)
    {:error, cs} = EstimationEngine.update_estimation(est, %{"currency_id" => ctx.currency_b.id})
    assert %{currency_id: ["does not belong to this organization"]} = errors_on(cs)
  end

  test "same-org references are accepted", ctx do
    [currency_a | _] = Currencies.list_currencies(ctx.org_a.id)
    {:ok, p} = Portfolio.update_project(ctx.project_a, %{"currency_id" => currency_a.id})
    assert p.currency_id == currency_a.id
  end
end
```

Check `customer_fixture/1` arity in `test/support/fixtures/crm_fixtures.ex` and adapt (it may accept `org` or `attrs`).

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/estimate/org_reference_test.exs`
Expected: FAIL — updates succeed with foreign ids (or raise FK/RLS errors).

- [ ] **Step 3: Create the helper**

`lib/estimate/changeset_helpers.ex`:

```elixir
defmodule Estimate.ChangesetHelpers do
  @moduledoc """
  Cross-cutting changeset validations that need the database.
  """

  import Ecto.Changeset
  import Ecto.Query, only: [from: 2]
  alias Estimate.Repo

  @doc """
  Adds an error on `field` when the changed value does not reference a row of
  `schema` owned by `org_id`. Skips when the field is unchanged or nil.
  Runs inside the caller's RLS context: a row hidden by RLS also fails.
  """
  def validate_org_reference(changeset, field, schema, org_id) do
    validate_change(changeset, field, fn ^field, id ->
      exists? =
        Repo.exists?(from(r in schema, where: r.id == ^id and r.organization_id == ^org_id))

      if exists?, do: [], else: [{field, "does not belong to this organization"}]
    end)
  end
end
```

- [ ] **Step 4: Apply in Portfolio**

`create_project`: replace the `Ecto.Multi.insert(:project, ...)` changeset with

```elixir
        %Project{}
        |> Project.changeset(Map.put(attrs, "customer_id", customer_id))
        |> ChangesetHelpers.validate_org_reference(:customer_id, Customer, org_id)
        |> ChangesetHelpers.validate_org_reference(:currency_id, Currency, org_id)
```

and add `alias Estimate.ChangesetHelpers`, `alias Estimate.CRM.Customer`, `alias Estimate.Accounts.Currency` at the module top (check existing aliases first).

`update_project`:

```elixir
      project
      |> Project.changeset(attrs)
      |> ChangesetHelpers.validate_org_reference(:customer_id, Customer, project.organization_id)
      |> ChangesetHelpers.validate_org_reference(:currency_id, Currency, project.organization_id)
      |> Repo.update()
```

- [ ] **Step 5: Apply in CRM and Estimations**

`crm.ex` `create_customer`: after `put_change(:organization_id, org_id)` add `|> ChangesetHelpers.validate_org_reference(:default_currency_id, Currency, org_id)`. `update_customer`: after `Customer.changeset(attrs)` add the same with `customer.organization_id`.

`estimations.ex` `update_estimation`: after `Estimation.update_changeset(attrs)` add `|> ChangesetHelpers.validate_org_reference(:currency_id, Estimate.Accounts.Currency, estimation.organization_id)`.

- [ ] **Step 6: Run tests, commit**

Run: `mix test test/estimate/org_reference_test.exs test/estimate/ test/estimate_web/mcp/tools/`
Expected: PASS.

```bash
git add lib/estimate/changeset_helpers.ex lib/estimate/portfolio.ex lib/estimate/crm.ex lib/estimate/estimation_engine/estimations.ex test/estimate/org_reference_test.exs
git commit -m "fix(contexts): reference FKs must belong to the org (customer, currency)"
```

---

### Task 6: `estimate_app` becomes NOLOGIN, loses CREATE on schema

**Files:**
- Create: `priv/repo/migrations/20260902120000_harden_app_role.exs`
- Test: `test/estimate/app_role_test.exs` (create)

- [ ] **Step 1: Write failing test**

```elixir
defmodule Estimate.AppRoleTest do
  use Estimate.DataCase, async: true

  test "estimate_app cannot log in and cannot create schema objects" do
    %{rows: [[can_login]]} =
      Estimate.Repo.query!("SELECT rolcanlogin FROM pg_roles WHERE rolname = 'estimate_app'")

    refute can_login

    %{rows: [[can_create]]} =
      Estimate.Repo.query!("SELECT has_schema_privilege('estimate_app', 'public', 'CREATE')")

    refute can_create
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/estimate/app_role_test.exs`
Expected: FAIL (`rolcanlogin` true, `has_schema_privilege` true).

- [ ] **Step 3: Write the migration**

```elixir
defmodule Estimate.Repo.Migrations.HardenAppRole do
  use Ecto.Migration

  # estimate_app is only ever assumed via SET ROLE (see Estimate.Repo.after_connect/1);
  # it never needs LOGIN and never creates schema objects.
  def up do
    execute "ALTER ROLE estimate_app NOLOGIN"
    execute "REVOKE CREATE ON SCHEMA public FROM estimate_app"
  end

  def down do
    execute "GRANT CREATE ON SCHEMA public TO estimate_app"
    execute "ALTER ROLE estimate_app LOGIN"
  end
end
```

- [ ] **Step 4: Run tests, commit**

Run: `mix test test/estimate/app_role_test.exs test/estimate/repo_without_rls_test.exs`
Expected: PASS (the `test` alias migrates first).

```bash
git add priv/repo/migrations/20260902120000_harden_app_role.exs test/estimate/app_role_test.exs
git commit -m "fix(db): estimate_app role NOLOGIN, no CREATE on schema"
```

---

### Task 7: `Estimate.RateLimit` on Hammer

**Files:**
- Modify: `mix.exs` (add `{:hammer, "~> 7.4"}`)
- Create: `lib/estimate/rate_limit.ex`
- Modify: `lib/estimate/application.ex` (child before `EstimateWeb.Endpoint`)
- Modify: `config/config.exs`, `config/test.exs`
- Test: `test/estimate/rate_limit_test.exs` (create)

**Interfaces:**
- Produces: `Estimate.RateLimit.check(bucket, key) :: {:allow, pos_integer()} | {:deny, retry_after_ms :: pos_integer()}` for buckets `:login_email | :login_ip | :totp_attempt | :totp_replay | :oauth_ip`; `Estimate.RateLimit.retry_seconds(ms) :: pos_integer()`.

- [ ] **Step 1: Add the dependency**

In `mix.exs` deps add `{:hammer, "~> 7.4"}`. Run `mix deps.get`.

- [ ] **Step 2: Write failing test**

```elixir
defmodule Estimate.RateLimitTest do
  use ExUnit.Case, async: true

  alias Estimate.RateLimit

  test "allows up to the limit then denies with retry ms" do
    key = "rl-test-#{System.unique_integer([:positive])}"
    for n <- 1..5, do: assert({:allow, ^n} = RateLimit.check(:totp_attempt, key))
    assert {:deny, ms} = RateLimit.check(:totp_attempt, key)
    assert ms > 0
  end

  test "totp_replay allows a code once per user" do
    user_id = Ecto.UUID.generate()
    assert {:allow, 1} = RateLimit.check(:totp_replay, {user_id, "123456"})
    assert {:deny, _} = RateLimit.check(:totp_replay, {user_id, "123456"})
    assert {:allow, 1} = RateLimit.check(:totp_replay, {user_id, "654321"})
  end

  test "retry_seconds rounds up" do
    assert RateLimit.retry_seconds(1) == 1
    assert RateLimit.retry_seconds(1_001) == 2
  end
end
```

- [ ] **Step 3: Run to verify failure**

Run: `mix test test/estimate/rate_limit_test.exs`
Expected: FAIL — module undefined.

- [ ] **Step 4: Implement**

`lib/estimate/rate_limit.ex`:

```elixir
defmodule Estimate.RateLimit do
  @moduledoc """
  Fixed-window rate limiting for auth-sensitive endpoints, backed by Hammer's ETS store.

  Limits are read from `config :estimate, Estimate.RateLimit` so the test env can
  raise IP-scoped limits (every test shares 127.0.0.1).
  """
  use Hammer, backend: :ets

  @windows %{
    login_email: :timer.minutes(1),
    login_ip: :timer.minutes(1),
    totp_attempt: :timer.minutes(15),
    totp_replay: :timer.seconds(90),
    oauth_ip: :timer.minutes(1)
  }

  @defaults %{login_email: 10, login_ip: 60, totp_attempt: 5, totp_replay: 1, oauth_ip: 20}

  @type bucket :: :login_email | :login_ip | :totp_attempt | :totp_replay | :oauth_ip

  @spec check(bucket(), term()) :: {:allow, pos_integer()} | {:deny, pos_integer()}
  def check(bucket, key) when is_map_key(@windows, bucket) do
    hit("#{bucket}:#{normalize(key)}", Map.fetch!(@windows, bucket), limit(bucket))
  end

  @spec retry_seconds(pos_integer()) :: pos_integer()
  def retry_seconds(ms), do: max(div(ms + 999, 1000), 1)

  defp limit(bucket) do
    :estimate
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(bucket, Map.fetch!(@defaults, bucket))
  end

  defp normalize(key) when is_binary(key), do: String.downcase(key)
  defp normalize({a, b}), do: "#{normalize(a)}|#{normalize(b)}"
  defp normalize(key), do: to_string(key)
end
```

`application.ex` children: insert `{Estimate.RateLimit, [clean_period: :timer.minutes(1)]}` after `{Task.Supervisor, name: Estimate.TaskSupervisor}`.

`config/config.exs` (after the mailer block):

```elixir
config :estimate, Estimate.RateLimit,
  login_email: 10,
  login_ip: 60,
  totp_attempt: 5,
  totp_replay: 1,
  oauth_ip: 20
```

`config/test.exs`:

```elixir
# All tests share 127.0.0.1; only per-identity buckets are meaningful here.
config :estimate, Estimate.RateLimit, login_ip: 100_000, oauth_ip: 100_000
```

- [ ] **Step 5: Run tests, commit**

Run: `mix test test/estimate/rate_limit_test.exs && mix compile --warnings-as-errors`
Expected: PASS.

```bash
git add mix.exs mix.lock lib/estimate/rate_limit.ex lib/estimate/application.ex config/config.exs config/test.exs test/estimate/rate_limit_test.exs
git commit -m "feat(security): Estimate.RateLimit on hammer (ets)"
```

---

### Task 8: Throttle `POST /users/log_in`

**Files:**
- Create: `lib/estimate_web/client_ip.ex`
- Modify: `lib/estimate_web/controllers/user_session_controller.ex` (`create/2`)
- Test: `test/estimate_web/controllers/user_session_controller_test.exs` (append), `test/estimate_web/client_ip_test.exs` (create)

**Interfaces:**
- Consumes: `Estimate.RateLimit.check/2`, `retry_seconds/1` (Task 7).
- Produces: `EstimateWeb.ClientIP.get(Plug.Conn.t()) :: String.t()`.

- [ ] **Step 1: Write failing tests**

`test/estimate_web/client_ip_test.exs`:

```elixir
defmodule EstimateWeb.ClientIPTest do
  use ExUnit.Case, async: true
  import Plug.Test
  alias EstimateWeb.ClientIP

  test "uses remote_ip when no forwarded header" do
    conn = conn(:get, "/")
    assert ClientIP.get(conn) == "127.0.0.1"
  end

  test "uses first x-forwarded-for hop" do
    conn = conn(:get, "/") |> Plug.Conn.put_req_header("x-forwarded-for", "203.0.113.7, 10.0.0.1")
    assert ClientIP.get(conn) == "203.0.113.7"
  end
end
```

Append to `user_session_controller_test.exs`:

```elixir
  describe "POST /users/log_in throttling" do
    test "11th attempt for the same email within a minute is refused", %{conn: conn} do
      user = user_fixture()
      params = %{"user" => %{"email" => user.email, "password" => "wrong"}}
      for _ <- 1..10, do: post(build_conn(), ~p"/users/log_in", params)

      conn = post(conn, ~p"/users/log_in", %{"user" => %{"email" => user.email, "password" => @password}})

      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Too many attempts"
      assert redirected_to(conn) == ~p"/users/log_in"
    end
  end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/estimate_web/client_ip_test.exs test/estimate_web/controllers/user_session_controller_test.exs`
Expected: FAIL — `ClientIP` undefined; 11th login succeeds.

- [ ] **Step 3: Implement ClientIP**

```elixir
defmodule EstimateWeb.ClientIP do
  @moduledoc """
  Best-effort client address for rate limiting: first `x-forwarded-for` hop when the
  app sits behind a proxy, else the socket peer. Spoofable without a trusted proxy,
  which is why every IP bucket is paired with an identity bucket.
  """

  @spec get(Plug.Conn.t()) :: String.t()
  def get(%Plug.Conn{} = conn) do
    case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
      [forwarded | _] ->
        forwarded |> String.split(",", parts: 2) |> hd() |> String.trim()

      [] ->
        conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end
end
```

- [ ] **Step 4: Throttle in the controller**

Replace `create/2`:

```elixir
  def create(conn, %{"user" => user_params} = params) do
    %{"email" => email, "password" => password} = user_params
    return_to = UserAuth.safe_return_to(params["return_to"])

    with {:allow, _} <- RateLimit.check(:login_ip, ClientIP.get(conn)),
         {:allow, _} <- RateLimit.check(:login_email, email) do
      do_create(conn, email, password, user_params, return_to)
    else
      {:deny, retry_ms} ->
        conn
        |> put_flash(:error, "Too many attempts. Try again in #{RateLimit.retry_seconds(retry_ms)} seconds.")
        |> redirect(to: login_path(return_to))
    end
  end

  defp do_create(conn, email, password, user_params, return_to) do
    if user = Accounts.get_user_by_email_and_password(email, password) do
      conn = if return_to, do: put_session(conn, :user_return_to, return_to), else: conn

      if User.totp_enabled?(user) do
        conn
        |> UserAuth.put_pending_2fa(user, user_params)
        |> redirect(to: ~p"/users/two-factor")
      else
        conn
        |> put_flash(:info, "Welcome back!")
        |> UserAuth.log_in_user(user, user_params)
      end
    else
      conn
      |> put_flash(:error, "Invalid email or password")
      |> redirect(to: login_path(return_to))
    end
  end

  defp login_path(nil), do: ~p"/users/log_in"
  defp login_path(return_to), do: ~p"/users/log_in?#{%{return_to: return_to}}"
```

Add `alias Estimate.RateLimit` and `alias EstimateWeb.ClientIP` at the top.

- [ ] **Step 5: Run tests, commit**

Run: `mix test test/estimate_web/client_ip_test.exs test/estimate_web/controllers/user_session_controller_test.exs test/estimate_web/live/auth_smoke_test.exs`
Expected: PASS.

```bash
git add lib/estimate_web/client_ip.ex lib/estimate_web/controllers/user_session_controller.ex test/estimate_web/client_ip_test.exs test/estimate_web/controllers/user_session_controller_test.exs
git commit -m "feat(security): throttle password login per email and per ip"
```

---

### Task 9: Server-side 2FA attempt counter and TOTP replay guard

**Files:**
- Modify: `lib/estimate_web/user_auth.ex:144-158` (remove cookie counter)
- Modify: `lib/estimate_web/controllers/user_session_controller.ex` (`verify_totp/2`, `do_verify_totp/2`)
- Test: `test/estimate_web/controllers/user_session_controller_test.exs` (append)

**Interfaces:**
- Consumes: `RateLimit.check(:totp_attempt, user_id)`, `RateLimit.check(:totp_replay, {user_id, code})`.
- Removes: `UserAuth.increment_2fa_attempts/1`, `UserAuth.too_many_2fa_attempts?/1`, `@max_2fa_attempts`, and `delete_session(:pending_2fa_attempts)` in `clear_pending_2fa/1`.

- [ ] **Step 1: Write failing tests**

Append inside `describe "POST /users/two-factor/verify"` (it has `%{conn: conn, user: user, secret: secret}` from setup, `conn` already in pending-2FA state):

```elixir
    test "five wrong codes lock the pending session even when the cookie is replayed", %{conn: conn, secret: secret} do
      # replay the SAME pre-attempt cookie every time: a client-side counter would never trip
      for _ <- 1..5 do
        c = post(conn, ~p"/users/two-factor/verify", %{"code" => "000000"})
        refute get_session(c, :user_token)
      end

      locked = post(conn, ~p"/users/two-factor/verify", %{"code" => valid_totp_code(secret)})
      refute get_session(locked, :user_token)
      refute get_session(locked, :pending_2fa_user_id)
      assert Phoenix.Flash.get(locked.assigns.flash, :error) =~ "Too many failed attempts"
      assert redirected_to(locked) == ~p"/users/log_in"
    end

    test "a valid TOTP code cannot be replayed", %{conn: conn, user: user, secret: secret} do
      code = valid_totp_code(secret)
      first = post(conn, ~p"/users/two-factor/verify", %{"code" => code})
      assert get_session(first, :user_token)

      again =
        post(build_conn(), ~p"/users/log_in", %{"user" => %{"email" => user.email, "password" => @password}})
        |> post(~p"/users/two-factor/verify", %{"code" => code})

      refute get_session(again, :user_token)
      assert Phoenix.Flash.get(again.assigns.flash, :error) =~ "Invalid verification code"
    end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/estimate_web/controllers/user_session_controller_test.exs`
Expected: both FAIL — replayed cookie never locks; replayed code logs in.

- [ ] **Step 3: Remove the cookie counter from UserAuth**

Delete `@max_2fa_attempts`, `increment_2fa_attempts/1`, `too_many_2fa_attempts?/1`; drop `|> delete_session(:pending_2fa_attempts)` from `clear_pending_2fa/1`. Grep `2fa_attempts` across `lib/` and `test/` to confirm no other callers.

- [ ] **Step 4: Rewrite verification in the controller**

```elixir
  def verify_totp(conn, %{"code" => code}) do
    case UserAuth.get_pending_2fa_user(conn) do
      nil ->
        conn
        |> put_flash(:error, "Session expired. Please log in again.")
        |> redirect(to: ~p"/users/log_in")

      user ->
        code = String.trim(code)

        with :ok <- attempt_allowed(user),
             {:ok, secret} <- Totp.get_decrypted_secret(user),
             true <- Totp.valid_code_or_backup?(user, secret, code),
             :ok <- replay_allowed(user, code) do
          remember_params = UserAuth.pending_2fa_remember_me_params(conn)

          conn
          |> UserAuth.clear_pending_2fa()
          |> put_flash(:info, "Welcome back!")
          |> UserAuth.log_in_user(user, remember_params)
        else
          :locked ->
            lock_out(conn)

          _invalid_or_replayed ->
            conn
            |> put_flash(:error, "Invalid verification code")
            |> redirect(to: ~p"/users/two-factor")
        end
    end
  end

  # The attempt bucket is hit on every submission (valid or not): 5 submissions per
  # 15 minutes per pending user, counted server-side so cookie replay cannot reset it.
  defp attempt_allowed(user) do
    case RateLimit.check(:totp_attempt, user.id) do
      {:allow, _} -> :ok
      {:deny, _} -> :locked
    end
  end

  # A valid code is accepted once per 90 s window; a replay reads as an invalid code.
  defp replay_allowed(user, code) do
    case RateLimit.check(:totp_replay, {user.id, code}) do
      {:allow, _} -> :ok
      {:deny, _} -> :replayed
    end
  end

  defp lock_out(conn) do
    conn
    |> UserAuth.clear_pending_2fa()
    |> put_flash(:error, "Too many failed attempts. Please log in again.")
    |> redirect(to: ~p"/users/log_in")
  end
```

Delete `do_verify_totp/2`. Add `alias Estimate.RateLimit` if Task 8 has not already.

- [ ] **Step 5: Run tests, commit**

Run: `mix test test/estimate_web/controllers/user_session_controller_test.exs test/estimate_web/user_auth_test.exs test/estimate_web/live/user_live/account_security_test.exs`
Expected: PASS. The existing "invalid code stays on two-factor" and "backup code logs in once" tests must still pass.

```bash
git add lib/estimate_web/user_auth.ex lib/estimate_web/controllers/user_session_controller.ex test/estimate_web/controllers/user_session_controller_test.exs
git commit -m "fix(security): server-side 2FA attempt limit and TOTP replay guard; drop cookie counter"
```

---

### Task 10: Rate-limit plug on OAuth register/token

**Files:**
- Create: `lib/estimate_web/plugs/rate_limit.ex`
- Modify: `lib/estimate_web/controllers/oauth_registration_controller.ex`, `oauth_token_controller.ex` (add `plug EstimateWeb.Plugs.RateLimit, bucket: :oauth_ip`)
- Test: `test/estimate_web/controllers/oauth_rate_limit_test.exs` (create)

**Interfaces:**
- Consumes: `RateLimit.check/2`, `ClientIP.get/1`.

- [ ] **Step 1: Write failing test**

```elixir
defmodule EstimateWeb.OAuthRateLimitTest do
  # async: false — temporarily lowers the shared oauth_ip limit
  use EstimateWeb.ConnCase, async: false

  setup do
    prev = Application.get_env(:estimate, Estimate.RateLimit)
    Application.put_env(:estimate, Estimate.RateLimit, Keyword.put(prev, :oauth_ip, 3))
    on_exit(fn -> Application.put_env(:estimate, Estimate.RateLimit, prev) end)
    # unique forwarded ip so other suites' hits on 127.0.0.1 don't interfere
    %{ip: "198.51.100.#{:rand.uniform(250)}"}
  end

  test "4th request from one ip within a minute gets 429", %{conn: conn, ip: ip} do
    post_reg = fn ->
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-forwarded-for", ip)
      |> post(~p"/oauth/register", Jason.encode!(%{client_name: "X", redirect_uris: ["https://claude.ai/cb"]}))
    end

    for _ <- 1..3, do: assert(post_reg.().status in [201, 400])
    conn = post_reg.()
    assert json_response(conn, 429) == %{"error" => "too_many_requests"}
    assert [retry] = get_resp_header(conn, "retry-after")
    assert String.to_integer(retry) >= 1
  end

  test "token endpoint shares the bucket", %{conn: conn, ip: ip} do
    for _ <- 1..3 do
      conn |> put_req_header("x-forwarded-for", ip) |> post(~p"/oauth/token", %{"grant_type" => "nope"})
    end

    conn = conn |> put_req_header("x-forwarded-for", ip) |> post(~p"/oauth/token", %{"grant_type" => "nope"})
    assert json_response(conn, 429)["error"] == "too_many_requests"
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/estimate_web/controllers/oauth_rate_limit_test.exs`
Expected: FAIL — 4th request returns 201/400.

- [ ] **Step 3: Implement the plug**

```elixir
defmodule EstimateWeb.Plugs.RateLimit do
  @moduledoc "Per-client-IP fixed-window limit for JSON endpoints. `bucket:` selects the Estimate.RateLimit bucket."
  import Plug.Conn

  alias Estimate.RateLimit
  alias EstimateWeb.ClientIP

  def init(opts), do: Keyword.fetch!(opts, :bucket)

  def call(conn, bucket) do
    case RateLimit.check(bucket, ClientIP.get(conn)) do
      {:allow, _} ->
        conn

      {:deny, retry_ms} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(RateLimit.retry_seconds(retry_ms)))
        |> put_resp_content_type("application/json")
        |> send_resp(429, Jason.encode!(%{error: "too_many_requests"}))
        |> halt()
    end
  end
end
```

Add `plug EstimateWeb.Plugs.RateLimit, bucket: :oauth_ip` after `use EstimateWeb, :controller` in both OAuth controllers (in the token controller, before `plug :no_store`).

- [ ] **Step 4: Run tests, commit**

Run: `mix test test/estimate_web/controllers/oauth_rate_limit_test.exs test/estimate_web/controllers/oauth_registration_test.exs test/estimate_web/controllers/oauth_token_test.exs test/estimate_web/oauth_end_to_end_test.exs`
Expected: PASS (existing OAuth suites make far fewer than 100_000 requests).

```bash
git add lib/estimate_web/plugs/rate_limit.ex lib/estimate_web/controllers/oauth_registration_controller.ex lib/estimate_web/controllers/oauth_token_controller.ex test/estimate_web/controllers/oauth_rate_limit_test.exs
git commit -m "feat(security): per-ip rate limit on OAuth register and token endpoints"
```

---

### Task 11: Full verification

**Files:** none new.

- [ ] **Step 1: Run precommit**

Run: `mix precommit`
Expected: compile with no warnings, unused deps check clean, format clean, all tests pass (533 + new).

- [ ] **Step 2: Re-run the audit probe scenario mentally against tests**

Confirm these tests exist and pass: `index_authz_test.exs` (estimator IDOR), `project_live/index_test.exs` "viewer collaborator cannot save project edits", `user_session_controller_test.exs` cookie-replay lockout and TOTP replay, `oauth_rate_limit_test.exs`, `app_role_test.exs`, `org_reference_test.exs`, `update_changeset_test.exs`.

- [ ] **Step 3: Commit any formatter output**

```bash
git add -A
git commit -m "chore: format" || true
```
