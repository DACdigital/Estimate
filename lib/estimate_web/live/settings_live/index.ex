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
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    org = socket.assigns.current_organization
    changeset = Organizations.change_organization(org)

    {:ok,
     socket
     |> assign(:page_title, "Settings")
     |> assign(:active_tab, :settings)
     |> assign(:settings_page, :general)
     |> assign(:can_edit, admin?(socket.assigns.current_membership))
     |> assign(:form, to_form(changeset))}
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
end
