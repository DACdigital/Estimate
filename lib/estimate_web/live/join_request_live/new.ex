defmodule EstimateWeb.JoinRequestLive.New do
  use EstimateWeb, :live_view

  alias Estimate.Accounts
  alias Estimate.Accounts.User

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

          <div class="relative my-6">
            <div class="absolute inset-0 flex items-center">
              <div class="w-full border-t border-gray-200"></div>
            </div>
            <div class="relative flex justify-center text-sm">
              <span class="px-4 bg-gray-50 text-gray-500">or</span>
            </div>
          </div>

          <div class="space-y-3">
            <a
              href={~p"/auth/google"}
              class="w-full py-3 px-4 bg-white border border-gray-300 rounded-lg font-medium text-gray-700 flex items-center justify-center gap-3 hover:bg-gray-50 transition-colors"
            >
              <svg class="w-5 h-5" viewBox="0 0 24 24">
                <path
                  fill="#4285F4"
                  d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"
                />
                <path
                  fill="#34A853"
                  d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"
                />
                <path
                  fill="#FBBC05"
                  d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"
                />
                <path
                  fill="#EA4335"
                  d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"
                />
              </svg>
              Continue with Google
            </a>
          </div>

          <p class="mt-8 text-center text-gray-600">
            Already have an account?
            <.link navigate={~p"/users/log_in"} class="text-blue-600 hover:text-blue-700 font-medium">
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

    organization =
      try do
        Accounts.get_organization!(org_id)
      rescue
        Ecto.NoResultsError -> nil
      end

    if user do
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
       |> assign(:pending_request, pending_request)
       |> assign(:form, nil)}
    else
      changeset = Accounts.change_user_registration(%User{})

      {:ok,
       socket
       |> assign(:organization, organization)
       |> assign(:already_member, false)
       |> assign(:pending_request, nil)
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
        case Accounts.create_join_request(user.id, org.id) do
          {:ok, _request} ->
            {:noreply,
             socket
             |> put_flash(:info, "Account created! Your join request for #{org.name} is pending approval.")
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

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, form: to_form(changeset, as: "user"))
  end
end
