defmodule EstimateWeb.RolesLive.Index do
  use EstimateWeb, :live_view

  alias Estimate.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto space-y-6">
      <%!-- Hourly Rates Table --%>
      <div class="bg-white border border-gray-200 rounded-xl overflow-hidden">
        <div class="p-6">
          <h2 class="text-xl font-semibold text-gray-900">Roles</h2>
          <p class="mt-1 text-sm text-gray-500">
            Define organization-wide roles. These are available when creating estimations.
          </p>
          <p class="mt-1 text-xs text-gray-400">
            Currency columns are based on your <.link
              navigate={~p"/org/#{@org_id}/settings/currencies"}
              class="text-violet-500 hover:text-violet-700 underline"
            >
              currency settings</.link>.
          </p>
        </div>

        <div class="border-t border-gray-200 overflow-x-auto">
          <table class="w-full">
            <thead>
              <tr class="bg-gray-50 text-[11px] font-medium text-gray-500 uppercase tracking-wider">
                <th class="px-6 py-3 whitespace-nowrap text-left">Role</th>
                <%= for currency <- @currencies do %>
                  <th class="py-3 whitespace-nowrap text-center w-24">
                    {currency.code}
                    <span class="text-gray-400 font-normal">({currency.symbol})</span>
                  </th>
                <% end %>
                <th class="py-3 whitespace-nowrap text-center w-20">PM %</th>
                <th class="py-3 whitespace-nowrap text-center w-20">QA %</th>
                <th class="py-3 whitespace-nowrap text-center w-20">Risk %</th>
                <th class="px-4 py-3 w-20"></th>
              </tr>
            </thead>
            <tbody class="divide-y divide-gray-100">
              <%= for template <- @role_templates do %>
                <tr class="group hover:bg-gray-50/50 transition-colors">
                  <td class="px-6 py-4">
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
                          class="w-36 px-2 py-1 border border-gray-300 rounded text-sm focus:outline-none focus:ring-2 focus:ring-gray-900"
                          autofocus
                        />
                        <input
                          type="text"
                          name="abbreviation"
                          value={template.abbreviation}
                          maxlength="5"
                          class="w-14 px-2 py-1 border border-gray-300 rounded text-sm font-mono uppercase focus:outline-none focus:ring-2 focus:ring-gray-900"
                        />
                        <button
                          type="submit"
                          class="px-2 py-1 bg-gray-900 text-white text-xs rounded hover:bg-gray-800"
                        >
                          Save
                        </button>
                        <button
                          type="button"
                          phx-click="cancel_edit"
                          class="text-gray-500 text-xs hover:text-gray-700"
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
                          <p class="text-sm font-medium text-gray-900 truncate">{template.name}</p>
                          <p class="text-xs text-gray-400 font-mono">{template.abbreviation}</p>
                        </div>
                      </div>
                    <% end %>
                  </td>
                  <%= for currency <- @currencies do %>
                    <% rate = Enum.find(template.rates, fn r -> r.currency_id == currency.id end) %>
                    <td class="py-4 text-center w-24">
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
                        class="w-16 px-2 py-1.5 border border-gray-200 rounded-md text-sm font-mono text-center focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent hover:border-gray-300"
                      />
                    </td>
                  <% end %>
                  <td class="py-4 text-center w-20">
                    <input
                      type="number"
                      step="1"
                      min="0"
                      max="100"
                      value={format_percent(template.pm_overhead)}
                      phx-blur="update_overhead"
                      phx-value-template-id={template.id}
                      phx-value-field="pm_overhead"
                      class="w-14 px-2 py-1.5 border border-gray-200 rounded-md text-sm font-mono text-center focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent hover:border-gray-300"
                    />
                  </td>
                  <td class="py-4 text-center w-20">
                    <input
                      type="number"
                      step="1"
                      min="0"
                      max="100"
                      value={format_percent(template.qa_overhead)}
                      phx-blur="update_overhead"
                      phx-value-template-id={template.id}
                      phx-value-field="qa_overhead"
                      class="w-14 px-2 py-1.5 border border-gray-200 rounded-md text-sm font-mono text-center focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent hover:border-gray-300"
                    />
                  </td>
                  <td class="py-4 text-center w-20">
                    <input
                      type="number"
                      step="1"
                      min="0"
                      max="100"
                      value={format_percent(template.risk_buffer)}
                      phx-blur="update_overhead"
                      phx-value-template-id={template.id}
                      phx-value-field="risk_buffer"
                      class="w-14 px-2 py-1.5 border border-gray-200 rounded-md text-sm font-mono text-center focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent hover:border-gray-300"
                    />
                  </td>
                  <td class="px-4 py-4">
                    <div class="flex items-center justify-end gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                      <button
                        phx-click="edit_template"
                        phx-value-id={template.id}
                        class="p-1.5 text-gray-400 hover:text-gray-600 hover:bg-gray-100 rounded transition-colors focus:outline-none"
                        title="Edit name"
                      >
                        <.icon name="hero-pencil" class="w-4 h-4" />
                      </button>
                      <button
                        :if={@is_admin}
                        phx-click="confirm_delete"
                        phx-value-id={template.id}
                        class="p-1.5 text-gray-400 hover:text-red-600 hover:bg-red-50 rounded transition-colors focus:outline-none"
                        title="Delete"
                      >
                        <.icon name="hero-trash" class="w-4 h-4" />
                      </button>
                    </div>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>

          <%= if Enum.empty?(@role_templates) do %>
            <div class="px-6 py-12 text-center">
              <.icon name="hero-user-group" class="w-12 h-12 text-gray-300 mx-auto" />
              <p class="mt-2 text-gray-500">No roles yet</p>
            </div>
          <% end %>
        </div>

        <.form
          for={@new_form}
          phx-submit="add_template"
          class="px-6 py-4 bg-gray-50 border-t border-gray-200"
        >
          <div class="flex items-center gap-3">
            <input
              type="text"
              name="name"
              value=""
              placeholder="Role name (e.g. Project Manager)"
              class="flex-1 px-3 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent"
            />
            <input
              type="text"
              name="abbreviation"
              value=""
              placeholder="PM"
              maxlength="5"
              class="w-16 px-3 py-2 border border-gray-300 rounded-lg text-sm font-mono uppercase text-center focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent"
            />
            <button
              type="submit"
              class="px-4 py-2 bg-gray-900 text-white text-sm rounded-lg hover:bg-gray-800 transition-colors font-medium"
            >
              Add Role
            </button>
          </div>
        </.form>
      </div>

      <%!-- Delete Confirmation Modal --%>
      <.modal
        :if={@deleting_template}
        id="delete-template-modal"
        show
        on_cancel={JS.push("cancel_delete")}
      >
        <div class="text-center">
          <div class="w-12 h-12 rounded-full bg-red-100 flex items-center justify-center mx-auto mb-4">
            <.icon name="hero-exclamation-triangle" class="w-6 h-6 text-red-600" />
          </div>
          <h3 class="text-lg font-semibold text-gray-900 mb-2">Delete Role</h3>
          <p class="text-sm text-gray-500 mb-6">
            Are you sure you want to delete <span class="font-medium text-gray-900"><%= @deleting_template.name %></span>?
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
              phx-click="delete_template"
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
    role_templates = Accounts.list_role_templates(socket.assigns.org_id)
    currencies = Accounts.list_currencies(socket.assigns.org_id)

    {:ok,
     socket
     |> assign(:page_title, "Roles")
     |> assign(:active_tab, :roles)
     |> assign(:role_templates, role_templates)
     |> assign(:currencies, currencies)
     |> assign(:editing_template_id, nil)
     |> assign(:is_admin, socket.assigns.current_membership.role in ["owner", "admin"])
     |> assign(:deleting_template, nil)
     |> assign(:new_form, to_form(%{}, as: "template"))
     |> assign(:edit_form, to_form(%{}, as: "template"))}
  end

  @impl true
  def handle_event("edit_template", %{"id" => id}, socket) do
    {:noreply, assign(socket, :editing_template_id, id)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, :editing_template_id, nil)}
  end

  def handle_event("add_template", %{"name" => name, "abbreviation" => abbr}, socket) do
    case Accounts.create_role_template(socket.assigns.org_id, %{
           "name" => name,
           "abbreviation" => abbr
         }) do
      {:ok, _template} ->
        role_templates = Accounts.list_role_templates(socket.assigns.org_id)

        {:noreply,
         socket
         |> put_flash(:info, "Role added")
         |> assign(:role_templates, role_templates)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not add role. Check name and abbreviation.")}
    end
  end

  def handle_event(
        "update_template",
        %{"template_id" => id, "name" => name, "abbreviation" => abbr},
        socket
      ) do
    template = Accounts.get_role_template!(id)

    case Accounts.update_role_template(template, %{"name" => name, "abbreviation" => abbr}) do
      {:ok, _template} ->
        role_templates = Accounts.list_role_templates(socket.assigns.org_id)

        {:noreply,
         socket
         |> put_flash(:info, "Role updated")
         |> assign(:role_templates, role_templates)
         |> assign(:editing_template_id, nil)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not update role.")}
    end
  end

  def handle_event("confirm_delete", %{"id" => id}, socket) do
    template = Accounts.get_role_template!(id)
    {:noreply, assign(socket, :deleting_template, template)}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :deleting_template, nil)}
  end

  def handle_event("delete_template", _params, socket) do
    unless socket.assigns.is_admin do
      {:noreply,
       socket
       |> put_flash(:error, "Not authorized")
       |> assign(:deleting_template, nil)}
    else
      template = socket.assigns.deleting_template

      case Accounts.delete_role_template(template) do
        {:ok, _} ->
          role_templates = Accounts.list_role_templates(socket.assigns.org_id)

          {:noreply,
           socket
           |> put_flash(:info, "Role deleted")
           |> assign(:role_templates, role_templates)
           |> assign(:deleting_template, nil)}

        {:error, _} ->
          {:noreply,
           socket
           |> put_flash(:error, "Could not delete role")
           |> assign(:deleting_template, nil)}
      end
    end
  end

  def handle_event("update_overhead", params, socket) do
    %{"template-id" => template_id, "field" => field, "value" => value} = params

    if field not in ~w(pm_overhead qa_overhead risk_buffer) do
      {:noreply, socket}
    else
      case Decimal.parse(value) do
        {decimal, _} ->
          if Decimal.compare(decimal, 0) != :lt and Decimal.compare(decimal, 100) != :gt do
            template = Accounts.get_role_template!(template_id)

            case Accounts.update_role_template(template, %{field => decimal}) do
              {:ok, _} ->
                role_templates = Accounts.list_role_templates(socket.assigns.org_id)
                {:noreply, assign(socket, :role_templates, role_templates)}

              {:error, _} ->
                {:noreply, put_flash(socket, :error, "Could not update #{field}")}
            end
          else
            {:noreply, put_flash(socket, :error, "Value must be between 0 and 100")}
          end

        :error ->
          {:noreply, socket}
      end
    end
  end

  def handle_event("update_rate", params, socket) do
    %{
      "template-id" => template_id,
      "currency-id" => currency_id,
      "rate-id" => rate_id,
      "value" => value
    } = params

    case Decimal.parse(value) do
      {rate, _} ->
        if Decimal.compare(rate, 0) != :lt do
          result =
            if rate_id == "" do
              Accounts.create_role_template_rate(template_id, currency_id, rate)
            else
              existing_rate = Accounts.get_role_template_rate!(rate_id)
              Accounts.update_role_template_rate(existing_rate, %{hourly_rate: rate})
            end

          case result do
            {:ok, _} ->
              role_templates = Accounts.list_role_templates(socket.assigns.org_id)
              {:noreply, assign(socket, :role_templates, role_templates)}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Could not update rate")}
          end
        else
          {:noreply, put_flash(socket, :error, "Rate must be positive")}
        end

      :error ->
        if value == "" and rate_id != "" do
          rate = Accounts.get_role_template_rate!(rate_id)
          Accounts.delete_role_template_rate(rate)
          role_templates = Accounts.list_role_templates(socket.assigns.org_id)
          {:noreply, assign(socket, :role_templates, role_templates)}
        else
          {:noreply, socket}
        end
    end
  end

  defp format_percent(decimal), do: decimal |> Decimal.round(0) |> Decimal.to_integer()
end
