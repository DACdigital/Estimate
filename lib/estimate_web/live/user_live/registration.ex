defmodule EstimateWeb.UserLive.Registration do
  use EstimateWeb, :live_view

  alias Estimate.Accounts
  alias Estimate.Accounts.User
  alias Estimate.Organizations

  def render(assigns) do
    ~H"""
    <div class="w-full">
      <h1 class="text-3xl font-bold text-center text-gray-900 mb-8">
        Create your account
      </h1>

      <form
        id="registration_form"
        phx-submit="save"
        phx-change="validate"
        phx-trigger-action={@trigger_submit}
        action={~p"/users/log_in?_action=registered"}
        method="post"
        class="space-y-4"
      >
        <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />

        <div
          :if={@check_errors}
          class="p-3 bg-red-50 border border-red-200 rounded-lg text-red-700 text-sm"
        >
          Oops, something went wrong! Please check the errors below.
        </div>

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

        <div class="relative my-6">
          <div class="absolute inset-0 flex items-center">
            <div class="w-full border-t border-gray-200"></div>
          </div>
          <div class="relative flex justify-center text-sm">
            <span class="px-4 bg-gray-50 text-gray-500">Organization</span>
          </div>
        </div>

        <div class="flex items-center gap-2 mb-3">
          <label class="relative inline-flex items-center cursor-pointer">
            <input
              type="checkbox"
              phx-click="toggle_invite_code"
              checked={@has_invite_code}
              class="sr-only peer"
            />
            <div class="w-9 h-5 bg-gray-200 peer-focus:outline-none peer-focus:ring-2 peer-focus:ring-gray-900 rounded-full peer peer-checked:after:translate-x-full rtl:peer-checked:after:-translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:start-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-4 after:w-4 after:transition-all peer-checked:bg-gray-900">
            </div>
          </label>
          <span class="text-sm text-gray-600">I have an invite code</span>
        </div>

        <%= if @has_invite_code do %>
          <div>
            <input
              type="text"
              name="invite_code"
              value={@invite_code}
              placeholder="e.g. XK7F2MPA"
              maxlength="8"
              class={"w-full px-4 py-3 border rounded-lg text-gray-900 placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent font-mono tracking-wider uppercase #{if @invite_code_error, do: "border-red-500", else: "border-gray-300"}"}
            />
            <p :if={@invite_code_error} class="mt-1 text-sm text-red-600">
              {@invite_code_error}
            </p>
          </div>
        <% else %>
          <div>
            <input
              type="text"
              name="organization[name]"
              value={@org_form[:name].value}
              placeholder="Organization Name"
              required
              class={"w-full px-4 py-3 border rounded-lg text-gray-900 placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent #{if @org_form[:name].errors != [], do: "border-red-500", else: "border-gray-300"}"}
            />
            <p :for={error <- @org_form[:name].errors} class="mt-1 text-sm text-red-600">
              {translate_error(error)}
            </p>
            <p class="mt-1 text-xs text-gray-500">You can invite team members later</p>
          </div>
        <% end %>

        <button
          type="submit"
          phx-disable-with="Creating account..."
          class="w-full py-3 px-4 bg-gray-900 text-white font-medium rounded-lg hover:bg-gray-800 transition-colors mt-6"
        >
          Create Account
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
    </div>
    """
  end

  def mount(_params, _session, socket) do
    changeset = Accounts.change_user_registration(%User{})
    org_changeset = Organizations.change_organization(%Accounts.Organization{})

    socket =
      socket
      |> assign(trigger_submit: false, check_errors: false)
      |> assign(has_invite_code: false, invite_code: "", invite_code_error: nil)
      |> assign_form(changeset)
      |> assign_org_form(org_changeset)

    {:ok, socket, temporary_assigns: [form: nil]}
  end

  def handle_event("toggle_invite_code", _params, socket) do
    {:noreply,
     socket
     |> assign(:has_invite_code, !socket.assigns.has_invite_code)
     |> assign(:invite_code_error, nil)}
  end

  def handle_event("save", %{"user" => user_params, "invite_code" => code}, socket) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        case Organizations.get_valid_invite_by_code(code) do
          nil ->
            {:noreply,
             socket
             |> assign(invite_code: code, invite_code_error: "Invalid or expired invite code")
             |> assign(check_errors: true)
             |> assign_form(Accounts.change_user_registration(user))}

          invite ->
            case Organizations.accept_invite(invite, user.id) do
              {:ok, _} ->
                changeset = Accounts.change_user_registration(user)
                {:noreply, socket |> assign(trigger_submit: true) |> assign_form(changeset)}

              {:error, _} ->
                {:noreply,
                 socket
                 |> assign(invite_code: code, invite_code_error: "Could not join organization")
                 |> assign(check_errors: true)
                 |> assign_form(Accounts.change_user_registration(user))}
            end
        end

      {:error, changeset} ->
        {:noreply, socket |> assign(check_errors: true) |> assign_form(changeset)}
    end
  end

  def handle_event("save", %{"user" => user_params, "organization" => org_params}, socket) do
    case Accounts.register_user_with_organization(user_params, org_params) do
      {:ok, %{user: user}} ->
        changeset = Accounts.change_user_registration(user)
        {:noreply, socket |> assign(trigger_submit: true) |> assign_form(changeset)}

      {:error, :user, changeset} ->
        {:noreply, socket |> assign(check_errors: true) |> assign_form(changeset)}

      {:error, :organization, changeset} ->
        {:noreply, socket |> assign(check_errors: true) |> assign_org_form(changeset)}

      {:error, :membership, _changeset} ->
        {:noreply, socket |> put_flash(:error, "Failed to create membership")}
    end
  end

  def handle_event("validate", params, socket) do
    user_params = Map.get(params, "user", %{})
    changeset = Accounts.change_user_registration(%User{}, user_params)

    socket = assign_form(socket, Map.put(changeset, :action, :validate))

    socket =
      case Map.get(params, "organization") do
        nil ->
          socket

        org_params ->
          org_changeset = Organizations.change_organization(%Accounts.Organization{}, org_params)
          assign_org_form(socket, Map.put(org_changeset, :action, :validate))
      end

    if Map.has_key?(params, "invite_code") do
      {:noreply, assign(socket, :invite_code, Map.get(params, "invite_code", ""))}
    else
      {:noreply, socket}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")
    assign(socket, form: form)
  end

  defp assign_org_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "organization")
    assign(socket, org_form: form)
  end
end
