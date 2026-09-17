defmodule EstimateWeb.EstimatorLive.Grid do
  @moduledoc """
  Owner of the estimator's `:rows` stream and its derived assigns
  (`:totals`, `:grid_empty?`). Every stream mutation goes through here so
  the update matrix (spec 3C) has one implementation.

  Reads: `:estimation`, `:enabled_priorities`, `:show_all_in_rates`.
  Writes: stream `:rows`, `:totals`, `:grid_empty?`.
  """
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [stream: 4, stream_configure: 3]

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
end
