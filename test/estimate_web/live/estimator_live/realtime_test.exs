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
    gamma = Enum.find(assigns(ctx.lv).estimation.epics, &(&1.name == "Gamma"))
    # Gamma ties with the seeded Alpha epic at position 0 (Epic.changeset/2
    # default); get_estimation!'s tiebreaker (inserted_at, id) decides the order,
    # so assert against that same order instead of assuming creation order.
    expected =
      [ctx.epic, gamma]
      |> Enum.sort_by(&{&1.position, &1.inserted_at, &1.id})
      |> Enum.map(& &1.name)

    assert Enum.map(assigns(ctx.lv).estimation.epics, & &1.name) == expected
  end

  test "every broadcast event triggers a full reload", ctx do
    {:ok, _} = EstimationEngine.update_task(ctx.task1, %{"name" => "T-one-db"})
    # NOTE: characterizes current behaviour; see report. update_task's own
    # broadcast (:task_updated) races the manual :sys.replace_state calls below
    # (different senders give no message-order guarantee), so we render/1 once
    # here to flush that natural broadcast through the LV before staging STALE.
    render(ctx.lv)
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
