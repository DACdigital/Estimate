defmodule EstimateWeb.TemplatesLive.Show.Epics do
  @moduledoc """
  Template epic modal, delete-confirm and reorder handlers.

  Reads: `:template`, `:deleting_epic`, `:current_membership` (via require_admin).
  Writes: `:modal`, `:current_epic_id`, `:epic_form`, `:deleting_epic`, `:template` (reload), flash.
  """
  use EstimateWeb, :live_handlers

  import EstimateWeb.TemplatesLive.Show.Authz
  alias Estimate.Templates

  def add_epic(socket, _params) do
    {:noreply,
     socket
     |> assign(:modal, :epic)
     |> assign(:current_epic_id, nil)
     |> assign(:epic_form, to_form(%{"name" => "", "description" => ""}, as: "epic"))}
  end

  def edit_epic(socket, %{"id" => id}) do
    epic = find_epic(socket.assigns.template, id)

    {:noreply,
     socket
     |> assign(:modal, :epic)
     |> assign(:current_epic_id, id)
     |> assign(
       :epic_form,
       to_form(%{"name" => epic.name, "description" => epic.description || ""}, as: "epic")
     )}
  end

  def save_epic(socket, %{"epic_id" => "", "name" => name} = params) do
    require_admin(socket, fn ->
      position = length(socket.assigns.template.epics)

      attrs = %{
        "name" => name,
        "description" => params["description"],
        "position" => position,
        "estimation_template_id" => socket.assigns.template.id
      }

      case Templates.create_template_epic(attrs) do
        {:ok, _} -> {:noreply, reload_and_close(socket)}
        {:error, _} -> {:noreply, put_flash(socket, :error, "Could not create epic")}
      end
    end)
  end

  def save_epic(socket, %{"epic_id" => id, "name" => name} = params) do
    require_admin(socket, fn ->
      epic = find_epic(socket.assigns.template, id)

      case Templates.update_template_epic(epic, %{
             "name" => name,
             "description" => params["description"]
           }) do
        {:ok, _} -> {:noreply, reload_and_close(socket)}
        {:error, _} -> {:noreply, put_flash(socket, :error, "Could not update epic")}
      end
    end)
  end

  def confirm_delete_epic(socket, %{"id" => id}) do
    epic = find_epic(socket.assigns.template, id)
    {:noreply, assign(socket, :deleting_epic, epic)}
  end

  def delete_epic(socket, _params) do
    require_admin(socket, fn ->
      case Templates.delete_template_epic(socket.assigns.deleting_epic) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(:deleting_epic, nil)
           |> reload_template()
           |> put_flash(:info, "Epic deleted")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not delete epic")}
      end
    end)
  end

  def reorder_epics(socket, %{"ids" => ids}) do
    require_admin(socket, fn ->
      socket.assigns.template.id
      |> Templates.reorder_template_epics(ids)
      |> after_reorder(socket)
    end)
  end
end
