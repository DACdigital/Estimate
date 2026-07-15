defmodule EstimateWeb.ProjectLive.Show.Dashboard do
  @moduledoc """
  Overview-tab estimation-dashboard view-selector handler.

  Reads: none (params only).
  Writes: `:dashboard_tab`.
  """
  use EstimateWeb, :live_handlers

  @allowed_dashboard_tabs ~w(by_role by_epic by_priority)

  def set_dashboard_tab(socket, %{"tab" => tab}) when tab in @allowed_dashboard_tabs do
    {:noreply, assign(socket, :dashboard_tab, String.to_existing_atom(tab))}
  end

  def set_dashboard_tab(socket, _params), do: {:noreply, socket}
end
