defmodule EstimateWeb.CustomerLive.Show do
  use EstimateWeb, :live_view

  alias Estimate.CRM
  alias Estimate.Portfolio

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto">
      <%!-- Breadcrumb --%>
      <nav class="flex items-center space-x-2 text-sm text-gray-500 mb-6">
        <.link navigate={~p"/org/#{@org_id}/customers"} class="hover:text-gray-900">
          Customers
        </.link>
        <span class="text-gray-300">›</span>
        <span class="text-gray-900 font-medium">{@customer.name}</span>
      </nav>

      <%!-- Customer Header --%>
      <div class="flex items-start justify-between mb-8">
        <div class="flex items-center gap-4">
          <div class="w-14 h-14 rounded-full bg-gradient-to-br from-emerald-500 to-teal-600 flex items-center justify-center text-white text-xl font-medium">
            {String.first(@customer.name) |> String.upcase()}
          </div>
          <div>
            <div class="flex items-center gap-3">
              <h1 class="text-2xl font-bold text-gray-900">{@customer.name}</h1>
              <span class="text-sm font-mono text-gray-400">{@customer.key}</span>
              <span
                :if={@customer.country}
                class="text-xs text-gray-400 px-1.5 py-0.5 bg-gray-100 rounded"
              >
                {@customer.country}
              </span>
            </div>
            <p :if={@customer.description} class="mt-1 text-gray-500">{@customer.description}</p>
            <div class="flex items-center gap-4 mt-2 text-sm">
              <a
                :if={@customer.website_url}
                href={@customer.website_url}
                target="_blank"
                class="text-blue-600 hover:underline"
              >
                {@customer.website_url}
              </a>
              <span :if={@customer.default_currency} class="text-gray-400">
                Default: {@customer.default_currency.code}
              </span>
            </div>
          </div>
        </div>
        <div class="flex items-center gap-2">
          <.link
            patch={~p"/org/#{@org_id}/customers/#{@customer.id}/edit"}
            class="px-3 py-1.5 text-sm text-gray-600 hover:text-gray-900 border border-gray-200 rounded-lg hover:border-gray-300 transition-colors"
          >
            Edit
          </.link>
          <button
            :if={@is_admin}
            phx-click="confirm_delete"
            class="px-3 py-1.5 text-sm text-red-600 hover:text-red-700 border border-red-200 rounded-lg hover:border-red-300 transition-colors"
          >
            Delete
          </button>
        </div>
      </div>

      <%!-- Projects Section --%>
      <div class="bg-white border border-gray-200 rounded-xl overflow-hidden">
        <div class="px-6 py-4 border-b border-gray-100 flex items-center justify-between">
          <h2 class="font-semibold text-gray-900">Projects</h2>
          <.link
            navigate={~p"/org/#{@org_id}/projects/new?customer_id=#{@customer.id}"}
            class="px-3 py-1.5 bg-gray-900 text-white text-sm rounded-lg hover:bg-gray-800 transition-colors"
          >
            New Project
          </.link>
        </div>

        <%= if @projects == [] do %>
          <div class="px-6 py-12 text-center">
            <div class="w-10 h-10 mx-auto mb-3 rounded-full bg-gray-100 flex items-center justify-center">
              <.icon name="hero-folder" class="w-5 h-5 text-gray-400" />
            </div>
            <p class="text-sm text-gray-500">No projects yet</p>
          </div>
        <% else %>
          <div
            :for={project <- @projects}
            class="px-6 py-4 flex items-center justify-between border-b border-gray-100 last:border-b-0 hover:bg-gray-50 transition-colors"
          >
            <.link navigate={~p"/org/#{@org_id}/projects/#{project.id}"} class="flex-1 min-w-0">
              <div class="flex items-center gap-3">
                <h3 class="text-sm font-medium text-gray-900">{project.name}</h3>
                <span class={"text-xs px-1.5 py-0.5 rounded #{status_color(project.status)}"}>
                  {project.status}
                </span>
              </div>
              <p :if={project.short_description} class="text-sm text-gray-500 truncate mt-0.5">
                {project.short_description}
              </p>
            </.link>
          </div>
        <% end %>
      </div>

      <div class="mt-6">
        <.link
          navigate={~p"/org/#{@org_id}/customers"}
          class="text-sm text-gray-500 hover:text-gray-700"
        >
          ← Back to Customers
        </.link>
      </div>

      <%!-- Delete Customer Modal --%>
      <.modal
        :if={@deleting_customer}
        id="delete-customer-modal"
        show
        on_cancel={JS.push("cancel_delete")}
      >
        <div class="text-center">
          <div class="w-12 h-12 rounded-full bg-red-100 flex items-center justify-center mx-auto mb-4">
            <.icon name="hero-exclamation-triangle" class="w-6 h-6 text-red-600" />
          </div>
          <h3 class="text-lg font-semibold text-gray-900 mb-2">Delete Customer</h3>
          <p class="text-sm text-gray-500 mb-6">
            Are you sure you want to delete <span class="font-medium text-gray-900"><%= @customer.name %></span>?
            This will also delete all their projects and estimations.
          </p>
          <div class="flex gap-3 justify-center">
            <button
              phx-click="cancel_delete"
              class="px-4 py-2 text-sm text-gray-600 hover:text-gray-900 transition-colors"
            >
              Cancel
            </button>
            <button
              phx-click="delete"
              class="px-4 py-2 bg-red-600 text-white text-sm rounded-lg hover:bg-red-700 transition-colors font-medium"
            >
              Delete Customer
            </button>
          </div>
        </div>
      </.modal>
    </div>
    """
  end

  defp status_color("active"), do: "bg-green-100 text-green-700"
  defp status_color("completed"), do: "bg-blue-100 text-blue-700"
  defp status_color("archived"), do: "bg-gray-100 text-gray-500"
  defp status_color(_), do: "bg-gray-100 text-gray-500"

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
     |> assign(:deleting_customer, false)}
  end

  @impl true
  def handle_event("confirm_delete", _params, socket) do
    {:noreply, assign(socket, :deleting_customer, true)}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :deleting_customer, false)}
  end

  def handle_event("delete", _params, socket) do
    unless socket.assigns.is_admin do
      {:noreply, put_flash(socket, :error, "Not authorized")}
    else
      do_delete_customer(socket)
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
