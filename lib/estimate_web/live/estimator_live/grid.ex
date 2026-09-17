defmodule EstimateWeb.EstimatorLive.Grid do
  @moduledoc """
  Owner of the estimator's `:rows` stream and its derived assigns
  (`:totals`, `:grid_empty?`). Every stream mutation goes through here so
  the update matrix (spec 3C) has one implementation.

  `stream_insert/3` with the default `at: -1` APPENDS any dom_id not
  currently rendered; every targeted update must therefore only touch rows
  already in the DOM, or fall back to `reset/1`.

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
    # Filtered once, shared by the row builder and the totals — the two used
    # to each filter the estimation's epics independently.
    filtered = ViewState.filtered_epics(estimation, view.enabled_priorities)
    rows = Rows.build_from_filtered(filtered, estimation, view)

    socket
    |> stream(:rows, rows, reset: true)
    |> assign_totals(filtered, view)
    |> assign(:grid_empty?, rows == [])
  end

  @doc false
  def assign_totals(socket, filtered_epics, view) do
    assign(
      socket,
      :totals,
      Totals.compute(filtered_epics, socket.assigns.estimation.roles, view.show_all_in_rates)
    )
  end

  @doc """
  Re-insert the task's row (+ its epic subtotal) and recompute totals. Falls
  back to a full `reset/1` when the task is no longer visible (filtered out,
  e.g. a priority change moved it out of the enabled set) — `Rows.for_task/3`
  then returns `[]`, and doing nothing would leave a stale row appended by a
  future insert, or leave it rendered when it should have disappeared.
  """
  def upsert_task(socket, task_id) do
    estimation = socket.assigns.estimation
    view = Rows.view(socket.assigns)
    filtered = ViewState.filtered_epics(estimation, view.enabled_priorities)

    case Rows.for_task(estimation, view, task_id) do
      [] ->
        reset(socket)

      rows ->
        rows
        |> Enum.reduce(socket, &stream_insert(&2, :rows, &1))
        |> assign_totals(filtered, view)
    end
  end

  @doc """
  Re-insert one epic header row. No totals recompute: the header row shows
  no numbers and priority is a task field.
  """
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
