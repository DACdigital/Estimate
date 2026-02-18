defmodule EstimateWeb.SettingsLive.Email do
  use EstimateWeb, :live_view

  alias Estimate.Organizations

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-3xl mx-auto">
      <div class="mb-8">
        <h1 class="text-2xl font-bold text-gray-900">Email (SMTP)</h1>
        <p class="mt-1 text-gray-500">Configure SMTP to send invite emails from your organization</p>
      </div>

      <div class="bg-white border border-gray-200 rounded-xl overflow-hidden">
        <.form for={@email_form} id="email-settings-form" phx-submit="save_email_settings">
          <div class="p-6">
            <div class="space-y-4 max-w-md">
              <div class="grid grid-cols-3 gap-4">
                <div class="col-span-2">
                  <label class="block text-xs font-medium text-gray-500 mb-1.5">
                    SMTP Host
                  </label>
                  <input
                    type="text"
                    name="email[smtp_host]"
                    value={@email_form[:smtp_host].value}
                    placeholder="smtp.gmail.com"
                    class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent text-sm"
                  />
                </div>
                <div>
                  <label class="block text-xs font-medium text-gray-500 mb-1.5">Port</label>
                  <input
                    type="number"
                    name="email[smtp_port]"
                    value={@email_form[:smtp_port].value}
                    placeholder="587"
                    class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent text-sm"
                  />
                </div>
              </div>
              <div>
                <label class="block text-xs font-medium text-gray-500 mb-1.5">Username</label>
                <input
                  type="text"
                  name="email[smtp_username]"
                  value={@email_form[:smtp_username].value}
                  placeholder="you@gmail.com"
                  class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent text-sm"
                />
              </div>
              <div>
                <label class="block text-xs font-medium text-gray-500 mb-1.5">
                  Password
                  <span
                    :if={@smtp_configured}
                    class="inline-flex items-center gap-1 px-2 py-0.5 text-xs font-medium bg-green-50 text-green-700 rounded-full"
                  >
                    <svg class="w-2.5 h-2.5" fill="currentColor" viewBox="0 0 8 8"><circle cx="4" cy="4" r="4" /></svg>
                    Connected · {@smtp_password_masked}
                  </span>
                </label>
                <input
                  type="password"
                  name="email[smtp_password]"
                  placeholder={if @smtp_configured, do: "Paste new password to replace", else: "App password"}
                  autocomplete="off"
                  class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent text-sm"
                />
              </div>
              <div class="grid grid-cols-2 gap-4">
                <div>
                  <label class="block text-xs font-medium text-gray-500 mb-1.5">
                    From Name <span class="text-gray-400">(optional)</span>
                  </label>
                  <input
                    type="text"
                    name="email[smtp_from_name]"
                    value={@email_form[:smtp_from_name].value}
                    placeholder={@current_organization.name}
                    class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent text-sm"
                  />
                </div>
                <div>
                  <label class="block text-xs font-medium text-gray-500 mb-1.5">
                    From Email
                  </label>
                  <input
                    type="email"
                    name="email[smtp_from_email]"
                    value={@email_form[:smtp_from_email].value}
                    placeholder="noreply@yourcompany.com"
                    class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent text-sm"
                  />
                </div>
              </div>
            </div>
          </div>
          <div class="px-6 py-3 bg-gray-50 border-t border-gray-200 flex items-center justify-between">
            <p class="text-sm text-gray-500">
              For Gmail: use smtp.gmail.com:587 with an App Password.
            </p>
            <div class="flex items-center gap-2">
              <button
                :if={@smtp_configured}
                type="button"
                phx-click="test_email"
                phx-disable-with="Sending..."
                class="px-4 py-1.5 text-sm text-gray-700 border border-gray-300 rounded-md hover:bg-gray-100 transition-colors font-medium"
              >
                Send Test
              </button>
              <button
                type="submit"
                phx-disable-with="Saving..."
                class="px-4 py-1.5 bg-gray-900 text-white text-sm rounded-md hover:bg-gray-800 transition-colors font-medium"
              >
                Save
              </button>
            </div>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.current_organization

    unless admin?(socket.assigns.current_membership) do
      {:ok,
       socket
       |> put_flash(:error, "Not authorized")
       |> push_navigate(to: ~p"/org/#{socket.assigns.org_id}/settings")}
    else
      email_changeset = Estimate.Accounts.Organization.smtp_settings_changeset(org, %{})

      {:ok,
       socket
       |> assign(:page_title, "Email (SMTP)")
       |> assign(:active_tab, :settings)
       |> assign(:settings_page, :email)
       |> assign(:email_form, to_form(email_changeset, as: :email))
       |> assign(:smtp_configured, Organizations.smtp_configured?(org))
       |> assign(:smtp_password_masked, Organizations.mask_smtp_password(org))}
    end
  end

  @impl true
  def handle_event("save_email_settings", %{"email" => email_params}, socket) do
    unless admin?(socket.assigns.current_membership) do
      {:noreply, put_flash(socket, :error, "Not authorized")}
    else
      # Don't overwrite password if left blank
      email_params =
        if email_params["smtp_password"] == "" do
          Map.delete(email_params, "smtp_password")
        else
          email_params
        end

      case Organizations.update_smtp_settings(socket.assigns.current_organization, email_params) do
        {:ok, org} ->
          email_changeset = Estimate.Accounts.Organization.smtp_settings_changeset(org, %{})

          {:noreply,
           socket
           |> put_flash(:info, "Email settings saved")
           |> assign(:current_organization, org)
           |> assign(:email_form, to_form(email_changeset, as: :email))
           |> assign(:smtp_configured, Organizations.smtp_configured?(org))
           |> assign(:smtp_password_masked, Organizations.mask_smtp_password(org))}

        {:error, changeset} ->
          {:noreply, assign(socket, email_form: to_form(changeset, as: :email))}
      end
    end
  end

  def handle_event("test_email", _params, socket) do
    unless admin?(socket.assigns.current_membership) do
      {:noreply, put_flash(socket, :error, "Not authorized")}
    else
      org = socket.assigns.current_organization

      email =
        Estimate.Emails.InviteEmail.test_email(org, socket.assigns.current_user.email)

      case Estimate.Mailer.deliver_with_org_smtp(email, org) do
        {:ok, _} ->
          {:noreply, put_flash(socket, :info, "Test email sent to #{socket.assigns.current_user.email}")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Email failed: #{inspect(reason)}")}
      end
    end
  end
end
