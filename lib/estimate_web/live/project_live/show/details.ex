defmodule EstimateWeb.ProjectLive.Show.Details do
  @moduledoc """
  Project details form handlers (the "Project Details" card on the overview tab).

  Reads: `:project`, `:can_edit_project` (via `Show.Authz.require_can_edit/2`).
  Writes: `:form`, and on save also `:project`, `:customer_key`.
  """
  use EstimateWeb, :live_handlers

  import EstimateWeb.ProjectLive.Show.Authz
  alias Estimate.Portfolio

  def validate(socket, %{"project" => project_params}) do
    changeset =
      socket.assigns.project
      |> Portfolio.change_project(project_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def save(socket, %{"project" => project_params}) do
    require_can_edit(socket, fn ->
      case Portfolio.update_project(socket.assigns.project, project_params) do
        {:ok, project} ->
          project = Portfolio.reload_project_with_roles(project)

          {:noreply,
           socket
           |> put_flash(:info, "Project updated")
           |> assign(:project, project)
           |> assign(:customer_key, if(project.customer, do: project.customer.key))
           |> assign(:form, to_form(Portfolio.change_project(project)))}

        {:error, changeset} ->
          {:noreply, assign(socket, form: to_form(changeset))}
      end
    end)
  end
end
