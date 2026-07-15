defmodule EstimateWeb.ProjectLive.Show.Dashboard do
  @moduledoc """
  Overview-tab estimation-dashboard view-selector handler.

  Reads: none (params only).
  Writes: `:dashboard_tab`.
  """
  use EstimateWeb, :live_handlers

  @dashboard_tabs %{"by_role" => :by_role, "by_epic" => :by_epic, "by_priority" => :by_priority}

  def set_dashboard_tab(socket, %{"tab" => tab}) do
    case @dashboard_tabs do
      %{^tab => atom} -> {:noreply, assign(socket, :dashboard_tab, atom)}
      _ -> {:noreply, socket}
    end
  end
end
