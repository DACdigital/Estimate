defmodule EstimateWeb.CustomerLive.Index do
  use EstimateWeb, :live_view

  alias Estimate.CRM
  alias Estimate.CRM.Customer
  alias Estimate.Organizations.Currencies
  import EstimateWeb.LiveHelpers

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto">
      <%!-- Page Header --%>
      <div class="flex items-center justify-between mb-8">
        <div>
          <h1 class="text-2xl font-bold text-base-content">Customers</h1>
          <p class="mt-1 text-base-content/60">Manage your customer relationships</p>
        </div>
        <.link
          :if={@is_admin}
          patch={~p"/org/#{@org_id}/customers/new"}
          class="px-4 py-2 bg-neutral text-neutral-content text-sm rounded-lg hover:bg-neutral/90 transition-colors font-medium"
        >
          Add Customer
        </.link>
      </div>

      <%!-- Customer List --%>
      <div class="bg-base-100 border border-base-300 rounded-xl overflow-hidden">
        <%= if @customers == [] do %>
          <div class="px-6 py-16 text-center">
            <div class="w-12 h-12 mx-auto mb-4 rounded-full bg-base-200 flex items-center justify-center">
              <.icon name="hero-building-office" class="w-6 h-6 text-base-content/40" />
            </div>
            <p class="text-sm font-medium text-base-content">No customers yet</p>
            <p class="text-sm text-base-content/60 mt-1">Add your first customer to get started.</p>
          </div>
        <% else %>
          <div
            :for={customer <- @customers}
            class="px-6 py-5 flex items-center gap-4 border-b border-base-content/10 last:border-b-0 hover:bg-base-200 transition-colors"
          >
            <.link
              navigate={~p"/org/#{@org_id}/customers/#{customer.id}"}
              class="flex items-center gap-4 flex-1 min-w-0"
            >
              <.avatar name={customer.name} seed={customer.id} type={:customer} size={:lg} />
              <span class="text-xs font-mono text-base-content/40 w-12 flex-shrink-0">
                {customer.key}
              </span>
              <div class="min-w-0">
                <h3 class="text-sm font-medium text-base-content truncate">{customer.name}</h3>
                <p :if={customer.description} class="text-sm text-base-content/60 truncate">
                  {customer.description}
                </p>
              </div>
            </.link>
            <div class="flex items-center gap-3 flex-shrink-0">
              <span :if={customer.country} class="text-xs text-base-content/40">
                {customer.country}
              </span>
              <span :if={customer.default_currency} class="text-xs text-base-content/40 font-mono">
                {customer.default_currency.code}
              </span>
              <.link
                :if={@is_admin}
                patch={~p"/org/#{@org_id}/customers/#{customer.id}/edit"}
                class="text-base-content/40 hover:text-base-content/70 transition-colors"
              >
                <.icon name="hero-pencil" class="w-5 h-5" />
              </.link>
            </div>
          </div>
        <% end %>
      </div>

      <%!-- Modal --%>
      <.modal
        :if={@live_action in [:new, :edit]}
        id="customer-modal"
        show
        on_cancel={JS.patch(~p"/org/#{@org_id}/customers")}
      >
        <h2 class="text-xl font-semibold text-base-content mb-6">
          {if @live_action == :new, do: "Add Customer", else: "Edit Customer"}
        </h2>

        <.form for={@form} id="customer-form" phx-submit="save" phx-change="validate">
          <div class="space-y-4">
            <div class="grid grid-cols-2 gap-4">
              <div>
                <label class="block text-xs font-medium text-base-content/60 mb-1.5">
                  Customer Key *
                </label>
                <input
                  type="text"
                  name={@form[:key].name}
                  value={@form[:key].value}
                  placeholder="ACME"
                  required
                  class="w-full px-3 py-2 border border-base-content/20 rounded-lg text-sm font-mono uppercase"
                />
              </div>
              <div>
                <label class="block text-xs font-medium text-base-content/60 mb-1.5">
                  Customer Name *
                </label>
                <input
                  type="text"
                  name={@form[:name].name}
                  value={@form[:name].value}
                  placeholder="Acme Corporation"
                  required
                  class="w-full px-3 py-2 border border-base-content/20 rounded-lg text-sm"
                />
              </div>
            </div>
            <div class="grid grid-cols-2 gap-4">
              <div>
                <label class="block text-xs font-medium text-base-content/60 mb-1.5">Country</label>
                <input
                  type="text"
                  name={@form[:country].name}
                  value={@form[:country].value}
                  placeholder="US"
                  maxlength="2"
                  class="w-full px-3 py-2 border border-base-content/20 rounded-lg text-sm uppercase"
                />
              </div>
              <div>
                <label class="block text-xs font-medium text-base-content/60 mb-1.5">Website</label>
                <input
                  type="url"
                  name={@form[:website_url].name}
                  value={@form[:website_url].value}
                  placeholder="https://acme.com"
                  class="w-full px-3 py-2 border border-base-content/20 rounded-lg text-sm"
                />
              </div>
            </div>
            <div>
              <label class="block text-xs font-medium text-base-content/60 mb-1.5">
                Default Currency
              </label>
              <select
                name={@form[:default_currency_id].name}
                class="w-full px-3 py-2 border border-base-content/20 rounded-lg text-sm"
              >
                <option value="">None</option>
                <%= for currency <- @currencies do %>
                  <option
                    value={currency.id}
                    selected={currency.id == @form[:default_currency_id].value}
                  >
                    {currency.code} - {currency.name}
                  </option>
                <% end %>
              </select>
            </div>
            <div>
              <label class="block text-xs font-medium text-base-content/60 mb-1.5">Description</label>
              <textarea
                name={@form[:description].name}
                rows="3"
                placeholder="Brief description..."
                class="w-full px-3 py-2 border border-base-content/20 rounded-lg text-sm resize-none"
              ><%= @form[:description].value %></textarea>
            </div>
          </div>
          <div class="mt-6 flex justify-end gap-3">
            <.link
              patch={~p"/org/#{@org_id}/customers"}
              class="px-4 py-2 text-sm text-base-content/70 hover:text-base-content transition-colors"
            >
              Cancel
            </.link>
            <button
              type="submit"
              phx-disable-with="Saving..."
              class="px-4 py-2 bg-neutral text-neutral-content text-sm rounded-lg hover:bg-neutral/90 transition-colors font-medium"
            >
              {if @live_action == :new, do: "Add Customer", else: "Save Changes"}
            </button>
          </div>
        </.form>
      </.modal>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    customers = CRM.list_customers(socket.assigns.org_id)
    currencies = Currencies.list_currencies(socket.assigns.org_id)

    {:ok,
     socket
     |> assign(:page_title, "Customers")
     |> assign(:active_tab, :customers)
     |> assign(:customers, customers)
     |> assign(:currencies, currencies)
     |> assign(:is_admin, admin?(socket.assigns.current_membership))
     |> assign(:customer, nil)
     |> assign(:form, nil)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    changeset = CRM.change_customer(%Customer{})

    socket
    |> assign(:page_title, "New Customer")
    |> assign(:customer, %Customer{})
    |> assign(:form, to_form(changeset))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    customer = CRM.get_customer!(id, socket.assigns.org_id)
    changeset = CRM.change_customer(customer)

    socket
    |> assign(:page_title, "Edit Customer")
    |> assign(:customer, customer)
    |> assign(:form, to_form(changeset))
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Customers")
    |> assign(:customer, nil)
    |> assign(:form, nil)
  end

  @impl true
  def handle_event("validate", %{"customer" => customer_params}, socket) do
    changeset =
      socket.assigns.customer
      |> CRM.change_customer(customer_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save", %{"customer" => customer_params}, socket) do
    require_admin(socket, fn ->
      save_customer(socket, socket.assigns.live_action, customer_params)
    end)
  end

  defp save_customer(socket, :new, customer_params) do
    case CRM.create_customer(socket.assigns.org_id, customer_params) do
      {:ok, _customer} ->
        customers = CRM.list_customers(socket.assigns.org_id)

        {:noreply,
         socket
         |> put_flash(:info, "Customer created successfully")
         |> assign(:customers, customers)
         |> push_patch(to: ~p"/org/#{socket.assigns.org_id}/customers")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_customer(socket, :edit, customer_params) do
    case CRM.update_customer(socket.assigns.customer, customer_params) do
      {:ok, _customer} ->
        customers = CRM.list_customers(socket.assigns.org_id)

        {:noreply,
         socket
         |> put_flash(:info, "Customer updated successfully")
         |> assign(:customers, customers)
         |> push_patch(to: ~p"/org/#{socket.assigns.org_id}/customers")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end
end
