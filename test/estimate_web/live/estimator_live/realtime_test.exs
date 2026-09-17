defmodule EstimateWeb.EstimatorLive.RealtimeTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import EstimateWeb.EstimatorLiveHelpers
  import Ecto.Query, only: [from: 2]

  alias Estimate.EstimationEngine
  alias Estimate.Repo
  alias Estimate.EstimationEngine.Task

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

  test "every broadcast event re-streams the grid from the database", ctx do
    events = [
      {:estimation_updated, nil},
      {:epic_created, nil},
      {:epic_deleted, nil},
      {:epics_reordered, nil},
      {:task_created, nil},
      {:task_deleted, nil},
      {:role_created, nil},
      {:role_deleted, nil},
      {:roles_reordered, nil},
      {:tasks_reordered, ctx.epic.id, []}
    ]

    for {event, i} <- Enum.with_index(events, 1) do
      name = "DB-#{i}"
      # diverge in the DB only (no broadcast): the rendered grid must not know yet
      Repo.update_all(from(t in Task, where: t.id == ^ctx.task1.id), set: [name: name])
      refute render(ctx.lv) =~ name, inspect(event)

      send(ctx.lv.pid, event)
      assert render(ctx.lv) =~ name, inspect(event)
    end
  end
end
