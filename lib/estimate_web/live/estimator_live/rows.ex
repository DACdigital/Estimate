defmodule EstimateWeb.EstimatorLive.Rows do
  @moduledoc """
  Pure builder of the estimator grid's stream rows. Three kinds, stable DOM ids:

    * `%Rows.EpicHeader{id: "epic-<id>"}`
    * `%Rows.Task{id: "task-<id>"}` with precomputed `total_hours`/`total_cost`
    * `%Rows.EpicSubtotal{id: "epic-<id>-subtotal"}` — only when the epic has
      more than one *visible* task (mirrors the pre-streams template)

  Row totals are computed here, once per build/insert, never at render.
  """
  alias Estimate.EstimationEngine.Calculator
  alias EstimateWeb.EstimatorLive.ViewState
  import EstimateWeb.EstimatorLive.Helpers, only: [display_roles: 2]

  defmodule EpicHeader, do: defstruct([:id, :epic])
  defmodule Task, do: defstruct([:id, :task, :epic_id, :total_hours, :total_cost])

  defmodule EpicSubtotal,
    do: defstruct([:id, :epic_id, :role_hours, :epic_hours, :epic_total_cost])

  @type view :: %{enabled_priorities: MapSet.t(), show_all_in_rates: boolean()}
  @type row :: %EpicHeader{} | %Task{} | %EpicSubtotal{}

  @doc "The view-state slice rows depend on, taken from socket assigns."
  @spec view(map()) :: view()
  def view(assigns),
    do: %{
      enabled_priorities: assigns.enabled_priorities,
      show_all_in_rates: assigns.show_all_in_rates
    }

  @spec build(map(), view()) :: [row()]
  def build(estimation, view) do
    estimation
    |> ViewState.filtered_epics(view.enabled_priorities)
    |> build_from_filtered(estimation, view)
  end

  @doc """
  Same as `build/2`, but takes epics already narrowed by
  `ViewState.filtered_epics/2` — for callers (`Grid.reset/1`) that need that
  filtered list for something else too and would otherwise filter twice.
  """
  @spec build_from_filtered([map()], map(), view()) :: [row()]
  def build_from_filtered(filtered_epics, estimation, view) do
    roles = display_roles(estimation.roles, view.show_all_in_rates)
    Enum.flat_map(filtered_epics, &epic_rows(&1, estimation.roles, roles))
  end

  @spec for_task(map(), view(), String.t()) :: [row()]
  def for_task(estimation, view, task_id) do
    roles = display_roles(estimation.roles, view.show_all_in_rates)

    estimation
    |> ViewState.filtered_epics(view.enabled_priorities)
    |> Enum.find_value([], fn epic ->
      case Enum.find(epic.tasks, &(&1.id == task_id)) do
        nil -> nil
        task -> [task_row(task, epic, roles) | subtotal_rows(epic, estimation.roles, roles)]
      end
    end)
  end

  @spec for_epic_header(map(), String.t()) :: [row()]
  def for_epic_header(estimation, epic_id) do
    case Enum.find(estimation.epics, &(&1.id == epic_id)) do
      nil -> []
      epic -> [header_row(epic)]
    end
  end

  defp epic_rows(epic, raw_roles, roles) do
    [header_row(epic)] ++
      Enum.map(epic.tasks, &task_row(&1, epic, roles)) ++
      subtotal_rows(epic, raw_roles, roles)
  end

  defp header_row(epic), do: %EpicHeader{id: "epic-#{epic.id}", epic: epic}

  defp task_row(task, epic, roles) do
    %Task{
      id: "task-#{task.id}",
      task: task,
      epic_id: epic.id,
      total_hours: Calculator.task_total_hours(task),
      total_cost: Calculator.task_total_cost(task, roles)
    }
  end

  defp subtotal_rows(%{tasks: tasks}, _raw_roles, _roles) when length(tasks) < 2, do: []

  defp subtotal_rows(epic, raw_roles, roles) do
    [
      %EpicSubtotal{
        id: "epic-#{epic.id}-subtotal",
        epic_id: epic.id,
        role_hours: Map.new(raw_roles, &{&1.id, Calculator.epic_role_hours(epic, &1.id)}),
        epic_hours: Calculator.epic_hours(epic),
        epic_total_cost: Calculator.epic_total_cost(epic, roles)
      }
    ]
  end
end
