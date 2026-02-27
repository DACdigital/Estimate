defmodule EstimateWeb.UserLive.AccountSettings do
  use EstimateWeb, :live_view

  alias Estimate.Accounts
  alias Estimate.Accounts.{User, Totp}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto">
      <div class="mb-8">
        <h1 class="text-2xl font-bold text-base-content">Account Settings</h1>
        <p class="mt-1 text-base-content/60">Manage your profile and security</p>
      </div>

      <div class="space-y-6">
        <%!-- Profile card --%>
        <.form for={@name_form} phx-change="validate_name" phx-submit="save_name">
          <div class="bg-base-100 border border-base-300 rounded-xl overflow-hidden">
            <div class="p-6">
              <div class="flex items-start justify-between">
                <div>
                  <h2 class="text-xl font-semibold text-base-content">Profile</h2>
                  <p class="mt-1 text-sm text-base-content/60">Your personal information</p>
                </div>
                <span class={[
                  "inline-flex items-center gap-1.5 px-2.5 py-1 text-xs font-medium rounded-full",
                  if(@is_oauth, do: "bg-info/10 text-info", else: "bg-base-200 text-base-content/60")
                ]}>
                  {if @is_oauth, do: "Signed in with Google", else: "Email & password"}
                </span>
              </div>
              <div class="mt-4 max-w-md space-y-4">
                <.input field={@name_form[:name]} label="Name" />
                <div class="fieldset mb-2">
                  <label>
                    <span class="label mb-1">Email</span>
                    <input
                      type="email"
                      value={@current_user.email}
                      disabled
                      class="w-full px-3 py-2 border border-base-content/20 rounded-lg text-sm bg-base-200 text-base-content/60"
                    />
                  </label>
                </div>
              </div>
            </div>
            <div class="px-6 py-3 border-t border-base-300 flex items-center justify-between">
              <p class="text-sm text-base-content/60">Email change coming soon.</p>
              <button
                type="submit"
                phx-disable-with="Saving..."
                class="px-4 py-1.5 bg-neutral text-neutral-content text-sm rounded-md hover:bg-neutral/90 transition-colors font-medium"
              >
                Save
              </button>
            </div>
          </div>
        </.form>

        <%!-- Password card --%>
        <.form for={@password_form} phx-change="validate_password" phx-submit="save_password">
          <div class="bg-base-100 border border-base-300 rounded-xl overflow-hidden">
            <div class="p-6">
              <h2 class="text-xl font-semibold text-base-content">
                {if @is_oauth, do: "Set Password", else: "Change Password"}
              </h2>
              <p class="mt-1 text-sm text-base-content/60">
                {if @is_oauth,
                  do: "Set a password to also sign in with email and password",
                  else: "Update your account password"}
              </p>
              <div class="mt-4 max-w-md space-y-4">
                <.input
                  :if={!@is_oauth}
                  field={@password_form[:current_password]}
                  type="password"
                  label="Current password"
                  autocomplete="current-password"
                />
                <.input
                  field={@password_form[:password]}
                  type="password"
                  label="New password"
                  autocomplete="new-password"
                />
                <.input
                  field={@password_form[:password_confirmation]}
                  type="password"
                  label="Confirm new password"
                  autocomplete="new-password"
                />
              </div>
            </div>
            <div class="px-6 py-3 border-t border-base-300 flex items-center justify-between">
              <p class="text-sm text-base-content/60">Minimum 8 characters.</p>
              <button
                type="submit"
                phx-disable-with="Saving..."
                class="px-4 py-1.5 bg-neutral text-neutral-content text-sm rounded-md hover:bg-neutral/90 transition-colors font-medium"
              >
                Save
              </button>
            </div>
          </div>
        </.form>

        <%!-- 2FA card --%>
        <div class="bg-base-100 border border-base-300 rounded-xl overflow-hidden">
          <div class="p-6">
            <h2 class="text-xl font-semibold text-base-content">Two-Factor Authentication</h2>
            <p class="mt-1 text-sm text-base-content/60">
              Add an extra layer of security using a TOTP authenticator app.
            </p>

            <div class="mt-4">
              <%= if @totp_enabled do %>
                <div class="flex items-center gap-3 mb-6">
                  <span class="inline-flex items-center gap-1.5 px-2.5 py-1 text-xs font-medium bg-success/10 text-success rounded-full">
                    <svg class="w-2.5 h-2.5" fill="currentColor" viewBox="0 0 8 8">
                      <circle cx="4" cy="4" r="4" />
                    </svg>
                    Enabled
                  </span>
                  <span class="text-sm text-base-content/60">
                    since {Calendar.strftime(@current_user.totp_enabled_at, "%b %d, %Y")}
                  </span>
                </div>

                <div class="flex gap-3">
                  <.link
                    navigate={~p"/account/two-factor/setup"}
                    class="px-4 py-1.5 text-sm font-medium text-base-content/70 border border-base-300 rounded-md hover:bg-base-200 transition-colors"
                  >
                    Regenerate backup codes
                  </.link>
                  <button
                    phx-click="show_disable_form"
                    class="px-4 py-1.5 text-sm font-medium text-error border border-error/30 rounded-md hover:bg-error/10 transition-colors"
                  >
                    Disable 2FA
                  </button>
                </div>

                <%= if @show_disable_form do %>
                  <div class="mt-6 p-4 border border-error/20 rounded-lg bg-error/5">
                    <p class="text-sm text-base-content/70 mb-3">
                      Enter your 6-digit code to confirm disabling 2FA:
                    </p>
                    <form phx-submit="disable_totp" class="flex gap-3">
                      <input
                        type="text"
                        name="code"
                        placeholder="000000"
                        maxlength="8"
                        autocomplete="one-time-code"
                        inputmode="numeric"
                        class="w-40 px-3 py-2 border border-base-content/20 rounded-lg text-sm font-mono tracking-widest text-center"
                      />
                      <button
                        type="submit"
                        phx-disable-with="Verifying..."
                        class="px-4 py-1.5 bg-error text-error-content text-sm rounded-md hover:bg-error/90 transition-colors font-medium"
                      >
                        Confirm Disable
                      </button>
                      <button
                        type="button"
                        phx-click="hide_disable_form"
                        class="px-4 py-1.5 text-sm text-base-content/60 hover:text-base-content transition-colors"
                      >
                        Cancel
                      </button>
                    </form>
                  </div>
                <% end %>
              <% else %>
                <div class="flex items-center gap-3 mb-6">
                  <span class="inline-flex items-center gap-1.5 px-2.5 py-1 text-xs font-medium bg-base-200 text-base-content/60 rounded-full">
                    Not enabled
                  </span>
                </div>

                <.link
                  navigate={~p"/account/two-factor/setup"}
                  class="inline-flex px-4 py-1.5 bg-neutral text-neutral-content text-sm rounded-md hover:bg-neutral/90 transition-colors font-medium"
                >
                  Enable two-factor authentication
                </.link>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    is_oauth = is_nil(user.hashed_password)

    name_changeset = Accounts.change_user_name(user)
    password_changeset = Accounts.change_user_password(user)

    {:ok,
     socket
     |> assign(:page_title, "Account Settings")
     |> assign(:settings_page, :security)
     |> assign(:is_oauth, is_oauth)
     |> assign(:totp_enabled, User.totp_enabled?(user))
     |> assign(:show_disable_form, false)
     |> assign(:name_form, to_form(name_changeset))
     |> assign(:password_form, to_form(password_changeset, as: "password"))}
  end

  ## Name events

  @impl true
  def handle_event("validate_name", %{"user" => params}, socket) do
    changeset =
      socket.assigns.current_user
      |> Accounts.change_user_name(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :name_form, to_form(changeset))}
  end

  def handle_event("save_name", %{"user" => params}, socket) do
    case Accounts.update_user_name(socket.assigns.current_user, params) do
      {:ok, user} ->
        changeset = Accounts.change_user_name(user)

        {:noreply,
         socket
         |> assign(:current_user, user)
         |> assign(:name_form, to_form(changeset))
         |> put_flash(:info, "Name updated")}

      {:error, changeset} ->
        {:noreply, assign(socket, :name_form, to_form(changeset))}
    end
  end

  ## Password events

  def handle_event("validate_password", %{"password" => params}, socket) do
    changeset =
      socket.assigns.current_user
      |> Accounts.change_user_password(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :password_form, to_form(changeset, as: "password"))}
  end

  def handle_event("save_password", %{"password" => params}, socket) do
    user = socket.assigns.current_user

    result =
      if socket.assigns.is_oauth do
        Accounts.set_user_password(user, params)
      else
        Accounts.update_user_password(user, params["current_password"], params)
      end

    case result do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Password updated — please sign in again")
         |> push_navigate(to: ~p"/users/log_in")}

      {:error, changeset} ->
        {:noreply, assign(socket, :password_form, to_form(changeset, as: "password"))}
    end
  end

  ## 2FA events

  def handle_event("show_disable_form", _params, socket) do
    {:noreply, assign(socket, :show_disable_form, true)}
  end

  def handle_event("hide_disable_form", _params, socket) do
    {:noreply, assign(socket, :show_disable_form, false)}
  end

  def handle_event("disable_totp", %{"code" => code}, socket) do
    user = socket.assigns.current_user

    with {:ok, secret} <- Totp.get_decrypted_secret(user),
         true <- Totp.valid_code_or_backup?(user, secret, String.trim(code)) do
      case Totp.disable_totp(user) do
        {:ok, updated_user} ->
          {:noreply,
           socket
           |> assign(:current_user, updated_user)
           |> assign(:totp_enabled, false)
           |> assign(:show_disable_form, false)
           |> put_flash(:info, "Two-factor authentication disabled")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to disable 2FA")}
      end
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Invalid code")}
    end
  end
end
