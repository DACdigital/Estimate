defmodule EstimateWeb.SettingsLive.Index do
  use EstimateWeb, :live_view

  alias Estimate.Organizations
  import EstimateWeb.LiveHelpers

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto">
      <%!-- Header --%>
      <div class="mb-8">
        <h1 class="text-2xl font-bold text-base-content">General</h1>
        <p class="mt-1 text-base-content/60">Manage your organization</p>
      </div>

      <div class="space-y-6">
        <%!-- Organization Name Card --%>
        <.form for={@form} id="org-form" phx-submit="save" phx-change="validate">
          <div class="bg-base-100 border border-base-300 rounded-xl overflow-hidden">
            <div class="p-6">
              <h2 class="text-xl font-semibold text-base-content">Organization Name</h2>
              <p class="mt-1 text-sm text-base-content/60">
                This is your organization's visible name. It will be shown to all members.
              </p>
              <div class="mt-4 max-w-md">
                <input
                  type="text"
                  name={@form[:name].name}
                  id={@form[:name].id}
                  value={@form[:name].value}
                  required
                  disabled={!@can_edit}
                  class={"w-full px-3 py-2 border border-base-content/20 rounded-lg text-sm #{unless @can_edit, do: "bg-base-200 text-base-content/60"}"}
                />
                <.error :for={msg <- Enum.map(@form[:name].errors || [], &translate_error(&1))}>
                  {msg}
                </.error>
              </div>
            </div>
            <div class="px-6 py-3 bg-base-100 border-t border-base-300 flex items-center justify-between">
              <p class="text-sm text-base-content/60">Please use 32 characters at maximum.</p>
              <button
                :if={@can_edit}
                type="submit"
                phx-disable-with="Saving..."
                class="px-4 py-1.5 bg-neutral text-neutral-content text-sm rounded-md hover:bg-neutral/90 transition-colors font-medium"
              >
                Save
              </button>
            </div>
          </div>
        </.form>

        <%!-- Security Card (admin only) --%>
        <div :if={@can_edit} class="bg-base-100 border border-base-300 rounded-xl overflow-hidden">
          <.form
            for={@security_form}
            id="security-settings-form"
            phx-submit="save_security_settings"
          >
            <div class="p-6 space-y-6">
              <div>
                <h2 class="text-xl font-semibold text-base-content">Security</h2>
                <p class="mt-1 text-sm text-base-content/60">
                  Two-factor authentication enforcement for your organization
                </p>
              </div>

              <div class="flex items-start gap-4">
                <div class="flex-1">
                  <label class="flex items-center gap-3 cursor-pointer">
                    <input type="hidden" name="security[enforce_2fa]" value="false" />
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
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.current_organization
    changeset = Organizations.change_organization(org)
    is_admin = admin?(socket.assigns.current_membership)

    members_without_2fa =
      if is_admin do
        Organizations.list_organization_members(socket.assigns.org_id)
        |> Enum.count(fn m -> !Estimate.Accounts.User.totp_enabled?(m.user) end)
      else
        0
      end

    {:ok,
     socket
     |> assign(:page_title, "Settings")
     |> assign(:active_tab, :settings)
     |> assign(:settings_page, :general)
     |> assign(:can_edit, is_admin)
     |> assign(:form, to_form(changeset))
     |> assign(:enforce_2fa, org.enforce_2fa)
     |> assign(:grace_days, org.enforce_2fa_grace_period_days)
     |> assign(:members_without_2fa, members_without_2fa)
     |> assign(:security_form, to_form(%{}, as: :security))}
  end

  @impl true
  def handle_event("validate", %{"organization" => org_params}, socket) do
    changeset =
      socket.assigns.current_organization
      |> Organizations.change_organization(org_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save", %{"organization" => org_params}, socket) do
    require_admin(socket, fn ->
      case Organizations.update_organization(socket.assigns.current_organization, org_params) do
        {:ok, org} ->
          {:noreply,
           socket
           |> put_flash(:info, "Organization updated successfully")
           |> assign(:current_organization, org)
           |> assign(:form, to_form(Organizations.change_organization(org)))}

        {:error, changeset} ->
          {:noreply, assign(socket, form: to_form(changeset))}
      end
    end)
  end

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
