defmodule EstimateWeb.EstimatorLive.BroadcastFromTest do
  use EstimateWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import EstimateWeb.EstimatorLiveHelpers

  alias Estimate.EstimationEngine

  setup :setup_estimator

  # Records every SELECT against "estimations" issued by a given LV process.
  defp watch_reloads(lv) do
    test_pid = self()
    handler = "reload-watch-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler,
      [:estimate, :repo, :query],
      fn _e, _m, %{source: source} = meta, _ ->
        if source == "estimations" and self() == lv.pid,
          do: send(test_pid, {:estimation_query, meta.query})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)
    :ok
  end

  defp reload_count(acc \\ 0) do
    receive do
      {:estimation_query, _} -> reload_count(acc + 1)
    after
      0 -> acc
    end
  end

  test "the originating LV does not reload on its own cell edit; a peer LV receives the event",
       ctx do
    {_user, {:ok, peer, _}} = mount_as("editor", ctx)
    watch_reloads(ctx.lv)
    render(ctx.lv)
    reload_count()

    render_click(ctx.lv, "save_estimate", %{
      "task-id" => ctx.task1.id,
      "role-id" => ctx.role.id,
      "value" => "7"
    })

    # flush the originator's mailbox: a self-delivered broadcast would be handled here
    render(ctx.lv)
    assert reload_count() == 0

    render(peer)

    hours =
      peer
      |> assigns()
      |> Map.fetch!(:estimation)
      |> Map.fetch!(:epics)
      |> hd()
      |> Map.fetch!(:tasks)
      |> Enum.find(&(&1.id == ctx.task1.id))
      |> Map.fetch!(:estimates)
      |> Enum.find(&(&1.estimation_role_id == ctx.role.id))
      |> Map.fetch!(:hours)

    assert Decimal.equal?(hours, Decimal.new(7))
  end

  test "a write from another process still reaches every LV", ctx do
    {_user, {:ok, peer, _}} = mount_as("editor", ctx)

    task =
      Task.async(fn ->
        Estimate.Repo.put_org_id(ctx.org.id)
        Estimate.Repo.put_user_id(ctx.owner.id)
        EstimationEngine.create_epic(%{"name" => "FromMCP", "estimation_id" => ctx.est.id})
      end)

    {:ok, _} = Task.await(task)
    assert render(ctx.lv) =~ "FromMCP"
    assert render(peer) =~ "FromMCP"
  end

  test "reorder_roles applies locally without waiting for a broadcast", ctx do
    [r1, r2 | rest] = ctx.est.roles
    ids = Enum.map([r2, r1 | rest], & &1.id)

    render_click(ctx.lv, "reorder_roles", %{"ids" => ids})
    assert Enum.map(assigns(ctx.lv).estimation.roles, & &1.id) == ids
  end
end
