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
    # NOTE: characterizes current behaviour; see report. save_task never assigns a
    # position on create (Task.changeset/2 defaults :position to 0), so T-three ties
    # with T-one (also position 0) and get_estimation!'s `order_by: t.position` has
    # no deterministic tiebreaker between them - asserting a set, not exact order.
    assert Enum.sort(Enum.map(hd(a.estimation.epics).tasks, & &1.name)) ==
             ["T-one", "T-three", "T-two"]

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

    test "validate_task is not edit-gated: a viewer with no open form gets Not found, not the edit-access flash",
         ctx do
      html = render_change(ctx.vlv, "validate_task", %{"task" => %{"name" => "x"}})
      assert html =~ "Not found"
      refute html =~ "You don&#39;t have edit access"
      assert assigns(ctx.vlv).task_form == nil
    end
  end
end
