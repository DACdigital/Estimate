defmodule EstimateWeb.SettingsLive.Members.Roster do
  @moduledoc "Event handlers for member role changes."
  use EstimateWeb, :live_handlers

  alias Estimate.Organizations
  alias Estimate.Accounts.Membership

  def change_member_role(socket, %{"id" => id, "role" => role}) do
    require_admin(socket, fn ->
      membership = Enum.find(socket.assigns.members, &(&1.id == id))

      cond do
        is_nil(membership) ->
          {:noreply, put_flash(socket, :error, "Member not found")}

        not Organizations.manageable_member?(membership, socket.assigns.current_user.id) ->
          {:noreply, put_flash(socket, :error, "Not authorized")}

        role not in Membership.assignable_roles() ->
          {:noreply, put_flash(socket, :error, "Invalid role")}

        true ->
          case Organizations.update_membership_role(membership, role) do
            {:ok, _} ->
              members = Organizations.list_organization_members(socket.assigns.org_id)
              {:noreply, socket |> put_flash(:info, "Role updated") |> assign(:members, members)}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Could not update role")}
          end
      end
    end)
  end
end
