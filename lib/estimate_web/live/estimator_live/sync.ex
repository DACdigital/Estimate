defmodule EstimateWeb.EstimatorLive.Sync do
  @moduledoc """
  Maps PubSub events from `Estimate.EstimationEngine` onto the grid (spec 3C
  update matrix). Payload-carrying updates patch `@estimation` in memory and
  re-insert only the affected rows; everything else reloads and resets.

  Reads: `:estimation`. Writes: `:estimation`, stream `:rows`, `:totals`, `:grid_empty?`.
  """
  import EstimateWeb.EstimatorLive.Authz, only: [reload_estimation: 1]
  import Phoenix.Component, only: [assign: 3]
  alias EstimateWeb.EstimatorLive.{Estimates, Grid}

  def handle({:estimate_updated, %{task_id: task_id} = estimate}, socket)
      when is_binary(task_id) do
    estimation = Estimates.update_estimate_in_memory(socket.assigns.estimation, estimate)
    {:noreply, socket |> assign(:estimation, estimation) |> Grid.upsert_task(task_id)}
  end

  def handle({:task_updated, %{id: id, name: _} = task}, socket) when is_binary(id) do
    estimation = Estimates.update_task_in_memory(socket.assigns.estimation, task)
    {:noreply, socket |> assign(:estimation, estimation) |> Grid.upsert_task(id)}
  end

  def handle({:epic_updated, %{id: id, name: _} = epic}, socket) when is_binary(id) do
    estimation = Estimates.update_epic_in_memory(socket.assigns.estimation, epic)
    {:noreply, socket |> assign(:estimation, estimation) |> Grid.upsert_epic_header(id)}
  end

  def handle({:role_updated, %{id: id, hourly_rate: _} = role}, socket) when is_binary(id) do
    estimation = Estimates.update_role_in_memory(socket.assigns.estimation, role)
    {:noreply, socket |> assign(:estimation, estimation) |> Grid.reset()}
  end

  # creates, deletes, reorders, estimation_updated, and any malformed payload
  def handle(_event, socket), do: {:noreply, reload_estimation(socket)}
end
