defmodule EstimateWeb.JoinRequestLive.New do
  use EstimateWeb, :live_view

  alias Estimate.Accounts
  alias Estimate.Accounts.User
  alias Estimate.Organizations

  @impl true
  def render(assigns) do
    ~H"""
    <div class="w-full">
      <%= if @organization do %>
        <%= if @current_user do %>
          <h1 class="text-3xl font-bold text-center text-gray-900 mb-8">
            Join {@organization.name}
          </h1>

          <div class="text-center">
            <%= if @already_member do %>
              <p class="text-gray-600 mb-6">You're already a member of this organization.</p>
              <.link navigate={~p"/org/#{@organization.id}"}>
                <button class="w-full py-3 px-4 bg-gray-900 text-white font-medium rounded-lg hover:bg-gray-800 transition-colors">
                  Go to Organization
                </button>
              </.link>
            <% else %>
              <%= if @pending_request do %>
                <p class="text-gray-600">Your request to join is pending approval.</p>
              <% else %>
                <p class="text-gray-600 mb-6">
                  An admin will review your request to join this organization.
                </p>
                <button
                  phx-click="request_join"
                  class="w-full py-3 px-4 bg-gray-900 text-white font-medium rounded-lg hover:bg-gray-800 transition-colors"
                >
                  Request to Join
                </button>
              <% end %>
            <% end %>
          </div>
        <% else %>
          <h1 class="text-3xl font-bold text-center text-gray-900 mb-2">
            Join {@organization.name}
          </h1>
          <p class="text-center text-gray-600 mb-8">Create an account to request access</p>

          <form
            id="registration_form"
            phx-submit="register_and_request_join"
            phx-change="validate"
            class="space-y-4"
          >
            <div>
              <input
                type="text"
                name="user[name]"
                value={@form[:name].value}
                placeholder="Full Name"
                required
                class={"w-full px-4 py-3 border rounded-lg text-gray-900 placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent #{if @form[:name].errors != [], do: "border-red-500", else: "border-gray-300"}"}
              />
              <p :for={error <- @form[:name].errors} class="mt-1 text-sm text-red-600">
                {translate_error(error)}
              </p>
            </div>

            <div>
              <input
                type="email"
                name="user[email]"
                value={@form[:email].value}
                placeholder="Email Address"
                required
                class={"w-full px-4 py-3 border rounded-lg text-gray-900 placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent #{if @form[:email].errors != [], do: "border-red-500", else: "border-gray-300"}"}
              />
              <p :for={error <- @form[:email].errors} class="mt-1 text-sm text-red-600">
                {translate_error(error)}
              </p>
            </div>

            <div>
              <input
                type="password"
                name="user[password]"
                placeholder="Password"
                required
                class={"w-full px-4 py-3 border rounded-lg text-gray-900 placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent #{if @form[:password].errors != [], do: "border-red-500", else: "border-gray-300"}"}
              />
              <p :for={error <- @form[:password].errors} class="mt-1 text-sm text-red-600">
                {translate_error(error)}
              </p>
            </div>

            <button
              type="submit"
              phx-disable-with="Creating account..."
              class="w-full py-3 px-4 bg-gray-900 text-white font-medium rounded-lg hover:bg-gray-800 transition-colors mt-2"
            >
              Create Account & Request to Join
            </button>
          </form>

          <.or_divider />

          <div class="space-y-3">
            <.google_button href={~p"/auth/google?#{%{return_to: @return_to}}"} />
          </div>

          <p class="mt-8 text-center text-gray-600">
            Already have an account?
            <.link navigate={~p"/users/log_in?#{%{return_to: @return_to}}"} class="text-blue-600 hover:text-blue-700 font-medium">
              Sign In
            </.link>
          </p>
        <% end %>
      <% else %>
        <h1 class="text-3xl font-bold text-center text-gray-900 mb-4">
          Organization Not Found
        </h1>
        <p class="text-center text-gray-600">This organization doesn't exist.</p>
      <% end %>
    </div>
    """
  end

  @impl true
  def mount(%{"id" => org_id}, _session, socket) do
    user = socket.assigns.current_user
    return_to = ~p"/organizations/#{org_id}/join"

    organization =
      try do
        Organizations.get_organization!(org_id)
      rescue
        Ecto.NoResultsError -> nil
      end

    if user do
      already_member =
        if organization do
          Organizations.get_user_membership(user.id, org_id) != nil
        else
          false
        end

      pending_request =
        if organization && !already_member do
          Organizations.list_pending_join_requests(org_id)
          |> Enum.find(&(&1.user_id == user.id))
        end

      {:ok,
       socket
       |> assign(:organization, organization)
       |> assign(:already_member, already_member)
       |> assign(:pending_request, pending_request)
       |> assign(:return_to, return_to)
       |> assign(:form, nil)}
    else
      changeset = Accounts.change_user_registration(%User{})

      {:ok,
       socket
       |> assign(:organization, organization)
       |> assign(:already_member, false)
       |> assign(:pending_request, nil)
       |> assign(:return_to, return_to)
       |> assign_form(changeset)}
    end
  end

  @impl true
  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset =
      %User{}
      |> Accounts.change_user_registration(user_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("register_and_request_join", %{"user" => user_params}, socket) do
    org = socket.assigns.organization

    case Accounts.register_user(user_params) do
      {:ok, user} ->
        case Organizations.create_join_request(user.id, org.id) do
          {:ok, _request} ->
            {:noreply,
             socket
             |> put_flash(
               :info,
               "Account created! Your join request for #{org.name} is pending approval."
             )
             |> redirect(to: ~p"/users/log_in")}

          {:error, _} ->
            {:noreply,
             socket
             |> put_flash(:error, "Account created but could not submit join request.")
             |> redirect(to: ~p"/users/log_in")}
        end

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("request_join", _params, socket) do
    user = socket.assigns.current_user
    org = socket.assigns.organization

    case Organizations.create_join_request(user.id, org.id) do
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

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, form: to_form(changeset, as: "user"))
  end
end
