defmodule EstimateWeb.InviteLive.Accept do
  use EstimateWeb, :live_view

  alias Estimate.Accounts
  alias Estimate.Accounts.User
  alias Estimate.Organizations

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-full">
      <%= if @invite do %>
        <%= if @current_user do %>
          <.auth_header title={"Join #{@invite.organization.name}"}>
            <:subtitle>You've been invited to join this organization</:subtitle>
          </.auth_header>

          <div class="text-center">
            <p class="text-base-content/70 mb-6">
              You're signed in as <strong>{@current_user.email}</strong>
            </p>
            <.auth_submit phx-click="accept_invite">
              Accept Invitation
            </.auth_submit>
          </div>
        <% else %>
          <.auth_header title={"Join #{@invite.organization.name}"}>
            <:subtitle>Create an account to join</:subtitle>
          </.auth_header>

          <form
            id="registration_form"
            phx-submit="register_and_accept"
            phx-change="validate"
            class="space-y-4"
          >
            <.auth_input field={@form[:name]} type="text" placeholder="Full Name" required />

            <.auth_input
              field={@form[:email]}
              type="email"
              placeholder="Email Address"
              required
              readonly={@invite.email != nil}
              class={if @invite.email, do: "bg-base-200 text-base-content/60"}
            />

            <.auth_input
              field={@form[:password]}
              type="password"
              placeholder="Password"
              required
            />

            <.auth_submit loading="Creating account...">Create Account & Join</.auth_submit>
          </form>

          <.oauth_section href={~p"/auth/google?#{%{return_to: @return_to}}"} />

          <p class="mt-8 text-center text-base-content/70">
            Already have an account?
            <.link
              navigate={~p"/users/log_in?#{%{return_to: @return_to}}"}
              class="text-info hover:text-info/80 font-medium"
            >
              Sign In
            </.link>
          </p>
        <% end %>
      <% else %>
        <.auth_header title="Invalid Invitation">
          <:subtitle>This invitation link is invalid or has expired.</:subtitle>
        </.auth_header>
      <% end %>
    </div>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    invite = Organizations.get_valid_invite_by_token(token)
    # Pre-seed the email so the readonly `<.auth_input field={@form[:email]}>` shows
    # the invite's email: auth_input's field-clause always renders `field.value`, so
    # a `value=` fallback attr at the call site would be silently discarded.
    initial_attrs = if invite && invite.email, do: %{"email" => invite.email}, else: %{}
    changeset = Accounts.change_user_registration(%User{}, initial_attrs)
    return_to = ~p"/invites/#{token}"

    {:ok,
     socket
     |> assign(:invite, invite)
     |> assign(:token, token)
     |> assign(:return_to, return_to)
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

  @impl true
  def handle_event("register_and_accept", %{"user" => user_params}, socket) do
    invite = socket.assigns.invite

    user_params =
      if invite.email,
        do: Map.put(user_params, "email", invite.email),
        else: user_params

    case Accounts.register_user_and_accept_invite(user_params, invite) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Account created and joined #{invite.organization.name}!")
         |> redirect(to: ~p"/users/log_in")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Could not accept invitation")
         |> redirect(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("accept_invite", _params, socket) do
    invite = socket.assigns.invite
    user = socket.assigns.current_user

    case Organizations.accept_invite(invite, user) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Joined #{invite.organization.name}!")
         |> redirect(to: ~p"/org/#{invite.organization_id}")}

      {:error, :email_mismatch} ->
        {:noreply,
         put_flash(socket, :error, "This invitation was sent to a different email address.")}

      {:error, _} ->
        {:noreply,
         put_flash(socket, :error, "Could not accept invitation. You may already be a member.")}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, form: to_form(changeset, as: "user"))
  end
end
