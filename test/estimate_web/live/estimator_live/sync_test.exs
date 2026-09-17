defmodule EstimateWeb.EstimatorLive.SyncTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import EstimateWeb.EstimatorLiveHelpers
  import Estimate.EstimationEngineFixtures, only: [task_fixture: 2]

  alias Estimate.Repo
  alias Estimate.EstimationEngine.{Epic, Task, TaskEstimate}

  setup :setup_estimator

  # a telemetry probe: any SELECT on "estimations" by the LV process = a reload
  defp watch_reloads(lv) do
    test_pid = self()
    handler = "sync-reload-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler,
      [:estimate, :repo, :query],
      fn _e, _m, %{source: source}, _ ->
        if source == "estimations" and self() == lv.pid, do: send(test_pid, :reload)
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)
  end

  defp reloads(n \\ 0),
    do:
      (receive do
         :reload -> reloads(n + 1)
       after
         0 -> n
       end)

  test "task_updated patches the row from the payload without a reload", ctx do
    watch_reloads(ctx.lv)
    render(ctx.lv)
    reloads()

    send(ctx.lv.pid, {:task_updated, %{ctx.task1 | name: "Patched"}})
    html = render(ctx.lv)

    assert html =~ "Patched"
    assert reloads() == 0
    # DB untouched: the payload is the source
    assert Repo.get!(Task, ctx.task1.id).name == "T-one"
    # in-memory estimates on the task survive the patch
    task =
      assigns(ctx.lv).estimation.epics
      |> hd()
      |> Map.fetch!(:tasks)
      |> Enum.find(&(&1.id == ctx.task1.id))

    assert is_list(task.estimates)
  end

  test "epic_updated patches the header row without touching its tasks", ctx do
    watch_reloads(ctx.lv)
    render(ctx.lv)
    reloads()

    send(ctx.lv.pid, {:epic_updated, %{ctx.epic | name: "Alpha Prime"}})
    html = render(ctx.lv)

    assert html =~ "Alpha Prime"
    assert html =~ "T-one" and html =~ "T-two"
    assert reloads() == 0
    assert Repo.get!(Epic, ctx.epic.id).name == "Alpha"
  end

  test "estimate_updated patches the cell, the subtotal and the footer without a reload", ctx do
    watch_reloads(ctx.lv)
    render(ctx.lv)
    reloads()

    estimate = %TaskEstimate{
      id: Ecto.UUID.generate(),
      task_id: ctx.task1.id,
      estimation_role_id: ctx.role.id,
      hours: Decimal.new(9)
    }

    send(ctx.lv.pid, {:estimate_updated, estimate})
    html = render(ctx.lv)

    nine = EstimateWeb.EstimatorLive.Helpers.format_hours(Decimal.new(9))
    assert html =~ nine
    assert Decimal.equal?(assigns(ctx.lv).totals.role_hours[ctx.role.id], Decimal.new(9))
    assert reloads() == 0
  end

  test "creates, deletes and reorders reload", ctx do
    watch_reloads(ctx.lv)
    render(ctx.lv)
    reloads()

    for event <- [
          {:task_created, nil},
          {:epic_deleted, nil},
          {:epics_reordered, []},
          {:tasks_reordered, ctx.epic.id, []},
          {:estimation_updated, nil}
        ] do
      send(ctx.lv.pid, event)
      render(ctx.lv)
      assert reloads() == 1, inspect(event)
    end
  end

  test "a malformed payload falls back to a reload", ctx do
    watch_reloads(ctx.lv)
    render(ctx.lv)
    reloads()

    send(ctx.lv.pid, {:task_updated, nil})
    render(ctx.lv)
    assert reloads() == 1
  end

  test "editing a cell re-inserts only that task row", ctx do
    watch_reloads(ctx.lv)
    key = "#{ctx.task1.id}-#{ctx.role.id}"
    render_click(ctx.lv, "edit_estimate", %{"key" => key})
    assert render(ctx.lv) =~ ~s(id="hours-#{key}")

    render_click(ctx.lv, "cancel_edit", %{})
    refute render(ctx.lv) =~ ~s(id="hours-#{key}")
    assert reloads() == 0
  end

  test "save_estimate is a targeted update; save_rate patches the role in memory without a reload",
       ctx do
    watch_reloads(ctx.lv)
    render(ctx.lv)
    reloads()

    render_click(ctx.lv, "edit_estimate", %{"key" => "#{ctx.task1.id}-#{ctx.role.id}"})

    render_click(ctx.lv, "save_estimate", %{
      "task-id" => ctx.task1.id,
      "role-id" => ctx.role.id,
      "value" => "5"
    })

    assert render(ctx.lv) =~ EstimateWeb.EstimatorLive.Helpers.format_hours(Decimal.new(5))
    assert reloads() == 0

    render_click(ctx.lv, "edit_rate", %{"role-id" => ctx.role.id})
    render_click(ctx.lv, "save_rate", %{"role-id" => ctx.role.id, "value" => "200"})
    assert reloads() == 0
    role = Enum.find(assigns(ctx.lv).estimation.roles, &(&1.id == ctx.role.id))
    assert Decimal.equal?(role.hourly_rate, Decimal.new(200))
  end

  test "a peer task_updated that changes priority under an active filter hides/shows rows correctly and keeps order",
       ctx do
    # A third task that never changes priority, so the epic keeps at least
    # one visible task throughout and a subtotal is possible at every step.
    _task3 = task_fixture(ctx.epic, %{name: "T-three", position: 2, priority: "must"})

    render_click(ctx.lv, "edit_task", %{"id" => ctx.task2.id})

    render_submit(ctx.lv, "save_task", %{
      "task" => %{"name" => "T-two", "priority" => "wont"}
    })

    render_click(ctx.lv, "toggle_priority", %{"priority" => "wont"})
    refute render(ctx.lv) =~ ~s(id="task-#{ctx.task2.id}")

    # (i) T-one's priority changes to "wont" (a peer edit) — it leaves the
    # enabled set and its row must disappear, not linger from a stale insert.
    send(ctx.lv.pid, {:task_updated, %{ctx.task1 | priority: "wont"}})
    refute render(ctx.lv) =~ ~s(id="task-#{ctx.task1.id}")

    # (ii) T-two's priority changes back to "must" — it re-enters the
    # enabled set. Its row must appear, in the correct list position
    # (before the epic subtotal), not appended at the stream's end.
    send(ctx.lv.pid, {:task_updated, %{ctx.task2 | priority: "must"}})
    html = render(ctx.lv)
    assert html =~ ~s(id="task-#{ctx.task2.id}")

    {task_pos, _} = :binary.match(html, ~s(id="task-#{ctx.task2.id}"))
    {subtotal_pos, _} = :binary.match(html, ~s(id="epic-#{ctx.epic.id}-subtotal"))
    assert task_pos < subtotal_pos
  end

  test "estimate_updated from a peer leaves an unrelated epic header element byte-identical",
       ctx do
    before_html = render(element(ctx.lv, "#epic-#{ctx.epic.id}"))

    estimate = %TaskEstimate{
      id: Ecto.UUID.generate(),
      task_id: ctx.task1.id,
      estimation_role_id: ctx.role.id,
      hours: Decimal.new(6)
    }

    send(ctx.lv.pid, {:estimate_updated, estimate})
    render(ctx.lv)

    after_html = render(element(ctx.lv, "#epic-#{ctx.epic.id}"))
    assert after_html == before_html
  end
end
