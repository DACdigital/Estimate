defmodule EstimateWeb.EstimatorLive.ViewState do
  @moduledoc """
  Pure view-state toggles: breakdown panel, all-in rates, descriptions,
  MoSCoW priority filter, and closing the generic modal. No engine writes;
  none of these are edit-gated (viewers may use them).

  Reads: `:show_breakdown`, `:show_all_in_rates`, `:show_descriptions`, `:enabled_priorities`.
  Writes: the same four, plus `:modal`, `:epic_form`, `:task_form`, `:current_epic_id` (close_modal).
  """
  use EstimateWeb, :live_handlers

  @all_priorities MapSet.new(["must", "should", "could", "wont"])

  def close_modal(socket, _params) do
    {:noreply,
     socket
     |> assign(:modal, nil)
     |> assign(:epic_form, nil)
     |> assign(:task_form, nil)
     |> assign(:current_epic_id, nil)}
  end

  def toggle_breakdown(socket, _params),
    do: {:noreply, assign(socket, :show_breakdown, !socket.assigns.show_breakdown)}

  def toggle_all_in_rates(socket, _params),
    do: {:noreply, assign(socket, :show_all_in_rates, !socket.assigns.show_all_in_rates)}

  def toggle_descriptions(socket, _params),
    do: {:noreply, assign(socket, :show_descriptions, !socket.assigns.show_descriptions)}

  def toggle_priority(socket, %{"priority" => priority}) do
    current = socket.assigns.enabled_priorities

    updated =
      if MapSet.member?(current, priority) and MapSet.size(current) > 1,
        do: MapSet.delete(current, priority),
        else: MapSet.put(current, priority)

    {:noreply,
     socket
     |> assign(:enabled_priorities, updated)
     |> push_event("save_priorities", %{priorities: MapSet.to_list(updated)})}
  end

  def restore_priorities(socket, %{"priorities" => priorities}) do
    valid = MapSet.intersection(MapSet.new(priorities), @all_priorities)

    if MapSet.size(valid) > 0,
      do: {:noreply, assign(socket, :enabled_priorities, valid)},
      else: {:noreply, socket}
  end

  @doc "Epics with tasks narrowed to the enabled priorities; epics left empty are dropped. Unfiltered when all four are enabled."
  def filtered_epics(estimation, enabled_priorities) do
    if MapSet.size(enabled_priorities) == 4 do
      estimation.epics
    else
      estimation.epics
      |> Enum.map(fn epic ->
        %{
          epic
          | tasks:
              Enum.filter(epic.tasks, &MapSet.member?(enabled_priorities, &1.priority || "must"))
        }
      end)
      |> Enum.reject(&Enum.empty?(&1.tasks))
    end
  end
end
