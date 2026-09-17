defmodule EstimateWeb.EstimatorLive.GridTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import EstimateWeb.EstimatorLiveHelpers
  import Ecto.Query, only: [from: 2]

  alias Estimate.Repo
  alias Estimate.EstimationEngine.Task

  setup :setup_estimator

  test "mount renders the grid as a stream container with stable row ids", ctx do
    html = render(ctx.lv)
    assert html =~ ~s(id="epics-container")
    assert html =~ ~s(phx-update="stream")
    assert html =~ ~s(id="epic-#{ctx.epic.id}")
    assert html =~ ~s(id="task-#{ctx.task1.id}")
    assert html =~ ~s(id="task-#{ctx.task2.id}")
    assert html =~ ~s(id="epic-#{ctx.epic.id}-subtotal")
    assert %EstimateWeb.EstimatorLive.Totals{empty?: false} = assigns(ctx.lv).totals
    refute assigns(ctx.lv).grid_empty?
  end

  test "a DB change reaches the DOM only after a reset event (stream is not re-rendered by itself)",
       ctx do
    Repo.update_all(from(t in Task, where: t.id == ^ctx.task1.id), set: [name: "DB-RENAMED"])
    refute render(ctx.lv) =~ "DB-RENAMED"

    send(ctx.lv.pid, {:task_created, nil})
    assert render(ctx.lv) =~ "DB-RENAMED"
  end

  test "the footer reads from @totals", ctx do
    render_click(ctx.lv, "edit_estimate", %{"key" => "#{ctx.task1.id}-#{ctx.role.id}"})

    render_click(ctx.lv, "save_estimate", %{
      "task-id" => ctx.task1.id,
      "role-id" => ctx.role.id,
      "value" => "3"
    })

    totals = assigns(ctx.lv).totals
    assert Decimal.equal?(totals.total_hours, Decimal.new(3))
    assert Decimal.equal?(totals.role_hours[ctx.role.id], Decimal.new(3))
    assert render(ctx.lv) =~ EstimateWeb.EstimatorLive.Helpers.format_hours(Decimal.new(3))
  end

  test "deleting the last epic shows the empty state", ctx do
    render_click(ctx.lv, "confirm_delete_epic", %{"id" => ctx.epic.id})
    render_click(ctx.lv, "delete_epic", %{})
    assert assigns(ctx.lv).grid_empty?
    assert render(ctx.lv) =~ "No epics yet"
  end
end
