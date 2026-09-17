defmodule EstimateWeb.Bench.EstimatorGridBenchTest do
  @moduledoc """
  Timing harness for the estimator grid. Run with:

      mix test --include bench test/bench/estimator_grid_bench_test.exs

  Seeds 20 epics x 5 tasks (100 tasks) with the default roles, then times
  (a) 20 cell edits, (b) 5 full reloads via a PubSub :epic_created event,
  (c) one priority toggle. Record the printed block in the commit message.

  Cell edits and priority toggle include test-client DOM work via render/1.
  Reloads are split: server measures :sys.get_state after handle_info (pushed
  diff unapplied in mailbox); client measures rendering all queued diffs to
  the test Floki DOM.
  """
  use EstimateWeb.ConnCase, async: false
  @moduletag :bench

  import Phoenix.LiveViewTest
  import Estimate.{AccountsFixtures, PortfolioFixtures, EstimationEngineFixtures}

  alias Estimate.EstimationEngine

  setup %{conn: conn} do
    %{user: owner, organization: org} = user_with_organization_fixture()
    project = project_fixture(nil, owner)
    est = estimation_fixture(project)

    for e <- 1..20 do
      epic = epic_fixture(est, %{name: "Epic #{e}", position: e})
      for t <- 1..5, do: task_fixture(epic, %{name: "Task #{e}.#{t}", position: t})
    end

    est = EstimationEngine.get_estimation!(est.id, org.id)
    conn = log_in_user(conn, owner)

    {:ok, lv, _} =
      live(conn, ~p"/org/#{org.id}/projects/#{project.id}/estimations/#{est.id}/estimator")

    %{lv: lv, est: est, role: hd(est.roles)}
  end

  test "cell edit, reload and filter timings", %{lv: lv, est: est, role: role} do
    tasks = est.epics |> Enum.flat_map(& &1.tasks) |> Enum.take(20)

    {edit_us, _} =
      :timer.tc(fn ->
        for {task, i} <- Enum.with_index(tasks, 1) do
          render_click(lv, "edit_estimate", %{"key" => "#{task.id}-#{role.id}"})

          render_click(lv, "save_estimate", %{
            "task-id" => task.id,
            "role-id" => role.id,
            "value" => Integer.to_string(i)
          })
        end
      end)

    # Server-only: :sys.get_state returns once handle_info has been processed;
    # the pushed diff sits in the test client's mailbox unapplied.
    {reload_server_us, _} =
      :timer.tc(fn ->
        for _ <- 1..5 do
          send(lv.pid, {:epic_created, nil})
          :sys.get_state(lv.pid)
        end
      end)

    # Client-only: applying the 5 queued diffs to the test client's Floki DOM.
    {reload_client_us, _} = :timer.tc(fn -> render(lv) end)

    {filter_us, _} =
      :timer.tc(fn ->
        render_click(lv, "toggle_priority", %{"priority" => "wont"})
        render_click(lv, "toggle_priority", %{"priority" => "wont"})
      end)

    IO.puts("""

    estimator grid bench (100 tasks x #{length(est.roles)} roles)
      20 cell edits:      #{div(edit_us, 1000)} ms  (#{div(edit_us, 20_000)} ms/edit)
      5 pubsub reloads (server): #{div(reload_server_us, 1000)} ms  (#{div(reload_server_us, 5_000)} ms/reload)
      5 pubsub reloads (client): #{div(reload_client_us, 1000)} ms
      priority toggle x2: #{div(filter_us, 1000)} ms
    """)

    assert edit_us > 0
  end
end
