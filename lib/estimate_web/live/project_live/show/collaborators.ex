defmodule EstimateWeb.ProjectLive.Show.Collaborators do
  @moduledoc """
  Member search/dropdown, add, change-role, and remove (with last-owner guard)
  handlers for the collaborators tab.

  Reads: `:project`, `:org_id`, `:collaborators`, `:available_members`,
  `:member_search`, `:show_member_dropdown`, `:selected_member`, `:selected_role`,
  `:removing_collaborator`, `:current_user`, `:current_collaborator`,
  `:can_manage_collaborators` (via `Show.Authz.require_can_manage/2` and directly
  in the change-role/remove predicates).
  Writes: `:member_search`, `:selected_role`, `:show_member_dropdown`,
  `:selected_member`, `:collaborators`, `:available_members`,
  `:removing_collaborator`.
  """
  use EstimateWeb, :live_handlers

  import EstimateWeb.ProjectLive.Show.Authz
  alias Estimate.Portfolio

  ## Member Search/Selection Events

  def collaborator_form_change(socket, params) do
    member_search = Map.get(params, "member_search", socket.assigns.member_search)
    selected_role = Map.get(params, "collaborator_role", socket.assigns.selected_role)

    {:noreply,
     socket
     |> assign(:member_search, member_search)
     |> assign(:selected_role, selected_role)
     |> assign(:show_member_dropdown, member_search != "" || socket.assigns.show_member_dropdown)}
  end

  def open_member_dropdown(socket, _params) do
    {:noreply, assign(socket, :show_member_dropdown, true)}
  end

  def close_member_dropdown(socket, _params) do
    {:noreply, assign(socket, :show_member_dropdown, false)}
  end

  def select_member(socket, %{"user-id" => user_id}) do
    member =
      Enum.find(socket.assigns.available_members, fn m -> m.user.id == user_id end)

    if member do
      {:noreply,
       socket
       |> assign(:selected_member, member.user)
       |> assign(:member_search, member.user.name || member.user.email)
       |> assign(:show_member_dropdown, false)}
    else
      {:noreply, socket}
    end
  end

  def clear_selected_member(socket, _params) do
    {:noreply,
     socket
     |> assign(:selected_member, nil)
     |> assign(:member_search, "")}
  end

  ## Manage Collaborator Events

  def add_collaborator(socket, _params) do
    require_can_manage(socket, fn ->
      member = socket.assigns.selected_member

      if member do
        project_id = socket.assigns.project.id

        case Portfolio.add_collaborator(project_id, member.id, socket.assigns.selected_role) do
          {:ok, _} ->
            {:noreply, reload_collaborators(socket, "Collaborator added")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not add collaborator")}
        end
      else
        {:noreply, socket}
      end
    end)
  end

  def change_collaborator_role(socket, %{"id" => id, "role" => role}) do
    require_can_manage(socket, fn ->
      collab = Enum.find(socket.assigns.collaborators, &(&1.id == id))

      if collab &&
           Portfolio.can_change_role?(
             socket.assigns.can_manage_collaborators,
             socket.assigns.current_user,
             collab
           ) do
        case Portfolio.update_collaborator_role(collab, role) do
          {:ok, _} ->
            {:noreply, reload_collaborators(socket, "Role updated")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not update role")}
        end
      else
        {:noreply, put_flash(socket, :error, "Not authorized")}
      end
    end)
  end

  def confirm_remove_collaborator(socket, %{"id" => id}) do
    collab = Enum.find(socket.assigns.collaborators, &(&1.id == id))
    {:noreply, assign(socket, :removing_collaborator, collab)}
  end

  def cancel_remove_collaborator(socket, _params) do
    {:noreply, assign(socket, :removing_collaborator, nil)}
  end

  def remove_collaborator(socket, _params) do
    collab = socket.assigns.removing_collaborator

    cond do
      is_nil(collab) ->
        {:noreply, assign(socket, :removing_collaborator, nil)}

      !Portfolio.can_remove_collaborator?(
        socket.assigns.can_manage_collaborators,
        socket.assigns.current_user,
        socket.assigns.current_collaborator,
        collab
      ) ->
        {:noreply,
         socket
         |> put_flash(:error, "Not authorized")
         |> assign(:removing_collaborator, nil)}

      collab.role == "owner" &&
          Enum.count(socket.assigns.collaborators, &(&1.role == "owner")) <= 1 ->
        {:noreply,
         socket
         |> put_flash(:error, "Cannot remove the last project owner")
         |> assign(:removing_collaborator, nil)}

      true ->
        case Portfolio.remove_collaborator(collab) do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(:removing_collaborator, nil)
             |> reload_collaborators("Collaborator removed")}

          {:error, _} ->
            {:noreply,
             socket
             |> put_flash(:error, "Could not remove collaborator")
             |> assign(:removing_collaborator, nil)}
        end
    end
  end

  defp reload_collaborators(socket, flash_msg) do
    project_id = socket.assigns.project.id
    org_id = socket.assigns.org_id
    collaborators = Portfolio.list_collaborators(project_id)
    available = Portfolio.list_available_members(project_id, org_id)

    socket
    |> put_flash(:info, flash_msg)
    |> assign(:collaborators, collaborators)
    |> assign(:available_members, available)
    |> assign(:selected_member, nil)
    |> assign(:member_search, "")
    |> assign(:selected_role, "viewer")
    |> assign(:show_member_dropdown, false)
  end
end
