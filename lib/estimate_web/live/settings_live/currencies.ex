defmodule EstimateWeb.SettingsLive.Currencies do
  use EstimateWeb, :live_view

  alias Estimate.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto space-y-6">
      <%!-- Currency List Card --%>
      <div class="bg-white border border-gray-200 rounded-xl overflow-hidden">
        <div class="p-6">
          <h2 class="text-xl font-semibold text-gray-900">Currencies</h2>
          <p class="mt-1 text-sm text-gray-500">
            Manage currencies and exchange rates. Click any row to set as main.
          </p>
        </div>

        <div class="border-t border-gray-200">
          <%!-- Table Header --%>
          <div class="px-6 py-3 bg-gray-50 grid grid-cols-12 gap-6 text-xs font-medium text-gray-500 uppercase tracking-wider">
            <div class="col-span-2">Code</div>
            <div class="col-span-3">Name</div>
            <div class="col-span-1">Symbol</div>
            <div class="col-span-2">Position</div>
            <div class="col-span-2">Rate to {@main_currency.code}</div>
            <div class="col-span-2"></div>
          </div>

          <%!-- Currency Rows --%>
          <%= for currency <- @currencies do %>
            <div class={"px-6 py-4 grid grid-cols-12 gap-6 items-center border-t border-gray-100 #{unless currency.is_main, do: "hover:bg-gray-50 group", else: "bg-gray-50"}"}>
              <div class="col-span-2 flex items-center gap-2">
                <input
                  type="text"
                  value={currency.code}
                  maxlength="3"
                  phx-blur="update_field"
                  phx-value-id={currency.id}
                  phx-value-field="code"
                  class="w-14 px-2 py-1 border border-transparent hover:border-gray-200 rounded text-sm font-mono font-medium text-gray-900 focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent uppercase bg-transparent"
                />
                <%= if currency.is_main do %>
                  <span class="px-1.5 py-0.5 text-xs bg-gray-900 text-white rounded">Main</span>
                <% else %>
                  <button
                    phx-click="set_main"
                    phx-value-id={currency.id}
                    class="px-1.5 py-0.5 text-xs border border-gray-300 text-gray-500 rounded opacity-0 group-hover:opacity-100 transition-opacity hover:bg-gray-100"
                  >
                    Set main
                  </button>
                <% end %>
              </div>
              <div class="col-span-3">
                <input
                  type="text"
                  value={currency.name}
                  phx-blur="update_field"
                  phx-value-id={currency.id}
                  phx-value-field="name"
                  class="w-full px-2 py-1 border border-transparent hover:border-gray-200 rounded text-sm text-gray-600 focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent bg-transparent"
                />
              </div>
              <div class="col-span-1">
                <input
                  type="text"
                  value={currency.symbol}
                  maxlength="5"
                  phx-blur="update_field"
                  phx-value-id={currency.id}
                  phx-value-field="symbol"
                  class="w-full px-2 py-1 border border-transparent hover:border-gray-200 rounded text-sm text-gray-600 focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent bg-transparent"
                />
              </div>
              <div class="col-span-2">
                <button
                  phx-click="toggle_position"
                  phx-value-id={currency.id}
                  class="flex items-center gap-1.5 px-2.5 py-1.5 text-xs border border-gray-200 rounded-md hover:border-gray-300 hover:bg-gray-50 transition-colors"
                  title="Toggle symbol position"
                >
                  <span class={"font-mono #{if currency.symbol_position == "prefix", do: "text-gray-900 font-medium", else: "text-gray-400"}"}>
                    {currency.symbol}99
                  </span>
                  <span class="text-gray-300">|</span>
                  <span class={"font-mono #{if currency.symbol_position == "suffix", do: "text-gray-900 font-medium", else: "text-gray-400"}"}>
                    99{currency.symbol}
                  </span>
                </button>
              </div>
              <div class="col-span-2">
                <%= if currency.is_main do %>
                  <span class="w-24 px-2 py-1 text-sm font-mono text-gray-500">1.0</span>
                <% else %>
                  <input
                    type="number"
                    step="0.0001"
                    min="0.0001"
                    value={currency.exchange_rate}
                    phx-blur="update_rate"
                    phx-value-id={currency.id}
                    phx-click="stop_propagation"
                    class="w-24 px-2 py-1 border border-gray-200 rounded text-sm font-mono focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent"
                  />
                <% end %>
              </div>
              <div class="col-span-2 text-right">
                <%= if @is_admin && !currency.is_main do %>
                  <button
                    phx-click="confirm_delete"
                    phx-value-id={currency.id}
                    class="text-gray-400 hover:text-red-600 transition-colors focus:outline-none"
                  >
                    <.icon name="hero-trash" class="w-4 h-4" />
                  </button>
                <% end %>
              </div>
            </div>
          <% end %>

          <%!-- Add Currency Row --%>
          <.form
            for={@new_currency_form}
            phx-submit="add_currency"
            class="px-6 py-4 grid grid-cols-12 gap-6 items-center border-t border-gray-100 bg-gray-50"
          >
            <div class="col-span-2">
              <input
                type="text"
                name={@new_currency_form[:code].name}
                value={@new_currency_form[:code].value}
                placeholder="USD"
                maxlength="3"
                class="w-full px-2.5 py-1.5 border border-gray-300 rounded-md text-sm font-mono uppercase focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent"
              />
            </div>
            <div class="col-span-3">
              <input
                type="text"
                name={@new_currency_form[:name].name}
                value={@new_currency_form[:name].value}
                placeholder="US Dollar"
                class="w-full px-2.5 py-1.5 border border-gray-300 rounded-md text-sm focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent"
              />
            </div>
            <div class="col-span-1">
              <input
                type="text"
                name={@new_currency_form[:symbol].name}
                value={@new_currency_form[:symbol].value}
                placeholder="$"
                maxlength="5"
                class="w-full px-2.5 py-1.5 border border-gray-300 rounded-md text-sm focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent"
              />
            </div>
            <div class="col-span-2">
              <select
                name={@new_currency_form[:symbol_position].name}
                class="w-full px-2.5 py-1.5 border border-gray-300 rounded-md text-sm focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent"
              >
                <option
                  value="prefix"
                  selected={@new_currency_form[:symbol_position].value != "suffix"}
                >
                  $99 (prefix)
                </option>
                <option
                  value="suffix"
                  selected={@new_currency_form[:symbol_position].value == "suffix"}
                >
                  99$ (suffix)
                </option>
              </select>
            </div>
            <div class="col-span-2">
              <input
                type="number"
                step="0.0001"
                min="0.0001"
                name={@new_currency_form[:exchange_rate].name}
                value={@new_currency_form[:exchange_rate].value}
                placeholder="1.0"
                class="w-24 px-2 py-1 border border-gray-300 rounded text-sm font-mono focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent"
              />
            </div>
            <div class="col-span-2 text-right">
              <button
                type="submit"
                class="px-3 py-1 bg-gray-900 text-white text-sm rounded hover:bg-gray-800 transition-colors"
              >
                Add
              </button>
            </div>
          </.form>
        </div>
      </div>

      <%!-- Delete Confirmation Modal --%>
      <.modal
        :if={@deleting_currency}
        id="delete-currency-modal"
        show
        on_cancel={JS.push("cancel_delete")}
      >
        <div class="text-center">
          <div class="w-12 h-12 rounded-full bg-red-100 flex items-center justify-center mx-auto mb-4">
            <.icon name="hero-exclamation-triangle" class="w-6 h-6 text-red-600" />
          </div>
          <h3 class="text-lg font-semibold text-gray-900 mb-2">Delete Currency</h3>
          <p class="text-sm text-gray-500 mb-6">
            Are you sure you want to delete <span class="font-medium text-gray-900"><%= @deleting_currency.code %></span>?
            This action cannot be undone.
          </p>
          <div class="flex gap-3 justify-center">
            <button
              phx-click="cancel_delete"
              class="px-4 py-2 text-sm text-gray-600 hover:text-gray-900 transition-colors"
            >
              Cancel
            </button>
            <button
              phx-click="delete_currency"
              class="px-4 py-2 bg-red-600 text-white text-sm rounded-lg hover:bg-red-700 transition-colors font-medium"
            >
              Delete
            </button>
          </div>
        </div>
      </.modal>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    currencies = Accounts.list_currencies(socket.assigns.org_id)
    main_currency = Enum.find(currencies, & &1.is_main)

    {:ok,
     socket
     |> assign(:page_title, "Currencies")
     |> assign(:active_tab, :settings)
     |> assign(:settings_page, :currencies)
     |> assign(:currencies, currencies)
     |> assign(:main_currency, main_currency)
     |> assign(:is_admin, socket.assigns.current_membership.role in ["owner", "admin"])
     |> assign(:deleting_currency, nil)
     |> assign(
       :new_currency_form,
       to_form(
         %{
           "code" => "",
           "name" => "",
           "symbol" => "",
           "symbol_position" => "prefix",
           "exchange_rate" => "1.0"
         },
         as: "currency"
       )
     )}
  end

  @impl true
  def handle_event("set_main", %{"id" => id}, socket) do
    currency = Accounts.get_currency!(id, socket.assigns.org_id)

    case Accounts.set_main_currency(currency) do
      {:ok, _} ->
        currencies = Accounts.list_currencies(socket.assigns.org_id)
        main = Enum.find(currencies, & &1.is_main)

        {:noreply,
         socket
         |> put_flash(:info, "#{currency.code} is now main")
         |> assign(:currencies, currencies)
         |> assign(:main_currency, main)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not set main currency")}
    end
  end

  def handle_event("stop_propagation", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("update_field", %{"id" => id, "field" => field, "value" => value}, socket) do
    currency = Accounts.get_currency!(id, socket.assigns.org_id)
    attrs = %{field => value}

    case Accounts.update_currency(currency, attrs) do
      {:ok, _} ->
        currencies = Accounts.list_currencies(socket.assigns.org_id)
        {:noreply, assign(socket, :currencies, currencies)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not update #{field}")}
    end
  end

  def handle_event("toggle_position", %{"id" => id}, socket) do
    currency = Accounts.get_currency!(id, socket.assigns.org_id)
    new_position = if currency.symbol_position == "prefix", do: "suffix", else: "prefix"

    case Accounts.update_currency(currency, %{symbol_position: new_position}) do
      {:ok, _} ->
        currencies = Accounts.list_currencies(socket.assigns.org_id)
        {:noreply, assign(socket, :currencies, currencies)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not update symbol position")}
    end
  end

  def handle_event("update_rate", %{"id" => id, "value" => rate_str}, socket) do
    currency = Accounts.get_currency!(id, socket.assigns.org_id)

    case Decimal.parse(rate_str) do
      {rate, _} ->
        if Decimal.gt?(rate, 0) do
          case Accounts.update_currency(currency, %{exchange_rate: rate}) do
            {:ok, _} ->
              currencies = Accounts.list_currencies(socket.assigns.org_id)
              {:noreply, assign(socket, :currencies, currencies)}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Could not update rate")}
          end
        else
          {:noreply, put_flash(socket, :error, "Rate must be positive")}
        end

      :error ->
        {:noreply, put_flash(socket, :error, "Invalid rate")}
    end
  end

  def handle_event("add_currency", %{"currency" => params}, socket) do
    case Accounts.create_currency(socket.assigns.org_id, params) do
      {:ok, _} ->
        currencies = Accounts.list_currencies(socket.assigns.org_id)

        {:noreply,
         socket
         |> put_flash(:info, "Currency added")
         |> assign(:currencies, currencies)
         |> assign(
           :new_currency_form,
           to_form(
             %{
               "code" => "",
               "name" => "",
               "symbol" => "",
               "symbol_position" => "prefix",
               "exchange_rate" => "1.0"
             },
             as: "currency"
           )
         )}

      {:error, _changeset} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Could not add currency. Check code is unique and 3 characters."
         )}
    end
  end

  def handle_event("confirm_delete", %{"id" => id}, socket) do
    currency = Accounts.get_currency!(id, socket.assigns.org_id)
    {:noreply, assign(socket, :deleting_currency, currency)}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :deleting_currency, nil)}
  end

  def handle_event("delete_currency", _params, socket) do
    unless socket.assigns.is_admin do
      {:noreply,
       socket
       |> put_flash(:error, "Not authorized")
       |> assign(:deleting_currency, nil)}
    else
      currency = socket.assigns.deleting_currency

      case Accounts.delete_currency(currency) do
        {:ok, _} ->
          currencies = Accounts.list_currencies(socket.assigns.org_id)

          {:noreply,
           socket
           |> put_flash(:info, "Currency deleted")
           |> assign(:currencies, currencies)
           |> assign(:deleting_currency, nil)}

        {:error, :is_main_currency} ->
          {:noreply,
           socket
           |> put_flash(:error, "Cannot delete main currency")
           |> assign(:deleting_currency, nil)}

        {:error, _} ->
          {:noreply,
           socket
           |> put_flash(:error, "Could not delete currency")
           |> assign(:deleting_currency, nil)}
      end
    end
  end
end
