defmodule EstimateWeb.SettingsLive.Security do
  use EstimateWeb, :live_view

  alias Estimate.Organizations
  import EstimateWeb.LiveHelpers

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto">
      <div class="mb-8">
        <h1 class="text-2xl font-bold text-base-content">Security</h1>
        <p class="mt-1 text-base-content/60">
          Manage two-factor authentication for your organization
        </p>
      </div>

      <div class="bg-base-100 border border-base-300 rounded-xl overflow-hidden">
        <.form for={@security_form} id="security-settings-form" phx-submit="save_security_settings">
          <div class="p-6 space-y-6">
            <div class="flex items-start gap-4">
              <div class="flex-1">
                <label class="flex items-center gap-3 cursor-pointer">
                  <input
                    type="hidden"
                    name="security[enforce_2fa]"
                    value="false"
                  />
                  <input
                    type="checkbox"
                    name="security[enforce_2fa]"
                    value="true"
                    checked={@enforce_2fa}
                    phx-change="toggle_enforce"
                    class="rounded border-base-content/20"
                  />
                  <div>
                    <span class="text-sm font-medium text-base-content">
                      Require two-factor authentication for all members
                    </span>
                    <p class="text-xs text-base-content/60 mt-0.5">
                      Members without 2FA will be required to set it up within the grace period
                    </p>
                  </div>
                </label>
              </div>
            </div>

            <div :if={@enforce_2fa} class="ml-7">
              <label class="block text-xs font-medium text-base-content/60 mb-1.5">
                Grace period (days)
              </label>
              <input
                type="number"
                name="security[enforce_2fa_grace_period_days]"
                value={@grace_days}
                min="1"
                max="90"
                class="w-24 px-3 py-2 border border-base-content/20 rounded-lg text-sm"
              />
              <p class="mt-1 text-xs text-base-content/40">
                Members will have this many days to set up 2FA after enforcement is enabled
              </p>
            </div>

            <div
              :if={@enforce_2fa && @members_without_2fa > 0}
              class="ml-7 p-3 bg-warning/10 border border-warning/20 rounded-lg"
            >
              <p class="text-sm text-warning">
                <span class="font-medium">{@members_without_2fa}</span>
                {if @members_without_2fa == 1, do: "member doesn't", else: "members don't"} have 2FA enabled yet.
              </p>
            </div>
          </div>
          <div class="px-6 py-3 bg-base-100 border-t border-base-300 flex justify-end">
            <button
              type="submit"
              phx-disable-with="Saving..."
              class="px-4 py-1.5 bg-neutral text-neutral-content text-sm rounded-md hover:bg-neutral/90 transition-colors font-medium"
            >
              Save
            </button>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    unless admin?(socket.assigns.current_membership) do
      {:ok,
       socket
       |> put_flash(:error, "Not authorized")
       |> push_navigate(to: ~p"/org/#{socket.assigns.org_id}/settings")}
    else
      org = socket.assigns.current_organization

      members_without_2fa =
        Organizations.list_organization_members(socket.assigns.org_id)
        |> Enum.count(fn m -> !Estimate.Accounts.User.totp_enabled?(m.user) end)

      {:ok,
       socket
       |> assign(:page_title, "Security")
       |> assign(:active_tab, :settings)
       |> assign(:settings_page, :security)
       |> assign(:enforce_2fa, org.enforce_2fa)
       |> assign(:grace_days, org.enforce_2fa_grace_period_days)
       |> assign(:members_without_2fa, members_without_2fa)
       |> assign(:security_form, to_form(%{}, as: :security))}
    end
  end

  @impl true
  def handle_event("toggle_enforce", %{"security" => %{"enforce_2fa" => "true"}}, socket) do
    {:noreply, assign(socket, :enforce_2fa, true)}
  end

  def handle_event("toggle_enforce", _params, socket) do
    {:noreply, assign(socket, :enforce_2fa, false)}
  end

  def handle_event("save_security_settings", %{"security" => params}, socket) do
    require_admin(socket, fn ->
      case Organizations.update_security_settings(socket.assigns.current_organization, params) do
        {:ok, org} ->
          members_without_2fa =
            Organizations.list_organization_members(socket.assigns.org_id)
            |> Enum.count(fn m -> !Estimate.Accounts.User.totp_enabled?(m.user) end)

          {:noreply,
           socket
           |> put_flash(:info, "Security settings saved")
           |> assign(:current_organization, org)
           |> assign(:enforce_2fa, org.enforce_2fa)
           |> assign(:grace_days, org.enforce_2fa_grace_period_days)
           |> assign(:members_without_2fa, members_without_2fa)}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Could not save settings")}
      end
    end)
  end
end
