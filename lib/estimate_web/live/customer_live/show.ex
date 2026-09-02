defmodule EstimateWeb.CustomerLive.Show do
  use EstimateWeb, :live_view

  alias Estimate.CRM
  alias Estimate.Portfolio

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto">
      <%!-- Breadcrumb --%>
      <nav class="flex items-center space-x-2 text-sm text-base-content/60 mb-6">
        <.link navigate={~p"/org/#{@org_id}/customers"} class="hover:text-base-content">
          Customers
        </.link>
        <span class="text-base-content/30">›</span>
        <span class="text-base-content font-medium">{@customer.name}</span>
      </nav>

      <%!-- Customer Header --%>
      <div class="flex items-start justify-between mb-8">
        <div class="flex items-center gap-4">
          <.avatar name={@customer.name} seed={@customer.id} type={:customer} size={:xl} />
          <div>
            <div class="flex items-center gap-3">
              <h1 class="text-2xl font-bold text-base-content">{@customer.name}</h1>
              <span class="text-sm font-mono text-base-content/40">{@customer.key}</span>
              <span
                :if={@customer.country}
                class="text-xs text-base-content/40 px-1.5 py-0.5 bg-base-200 rounded"
              >
                {@customer.country}
              </span>
            </div>
            <p :if={@customer.description} class="mt-1 text-base-content/60">
              {@customer.description}
            </p>
            <div class="flex items-center gap-4 mt-2 text-sm">
              <a
                :if={@customer.website_url}
                href={@customer.website_url}
                target="_blank"
                class="text-info hover:underline"
              >
                {@customer.website_url}
              </a>
              <span :if={@customer.default_currency} class="text-base-content/40">
                Default: {@customer.default_currency.code}
              </span>
            </div>
          </div>
        </div>
        <div class="flex items-center gap-2">
          <.link
            patch={~p"/org/#{@org_id}/customers/#{@customer.id}/edit"}
            class="px-3 py-1.5 text-sm text-base-content/70 hover:text-base-content border border-base-300 rounded-lg hover:border-base-content/20 transition-colors"
          >
            Edit
          </.link>
          <button
            :if={@is_admin}
            phx-click="confirm_delete"
            class="px-3 py-1.5 text-sm text-error hover:text-error border border-error/30 dark:border-error/50 rounded-lg hover:border-error/50 transition-colors"
          >
            Delete
          </button>
        </div>
      </div>

      <%!-- Projects Section --%>
      <div class="bg-base-100 border border-base-300 rounded-xl overflow-hidden">
        <div class="px-6 py-4 border-b border-base-content/10 flex items-center justify-between">
          <h2 class="font-semibold text-base-content">Projects</h2>
          <.link
            navigate={~p"/org/#{@org_id}/projects/new?customer_id=#{@customer.id}"}
            class="px-3 py-1.5 bg-neutral text-neutral-content text-sm rounded-lg hover:bg-neutral/90 transition-colors"
          >
            New Project
          </.link>
        </div>

        <%= if @projects == [] do %>
          <div class="px-6 py-12 text-center">
            <div class="w-10 h-10 mx-auto mb-3 rounded-full bg-base-200 flex items-center justify-center">
              <.icon name="hero-folder" class="w-5 h-5 text-base-content/40" />
            </div>
            <p class="text-sm text-base-content/60">No projects yet</p>
          </div>
        <% else %>
          <div
            :for={project <- @projects}
            class="px-6 py-4 flex items-center justify-between border-b border-base-content/10 last:border-b-0 hover:bg-base-200 transition-colors"
          >
            <.link navigate={~p"/org/#{@org_id}/projects/#{project.id}"} class="flex-1 min-w-0">
              <div class="flex items-center gap-3">
                <h3 class="text-sm font-medium text-base-content">{project.name}</h3>
                <span class={"text-xs px-1.5 py-0.5 rounded #{project_status_class(project.status)}"}>
                  {project.status}
                </span>
              </div>
              <p :if={project.short_description} class="text-sm text-base-content/60 truncate mt-0.5">
                {project.short_description}
              </p>
            </.link>
          </div>
        <% end %>
      </div>

      <div class="mt-6">
        <.link
          navigate={~p"/org/#{@org_id}/customers"}
          class="text-sm text-base-content/60 hover:text-base-content/80"
        >
          ← Back to Customers
        </.link>
      </div>

      <.modal
        :if={@deleting_customer}
        id="delete-customer-modal"
        show
        on_cancel={JS.push("cancel_delete")}
      >
        <div>
          <div class="w-12 h-12 rounded-full bg-error/10 flex items-center justify-center mx-auto mb-4">
            <.icon name="hero-exclamation-triangle" class="w-6 h-6 text-error" />
          </div>
          <h3 class="text-lg font-semibold text-base-content mb-2 text-center">Delete Customer</h3>
          <p class="text-sm text-base-content/60 mb-4 text-center">
            This will permanently delete:
          </p>
          <ul class="text-sm text-base-content/60 mb-4 space-y-1 pl-4">
            <li>
              <span class="font-medium text-base-content">{@delete_impact.project_count}</span>
              projects
            </li>
            <li>
              <span class="font-medium text-base-content">{@delete_impact.estimation_count}</span>
              estimations
            </li>
          </ul>
          <p class="text-sm text-base-content/60 mb-2">
            Type <span class="font-medium text-base-content">{@customer.name}</span> to confirm:
          </p>
          <input
            type="text"
            phx-keyup="validate_delete_confirmation"
            value={@delete_confirmation_input}
            class="w-full px-3 py-2 border border-base-content/20 rounded-lg text-sm mb-4"
            placeholder={@customer.name}
            autocomplete="off"
          />
          <div class="flex gap-3 justify-center">
            <button
              phx-click="cancel_delete"
              class="px-4 py-2 text-sm text-base-content/70 hover:text-base-content"
            >
              Cancel
            </button>
            <button
              phx-click="delete"
              disabled={@delete_confirmation_input != @customer.name}
              class={"px-4 py-2 text-sm rounded-lg font-medium #{if @delete_confirmation_input == @customer.name, do: "bg-error text-neutral-content hover:bg-error/90", else: "bg-base-300 text-base-content/30 cursor-not-allowed"}"}
            >
              Delete Customer
            </button>
          </div>
        </div>
      </.modal>
    </div>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    org_id = socket.assigns.org_id
    user = socket.assigns.current_user
    role = socket.assigns.current_membership.role
    customer = CRM.get_customer!(id, org_id)
    projects = Portfolio.list_customer_projects(customer.id, org_id, user.id, role)

    {:ok,
     socket
     |> assign(:page_title, customer.name)
     |> assign(:active_tab, :customers)
     |> assign(:customer, customer)
     |> assign(:projects, projects)
     |> assign(:is_admin, admin?(socket.assigns.current_membership))
     |> assign(:deleting_customer, false)
     |> assign(:delete_impact, %{project_count: 0, estimation_count: 0})
     |> assign(:delete_confirmation_input, "")}
  end

  @impl true
  def handle_event("confirm_delete", _params, socket) do
    require_admin(socket, fn ->
      impact = CRM.deletion_impact(socket.assigns.customer)

      {:noreply,
       socket
       |> assign(:deleting_customer, true)
       |> assign(:delete_impact, impact)
       |> assign(:delete_confirmation_input, "")}
    end)
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply,
     socket
     |> assign(:deleting_customer, false)
     |> assign(:delete_confirmation_input, "")}
  end

  def handle_event("validate_delete_confirmation", %{"value" => value}, socket) do
    {:noreply, assign(socket, :delete_confirmation_input, value)}
  end

  def handle_event("delete", _params, socket) do
    if socket.assigns.delete_confirmation_input != socket.assigns.customer.name do
      {:noreply, put_flash(socket, :error, "Name does not match")}
    else
      require_admin(socket, fn ->
        do_delete_customer(socket)
      end)
    end
  end

  defp do_delete_customer(socket) do
    case CRM.delete_customer(socket.assigns.customer) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Customer deleted")
         |> push_navigate(to: ~p"/org/#{socket.assigns.org_id}/customers")}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Could not delete customer")
         |> assign(:deleting_customer, false)}
    end
  end
end
