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

            {:error, :invalid_role} ->
              {:noreply, put_flash(socket, :error, "Invalid role")}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Could not update role")}
          end
      end
    end)
  end

  def confirm_transfer_ownership(socket, %{"id" => id}) do
    require_owner(socket, fn ->
      case Enum.find(
             socket.assigns.members,
             &(&1.id == id and &1.user_id != socket.assigns.current_user.id)
           ) do
        nil -> {:noreply, put_flash(socket, :error, "Member not found")}
        m -> {:noreply, assign(socket, :transferring_to, m)}
      end
    end)
  end

  def cancel_transfer_ownership(socket, _), do: {:noreply, assign(socket, :transferring_to, nil)}

  def transfer_ownership(socket, _params) do
    require_owner(socket, fn ->
      case socket.assigns.transferring_to do
        nil ->
          {:noreply, socket}

        target ->
          case Organizations.transfer_ownership(
                 socket.assigns.org_id,
                 socket.assigns.current_user.id,
                 target.user_id
               ) do
            {:ok, %{previous_owner: me}} ->
              {:noreply,
               socket
               |> put_flash(:info, "Ownership transferred")
               |> assign(:transferring_to, nil)
               |> assign(:current_membership, me)
               |> assign(:is_admin, true)
               |> assign(:members, Organizations.list_organization_members(socket.assigns.org_id))}

            {:error, _} ->
              {:noreply,
               socket
               |> put_flash(:error, "Could not transfer ownership")
               |> assign(:transferring_to, nil)}
          end
      end
    end)
  end

  defp require_owner(socket, fun) do
    if socket.assigns.current_membership.role == "owner",
      do: fun.(),
      else: {:noreply, put_flash(socket, :error, "Not authorized")}
  end
end
