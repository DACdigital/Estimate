defmodule EstimateWeb.DashboardLive.Index do
  use EstimateWeb, :live_view

  alias Estimate.Portfolio
  alias Estimate.CRM
  alias Estimate.EstimationEngine
  alias Estimate.Organizations

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <%!-- Header --%>
      <div class="mb-8">
        <h1 class="text-2xl font-bold text-base-content">Dashboard</h1>
        <p class="mt-1 text-base-content/60">Overview of your estimation activity</p>
      </div>
      
    <!-- Stats -->
      <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
        <.link
          navigate={~p"/org/#{@org_id}/customers"}
          class="bg-base-100 border border-base-300 rounded-xl p-6 flex items-center justify-between hover:border-base-content/20 hover:shadow-sm transition-all"
        >
          <div>
            <p class="text-sm text-base-content/60">Total Customers</p>
            <p class="text-4xl font-bold text-base-content mt-1">{@customer_count}</p>
          </div>
          <div class="w-12 h-12 bg-base-200 rounded-full flex items-center justify-center">
            <.icon name="hero-building-office-2" class="w-6 h-6 text-base-content/70" />
          </div>
        </.link>

        <.link
          navigate={~p"/org/#{@org_id}/projects"}
          class="bg-base-100 border border-base-300 rounded-xl p-6 flex items-center justify-between hover:border-base-content/20 hover:shadow-sm transition-all"
        >
          <div>
            <p class="text-sm text-base-content/60">Total Projects</p>
            <p class="text-4xl font-bold text-base-content mt-1">{@project_count}</p>
          </div>
          <div class="w-12 h-12 bg-base-200 rounded-full flex items-center justify-center">
            <.icon name="hero-folder" class="w-6 h-6 text-base-content/70" />
          </div>
        </.link>

        <div class="bg-base-100 border border-base-300 rounded-xl p-6 flex items-center justify-between">
          <div>
            <p class="text-sm text-base-content/60">Active Estimations</p>
            <p class="text-4xl font-bold text-base-content mt-1">{@estimation_count}</p>
          </div>
          <div class="w-12 h-12 bg-base-200 rounded-full flex items-center justify-center">
            <.icon name="hero-chart-bar" class="w-6 h-6 text-base-content/70" />
          </div>
        </div>
      </div>
      
    <!-- Quality Watchtower (admin only) -->
      <div :if={@is_admin} class="mt-8">
        <div class="mb-6">
          <h2 class="text-2xl font-bold text-base-content">Quality Watchtower</h2>
          <p class="mt-1 text-base-content/60">Data quality issues across your organization</p>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
          <.watchtower_card
            count={@watchtower_customers}
            label="Customers Missing Description"
            icon="hero-building-office-2"
            navigate={~p"/org/#{@org_id}/customers?watchtower=missing_description"}
          />
          <.watchtower_card
            count={@watchtower_projects}
            label="Projects Missing Descriptions"
            icon="hero-folder"
            navigate={~p"/org/#{@org_id}/projects?watchtower=missing_descriptions"}
          />
          <.watchtower_card
            count={@watchtower_2fa}
            label="Members Without 2FA"
            icon="hero-shield-exclamation"
            navigate={~p"/org/#{@org_id}/settings"}
          />
          <.watchtower_card
            count={@watchtower_deleted_estimations}
            label="Deleted Estimations"
            icon="hero-trash"
            navigate={~p"/org/#{@org_id}/settings"}
          />
        </div>
      </div>
      
    <!-- Quick Links -->
      <div class="mt-8 grid grid-cols-1 md:grid-cols-2 gap-6">
        <div class="bg-base-100 border border-base-300 rounded-xl p-6">
          <h2 class="text-lg font-semibold text-base-content mb-4">Recently Updated</h2>
          <div class="space-y-3">
            <%= if Enum.empty?(@recent_estimations) do %>
              <p class="text-sm text-base-content/60">No estimations yet</p>
            <% else %>
              <%= for estimation <- @recent_estimations do %>
                <.link
                  navigate={
                    ~p"/org/#{@org_id}/projects/#{estimation.project_id}/estimations/#{estimation.id}/estimator"
                  }
                  class="block p-3 -mx-3 rounded-lg hover:bg-base-200 transition-colors"
                >
                  <p class="font-medium text-base-content">{estimation.name}</p>
                  <p class="text-sm text-base-content/60">
                    {estimation.project.name} · {estimation.project.customer.name}
                  </p>
                  <p class="text-xs text-base-content/40 mt-1">
                    Updated {Calendar.strftime(estimation.updated_at, "%b %d, %Y")}
                  </p>
                </.link>
              <% end %>
            <% end %>
          </div>
        </div>

        <div class="bg-base-100 border border-base-300 rounded-xl p-6">
          <h2 class="text-lg font-semibold text-base-content mb-4">Newest Estimations</h2>
          <div class="space-y-3">
            <%= if Enum.empty?(@newest_estimations) do %>
              <p class="text-sm text-base-content/60">No estimations yet</p>
            <% else %>
              <%= for estimation <- @newest_estimations do %>
                <.link
                  navigate={
                    ~p"/org/#{@org_id}/projects/#{estimation.project_id}/estimations/#{estimation.id}/estimator"
                  }
                  class="block p-3 -mx-3 rounded-lg hover:bg-base-200 transition-colors"
                >
                  <p class="font-medium text-base-content">{estimation.name}</p>
                  <p class="text-sm text-base-content/60">
                    {estimation.project.name} · {estimation.project.customer.name}
                  </p>
                  <p class="text-xs text-base-content/40 mt-1">
                    Created {Calendar.strftime(estimation.inserted_at, "%b %d, %Y")}
                  </p>
                </.link>
              <% end %>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :count, :integer, required: true
  attr :label, :string, required: true
  attr :icon, :string, required: true
  attr :navigate, :string, required: true

  defp watchtower_card(%{count: 0} = assigns) do
    ~H"""
    <div class="bg-success/5 border border-success/20 rounded-xl p-6">
      <div class="flex items-center justify-between">
        <div>
          <p class="text-sm text-base-content/60">{@label}</p>
          <p class="text-4xl font-bold text-success mt-1">0</p>
        </div>
        <div class="w-10 h-10 flex-shrink-0 bg-success/10 rounded-full flex items-center justify-center">
          <.icon name="hero-check-circle" class="w-5 h-5 text-success" />
        </div>
      </div>
    </div>
    """
  end

  defp watchtower_card(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class="bg-warning/5 border border-warning/20 rounded-xl p-6 hover:border-warning/40 transition-all"
    >
      <div class="flex items-center justify-between">
        <div>
          <p class="text-sm text-base-content/60">{@label}</p>
          <p class="text-4xl font-bold text-warning mt-1">{@count}</p>
        </div>
        <div class="w-10 h-10 flex-shrink-0 bg-warning/10 rounded-full flex items-center justify-center">
          <.icon name={@icon} class="w-5 h-5 text-warning" />
        </div>
      </div>
    </.link>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    org_id = socket.assigns.org_id
    user = socket.assigns.current_user
    membership = socket.assigns.current_membership
    role = membership.role
    is_admin = admin?(membership)
    customer_count = length(CRM.list_customers(org_id))
    project_count = length(Portfolio.list_projects(org_id, user.id, role))
    estimation_count = EstimationEngine.count_estimations_for_org(org_id)
    recent_estimations = EstimationEngine.list_recent_estimations_for_org(org_id)
    newest_estimations = EstimationEngine.list_newest_estimations_for_org(org_id)

    watchtower =
      if is_admin do
        %{
          customers: CRM.count_customers_missing_description(org_id),
          projects: Portfolio.count_projects_missing_descriptions(org_id),
          tfa: Organizations.count_members_without_2fa(org_id),
          deleted_estimations: EstimationEngine.count_deleted_estimations_for_org(org_id)
        }
      else
        %{customers: 0, projects: 0, tfa: 0, deleted_estimations: 0}
      end

    {:ok,
     socket
     |> assign(:customer_count, customer_count)
     |> assign(:project_count, project_count)
     |> assign(:estimation_count, estimation_count)
     |> assign(:recent_estimations, recent_estimations)
     |> assign(:newest_estimations, newest_estimations)
     |> assign(:is_admin, is_admin)
     |> assign(:watchtower_customers, watchtower.customers)
     |> assign(:watchtower_projects, watchtower.projects)
     |> assign(:watchtower_2fa, watchtower.tfa)
     |> assign(:watchtower_deleted_estimations, watchtower.deleted_estimations)
     |> assign(:page_title, "Dashboard")
     |> assign(:active_tab, :dashboard)}
  end
end
