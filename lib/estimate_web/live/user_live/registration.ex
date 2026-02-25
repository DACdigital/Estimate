defmodule EstimateWeb.UserLive.Registration do
  use EstimateWeb, :live_view

  alias Estimate.Accounts
  alias Estimate.Accounts.User
  alias Estimate.Organizations

  def render(assigns) do
    ~H"""
    <div class="w-full">
      <h1 class="text-3xl font-bold text-center text-base-content mb-8">
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
          class="p-3 bg-error/10 border border-error/20 rounded-lg text-error text-sm"
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
            class={"w-full px-4 py-3 border rounded-lg text-base-content placeholder-base-content/60 #{if @form[:name].errors != [], do: "border-error", else: "border-base-content/20"}"}
          />
          <p :for={error <- @form[:name].errors} class="mt-1 text-sm text-error">
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
            class={"w-full px-4 py-3 border rounded-lg text-base-content placeholder-base-content/60 #{if @form[:email].errors != [], do: "border-error", else: "border-base-content/20"}"}
          />
          <p :for={error <- @form[:email].errors} class="mt-1 text-sm text-error">
            {translate_error(error)}
          </p>
        </div>

        <div>
          <input
            type="password"
            name="user[password]"
            placeholder="Password"
            required
            class={"w-full px-4 py-3 border rounded-lg text-base-content placeholder-base-content/60 #{if @form[:password].errors != [], do: "border-error", else: "border-base-content/20"}"}
          />
          <p :for={error <- @form[:password].errors} class="mt-1 text-sm text-error">
            {translate_error(error)}
          </p>
        </div>

        <div class="relative my-6">
          <div class="absolute inset-0 flex items-center">
            <div class="w-full border-t border-base-300"></div>
          </div>
          <div class="relative flex justify-center text-sm">
            <span class="px-4 bg-base-200 text-base-content/60">Organization</span>
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
            <div class="w-9 h-5 bg-base-300 peer-focus:outline-none peer-focus:ring-2 peer-focus:ring-base-content rounded-full peer peer-checked:after:translate-x-full rtl:peer-checked:after:-translate-x-full peer-checked:after:border-base-100 after:content-[''] after:absolute after:top-[2px] after:start-[2px] after:bg-base-100 after:border-base-content/20 after:border after:rounded-full after:h-4 after:w-4 after:transition-all peer-checked:bg-neutral">
            </div>
          </label>
          <span class="text-sm text-base-content/70">I have an invite code</span>
        </div>

        <%= if @has_invite_code do %>
          <div>
            <input
              type="text"
              name="invite_code"
              value={@invite_code}
              placeholder="e.g. XK7F2MPA"
              maxlength="8"
              class={"w-full px-4 py-3 border rounded-lg text-base-content placeholder-base-content/60 font-mono tracking-wider uppercase #{if @invite_code_error, do: "border-error", else: "border-base-content/20"}"}
            />
            <p :if={@invite_code_error} class="mt-1 text-sm text-error">
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
              class={"w-full px-4 py-3 border rounded-lg text-base-content placeholder-base-content/60 #{if @org_form[:name].errors != [], do: "border-error", else: "border-base-content/20"}"}
            />
            <p :for={error <- @org_form[:name].errors} class="mt-1 text-sm text-error">
              {translate_error(error)}
            </p>
            <p class="mt-1 text-xs text-base-content/60">You can invite team members later</p>
          </div>
        <% end %>

        <button
          type="submit"
          phx-disable-with="Creating account..."
          class="w-full py-3 px-4 bg-neutral text-neutral-content font-medium rounded-lg hover:bg-neutral/90 transition-colors mt-6"
        >
          Create Account
        </button>
      </form>

      <.or_divider />

      <div class="space-y-3">
        <.google_button href={~p"/auth/google"} />
      </div>

      <p class="mt-8 text-center text-base-content/70">
        Already have an account?
        <.link navigate={~p"/users/log_in"} class="text-info hover:text-info font-medium">
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
            case Organizations.accept_invite(invite, user) do
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
