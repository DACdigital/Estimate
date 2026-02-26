defmodule EstimateWeb.UserLive.AccountSettings do
  use EstimateWeb, :live_view

  alias Estimate.Accounts.{User, Totp}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto">
      <div class="mb-8">
        <h1 class="text-2xl font-bold text-base-content">Account Settings</h1>
        <p class="mt-1 text-base-content/60">Manage your security preferences</p>
      </div>

      <div class="bg-base-100 border border-base-300 rounded-xl overflow-hidden">
        <div class="px-6 py-4 border-b border-base-300">
          <h2 class="text-lg font-semibold text-base-content">Two-Factor Authentication</h2>
          <p class="text-sm text-base-content/60 mt-1">
            Add an extra layer of security to your account using a TOTP authenticator app.
          </p>
        </div>

        <div class="p-6">
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
                class="px-4 py-2 text-sm font-medium text-base-content/70 border border-base-300 rounded-lg hover:bg-base-200 transition-colors"
              >
                Regenerate backup codes
              </.link>
              <button
                phx-click="show_disable_form"
                class="px-4 py-2 text-sm font-medium text-error border border-error/30 rounded-lg hover:bg-error/10 transition-colors"
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
                    class="px-4 py-2 bg-error text-error-content text-sm rounded-lg hover:bg-error/90 transition-colors font-medium"
                  >
                    Confirm Disable
                  </button>
                  <button
                    type="button"
                    phx-click="hide_disable_form"
                    class="px-4 py-2 text-sm text-base-content/60 hover:text-base-content transition-colors"
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
              class="inline-flex px-4 py-2 bg-neutral text-neutral-content text-sm rounded-lg hover:bg-neutral/90 transition-colors font-medium"
            >
              Enable two-factor authentication
            </.link>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    {:ok,
     socket
     |> assign(:page_title, "Account Settings")
     |> assign(:settings_page, :security)
     |> assign(:totp_enabled, User.totp_enabled?(user))
     |> assign(:show_disable_form, false)}
  end

  @impl true
  def handle_event("show_disable_form", _params, socket) do
    {:noreply, assign(socket, :show_disable_form, true)}
  end

  def handle_event("hide_disable_form", _params, socket) do
    {:noreply, assign(socket, :show_disable_form, false)}
  end

  def handle_event("disable_totp", %{"code" => code}, socket) do
    user = socket.assigns.current_user

    with {:ok, secret} <- Totp.get_decrypted_secret(user),
         true <- valid_totp_or_backup?(user, secret, code) do
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

  defp valid_totp_or_backup?(user, secret, code) do
    Totp.valid_code?(secret, code) or
      match?({:ok, _}, Totp.consume_backup_code(user, code))
  end
end
