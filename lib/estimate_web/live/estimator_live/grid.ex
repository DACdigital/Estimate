defmodule EstimateWeb.EstimatorLive.Grid do
  @moduledoc """
  Owner of the estimator's `:rows` stream and its derived assigns
  (`:totals`, `:grid_empty?`). Every stream mutation goes through here so
  the update matrix (spec 3C) has one implementation.

  Reads: `:estimation`, `:enabled_priorities`, `:show_all_in_rates`.
  Writes: stream `:rows`, `:totals`, `:grid_empty?`.
  """
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [stream: 4, stream_configure: 3, stream_insert: 3]

  alias EstimateWeb.EstimatorLive.{Rows, Totals, ViewState}

  @doc "Configure the stream (once, in mount) and render the initial rows."
  def init(socket) do
    socket
    |> stream_configure(:rows, dom_id: & &1.id)
    |> reset()
  end

  @doc "Rebuild every row and every total from `@estimation` and the view state."
  def reset(socket) do
    estimation = socket.assigns.estimation
    view = Rows.view(socket.assigns)
    rows = Rows.build(estimation, view)

    socket
    |> stream(:rows, rows, reset: true)
    |> assign_totals(estimation, view)
    |> assign(:grid_empty?, rows == [])
  end

  @doc false
  def assign_totals(socket, estimation, view) do
    epics = ViewState.filtered_epics(estimation, view.enabled_priorities)
    assign(socket, :totals, Totals.compute(epics, estimation.roles, view.show_all_in_rates))
  end

  @doc "Re-insert the task's row (+ its epic subtotal) and recompute totals."
  def upsert_task(socket, task_id) do
    estimation = socket.assigns.estimation
    view = Rows.view(socket.assigns)

    estimation
    |> Rows.for_task(view, task_id)
    |> Enum.reduce(socket, &stream_insert(&2, :rows, &1))
    |> assign_totals(estimation, view)
  end

  @doc "Re-insert one epic header row."
  def upsert_epic_header(socket, epic_id) do
    socket.assigns.estimation
    |> Rows.for_epic_header(epic_id)
    |> Enum.reduce(socket, &stream_insert(&2, :rows, &1))
  end

  @doc "Re-insert the task rows behind the previous and the new editing key (\"<task_id>-<role_id>\")."
  def refresh_editing(socket, old_key, new_key) do
    # editing keys are "<task_id>-<role_id>"; both are 36-char UUIDs (dashes inside), so slice, don't split
    [old_key, new_key]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&String.slice(&1, 0, 36))
    |> Enum.uniq()
    |> Enum.reduce(socket, fn task_id, sock -> upsert_task_rows_only(sock, task_id) end)
  end

  defp upsert_task_rows_only(socket, task_id) do
    socket.assigns.estimation
    |> Rows.for_task(Rows.view(socket.assigns), task_id)
    |> Enum.reduce(socket, &stream_insert(&2, :rows, &1))
  end
end
