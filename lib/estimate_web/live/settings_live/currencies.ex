defmodule EstimateWeb.SettingsLive.Currencies do
  use EstimateWeb, :live_view

  alias Estimate.Organizations.Currencies
  import EstimateWeb.LiveHelpers

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto space-y-6">
      <div class="mb-8">
        <h1 class="text-2xl font-bold text-base-content">Currencies</h1>
        <p class="mt-1 text-base-content/60">
          Manage currencies and exchange rates<%= if @is_admin do %>
            . Click any row to set as main
          <% end %>
        </p>
      </div>

      <%!-- Refresh Rates Bar --%>
      <div
        :if={@is_admin}
        class="flex items-center justify-between px-4 py-3 bg-base-100 border border-base-300 rounded-xl"
      >
        <p class="text-sm text-base-content/60">
          Rates last fetched {time_ago(@rates_fetched_at)}
        </p>
        <button
          phx-click="refresh_rates"
          disabled={@refreshing_rates}
          phx-disable-with="Fetching..."
          class="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium bg-neutral text-neutral-content rounded-lg hover:bg-neutral/90 transition-colors disabled:opacity-50"
        >
          <.icon
            name="hero-arrow-path"
            class={"w-4 h-4 #{if @refreshing_rates, do: "motion-safe:animate-spin"}"}
          /> Refresh Rates
        </button>
      </div>

      <%!-- Currency List Card --%>
      <div class="bg-base-100 border border-base-300 rounded-xl overflow-hidden">
        <div>
          <%!-- Table Header --%>
          <div class="px-6 py-3 bg-base-100 grid grid-cols-12 gap-6 text-xs font-medium text-base-content/60 uppercase tracking-wider">
            <div class="col-span-2">Code</div>
            <div class="col-span-3">Name</div>
            <div class="col-span-1">Symbol</div>
            <div class="col-span-2">Position</div>
            <div class="col-span-2">Rate to {@main_currency.code}</div>
            <div class="col-span-2"></div>
          </div>

          <%!-- Currency Rows --%>
          <%= for currency <- @currencies do %>
            <div class={"px-6 py-4 grid grid-cols-12 gap-6 items-center border-t border-base-content/10 #{unless currency.is_main, do: "hover:bg-base-200 group", else: "bg-base-content/5"}"}>
              <div class="col-span-2 flex items-center gap-2">
                <input
                  type="text"
                  value={currency.code}
                  maxlength="3"
                  phx-blur="update_field"
                  phx-value-id={currency.id}
                  phx-value-field="code"
                  disabled={!@is_admin}
                  class={"w-14 px-2 py-1 border border-transparent hover:border-base-300 rounded text-sm font-mono font-medium uppercase bg-transparent #{if @is_admin, do: "text-base-content", else: "text-base-content/60 cursor-not-allowed"}"}
                />
                <%= if currency.is_main do %>
                  <span class="px-1.5 py-0.5 text-xs bg-neutral text-neutral-content rounded">
                    Main
                  </span>
                <% else %>
                  <button
                    :if={@is_admin}
                    phx-click="set_main"
                    phx-value-id={currency.id}
                    class="px-1.5 py-0.5 text-xs border border-base-content/20 text-base-content/60 rounded opacity-0 group-hover:opacity-100 transition-opacity hover:bg-base-300 whitespace-nowrap"
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
                  disabled={!@is_admin}
                  class={"w-full px-2 py-1 border border-transparent hover:border-base-300 rounded text-sm bg-transparent #{if @is_admin, do: "text-base-content/70", else: "text-base-content/60 cursor-not-allowed"}"}
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
                  disabled={!@is_admin}
                  class={"w-full px-2 py-1 border border-transparent hover:border-base-300 rounded text-sm bg-transparent #{if @is_admin, do: "text-base-content/70", else: "text-base-content/60 cursor-not-allowed"}"}
                />
              </div>
              <div class="col-span-2">
                <button
                  phx-click="toggle_position"
                  phx-value-id={currency.id}
                  disabled={!@is_admin}
                  class={"flex items-center gap-1.5 px-2.5 py-1.5 text-xs border border-base-300 rounded-md transition-colors #{if @is_admin, do: "hover:border-base-content/20 hover:bg-base-200", else: "cursor-not-allowed opacity-60"}"}
                  title="Toggle symbol position"
                >
                  <span class={"font-mono #{if currency.symbol_position == "prefix", do: "text-base-content font-medium", else: "text-base-content/40"}"}>
                    {currency.symbol}99
                  </span>
                  <span class="text-base-content/30">|</span>
                  <span class={"font-mono #{if currency.symbol_position == "suffix", do: "text-base-content font-medium", else: "text-base-content/40"}"}>
                    99{currency.symbol}
                  </span>
                </button>
              </div>
              <div class="col-span-2">
                <%= if currency.is_main do %>
                  <span class="w-24 px-2 py-1 text-sm font-mono text-base-content/60">1.0</span>
                <% else %>
                  <input
                    type="number"
                    step="0.0001"
                    min="0.0001"
                    value={currency.exchange_rate}
                    phx-blur="update_rate"
                    phx-value-id={currency.id}
                    phx-click="stop_propagation"
                    disabled={!@is_admin}
                    class={"w-24 px-2 py-1 border border-base-300 rounded text-sm font-mono #{unless @is_admin, do: "cursor-not-allowed bg-base-200 text-base-content/60"}"}
                  />
                <% end %>
              </div>
              <div class="col-span-2 text-right">
                <%= if @is_admin && !currency.is_main do %>
                  <button
                    phx-click="confirm_delete"
                    phx-value-id={currency.id}
                    class="text-base-content/40 hover:text-error transition-colors focus:outline-none"
                  >
                    <.icon name="hero-trash" class="w-4 h-4" />
                  </button>
                <% end %>
              </div>
            </div>
          <% end %>

          <%!-- Add Currency Row --%>
          <.form
            :if={@is_admin}
            for={@new_currency_form}
            phx-submit="add_currency"
            class="px-6 py-4 grid grid-cols-12 gap-6 items-center border-t border-base-content/10 bg-base-100"
          >
            <div class="col-span-2">
              <input
                type="text"
                name={@new_currency_form[:code].name}
                value={@new_currency_form[:code].value}
                placeholder="USD"
                maxlength="3"
                class="w-full px-2.5 py-1.5 border border-base-content/20 rounded-md text-sm font-mono uppercase"
              />
            </div>
            <div class="col-span-3">
              <input
                type="text"
                name={@new_currency_form[:name].name}
                value={@new_currency_form[:name].value}
                placeholder="US Dollar"
                class="w-full px-2.5 py-1.5 border border-base-content/20 rounded-md text-sm"
              />
            </div>
            <div class="col-span-1">
              <input
                type="text"
                name={@new_currency_form[:symbol].name}
                value={@new_currency_form[:symbol].value}
                placeholder="$"
                maxlength="5"
                class="w-full px-2.5 py-1.5 border border-base-content/20 rounded-md text-sm"
              />
            </div>
            <div class="col-span-2">
              <select
                name={@new_currency_form[:symbol_position].name}
                class="w-full px-2.5 py-1.5 border border-base-content/20 rounded-md text-sm"
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
                class="w-24 px-2 py-1 border border-base-content/20 rounded text-sm font-mono"
              />
            </div>
            <div class="col-span-2 text-right">
              <button
                type="submit"
                class="px-3 py-1 bg-neutral text-neutral-content text-sm rounded hover:bg-neutral/90 transition-colors"
              >
                Add
              </button>
            </div>
          </.form>
        </div>
      </div>

      <p class="text-xs text-base-content/40 px-1">
        Exchange rates from
        <a
          href="https://www.frankfurter.dev"
          target="_blank"
          rel="noopener"
          class="underline hover:text-base-content/60"
        >
          Frankfurter
        </a>
        (European Central Bank reference rates). Rates are indicative and may not reflect real-time market prices.
      </p>

      <.confirm_modal
        :if={@deleting_currency}
        id="delete-currency-modal"
        title="Delete Currency"
        item_name={@deleting_currency.code}
        confirm_event="delete_currency"
        cancel_event="cancel_delete"
      />
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    currencies = Currencies.list_currencies(socket.assigns.org_id)
    main_currency = Enum.find(currencies, & &1.is_main)

    {:ok,
     socket
     |> assign(:page_title, "Currencies")
     |> assign(:active_tab, :settings)
     |> assign(:settings_page, :currencies)
     |> assign(:currencies, currencies)
     |> assign(:main_currency, main_currency)
     |> assign(:is_admin, admin?(socket.assigns.current_membership))
     |> assign(:rates_fetched_at, socket.assigns.current_organization.rates_fetched_at)
     |> assign(:refreshing_rates, false)
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
    require_admin(socket, fn ->
      currency = Currencies.get_currency!(id, socket.assigns.org_id)

      case Currencies.set_main_currency(currency) do
        {:ok, _} ->
          {flash_suffix, rates_fetched_at} =
            case Currencies.fetch_and_apply_rates(socket.assigns.org_id) do
              {:ok, %{fetched_at: ts}} -> {" · rates refreshed", ts}
              _ -> {"", socket.assigns.rates_fetched_at}
            end

          currencies = Currencies.list_currencies(socket.assigns.org_id)
          main = Enum.find(currencies, & &1.is_main)

          {:noreply,
           socket
           |> put_flash(:info, "#{currency.code} is now main#{flash_suffix}")
           |> assign(:currencies, currencies)
           |> assign(:main_currency, main)
           |> assign(:rates_fetched_at, rates_fetched_at)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not set main currency")}
      end
    end)
  end

  def handle_event("refresh_rates", _params, socket) do
    require_admin(socket, fn ->
      case Currencies.fetch_and_apply_rates(socket.assigns.org_id) do
        {:ok, %{fetched_at: fetched_at, updated_count: count}} ->
          currencies = Currencies.list_currencies(socket.assigns.org_id)

          {:noreply,
           socket
           |> put_flash(:info, "#{count} rate(s) updated")
           |> assign(:currencies, currencies)
           |> assign(:rates_fetched_at, fetched_at)}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Could not fetch rates: #{reason}")}
      end
    end)
  end

  def handle_event("stop_propagation", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("update_field", %{"id" => id, "field" => field, "value" => value}, socket) do
    require_admin(socket, fn ->
      currency = Currencies.get_currency!(id, socket.assigns.org_id)
      attrs = %{field => value}

      case Currencies.update_currency(currency, attrs) do
        {:ok, _} ->
          currencies = Currencies.list_currencies(socket.assigns.org_id)
          {:noreply, assign(socket, :currencies, currencies)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not update #{field}")}
      end
    end)
  end

  def handle_event("toggle_position", %{"id" => id}, socket) do
    require_admin(socket, fn ->
      currency = Currencies.get_currency!(id, socket.assigns.org_id)
      new_position = if currency.symbol_position == "prefix", do: "suffix", else: "prefix"

      case Currencies.update_currency(currency, %{symbol_position: new_position}) do
        {:ok, _} ->
          currencies = Currencies.list_currencies(socket.assigns.org_id)
          {:noreply, assign(socket, :currencies, currencies)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not update symbol position")}
      end
    end)
  end

  def handle_event("update_rate", %{"id" => id, "value" => rate_str}, socket) do
    require_admin(socket, fn ->
      currency = Currencies.get_currency!(id, socket.assigns.org_id)

      case Decimal.parse(rate_str) do
        {rate, _} ->
          if Decimal.gt?(rate, 0) do
            case Currencies.update_currency(currency, %{exchange_rate: rate}) do
              {:ok, _} ->
                currencies = Currencies.list_currencies(socket.assigns.org_id)
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
    end)
  end

  def handle_event("add_currency", %{"currency" => params}, socket) do
    require_admin(socket, fn ->
      case Currencies.create_currency(socket.assigns.org_id, params) do
        {:ok, _} ->
          currencies = Currencies.list_currencies(socket.assigns.org_id)

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
    end)
  end

  def handle_event("confirm_delete", %{"id" => id}, socket) do
    currency = Currencies.get_currency!(id, socket.assigns.org_id)
    {:noreply, assign(socket, :deleting_currency, currency)}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :deleting_currency, nil)}
  end

  def handle_event("delete_currency", _params, socket) do
    require_admin(socket, fn ->
      currency = socket.assigns.deleting_currency

      case Currencies.delete_currency(currency) do
        {:ok, _} ->
          currencies = Currencies.list_currencies(socket.assigns.org_id)

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
    end)
  end
end
