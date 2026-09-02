defmodule EstimateWeb.ProjectLive.Show.DangerZone do
  @moduledoc """
  Project delete-confirmation flow (the "Danger Zone" card + delete-project modal).

  Reads: `:project`, `:can_delete_project` (via `Show.Authz.require_can_delete/3`),
  `:delete_confirmation_input`, `:org_id`.
  Writes: `:deleting_project`, `:delete_impact`, `:delete_confirmation_input`.
  """
  use EstimateWeb, :live_handlers

  import EstimateWeb.ProjectLive.Show.Authz
  alias Estimate.Portfolio

  def confirm_delete_project(socket, _params) do
    require_can_delete(socket, [deleting_project: false], fn ->
      impact = Portfolio.deletion_impact(socket.assigns.project)

      {:noreply,
       socket
       |> assign(:deleting_project, true)
       |> assign(:delete_impact, impact)
       |> assign(:delete_confirmation_input, "")}
    end)
  end

  def cancel_delete_project(socket, _params) do
    {:noreply,
     socket
     |> assign(:deleting_project, false)
     |> assign(:delete_confirmation_input, "")}
  end

  def validate_delete_confirmation(socket, %{"value" => value}) do
    {:noreply, assign(socket, :delete_confirmation_input, value)}
  end

  def delete_project(socket, _params) do
    require_can_delete(socket, [deleting_project: false], fn ->
      if socket.assigns.delete_confirmation_input == socket.assigns.project.name do
        case Portfolio.delete_project(socket.assigns.project) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "Project deleted")
             |> push_navigate(to: ~p"/org/#{socket.assigns.org_id}/projects")}

          {:error, _} ->
            {:noreply,
             socket
             |> put_flash(:error, "Could not delete project")
             |> assign(:deleting_project, false)}
        end
      else
        {:noreply,
         socket
         |> put_flash(:error, "Not authorized")
         |> assign(:deleting_project, false)}
      end
    end)
  end
end
