defmodule EstimateWeb.InviteLive.Accept do
  use EstimateWeb, :live_view

  alias Estimate.Accounts
  alias Estimate.Accounts.User
  alias Estimate.Organizations

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-md">
      <%= if @invite do %>
        <.header class="text-center">
          Join {@invite.organization.name}
          <:subtitle>
            You've been invited to join this organization
          </:subtitle>
        </.header>

        <%= if @current_user do %>
          <div class="mt-8 text-center">
            <p class="mb-4">You're signed in as <strong>{@current_user.email}</strong></p>
            <.button phx-click="accept_invite">
              Accept Invitation
            </.button>
          </div>
        <% else %>
          <div class="mt-8">
            <p class="text-center mb-6">Create an account to join:</p>

            <.simple_form
              for={@form}
              id="registration_form"
              phx-submit="register_and_accept"
              phx-change="validate"
            >
              <.input field={@form[:name]} type="text" label="Name" required />
              <.input field={@form[:email]} type="email" label="Email" value={@invite.email} required />
              <.input field={@form[:password]} type="password" label="Password" required />

              <:actions>
                <.button phx-disable-with="Creating account..." class="w-full">
                  Create Account & Join
                </.button>
              </:actions>
            </.simple_form>

            <p class="text-center text-sm mt-4">
              Already have an account?
              <.link href={~p"/users/log_in"} class="text-brand hover:underline">Sign in</.link>
            </p>
          </div>
        <% end %>
      <% else %>
        <.header class="text-center">
          Invalid Invitation
          <:subtitle>
            This invitation link is invalid or has expired.
          </:subtitle>
        </.header>
      <% end %>
    </div>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    invite = Organizations.get_valid_invite_by_token(token)
    changeset = Accounts.change_user_registration(%User{})

    {:ok,
     socket
     |> assign(:invite, invite)
     |> assign(:token, token)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset =
      %User{}
      |> Accounts.change_user_registration(user_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("register_and_accept", %{"user" => user_params}, socket) do
    invite = socket.assigns.invite

    case Accounts.register_user(user_params) do
      {:ok, user} ->
        case Organizations.accept_invite(invite, user.id) do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "Account created and joined #{invite.organization.name}!")
             |> redirect(to: ~p"/users/log_in")}

          {:error, _} ->
            {:noreply,
             socket
             |> put_flash(:error, "Could not accept invitation")
             |> redirect(to: ~p"/")}
        end

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("accept_invite", _params, socket) do
    invite = socket.assigns.invite
    user = socket.assigns.current_user

    case Organizations.accept_invite(invite, user.id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Joined #{invite.organization.name}!")
         |> redirect(to: ~p"/org/#{invite.organization_id}")}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Could not accept invitation. You may already be a member.")}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, form: to_form(changeset, as: "user"))
  end
end
