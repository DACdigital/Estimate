defmodule EstimateWeb.RolesLive.Index do
  use EstimateWeb, :live_view

  alias Estimate.Accounts
  alias Estimate.Organizations.Currencies
  import EstimateWeb.EstimatorLive.Helpers, only: [format_percent: 1]

  @overhead_fields ~w(pm_overhead qa_overhead risk_buffer)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto space-y-6">
      <div class="mb-8">
        <h1 class="text-2xl font-bold text-base-content">Roles</h1>
        <p class="mt-1 text-base-content/60">
          Define organization-wide roles for estimations
        </p>
        <p class="mt-1 text-xs text-base-content/40">
          Currency columns are based on your <.link
            navigate={~p"/org/#{@org_id}/settings/currencies"}
            class="text-violet-500 hover:text-violet-700 underline"
          >
            currency settings</.link>.
        </p>
      </div>

      <% grid_cols = "#{if @is_admin, do: "2rem ", else: ""}minmax(12rem,1fr) #{Enum.map_join(@currencies, " ", fn _ -> "6rem" end)} 5rem 5rem 5rem" %>

      <%!-- Hourly Rates Grid --%>
      <div class="bg-base-100 border border-base-300 rounded-xl overflow-hidden">
        <div class="overflow-x-auto">
          <%!-- Header --%>
          <div
            class="grid items-center bg-base-100 text-[11px] font-medium text-base-content/60 uppercase tracking-wider"
            style={"grid-template-columns: #{grid_cols}"}
          >
            <div :if={@is_admin}></div>
            <div class="px-6 py-3 whitespace-nowrap text-left">Role</div>
            <%= for currency <- @currencies do %>
              <div class="py-3 whitespace-nowrap text-center">
                {currency.code}
                <span class="text-base-content/40 font-normal">({currency.symbol})</span>
              </div>
            <% end %>
            <div class="py-3 whitespace-nowrap text-center">PM %</div>
            <div class="py-3 whitespace-nowrap text-center">QA %</div>
            <div class="py-3 whitespace-nowrap text-center">Risk %</div>
          </div>

          <%!-- Sortable rows --%>
          <div
            id="roles-sortable"
            phx-hook={if @is_admin, do: "TemplateSortable"}
            data-sort-event="reorder_roles"
            class="divide-y divide-base-content/10"
          >
            <%= for template <- @role_templates do %>
              <div
                data-id={template.id}
                class="grid items-center group hover:bg-base-200/50 transition-colors"
                style={"grid-template-columns: #{grid_cols}"}
              >
                <div :if={@is_admin} class="drag-handle cursor-grab text-base-content/30 hover:text-base-content/60 flex justify-center">
                  <.icon name="hero-bars-3" class="w-4 h-4" />
                </div>
                <div class="px-6 py-4">
                  <%= if @editing_template_id == template.id do %>
                    <.form
                      for={@edit_form}
                      phx-submit="update_template"
                      class="flex items-center gap-2"
                    >
                      <input type="hidden" name="template_id" value={template.id} />
                      <input
                        type="text"
                        name="name"
                        value={template.name}
                        class="w-36 px-2 py-1 border border-base-content/20 rounded text-sm"
                        autofocus
                      />
                      <input
                        type="text"
                        name="abbreviation"
                        value={template.abbreviation}
                        maxlength="5"
                        class="w-14 px-2 py-1 border border-base-content/20 rounded text-sm font-mono uppercase"
                      />
                      <button
                        type="submit"
                        class="px-2 py-1 bg-neutral text-neutral-content text-xs rounded hover:bg-neutral/90"
                      >
                        Save
                      </button>
                      <button
                        type="button"
                        phx-click="cancel_edit"
                        class="text-base-content/60 text-xs hover:text-base-content/80"
                      >
                        Cancel
                      </button>
                    </.form>
                  <% else %>
                    <div class="flex items-center gap-3">
                      <span class="w-9 h-9 rounded-lg bg-gradient-to-br from-indigo-500 to-purple-600 flex items-center justify-center text-white font-semibold text-xs flex-shrink-0">
                        {template.abbreviation}
                      </span>
                      <div class="min-w-0">
                        <p class="text-sm font-medium text-base-content truncate">
                          {template.name}
                        </p>
                        <p class="text-xs text-base-content/40 font-mono">
                          {template.abbreviation}
                        </p>
                      </div>
                      <div class="flex items-center gap-2 opacity-0 group-hover:opacity-100 transition-opacity ml-auto">
                        <button
                          :if={@is_admin}
                          phx-click="edit_template"
                          phx-value-id={template.id}
                          class="text-base-content/40 hover:text-base-content/70 transition-colors"
                          title="Edit name"
                        >
                          <.icon name="hero-pencil" class="w-4 h-4" />
                        </button>
                        <button
                          :if={@is_admin}
                          phx-click="confirm_delete"
                          phx-value-id={template.id}
                          class="text-base-content/40 hover:text-error transition-colors"
                          title="Delete"
                        >
                          <.icon name="hero-trash" class="w-4 h-4" />
                        </button>
                      </div>
                    </div>
                  <% end %>
                </div>
                <%= for currency <- @currencies do %>
                  <% rate = Enum.find(template.rates, fn r -> r.currency_id == currency.id end) %>
                  <div class="py-4 text-center">
                    <input
                      type="number"
                      step="0.01"
                      min="0"
                      value={if rate, do: rate.hourly_rate, else: ""}
                      placeholder="0"
                      phx-blur="update_rate"
                      phx-value-template-id={template.id}
                      phx-value-currency-id={currency.id}
                      phx-value-rate-id={if rate, do: rate.id, else: ""}
                      disabled={!@is_admin}
                      class={"w-16 px-2 py-1.5 border border-base-content/15 rounded-md text-sm font-mono text-center #{if @is_admin, do: "hover:border-base-content/20", else: "cursor-not-allowed bg-base-200 text-base-content/60"}"}
                    />
                  </div>
                <% end %>
                <div class="py-4 text-center">
                  <input
                    type="number"
                    step="1"
                    min="0"
                    max="100"
                    value={format_percent(template.pm_overhead)}
                    phx-blur="update_overhead"
                    phx-value-template-id={template.id}
                    phx-value-field="pm_overhead"
                    disabled={!@is_admin}
                    class={"w-14 px-2 py-1.5 border border-base-content/15 rounded-md text-sm font-mono text-center #{if @is_admin, do: "hover:border-base-content/20", else: "cursor-not-allowed bg-base-200 text-base-content/60"}"}
                  />
                </div>
                <div class="py-4 text-center">
                  <input
                    type="number"
                    step="1"
                    min="0"
                    max="100"
                    value={format_percent(template.qa_overhead)}
                    phx-blur="update_overhead"
                    phx-value-template-id={template.id}
                    phx-value-field="qa_overhead"
                    disabled={!@is_admin}
                    class={"w-14 px-2 py-1.5 border border-base-content/15 rounded-md text-sm font-mono text-center #{if @is_admin, do: "hover:border-base-content/20", else: "cursor-not-allowed bg-base-200 text-base-content/60"}"}
                  />
                </div>
                <div class="py-4 text-center">
                  <input
                    type="number"
                    step="1"
                    min="0"
                    max="100"
                    value={format_percent(template.risk_buffer)}
                    phx-blur="update_overhead"
                    phx-value-template-id={template.id}
                    phx-value-field="risk_buffer"
                    disabled={!@is_admin}
                    class={"w-14 px-2 py-1.5 border border-base-content/15 rounded-md text-sm font-mono text-center #{if @is_admin, do: "hover:border-base-content/20", else: "cursor-not-allowed bg-base-200 text-base-content/60"}"}
                  />
                </div>
              </div>
            <% end %>
          </div>

          <%= if Enum.empty?(@role_templates) do %>
            <div class="px-6 py-12 text-center">
              <.icon name="hero-user-group" class="w-12 h-12 text-base-content/30 mx-auto" />
              <p class="mt-2 text-base-content/60">No roles yet</p>
            </div>
          <% end %>
        </div>

        <.form
          :if={@is_admin}
          for={@new_form}
          phx-submit="add_template"
          class="px-6 py-4 bg-base-100 border-t border-base-300"
        >
          <div class="flex items-center gap-3">
            <input
              type="text"
              name="name"
              value=""
              placeholder="Role name (e.g. Project Manager)"
              class="flex-1 px-3 py-2 border border-base-content/20 rounded-lg text-sm"
            />
            <input
              type="text"
              name="abbreviation"
              value=""
              placeholder="PM"
              maxlength="5"
              class="w-16 px-3 py-2 border border-base-content/20 rounded-lg text-sm font-mono uppercase text-center"
            />
            <button
              type="submit"
              class="px-4 py-2 bg-neutral text-neutral-content text-sm rounded-lg hover:bg-neutral/90 transition-colors font-medium"
            >
              Add Role
            </button>
          </div>
        </.form>
      </div>

      <.confirm_modal
        :if={@deleting_template}
        id="delete-template-modal"
        title="Delete Role"
        item_name={@deleting_template.name}
        confirm_event="delete_template"
        cancel_event="cancel_delete"
      />
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    role_templates = Accounts.list_role_templates(socket.assigns.org_id)
    currencies = Currencies.list_currencies(socket.assigns.org_id)

    {:ok,
     socket
     |> assign(:page_title, "Roles")
     |> assign(:active_tab, :roles)
     |> assign(:role_templates, role_templates)
     |> assign(:currencies, currencies)
     |> assign(:editing_template_id, nil)
     |> assign(:is_admin, admin?(socket.assigns.current_membership))
     |> assign(:deleting_template, nil)
     |> assign(:new_form, to_form(%{}, as: "template"))
     |> assign(:edit_form, to_form(%{}, as: "template"))}
  end

  @impl true
  def handle_event("reorder_roles", %{"ids" => ids}, socket) do
    require_admin(socket, fn ->
      Accounts.reorder_role_templates(socket.assigns.org_id, ids)
      {:noreply, reload_templates(socket)}
    end)
  end

  def handle_event("edit_template", %{"id" => id}, socket) do
    {:noreply, assign(socket, :editing_template_id, id)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, :editing_template_id, nil)}
  end

  def handle_event("add_template", %{"name" => name, "abbreviation" => abbr}, socket) do
    require_admin(socket, fn ->
      case Accounts.create_role_template(socket.assigns.org_id, %{
             "name" => name,
             "abbreviation" => abbr
           }) do
        {:ok, _template} ->
          {:noreply,
           socket
           |> put_flash(:info, "Role added")
           |> reload_templates()}

        {:error, _changeset} ->
          {:noreply,
           put_flash(socket, :error, "Could not add role. Check name and abbreviation.")}
      end
    end)
  end

  def handle_event(
        "update_template",
        %{"template_id" => id, "name" => name, "abbreviation" => abbr},
        socket
      ) do
    require_admin(socket, fn ->
      template = Accounts.get_role_template!(id, socket.assigns.org_id)

      case Accounts.update_role_template(template, %{"name" => name, "abbreviation" => abbr}) do
        {:ok, _template} ->
          {:noreply,
           socket
           |> put_flash(:info, "Role updated")
           |> reload_templates()
           |> assign(:editing_template_id, nil)}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Could not update role.")}
      end
    end)
  end

  def handle_event("confirm_delete", %{"id" => id}, socket) do
    require_admin(socket, fn ->
      template = Accounts.get_role_template!(id, socket.assigns.org_id)
      {:noreply, assign(socket, :deleting_template, template)}
    end)
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :deleting_template, nil)}
  end

  def handle_event("delete_template", _params, socket) do
    require_admin(socket, fn ->
      template = socket.assigns.deleting_template

      case Accounts.delete_role_template(template) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "Role deleted")
           |> reload_templates()
           |> assign(:deleting_template, nil)}

        {:error, _} ->
          {:noreply,
           socket
           |> put_flash(:error, "Could not delete role")
           |> assign(:deleting_template, nil)}
      end
    end)
  end

  def handle_event("update_overhead", params, socket) do
    require_admin(socket, fn ->
      %{"template-id" => template_id, "field" => field, "value" => value} = params

      if field not in @overhead_fields do
        {:noreply, socket}
      else
        with {:ok, decimal} <- parse_percent(value),
             template <- Accounts.get_role_template!(template_id, socket.assigns.org_id),
             {:ok, _} <- Accounts.update_role_template(template, %{field => decimal}) do
          {:noreply, reload_templates(socket)}
        else
          {:error, msg} when is_binary(msg) -> {:noreply, put_flash(socket, :error, msg)}
          {:error, _} -> {:noreply, put_flash(socket, :error, "Could not update #{field}")}
        end
      end
    end)
  end

  def handle_event("update_rate", params, socket) do
    require_admin(socket, fn ->
      %{
        "template-id" => template_id,
        "currency-id" => currency_id,
        "rate-id" => rate_id,
        "value" => value
      } = params

      case parse_rate(value) do
        {:ok, rate} ->
          result =
            if rate_id == "" do
              Accounts.create_role_template_rate(template_id, currency_id, rate)
            else
              existing_rate = Accounts.get_role_template_rate!(rate_id, socket.assigns.org_id)
              Accounts.update_role_template_rate(existing_rate, %{hourly_rate: rate})
            end

          case result do
            {:ok, _} -> {:noreply, reload_templates(socket)}
            {:error, _} -> {:noreply, put_flash(socket, :error, "Could not update rate")}
          end

        {:error, :empty} when rate_id != "" ->
          rate = Accounts.get_role_template_rate!(rate_id, socket.assigns.org_id)
          Accounts.delete_role_template_rate(rate)
          {:noreply, reload_templates(socket)}

        {:error, :not_positive} ->
          {:noreply, put_flash(socket, :error, "Rate must be positive")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Invalid rate")}
      end
    end)
  end

  defp reload_templates(socket) do
    assign(socket, :role_templates, Accounts.list_role_templates(socket.assigns.org_id))
  end

  defp parse_percent(value) do
    case Decimal.parse(value) do
      {d, _} ->
        if Decimal.compare(d, 0) != :lt and Decimal.compare(d, 100) != :gt,
          do: {:ok, d},
          else: {:error, "Value must be between 0 and 100"}

      :error ->
        {:error, "Invalid number"}
    end
  end

  defp parse_rate(value) do
    case Decimal.parse(value) do
      {r, _} ->
        if Decimal.compare(r, 0) != :lt,
          do: {:ok, r},
          else: {:error, :not_positive}

      :error ->
        if value == "", do: {:error, :empty}, else: {:error, :not_a_number}
    end
  end
end
