defmodule EstimateWeb.JoinRequestLive.New do
  use EstimateWeb, :live_view

  alias Estimate.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-md">
      <%= if @organization do %>
        <.header class="text-center">
          Join {@organization.name}
          <:subtitle>
            Request to join this organization
          </:subtitle>
        </.header>

        <div class="mt-8 text-center">
          <%= if @already_member do %>
            <p class="text-gray-600 mb-4">You're already a member of this organization.</p>
            <.link navigate={~p"/org/#{@organization.id}"}>
              <.button>Go to Organization</.button>
            </.link>
          <% else %>
            <%= if @pending_request do %>
              <p class="text-gray-600">Your request to join is pending approval.</p>
            <% else %>
              <p class="text-gray-600 mb-4">
                An admin will review your request to join this organization.
              </p>
              <.button phx-click="request_join">
                Request to Join
              </.button>
            <% end %>
          <% end %>
        </div>
      <% else %>
        <.header class="text-center">
          Organization Not Found
          <:subtitle>
            This organization doesn't exist.
          </:subtitle>
        </.header>
      <% end %>
    </div>
    """
  end

  @impl true
  def mount(%{"id" => org_id}, _session, socket) do
    user = socket.assigns.current_user

    organization =
      try do
        Accounts.get_organization!(org_id)
      rescue
        Ecto.NoResultsError -> nil
      end

    already_member =
      if organization do
        Accounts.get_user_membership(user.id, org_id) != nil
      else
        false
      end

    pending_request =
      if organization && !already_member do
        Accounts.list_pending_join_requests(org_id)
        |> Enum.find(&(&1.user_id == user.id))
      end

    {:ok,
     socket
     |> assign(:organization, organization)
     |> assign(:already_member, already_member)
     |> assign(:pending_request, pending_request)}
  end

  @impl true
  def handle_event("request_join", _params, socket) do
    user = socket.assigns.current_user
    org = socket.assigns.organization

    case Accounts.create_join_request(user.id, org.id) do
      {:ok, _request} ->
        {:noreply,
         socket
         |> put_flash(:info, "Join request submitted!")
         |> assign(:pending_request, true)}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Could not submit join request")}
    end
  end
end
