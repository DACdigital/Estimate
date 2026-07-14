defmodule EstimateWeb.SettingsLive.Members.Removal do
  @moduledoc "Event handlers + state for member removal and its ownership-reassignment flow."
  use EstimateWeb, :live_handlers

  alias Estimate.{Organizations, Portfolio}

  def confirm_remove_member(socket, %{"id" => id}) do
    require_admin(socket, fn ->
      membership = Enum.find(socket.assigns.members, &(&1.id == id))

      if Organizations.manageable_member?(membership, socket.assigns.current_user.id) do
        org_id = socket.assigns.org_id
        sole_owned = Portfolio.list_sole_owned_projects(membership.user_id, org_id)

        eligible =
          socket.assigns.members
          |> Enum.reject(&(&1.user_id == membership.user_id))
          |> Enum.sort_by(& &1.user.name)

        reassignments =
          case eligible do
            [first | _] -> Map.new(sole_owned, fn {p, _} -> {p.id, first.user_id} end)
            [] -> %{}
          end

        {:noreply,
         socket
         |> assign(
           removing_member: membership,
           sole_owned_projects: sole_owned,
           eligible_members: eligible,
           reassign_tab: :all,
           reassignments: reassignments
         )}
      else
        {:noreply, put_flash(socket, :error, "Not authorized")}
      end
    end)
  end

  def cancel_remove_member(socket, _params) do
    {:noreply, reset_removal_state(socket)}
  end

  def switch_reassign_tab(socket, tab),
    do: {:noreply, assign(socket, :reassign_tab, String.to_existing_atom(tab))}

  def reassign_all(socket, %{"user_id" => user_id}) do
    require_admin(socket, fn ->
      reassignments =
        if valid_eligible_member?(socket, user_id) do
          Map.new(socket.assigns.sole_owned_projects, fn {p, _} -> {p.id, user_id} end)
        else
          %{}
        end

      {:noreply, assign(socket, :reassignments, reassignments)}
    end)
  end

  def reassign_customer(socket, %{"customer_id" => customer_id, "user_id" => user_id}) do
    require_admin(socket, fn ->
      project_ids = sole_owned_project_ids_for_customer(socket, customer_id)

      reassignments =
        if valid_eligible_member?(socket, user_id) do
          Enum.reduce(project_ids, socket.assigns.reassignments, &Map.put(&2, &1, user_id))
        else
          Map.drop(socket.assigns.reassignments, project_ids)
        end

      {:noreply, assign(socket, :reassignments, reassignments)}
    end)
  end

  def reassign_project(socket, %{"project_id" => project_id, "user_id" => user_id}) do
    require_admin(socket, fn ->
      if valid_sole_owned_project?(socket, project_id) do
        reassignments =
          if valid_eligible_member?(socket, user_id),
            do: Map.put(socket.assigns.reassignments, project_id, user_id),
            else: Map.delete(socket.assigns.reassignments, project_id)

        {:noreply, assign(socket, :reassignments, reassignments)}
      else
        {:noreply, socket}
      end
    end)
  end

  def remove_member(socket, _params) do
    require_admin(socket, fn ->
      membership = socket.assigns.removing_member

      if Organizations.manageable_member?(membership, socket.assigns.current_user.id) do
        case Organizations.delete_membership(membership, socket.assigns.reassignments) do
          {:ok, _} ->
            members = Organizations.list_organization_members(socket.assigns.org_id)

            {:noreply,
             socket
             |> put_flash(:info, "Member removed")
             |> assign(:members, members)
             |> reset_removal_state()}

          {:error, :incomplete_reassignment} ->
            {:noreply,
             socket
             |> put_flash(:error, "Reassign all projects before removing")
             |> reset_removal_state()}

          {:error, reason}
          when reason in [:invalid_project, :invalid_member, :self_reassignment] ->
            {:noreply,
             socket
             |> put_flash(:error, "Invalid reassignment")
             |> reset_removal_state()}

          {:error, _} ->
            {:noreply,
             socket
             |> put_flash(:error, "Could not remove member")
             |> reset_removal_state()}
        end
      else
        {:noreply,
         socket
         |> put_flash(:error, "Cannot remove this member")
         |> reset_removal_state()}
      end
    end)
  end

  def reset_removal_state(socket) do
    assign(socket,
      removing_member: nil,
      sole_owned_projects: [],
      eligible_members: [],
      reassign_tab: :all,
      reassignments: %{}
    )
  end

  defp valid_eligible_member?(socket, user_id) do
    user_id != "" and Enum.any?(socket.assigns.eligible_members, &(&1.user_id == user_id))
  end

  defp valid_sole_owned_project?(socket, project_id) do
    Enum.any?(socket.assigns.sole_owned_projects, fn {p, _} -> p.id == project_id end)
  end

  defp sole_owned_project_ids_for_customer(socket, customer_id) do
    socket.assigns.sole_owned_projects
    |> Enum.filter(fn {p, _} -> p.customer_id == customer_id end)
    |> Enum.map(fn {p, _} -> p.id end)
  end
end
