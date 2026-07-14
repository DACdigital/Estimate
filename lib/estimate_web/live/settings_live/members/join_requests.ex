defmodule EstimateWeb.SettingsLive.Members.JoinRequests do
  @moduledoc "Event handlers for approving/rejecting organization join requests."
  use EstimateWeb, :live_handlers

  alias Estimate.Organizations

  def approve_request(socket, %{"id" => id}) do
    require_admin(socket, fn ->
      org_id = socket.assigns.org_id
      request = Organizations.get_join_request!(id, org_id)

      case Organizations.approve_join_request(request, socket.assigns.current_user.id) do
        {:ok, _} ->
          members = Organizations.list_organization_members(org_id)
          join_requests = Organizations.list_pending_join_requests(org_id)

          {:noreply,
           socket
           |> put_flash(:info, "Request approved!")
           |> assign(:members, members)
           |> assign(:join_requests, join_requests)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not approve request")}
      end
    end)
  end

  def reject_request(socket, %{"id" => id}) do
    require_admin(socket, fn ->
      org_id = socket.assigns.org_id
      request = Organizations.get_join_request!(id, org_id)

      case Organizations.reject_join_request(request, socket.assigns.current_user.id) do
        {:ok, _} ->
          join_requests = Organizations.list_pending_join_requests(org_id)

          {:noreply,
           socket
           |> put_flash(:info, "Request rejected")
           |> assign(:join_requests, join_requests)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not reject request")}
      end
    end)
  end
end
