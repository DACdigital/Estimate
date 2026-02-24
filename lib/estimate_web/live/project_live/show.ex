defmodule EstimateWeb.ProjectLive.Show do
  use EstimateWeb, :live_view

  alias Estimate.Portfolio
  alias Estimate.Portfolio.Project
  alias Estimate.EstimationEngine
  alias Estimate.EstimationEngine.Calculator
  alias Estimate.Accounts
  alias Estimate.Organizations.Currencies
  import EstimateWeb.Components.JsonImportComponent
  import EstimateWeb.JsonImportHelpers
  import EstimateWeb.EstimatorLive.Helpers,
    only: [priority_label: 1, priority_class: 1, format_rate: 2, format_cost: 2]

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto">
      <%!-- Breadcrumb --%>
      <nav class="flex items-center space-x-2 text-sm text-gray-500 mb-6">
        <.link
          :if={@project.customer}
          navigate={~p"/org/#{@org_id}/customers/#{@project.customer.id}"}
          class="hover:text-gray-900"
        >
          {@project.customer.name}
        </.link>
        <span class="text-gray-300">›</span>
        <span class="text-gray-900 font-medium">{@project.name}</span>
        <span :if={@current_estimation && @current_estimation.currency} class="text-gray-300 ml-2">
          •
        </span>
        <span :if={@current_estimation && @current_estimation.currency} class="text-gray-400">
          {@current_estimation.currency.code}
        </span>
      </nav>

      <%!-- Header --%>
      <div class="flex items-start justify-between mb-6">
        <div class="flex items-center gap-4">
          <.avatar name={@project.name} seed={@project.id} size={:xl} />
          <div>
            <div class="flex items-center gap-3">
              <h1 class="text-2xl font-bold text-gray-900">{@project.name}</h1>
              <span class={"text-xs px-2 py-0.5 rounded-full #{project_status_class(@project.status)}"}>
                {@project.status}
              </span>
            </div>
            <div class="flex items-center gap-3 mt-1">
              <span :if={Project.composite_key(@project)} class="text-sm font-mono text-gray-400">
                {Project.composite_key(@project)}
              </span>
            </div>
          </div>
        </div>
      </div>

      <%!-- Tabs --%>
      <div class="border-b border-gray-200 mb-6">
        <nav class="flex gap-6">
          <.link
            patch={~p"/org/#{@org_id}/projects/#{@project.id}"}
            class={"pb-3 px-1 text-sm font-medium border-b-2 transition-colors #{if @tab == :overview, do: "border-gray-900 text-gray-900", else: "border-transparent text-gray-500 hover:text-gray-700"}"}
          >
            Overview
          </.link>
          <.link
            patch={~p"/org/#{@org_id}/projects/#{@project.id}/collaborators"}
            class={"pb-3 px-1 text-sm font-medium border-b-2 transition-colors #{if @tab == :collaborators, do: "border-gray-900 text-gray-900", else: "border-transparent text-gray-500 hover:text-gray-700"}"}
          >
            Collaborators
          </.link>
          <.link
            patch={~p"/org/#{@org_id}/projects/#{@project.id}/estimations"}
            class={"pb-3 px-1 text-sm font-medium border-b-2 transition-colors #{if @tab == :estimations, do: "border-gray-900 text-gray-900", else: "border-transparent text-gray-500 hover:text-gray-700"}"}
          >
            Estimations
          </.link>
        </nav>
      </div>

      <%!-- Tab Content --%>
      <%= case @tab do %>
        <% :overview -> %>
          <.tab_overview {assigns} />
        <% :collaborators -> %>
          <.tab_collaborators {assigns} />
        <% :estimations -> %>
          <.tab_estimations {assigns} />
      <% end %>

      <%!-- New Estimation Modal --%>
      <.modal
        :if={@show_new_estimation_modal}
        id="new-estimation-modal"
        show
        on_cancel={JS.push("close_estimation_modal")}
      >
        <h2 class="text-xl font-semibold text-gray-900 mb-4">New Estimation</h2>

        <%!-- Source Selection --%>
        <div class="flex gap-2 mb-6">
          <button
            type="button"
            phx-click="set_estimation_source"
            phx-value-source="fresh"
            class={"flex-1 px-3 py-2.5 text-sm font-medium rounded-lg border-2 transition-colors #{if @estimation_source == "fresh", do: "border-gray-900 bg-gray-900 text-white", else: "border-gray-200 text-gray-600 hover:border-gray-300"}"}
          >
            <.icon name="hero-plus" class="w-4 h-4 inline-block mr-1.5 -mt-0.5" /> Start fresh
          </button>
          <button
            type="button"
            phx-click="set_estimation_source"
            phx-value-source="copy"
            disabled={Enum.empty?(@estimations)}
            class={"flex-1 px-3 py-2.5 text-sm font-medium rounded-lg border-2 transition-colors #{if @estimation_source == "copy", do: "border-gray-900 bg-gray-900 text-white", else: "border-gray-200 text-gray-600 hover:border-gray-300"} #{if Enum.empty?(@estimations), do: "opacity-50 cursor-not-allowed"}"}
          >
            <.icon name="hero-document-duplicate" class="w-4 h-4 inline-block mr-1.5 -mt-0.5" />
            Copy existing
          </button>
          <button
            type="button"
            phx-click="set_estimation_source"
            phx-value-source="template"
            disabled={Enum.empty?(@estimation_templates)}
            class={"flex-1 px-3 py-2.5 text-sm font-medium rounded-lg border-2 transition-colors #{if @estimation_source == "template", do: "border-gray-900 bg-gray-900 text-white", else: "border-gray-200 text-gray-600 hover:border-gray-300"} #{if Enum.empty?(@estimation_templates), do: "opacity-50 cursor-not-allowed"}"}
          >
            <.icon name="hero-rectangle-stack" class="w-4 h-4 inline-block mr-1.5 -mt-0.5" />
            From template
          </button>
          <button
            type="button"
            phx-click="set_estimation_source"
            phx-value-source="json"
            class={"flex-1 px-3 py-2.5 text-sm font-medium rounded-lg border-2 transition-colors #{if @estimation_source == "json", do: "border-gray-900 bg-gray-900 text-white", else: "border-gray-200 text-gray-600 hover:border-gray-300"}"}
          >
            <.icon name="hero-arrow-up-tray" class="w-4 h-4 inline-block mr-1.5 -mt-0.5" />
            Import JSON
          </button>
        </div>

        <.form
          for={@estimation_form}
          id="new-estimation-form"
          phx-submit="create_estimation"
          phx-change="validate_estimation"
        >
          <input type="hidden" name="source" value={@estimation_source} />

          <div class="space-y-5">
            <%!-- JSON Import --%>
            <div :if={@estimation_source == "json"}>
              <.json_import_panel
                json_input={@json_input}
                json_error={@json_error}
                json_parsed={@json_parsed}
              />
            </div>

            <%!-- Copy source selector --%>
            <div :if={@estimation_source == "copy"}>
              <label class="block text-xs font-medium text-gray-500 mb-1.5">Copy from</label>
              <select
                name="source_estimation_id"
                phx-change="validate_estimation"
                class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent text-sm"
              >
                <%= for est <- @estimations do %>
                  <option
                    value={est.id}
                    selected={to_string(est.id) == to_string(@source_estimation_id)}
                  >
                    {est.name}
                    <%= if est.is_current do %>
                      (current)
                    <% end %>
                  </option>
                <% end %>
              </select>
            </div>

            <div>
              <label class="block text-xs font-medium text-gray-500 mb-1.5">Estimation Name *</label>
              <input
                type="text"
                name={@estimation_form[:name].name}
                value={@estimation_form[:name].value}
                placeholder={
                  if @estimation_source == "copy", do: "Copy of ...", else: "Q1 2026 Estimate"
                }
                required
                class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent text-sm"
              />
            </div>

            <div>
              <label class="block text-xs font-medium text-gray-500 mb-1.5">Description</label>
              <textarea
                name={@estimation_form[:description].name}
                rows="2"
                placeholder="Optional description..."
                class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent text-sm resize-none"
              ><%= @estimation_form[:description].value %></textarea>
            </div>

            <div>
              <label class="block text-xs font-medium text-gray-500 mb-1.5">Currency</label>
              <select
                name="currency_id"
                class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent text-sm"
              >
                <%= for currency <- @currencies do %>
                  <option
                    value={currency.id}
                    selected={to_string(currency.id) == to_string(@modal_currency_id)}
                  >
                    {currency.code} - {currency.name}
                  </option>
                <% end %>
              </select>
            </div>

            <%!-- Roles section for fresh start and JSON import --%>
            <div :if={@estimation_source in ["fresh", "json"]}>
              <label class="block text-xs font-medium text-gray-500 mb-2">Roles</label>
              <div class="space-y-2 max-h-48 overflow-y-auto border border-gray-200 rounded-lg p-3">
                <%= for template <- @role_templates do %>
                  <% rate = Enum.find(template.rates, fn r -> r.currency_id == @modal_currency_id end) %>
                  <label class="flex items-center justify-between p-2 hover:bg-gray-50 rounded cursor-pointer">
                    <div class="flex items-center gap-3">
                      <input
                        type="checkbox"
                        name="template_ids[]"
                        value={template.id}
                        checked={template.id in @selected_template_ids}
                        class="w-4 h-4 text-gray-900 border-gray-300 rounded focus:ring-gray-900"
                      />
                      <span class="text-sm font-medium text-gray-900">{template.name}</span>
                      <span class="text-xs text-gray-400 font-mono">({template.abbreviation})</span>
                    </div>
                    <span class="text-sm text-gray-500">
                      {if rate, do: format_rate(rate.hourly_rate, @modal_currency), else: "-"}
                    </span>
                  </label>
                <% end %>
                <%= if Enum.empty?(@role_templates) do %>
                  <p class="text-sm text-gray-500 text-center py-4">
                    No roles defined.
                    <.link navigate={~p"/org/#{@org_id}/roles"} class="text-blue-600 hover:underline">
                      Add roles
                    </.link>
                    first.
                  </p>
                <% end %>
              </div>
            </div>

            <%!-- Template mode: template selector + roles --%>
            <div :if={@estimation_source == "template"}>
              <label class="block text-xs font-medium text-gray-500 mb-1.5">
                Estimation Template
              </label>
              <select
                name="estimation_template_id"
                class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent text-sm"
              >
                <%= for tmpl <- @estimation_templates do %>
                  <option
                    value={tmpl.id}
                    selected={to_string(tmpl.id) == to_string(@selected_estimation_template_id)}
                  >
                    {tmpl.name} ({length(tmpl.epics)} epics, {Enum.sum(
                      Enum.map(tmpl.epics, fn e -> length(e.tasks) end)
                    )} tasks)
                  </option>
                <% end %>
              </select>
            </div>

            <div :if={@estimation_source == "template"}>
              <label class="block text-xs font-medium text-gray-500 mb-2">Roles</label>
              <div class="space-y-2 max-h-48 overflow-y-auto border border-gray-200 rounded-lg p-3">
                <%= for template <- @role_templates do %>
                  <% rate = Enum.find(template.rates, fn r -> r.currency_id == @modal_currency_id end) %>
                  <label class="flex items-center justify-between p-2 hover:bg-gray-50 rounded cursor-pointer">
                    <div class="flex items-center gap-3">
                      <input
                        type="checkbox"
                        name="template_ids[]"
                        value={template.id}
                        checked={template.id in @selected_template_ids}
                        class="w-4 h-4 text-gray-900 border-gray-300 rounded focus:ring-gray-900"
                      />
                      <span class="text-sm font-medium text-gray-900">{template.name}</span>
                      <span class="text-xs text-gray-400 font-mono">({template.abbreviation})</span>
                    </div>
                    <span class="text-sm text-gray-500">
                      {if rate, do: format_rate(rate.hourly_rate, @modal_currency), else: "-"}
                    </span>
                  </label>
                <% end %>
              </div>
            </div>

            <div :if={@estimation_source == "template"} class="bg-gray-50 rounded-lg p-4">
              <div class="flex items-start gap-3">
                <.icon
                  name="hero-information-circle"
                  class="w-5 h-5 text-gray-400 flex-shrink-0 mt-0.5"
                />
                <div class="text-sm text-gray-600">
                  <p class="font-medium text-gray-700">What will be created:</p>
                  <ul class="mt-1 space-y-0.5 text-gray-500">
                    <li>• Epic & task structure from template</li>
                    <li>• Roles from selection above</li>
                    <li>• No hour estimates</li>
                  </ul>
                </div>
              </div>
            </div>

            <%!-- Info for copy mode --%>
            <div :if={@estimation_source == "copy"} class="bg-gray-50 rounded-lg p-4">
              <div class="flex items-start gap-3">
                <.icon
                  name="hero-information-circle"
                  class="w-5 h-5 text-gray-400 flex-shrink-0 mt-0.5"
                />
                <div class="text-sm text-gray-600">
                  <p class="font-medium text-gray-700">What will be copied:</p>
                  <ul class="mt-1 space-y-0.5 text-gray-500">
                    <li>• All epics and tasks</li>
                    <li>• All hour estimates</li>
                    <li>• Roles and rates</li>
                  </ul>
                </div>
              </div>
            </div>
          </div>

          <div class="mt-6 flex justify-end gap-3">
            <button
              type="button"
              phx-click="close_estimation_modal"
              class="px-4 py-2 text-sm text-gray-600 hover:text-gray-900 transition-colors"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={@estimation_source == "json" && !@json_parsed}
              phx-disable-with={
                if @estimation_source == "copy", do: "Copying...", else: "Creating..."
              }
              class={"px-4 py-2 bg-gray-900 text-white text-sm rounded-lg hover:bg-gray-800 transition-colors font-medium #{if @estimation_source == "json" && !@json_parsed, do: "opacity-50 cursor-not-allowed"}"}
            >
              {if @estimation_source == "copy", do: "Create Copy", else: "Create"}
            </button>
          </div>
        </.form>
      </.modal>

      <%!-- Delete Project Modal --%>
      <.modal
        :if={@deleting_project}
        id="delete-project-modal"
        show
        on_cancel={JS.push("cancel_delete_project")}
      >
        <div class="text-center">
          <div class="w-12 h-12 rounded-full bg-red-100 flex items-center justify-center mx-auto mb-4">
            <.icon name="hero-exclamation-triangle" class="w-6 h-6 text-red-600" />
          </div>
          <h3 class="text-lg font-semibold text-gray-900 mb-2">Delete Project</h3>
          <p class="text-sm text-gray-500 mb-6">
            Are you sure you want to delete <span class="font-medium text-gray-900"><%= @project.name %></span>?
            This will also delete all estimations. This action cannot be undone.
          </p>
          <div class="flex gap-3 justify-center">
            <button
              phx-click="cancel_delete_project"
              class="px-4 py-2 text-sm text-gray-600 hover:text-gray-900"
            >
              Cancel
            </button>
            <button
              phx-click="delete_project"
              class="px-4 py-2 bg-red-600 text-white text-sm rounded-lg hover:bg-red-700 font-medium"
            >
              Delete Project
            </button>
          </div>
        </div>
      </.modal>

      <%!-- Remove Collaborator Modal --%>
      <.modal
        :if={@removing_collaborator}
        id="remove-collaborator-modal"
        show
        on_cancel={JS.push("cancel_remove_collaborator")}
      >
        <div class="text-center">
          <div class="w-12 h-12 rounded-full bg-red-100 flex items-center justify-center mx-auto mb-4">
            <.icon name="hero-exclamation-triangle" class="w-6 h-6 text-red-600" />
          </div>
          <h3 class="text-lg font-semibold text-gray-900 mb-2">Remove Collaborator</h3>
          <p class="text-sm text-gray-500 mb-6">
            Are you sure you want to remove
            <span class="font-medium text-gray-900">
              {@removing_collaborator.user.name || @removing_collaborator.user.email}
            </span>
            from this project?
          </p>
          <div class="flex gap-3 justify-center">
            <button
              phx-click="cancel_remove_collaborator"
              class="px-4 py-2 text-sm text-gray-600 hover:text-gray-900 transition-colors"
            >
              Cancel
            </button>
            <button
              phx-click="remove_collaborator"
              class="px-4 py-2 bg-red-600 text-white text-sm rounded-lg hover:bg-red-700 transition-colors font-medium"
            >
              Remove
            </button>
          </div>
        </div>
      </.modal>
    </div>
    """
  end

  ## Tab Components

  defp tab_overview(assigns) do
    ~H"""
    <div class="space-y-6">
      <%!-- Estimation Dashboard --%>
      <%= if @current_estimation do %>
        <.estimation_dashboard
          estimation={@current_estimation}
          currency={@current_estimation.currency}
          dashboard_tab={@dashboard_tab}
        />
      <% else %>
        <div class="bg-white border border-gray-200 rounded-xl p-8 text-center">
          <.icon name="hero-calculator" class="w-12 h-12 text-gray-300 mx-auto" />
          <p class="mt-3 text-gray-500">No estimations yet</p>
          <.link
            :if={@can_edit_project}
            navigate={~p"/org/#{@org_id}/projects/#{@project.id}/estimations/new"}
            class="mt-4 inline-block px-4 py-2 bg-gray-900 text-white text-sm rounded-lg hover:bg-gray-800 transition-colors font-medium"
          >
            Create Estimation
          </.link>
        </div>
      <% end %>

      <%!-- Project Details Card --%>
      <.form for={@form} id="project-form" phx-submit="save" phx-change="validate">
        <div class="bg-white border border-gray-200 rounded-xl overflow-hidden">
          <div class="p-6 space-y-4">
            <h2 class="text-lg font-semibold text-gray-900">Project Details</h2>

            <%!-- Top row: Name, Key, Status --%>
            <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
              <div class="md:col-span-1">
                <label class="block text-xs font-medium text-gray-500 mb-1.5">Project Name *</label>
                <input
                  type="text"
                  name={@form[:name].name}
                  value={@form[:name].value}
                  placeholder="Website Redesign"
                  required
                  class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent text-sm"
                />
              </div>

              <div>
                <label class="block text-xs font-medium text-gray-500 mb-1.5">Project Key</label>
                <div class="flex items-center gap-1">
                  <span class="px-3 py-2 bg-gray-100 border border-gray-300 rounded-l-lg text-sm text-gray-500 font-mono">
                    {@customer_key || "---"}
                  </span>
                  <span class="text-gray-400">-</span>
                  <input
                    type="text"
                    name={@form[:key].name}
                    value={@form[:key].value}
                    placeholder="PROJ"
                    maxlength="10"
                    class="w-full px-3 py-2 border border-gray-300 rounded-r-lg focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent text-sm font-mono uppercase"
                  />
                </div>
              </div>

              <div>
                <label class="block text-xs font-medium text-gray-500 mb-1.5">Status</label>
                <select
                  name={@form[:status].name}
                  class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent text-sm"
                >
                  <option value="active" selected={@form[:status].value == "active"}>Active</option>
                  <option value="completed" selected={@form[:status].value == "completed"}>
                    Completed
                  </option>
                  <option value="archived" selected={@form[:status].value == "archived"}>
                    Archived
                  </option>
                </select>
              </div>
            </div>

            <%!-- Default Currency --%>
            <div>
              <label class="block text-xs font-medium text-gray-500 mb-1.5">Default Currency</label>
              <select
                name={@form[:currency_id].name}
                class="w-full max-w-md px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent text-sm"
              >
                <option value="">None</option>
                <%= for currency <- @currencies do %>
                  <option
                    value={currency.id}
                    selected={to_string(currency.id) == to_string(@form[:currency_id].value)}
                  >
                    {currency.code} - {currency.name}
                  </option>
                <% end %>
              </select>
              <p class="text-xs text-gray-400 mt-1">Used as default for new estimations</p>
            </div>

            <%!-- Short Description --%>
            <div>
              <label class="block text-xs font-medium text-gray-500 mb-1.5">Short Description</label>
              <input
                type="text"
                name={@form[:short_description].name}
                value={@form[:short_description].value}
                placeholder="One-liner about the project"
                class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent text-sm"
              />
            </div>

            <%!-- Detailed Description --%>
            <div>
              <label class="block text-xs font-medium text-gray-500 mb-1.5">
                Detailed Description
              </label>
              <textarea
                name={@form[:detailed_description].name}
                rows="4"
                placeholder="Comprehensive scope and details..."
                class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent text-sm resize-none"
              ><%= @form[:detailed_description].value %></textarea>
            </div>

            <%!-- Repository URL --%>
            <div>
              <label class="block text-xs font-medium text-gray-500 mb-1.5">Repository URL</label>
              <input
                type="url"
                name={@form[:repository_url].name}
                value={@form[:repository_url].value}
                placeholder="https://github.com/org/repo"
                class="w-full max-w-md px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent text-sm"
              />
            </div>

            <%!-- Customer (readonly) --%>
            <div>
              <label class="block text-xs font-medium text-gray-500 mb-1.5">Customer</label>
              <%= if @project.customer do %>
                <.link
                  navigate={~p"/org/#{@org_id}/customers/#{@project.customer.id}"}
                  class="inline-flex items-center gap-1 text-sm text-blue-600 hover:text-blue-700"
                >
                  {@project.customer.name}
                  <.icon name="hero-arrow-top-right-on-square" class="w-3.5 h-3.5" />
                </.link>
              <% else %>
                <span class="text-sm text-gray-400">Not set</span>
              <% end %>
            </div>
          </div>

          <div
            :if={@can_edit_project}
            class="px-6 py-3 bg-gray-50 border-t border-gray-200 flex justify-end"
          >
            <button
              type="submit"
              phx-disable-with="Saving..."
              class="px-4 py-1.5 bg-gray-900 text-white text-sm rounded-md hover:bg-gray-800 transition-colors font-medium"
            >
              Save
            </button>
          </div>
        </div>
      </.form>

      <%!-- Danger Zone --%>
      <div :if={@can_delete_project} class="bg-white border border-red-200 rounded-xl overflow-hidden">
        <div class="p-6">
          <h2 class="text-lg font-semibold text-red-600">Danger Zone</h2>
          <p class="text-sm text-gray-500 mt-1">
            Permanently delete this project and all its data.
          </p>
          <button
            phx-click="confirm_delete_project"
            class="mt-4 px-4 py-2 border border-red-300 text-red-600 text-sm rounded-lg hover:bg-red-50 transition-colors font-medium"
          >
            Delete Project
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :estimation, :map, required: true
  attr :currency, :map, required: true
  attr :dashboard_tab, :atom, required: true

  defp estimation_dashboard(assigns) do
    est = assigns.estimation
    roles = est.roles
    epics = est.epics

    # Calculate totals
    base_hours = Calculator.calc_total_hours(epics)
    base_cost = Calculator.calc_base_cost(epics, roles)

    pm_hours = Calculator.calc_overhead_hours(epics, roles, :pm_overhead)
    pm_cost = Calculator.calc_overhead_cost(epics, roles, :pm_overhead)

    qa_hours = Calculator.calc_overhead_hours(epics, roles, :qa_overhead)
    qa_cost = Calculator.calc_overhead_cost(epics, roles, :qa_overhead)

    risk_hours = Calculator.calc_overhead_hours(epics, roles, :risk_buffer)
    risk_cost = Calculator.calc_overhead_cost(epics, roles, :risk_buffer)

    total_hours =
      base_hours
      |> Decimal.add(pm_hours)
      |> Decimal.add(qa_hours)
      |> Decimal.add(risk_hours)

    total_cost =
      base_cost
      |> Decimal.add(pm_cost)
      |> Decimal.add(qa_cost)
      |> Decimal.add(risk_cost)

    assigns =
      assigns
      |> assign(:base_hours, base_hours)
      |> assign(:base_cost, base_cost)
      |> assign(:pm_hours, pm_hours)
      |> assign(:pm_cost, pm_cost)
      |> assign(:qa_hours, qa_hours)
      |> assign(:qa_cost, qa_cost)
      |> assign(:risk_hours, risk_hours)
      |> assign(:risk_cost, risk_cost)
      |> assign(:total_hours, total_hours)
      |> assign(:total_cost, total_cost)
      |> assign(:roles, roles)
      |> assign(:epics, epics)

    ~H"""
    <div class="bg-white border border-gray-200 rounded-xl overflow-hidden">
      <div class="px-6 py-4 border-b border-gray-100">
        <div class="flex items-start justify-between">
          <div>
            <h2 class="text-lg font-semibold text-gray-900">Project Summary & Cost Estimates</h2>
            <p class="text-sm text-gray-500 mt-0.5">
              Hours and costs with overhead calculations ({if @currency, do: @currency.code, else: "-"})
            </p>
          </div>
          <div class="text-right">
            <p class="text-xs text-gray-400">Based on</p>
            <p class="text-sm font-medium text-gray-700">{@estimation.name}</p>
          </div>
        </div>
      </div>

      <div class="p-6">
        <%!-- Summary Cards --%>
        <div class="grid grid-cols-2 md:grid-cols-5 gap-3">
          <div class="border border-gray-200 rounded-lg p-4">
            <p class="text-[10px] font-semibold text-gray-500 uppercase tracking-wide mb-1">Base</p>
            <p class="text-2xl font-bold text-gray-900">{format_hours_h(@base_hours)}</p>
            <p class="text-sm text-gray-500">{format_cost(@base_cost, @currency)}</p>
          </div>

          <div class="border border-gray-200 rounded-lg p-4">
            <p class="text-[10px] font-semibold text-gray-500 uppercase tracking-wide mb-1">
              PM Overhead
            </p>
            <p class="text-2xl font-bold text-gray-900">{format_hours_h(@pm_hours)}</p>
            <p class="text-sm text-gray-500">{format_cost(@pm_cost, @currency)}</p>
          </div>

          <div class="border border-gray-200 rounded-lg p-4">
            <p class="text-[10px] font-semibold text-gray-500 uppercase tracking-wide mb-1">
              QA Overhead
            </p>
            <p class="text-2xl font-bold text-gray-900">{format_hours_h(@qa_hours)}</p>
            <p class="text-sm text-gray-500">{format_cost(@qa_cost, @currency)}</p>
          </div>

          <div class="border border-gray-200 rounded-lg p-4">
            <p class="text-[10px] font-semibold text-gray-500 uppercase tracking-wide mb-1">
              Risk Buffer
            </p>
            <p class="text-2xl font-bold text-gray-900">{format_hours_h(@risk_hours)}</p>
            <p class="text-sm text-gray-500">{format_cost(@risk_cost, @currency)}</p>
          </div>

          <div class="bg-gray-900 rounded-lg p-4">
            <p class="text-[10px] font-semibold text-gray-400 uppercase tracking-wide mb-1">
              Final Total
            </p>
            <p class="text-2xl font-bold text-white">{format_hours_h(@total_hours)}</p>
            <p class="text-sm text-gray-300">{format_cost(@total_cost, @currency)}</p>
          </div>
        </div>

        <%!-- Dashboard Tabs --%>
        <div class="mt-6 border-b border-gray-200">
          <nav class="flex gap-6">
            <button
              phx-click="set_dashboard_tab"
              phx-value-tab="by_role"
              class={"pb-2 px-1 text-sm font-medium border-b-2 transition-colors #{if @dashboard_tab == :by_role, do: "border-gray-900 text-gray-900", else: "border-transparent text-gray-500 hover:text-gray-700"}"}
            >
              By Role
            </button>
            <button
              phx-click="set_dashboard_tab"
              phx-value-tab="by_epic"
              class={"pb-2 px-1 text-sm font-medium border-b-2 transition-colors #{if @dashboard_tab == :by_epic, do: "border-gray-900 text-gray-900", else: "border-transparent text-gray-500 hover:text-gray-700"}"}
            >
              By Epic
            </button>
            <button
              phx-click="set_dashboard_tab"
              phx-value-tab="by_priority"
              class={"pb-2 px-1 text-sm font-medium border-b-2 transition-colors #{if @dashboard_tab == :by_priority, do: "border-gray-900 text-gray-900", else: "border-transparent text-gray-500 hover:text-gray-700"}"}
            >
              By Priority
            </button>
          </nav>
        </div>

        <%!-- Tab Content --%>
        <div class="mt-4">
          <%= case @dashboard_tab do %>
            <% :by_role -> %>
              <.dashboard_by_role roles={@roles} epics={@epics} currency={@currency} />
            <% :by_epic -> %>
              <.dashboard_by_epic roles={@roles} epics={@epics} currency={@currency} />
            <% :by_priority -> %>
              <.dashboard_by_priority roles={@roles} epics={@epics} currency={@currency} />
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp dashboard_by_role(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="w-full text-sm">
        <thead>
          <tr class="border-b border-gray-200 text-[11px] font-medium text-gray-500 uppercase tracking-wider">
            <th class="px-3 py-2 text-left">Role</th>
            <th class="px-3 py-2 text-right">Rate</th>
            <th class="px-3 py-2 text-right">Base</th>
            <th class="px-3 py-2 text-right">PM</th>
            <th class="px-3 py-2 text-right">QA</th>
            <th class="px-3 py-2 text-right">Risk</th>
            <th class="px-3 py-2 text-right">Final</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-gray-100">
          <%= for role <- @roles, Decimal.compare(Calculator.role_hours(@epics, role.id), 0) == :gt do %>
            <% base_h = Calculator.role_hours(@epics, role.id) %>
            <% base_c = Decimal.mult(base_h, role.hourly_rate) %>
            <% pm_h = Calculator.role_overhead_hours(base_h, role.pm_overhead) %>
            <% pm_c = Calculator.role_overhead_cost(base_c, role.pm_overhead) %>
            <% qa_h = Calculator.role_overhead_hours(base_h, role.qa_overhead) %>
            <% qa_c = Calculator.role_overhead_cost(base_c, role.qa_overhead) %>
            <% risk_h = Calculator.role_overhead_hours(base_h, role.risk_buffer) %>
            <% risk_c = Calculator.role_overhead_cost(base_c, role.risk_buffer) %>
            <% final_h = base_h |> Decimal.add(pm_h) |> Decimal.add(qa_h) |> Decimal.add(risk_h) %>
            <% final_c = base_c |> Decimal.add(pm_c) |> Decimal.add(qa_c) |> Decimal.add(risk_c) %>
            <tr class="hover:bg-gray-50">
              <td class="px-3 py-3">
                <span class="font-medium text-gray-900">{role.name}</span>
                <span class="text-gray-400 ml-1">({role.abbreviation})</span>
              </td>
              <td class="px-3 py-3 text-right text-gray-500">
                {format_cost(role.hourly_rate, @currency)}/h
              </td>
              <td class="px-3 py-3 text-right">
                <div class="text-gray-900">{format_hours_h(base_h)}</div>
                <div class="text-xs text-gray-400">{format_cost(base_c, @currency)}</div>
              </td>
              <td class="px-3 py-3 text-right">
                <div class="text-gray-900">{format_hours_h(pm_h)}</div>
                <div class="text-xs text-gray-400">{format_cost(pm_c, @currency)}</div>
              </td>
              <td class="px-3 py-3 text-right">
                <div class="text-gray-900">{format_hours_h(qa_h)}</div>
                <div class="text-xs text-gray-400">{format_cost(qa_c, @currency)}</div>
              </td>
              <td class="px-3 py-3 text-right">
                <div class="text-gray-900">{format_hours_h(risk_h)}</div>
                <div class="text-xs text-gray-400">{format_cost(risk_c, @currency)}</div>
              </td>
              <td class="px-3 py-3 text-right">
                <div class="font-semibold text-gray-900">{format_hours_h(final_h)}</div>
                <div class="text-xs font-medium text-gray-600">{format_cost(final_c, @currency)}</div>
              </td>
            </tr>
          <% end %>
        </tbody>
        <tfoot>
          <tr class="border-t-2 border-gray-300 bg-gray-50">
            <td class="px-3 py-3 font-semibold text-gray-900" colspan="2">Total</td>
            <td class="px-3 py-3 text-right">
              <div class="font-semibold text-gray-900">
                {format_hours_h(Calculator.calc_total_hours(@epics))}
              </div>
              <div class="text-xs text-gray-500">
                {format_cost(Calculator.calc_base_cost(@epics, @roles), @currency)}
              </div>
            </td>
            <td class="px-3 py-3 text-right">
              <div class="font-semibold text-gray-900">
                {format_hours_h(Calculator.calc_overhead_hours(@epics, @roles, :pm_overhead))}
              </div>
              <div class="text-xs text-gray-500">
                {format_cost(Calculator.calc_overhead_cost(@epics, @roles, :pm_overhead), @currency)}
              </div>
            </td>
            <td class="px-3 py-3 text-right">
              <div class="font-semibold text-gray-900">
                {format_hours_h(Calculator.calc_overhead_hours(@epics, @roles, :qa_overhead))}
              </div>
              <div class="text-xs text-gray-500">
                {format_cost(Calculator.calc_overhead_cost(@epics, @roles, :qa_overhead), @currency)}
              </div>
            </td>
            <td class="px-3 py-3 text-right">
              <div class="font-semibold text-gray-900">
                {format_hours_h(Calculator.calc_overhead_hours(@epics, @roles, :risk_buffer))}
              </div>
              <div class="text-xs text-gray-500">
                {format_cost(Calculator.calc_overhead_cost(@epics, @roles, :risk_buffer), @currency)}
              </div>
            </td>
            <td class="px-3 py-3 text-right">
              <% total_h = Calculator.calc_total_with_overhead_hours(@epics, @roles) %>
              <% total_c = Calculator.calc_total_with_overhead_cost(@epics, @roles) %>
              <div class="font-semibold text-gray-900">{format_hours_h(total_h)}</div>
              <div class="text-xs font-medium text-gray-600">{format_cost(total_c, @currency)}</div>
            </td>
          </tr>
        </tfoot>
      </table>
    </div>
    """
  end

  defp dashboard_by_epic(assigns) do
    ~H"""
    <div class="overflow-x-auto">
      <table class="w-full text-sm">
        <thead>
          <tr class="border-b border-gray-200 text-[11px] font-medium text-gray-500 uppercase tracking-wider">
            <th class="px-3 py-2 text-left">Epic</th>
            <th class="px-3 py-2 text-right">Tasks</th>
            <th class="px-3 py-2 text-right">Base Hours</th>
            <th class="px-3 py-2 text-right">Base Cost</th>
            <th class="px-3 py-2 text-right">With Overhead</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-gray-100">
          <%= for epic <- @epics do %>
            <% base_h = Calculator.epic_hours(epic) %>
            <% base_c = Calculator.epic_base_cost(epic, @roles) %>
            <% total_c = Calculator.epic_total_with_overhead(epic, @roles) %>
            <tr class="hover:bg-gray-50">
              <td class="px-3 py-3 font-medium text-gray-900">{epic.name}</td>
              <td class="px-3 py-3 text-right text-gray-500">{length(epic.tasks)}</td>
              <td class="px-3 py-3 text-right text-gray-900">{format_hours_h(base_h)}</td>
              <td class="px-3 py-3 text-right text-gray-600">{format_cost(base_c, @currency)}</td>
              <td class="px-3 py-3 text-right font-semibold text-gray-900">
                {format_cost(total_c, @currency)}
              </td>
            </tr>
          <% end %>
        </tbody>
        <tfoot>
          <tr class="border-t-2 border-gray-300 bg-gray-50 font-semibold">
            <td class="px-3 py-3 text-gray-900">Total</td>
            <td class="px-3 py-3 text-right text-gray-600">
              {Enum.reduce(@epics, 0, fn e, acc -> acc + length(e.tasks) end)}
            </td>
            <td class="px-3 py-3 text-right text-gray-900">
              {format_hours_h(Calculator.calc_total_hours(@epics))}
            </td>
            <td class="px-3 py-3 text-right text-gray-600">
              {format_cost(Calculator.calc_base_cost(@epics, @roles), @currency)}
            </td>
            <td class="px-3 py-3 text-right text-gray-900">
              {format_cost(Calculator.calc_total_with_overhead_cost(@epics, @roles), @currency)}
            </td>
          </tr>
        </tfoot>
      </table>
    </div>
    """
  end

  defp dashboard_by_priority(assigns) do
    priorities = ["must", "should", "could", "wont"]

    priority_data =
      Enum.map(priorities, fn p ->
        tasks =
          Enum.flat_map(assigns.epics, fn epic ->
            Enum.filter(epic.tasks, fn t -> (t.priority || "must") == p end)
          end)

        hours =
          Enum.reduce(tasks, Decimal.new(0), fn task, acc ->
            Enum.reduce(task.estimates, acc, fn est, inner_acc ->
              Decimal.add(inner_acc, est.hours)
            end)
          end)

        cost =
          Enum.reduce(tasks, Decimal.new(0), fn task, acc ->
            Enum.reduce(task.estimates, acc, fn est, inner_acc ->
              role = Enum.find(assigns.roles, &(&1.id == est.estimation_role_id))

              if role do
                base = Decimal.mult(est.hours, role.hourly_rate)
                pm = Decimal.mult(base, Decimal.div(role.pm_overhead, 100))
                qa = Decimal.mult(base, Decimal.div(role.qa_overhead, 100))
                risk = Decimal.mult(base, Decimal.div(role.risk_buffer, 100))

                Decimal.add(
                  inner_acc,
                  base |> Decimal.add(pm) |> Decimal.add(qa) |> Decimal.add(risk)
                )
              else
                inner_acc
              end
            end)
          end)

        %{priority: p, tasks: length(tasks), hours: hours, cost: cost}
      end)

    assigns = assign(assigns, :priority_data, priority_data)

    ~H"""
    <div class="overflow-x-auto">
      <table class="w-full text-sm">
        <thead>
          <tr class="border-b border-gray-200 text-[11px] font-medium text-gray-500 uppercase tracking-wider">
            <th class="px-3 py-2 text-left">Priority</th>
            <th class="px-3 py-2 text-right">Tasks</th>
            <th class="px-3 py-2 text-right">Base Hours</th>
            <th class="px-3 py-2 text-right">Total Cost</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-gray-100">
          <%= for data <- @priority_data do %>
            <tr class="hover:bg-gray-50">
              <td class="px-3 py-3">
                <span class={"text-xs px-2 py-1 rounded font-medium #{priority_class(data.priority)}"}>
                  {priority_label(data.priority)}
                </span>
              </td>
              <td class="px-3 py-3 text-right text-gray-600">{data.tasks}</td>
              <td class="px-3 py-3 text-right text-gray-900">{format_hours_h(data.hours)}</td>
              <td class="px-3 py-3 text-right font-semibold text-gray-900">
                {format_cost(data.cost, @currency)}
              </td>
            </tr>
          <% end %>
        </tbody>
        <tfoot>
          <tr class="border-t-2 border-gray-300 bg-gray-50 font-semibold">
            <td class="px-3 py-3 text-gray-900">Total</td>
            <td class="px-3 py-3 text-right text-gray-600">
              {Enum.reduce(@priority_data, 0, fn d, acc -> acc + d.tasks end)}
            </td>
            <td class="px-3 py-3 text-right text-gray-900">
              {format_hours_h(
                Enum.reduce(@priority_data, Decimal.new(0), fn d, acc -> Decimal.add(acc, d.hours) end)
              )}
            </td>
            <td class="px-3 py-3 text-right text-gray-900">
              {format_cost(
                Enum.reduce(@priority_data, Decimal.new(0), fn d, acc -> Decimal.add(acc, d.cost) end),
                @currency
              )}
            </td>
          </tr>
        </tfoot>
      </table>
    </div>
    """
  end

  defp tab_collaborators(assigns) do
    filtered_members =
      if assigns.member_search == "" do
        assigns.available_members
      else
        term = String.downcase(assigns.member_search)

        Enum.filter(assigns.available_members, fn m ->
          String.contains?(String.downcase(m.user.name || ""), term) ||
            String.contains?(String.downcase(m.user.email), term)
        end)
      end

    assigns = assign(assigns, :filtered_members, filtered_members)

    ~H"""
    <div class="space-y-6">
      <%!-- Add Collaborator --%>
      <div
        :if={@can_manage_collaborators}
        class="bg-white border border-gray-200 rounded-xl"
      >
        <form phx-change="collaborator_form_change" phx-submit="add_collaborator" class="p-6">
          <h2 class="text-lg font-semibold text-gray-900 mb-4">Add Collaborator</h2>
          <div class="flex gap-4">
            <div class="flex-1 relative">
              <label class="block text-xs font-medium text-gray-500 mb-1.5">Member</label>
              <%= if @selected_member do %>
                <div class="flex items-center gap-2 px-3 py-2 bg-gray-50 border border-gray-200 rounded-lg">
                  <.avatar name={@selected_member.name || @selected_member.email} seed={@selected_member.id} size={:xs} />
                  <span class="text-sm text-gray-900">
                    {@selected_member.name || @selected_member.email}
                  </span>
                  <button
                    type="button"
                    phx-click="clear_selected_member"
                    class="ml-auto text-gray-400 hover:text-gray-600"
                  >
                    <.icon name="hero-x-mark" class="w-4 h-4" />
                  </button>
                </div>
              <% else %>
                <div class="relative">
                  <div class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                    <.icon name="hero-magnifying-glass" class="w-4 h-4 text-gray-400" />
                  </div>
                  <input
                    type="text"
                    name="member_search"
                    value={@member_search}
                    placeholder="Search members..."
                    phx-focus="open_member_dropdown"
                    phx-click-away="close_member_dropdown"
                    phx-debounce="100"
                    autocomplete="off"
                    class="w-full pl-9 pr-3 py-2 bg-gray-50 border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent focus:bg-white text-sm"
                  />
                </div>
                <div
                  :if={@show_member_dropdown && @filtered_members != []}
                  class="absolute z-10 mt-1 w-full bg-white border border-gray-200 rounded-lg shadow-lg max-h-48 overflow-y-auto"
                >
                  <button
                    :for={membership <- @filtered_members}
                    type="button"
                    phx-click="select_member"
                    phx-value-user-id={membership.user.id}
                    class="w-full px-3 py-2 flex items-center gap-3 hover:bg-gray-50 text-left"
                  >
                    <.avatar name={membership.user.name || membership.user.email} seed={membership.user.id} size={:sm} />
                    <div class="min-w-0">
                      <p class="text-sm font-medium text-gray-900 truncate">
                        {membership.user.name || membership.user.email}
                      </p>
                      <p class="text-xs text-gray-500 truncate">{membership.user.email}</p>
                    </div>
                    <span class="ml-auto text-xs text-gray-400 capitalize flex-shrink-0">
                      {membership.role}
                    </span>
                  </button>
                </div>
              <% end %>
            </div>
            <div class="w-36">
              <label class="block text-xs font-medium text-gray-500 mb-1.5">Role</label>
              <select
                name="collaborator_role"
                class="w-full px-3 py-2 bg-gray-50 border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent focus:bg-white text-sm"
              >
                <option value="viewer" selected={@selected_role == "viewer"}>Viewer</option>
                <option value="editor" selected={@selected_role == "editor"}>Editor</option>
                <option value="owner" selected={@selected_role == "owner"}>Owner</option>
              </select>
            </div>
            <div class="flex items-end">
              <button
                type="submit"
                disabled={is_nil(@selected_member)}
                class={"px-4 py-2 bg-gray-900 text-white text-sm rounded-lg font-medium transition-colors #{if is_nil(@selected_member), do: "opacity-50 cursor-not-allowed", else: "hover:bg-gray-800"}"}
              >
                Add
              </button>
            </div>
          </div>
        </form>
      </div>

      <%!-- Collaborators List --%>
      <div class="bg-white border border-gray-200 rounded-xl overflow-hidden">
        <div class="px-6 py-4 border-b border-gray-100">
          <h2 class="text-lg font-semibold text-gray-900">Collaborators</h2>
        </div>
        <%= if @collaborators == [] do %>
          <div class="px-6 py-12 text-center">
            <div class="w-12 h-12 mx-auto mb-4 rounded-full bg-gray-100 flex items-center justify-center">
              <.icon name="hero-users" class="w-6 h-6 text-gray-400" />
            </div>
            <p class="text-sm font-medium text-gray-900">No collaborators</p>
            <p class="text-sm text-gray-500 mt-1">Add team members to this project.</p>
          </div>
        <% else %>
          <div
            :for={collab <- Enum.sort_by(@collaborators, &(&1.user_id != @current_user.id))}
            class="px-6 py-4 flex items-center justify-between border-b border-gray-100 last:border-b-0"
          >
            <div class="flex items-center gap-3">
              <.avatar name={collab.user.name || collab.user.email} seed={collab.user.id} />
              <div>
                <div class="flex items-center gap-2">
                  <h3 class="text-sm font-medium text-gray-900">{collab.user.name}</h3>
                  <span
                    :if={collab.user_id == @current_user.id}
                    class="text-[10px] px-1.5 py-0.5 bg-gray-100 text-gray-500 rounded-full font-medium"
                  >
                    You
                  </span>
                </div>
                <p class="text-sm text-gray-500">{collab.user.email}</p>
              </div>
            </div>
            <div class="flex items-center gap-4">
              <%= if can_change_role?(assigns, collab) do %>
                <form phx-change="change_collaborator_role" phx-value-id={collab.id}>
                  <select
                    name="role"
                    class="text-sm px-2 py-1 border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent"
                  >
                    <option value="viewer" selected={collab.role == "viewer"}>Viewer</option>
                    <option value="editor" selected={collab.role == "editor"}>Editor</option>
                    <option value="owner" selected={collab.role == "owner"}>Owner</option>
                  </select>
                </form>
              <% else %>
                <span class="text-sm text-gray-500 capitalize">{collab.role}</span>
              <% end %>
              <%= if can_remove_collaborator?(assigns, collab) do %>
                <button
                  phx-click="confirm_remove_collaborator"
                  phx-value-id={collab.id}
                  class="text-gray-400 hover:text-red-600 transition-colors"
                >
                  <.icon name="hero-x-mark" class="w-5 h-5" />
                </button>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp tab_estimations(assigns) do
    ~H"""
    <div class="bg-white border border-gray-200 rounded-xl overflow-hidden">
      <div class="px-6 py-4 border-b border-gray-100 flex items-center justify-between">
        <h2 class="text-lg font-semibold text-gray-900">Estimations</h2>
        <button
          :if={@can_edit_project}
          phx-click="open_estimation_modal"
          class="px-3 py-1.5 bg-gray-900 text-white text-sm rounded-lg hover:bg-gray-800 transition-colors font-medium"
        >
          New Estimation
        </button>
      </div>

      <%= if @estimations == [] do %>
        <div class="px-6 py-12 text-center">
          <div class="w-12 h-12 mx-auto mb-4 rounded-full bg-gray-100 flex items-center justify-center">
            <.icon name="hero-calculator" class="w-6 h-6 text-gray-400" />
          </div>
          <p class="text-sm font-medium text-gray-900">No estimations yet</p>
          <p class="text-sm text-gray-500 mt-1">Create your first estimation to get started.</p>
        </div>
      <% else %>
        <%= for estimation <- @estimations do %>
          <div class="flex items-center border-b border-gray-100 last:border-b-0">
            <.link
              navigate={
                ~p"/org/#{@org_id}/projects/#{@project.id}/estimations/#{estimation.id}/estimator"
              }
              class="flex-1 px-6 py-4 hover:bg-gray-50 transition-colors"
            >
              <div class="flex items-center gap-2">
                <h3 class="text-sm font-medium text-gray-900">{estimation.name}</h3>
                <span
                  :if={estimation.is_current}
                  class="text-[10px] px-1.5 py-0.5 bg-green-100 text-green-700 rounded font-medium"
                >
                  Current
                </span>
              </div>
              <p class="text-xs text-gray-500 mt-0.5">
                {length(estimation.roles)} roles · Updated {Calendar.strftime(
                  estimation.updated_at,
                  "%b %d, %Y"
                )}
              </p>
            </.link>
            <div class="px-4 flex items-center gap-2">
              <button
                :if={!estimation.is_current}
                phx-click="set_current_estimation"
                phx-value-id={estimation.id}
                class="text-xs text-gray-400 hover:text-gray-600 px-2 py-1 rounded hover:bg-gray-100"
                title="Set as current"
              >
                Set current
              </button>
              <span :if={estimation.is_current} class="text-xs text-green-600 px-2 py-1">
                <.icon name="hero-check-circle-solid" class="w-4 h-4" />
              </span>
            </div>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  ## Mount & Params

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    org_id = socket.assigns.org_id
    user = socket.assigns.current_user
    # Collaborator access check for non-admins
    current_collaborator = Portfolio.get_collaborator(id, user.id)

    unless admin?(socket.assigns.current_membership) or current_collaborator do
      {:ok,
       socket
       |> Phoenix.LiveView.put_flash(:error, "You don't have access to this project.")
       |> Phoenix.LiveView.redirect(to: ~p"/org/#{org_id}/projects")}
    else
      mount_project(socket, id, org_id, current_collaborator)
    end
  end

  defp mount_project(socket, id, org_id, current_collaborator) do
    project = Portfolio.get_project_with_roles!(id, org_id)
    estimations = EstimationEngine.list_estimations(id)
    role_templates = Accounts.list_role_templates(org_id)
    estimation_templates = Estimate.Templates.list_estimation_templates(org_id)
    currencies = Currencies.list_currencies(org_id)

    # Load the current estimation (is_current=true) with full data for the dashboard
    current_estimation =
      case Enum.find(estimations, & &1.is_current) do
        nil -> nil
        est -> EstimationEngine.get_estimation!(est.id, org_id)
      end

    changeset = Portfolio.change_project(project)

    is_org_admin = admin?(socket.assigns.current_membership)
    collab_role = current_collaborator && current_collaborator.role

    can_edit_project = is_org_admin || collab_role in ["owner", "editor"]
    can_delete_project = is_org_admin || collab_role == "owner"

    can_manage_collabs =
      (current_collaborator && current_collaborator.role == "owner") || is_org_admin

    {:ok,
     socket
     |> assign(:page_title, project.name)
     |> assign(:active_tab, :projects)
     |> assign(:project, project)
     |> assign(:estimations, estimations)
     |> assign(:role_templates, role_templates)
     |> assign(:currencies, currencies)
     |> assign(:current_estimation, current_estimation)
     |> assign(:dashboard_tab, :by_role)
     |> assign(:customer_key, if(project.customer, do: project.customer.key))
     |> assign(:tab, :overview)
     |> assign(:form, to_form(changeset))
     |> assign(:deleting_project, false)
     |> assign(:show_new_estimation_modal, false)
     |> assign(:estimation_form, to_form(%{}, as: "estimation"))
     |> assign(:selected_template_ids, Enum.map(role_templates, & &1.id))
     |> assign(:modal_currency_id, project.currency_id)
     |> assign(:modal_currency, project.currency)
     |> assign(:estimation_source, "fresh")
     |> assign(:source_estimation_id, nil)
     |> assign(:estimation_templates, estimation_templates)
     |> assign(
       :selected_estimation_template_id,
       if(estimation_templates != [], do: hd(estimation_templates).id)
     )
     |> assign(:current_collaborator, current_collaborator)
     |> assign(:can_edit_project, can_edit_project)
     |> assign(:can_delete_project, can_delete_project)
     |> assign(:can_manage_collaborators, can_manage_collabs)
     |> assign(:collaborators, [])
     |> assign(:available_members, [])
     |> assign(:member_search, "")
     |> assign(:show_member_dropdown, false)
     |> assign(:selected_member, nil)
     |> assign(:selected_role, "viewer")
     |> assign(:removing_collaborator, nil)
     |> init_json_assigns()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :show, _params) do
    socket
    |> assign(:tab, :overview)
    |> assign(:page_title, socket.assigns.project.name)
  end

  defp apply_action(socket, :collaborators, _params) do
    project_id = socket.assigns.project.id
    collaborators = Portfolio.list_collaborators(project_id)
    available = Portfolio.list_available_members(project_id, socket.assigns.org_id)

    socket
    |> assign(:tab, :collaborators)
    |> assign(:collaborators, collaborators)
    |> assign(:available_members, available)
    |> assign(:page_title, "Collaborators - #{socket.assigns.project.name}")
  end

  defp apply_action(socket, :estimations, _params) do
    socket
    |> assign(:tab, :estimations)
    |> assign(:page_title, "Estimations - #{socket.assigns.project.name}")
  end

  defp apply_action(socket, :new_estimation, _params) do
    socket
    |> assign(:tab, :estimations)
    |> assign(:show_new_estimation_modal, true)
    |> assign(:page_title, "New Estimation - #{socket.assigns.project.name}")
  end

  ## Event Handlers

  @impl true
  def handle_event("validate", %{"project" => project_params}, socket) do
    changeset =
      socket.assigns.project
      |> Portfolio.change_project(project_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save", %{"project" => project_params}, socket) do
    unless socket.assigns.can_edit_project do
      {:noreply, put_flash(socket, :error, "Not authorized")}
    else
      case Portfolio.update_project(socket.assigns.project, project_params) do
        {:ok, project} ->
          project = Portfolio.reload_project_with_roles(project)

          {:noreply,
           socket
           |> put_flash(:info, "Project updated")
           |> assign(:project, project)
           |> assign(:customer_key, if(project.customer, do: project.customer.key))
           |> assign(:form, to_form(Portfolio.change_project(project)))}

        {:error, changeset} ->
          {:noreply, assign(socket, form: to_form(changeset))}
      end
    end
  end

  def handle_event("confirm_delete_project", _params, socket) do
    {:noreply, assign(socket, :deleting_project, true)}
  end

  def handle_event("cancel_delete_project", _params, socket) do
    {:noreply, assign(socket, :deleting_project, false)}
  end

  def handle_event("delete_project", _params, socket) do
    unless socket.assigns.can_delete_project do
      {:noreply,
       socket
       |> put_flash(:error, "Not authorized")
       |> assign(:deleting_project, false)}
    else
      case Portfolio.delete_project(socket.assigns.project) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "Project deleted")
           |> push_navigate(to: ~p"/org/#{socket.assigns.org_id}/projects")}

        {:error, _} ->
          {:noreply,
           socket
           |> put_flash(:error, "Could not delete project")
           |> assign(:deleting_project, false)}
      end
    end
  end

  def handle_event("set_dashboard_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :dashboard_tab, String.to_existing_atom(tab))}
  end

  ## Estimation Events

  def handle_event("open_estimation_modal", _params, socket) do
    project = socket.assigns.project
    estimations = socket.assigns.estimations
    first_estimation_id = if Enum.any?(estimations), do: hd(estimations).id, else: nil

    {:noreply,
     socket
     |> assign(:show_new_estimation_modal, true)
     |> assign(:estimation_form, to_form(%{"name" => "", "description" => ""}, as: "estimation"))
     |> assign(:selected_template_ids, Enum.map(socket.assigns.role_templates, & &1.id))
     |> assign(:modal_currency_id, project.currency_id)
     |> assign(:modal_currency, project.currency)
     |> assign(:estimation_source, "fresh")
     |> assign(:source_estimation_id, first_estimation_id)}
  end

  def handle_event("set_estimation_source", %{"source" => source}, socket) do
    estimations = socket.assigns.estimations

    socket =
      if source == "copy" && Enum.any?(estimations) do
        first_est = hd(estimations)

        socket
        |> assign(
          :estimation_form,
          to_form(%{"name" => "Copy of #{first_est.name}", "description" => ""}, as: "estimation")
        )
        |> assign(:source_estimation_id, first_est.id)
        |> assign(:modal_currency_id, first_est.currency_id)
        |> assign(
          :modal_currency,
          Enum.find(socket.assigns.currencies, &(&1.id == first_est.currency_id))
        )
      else
        socket
        |> assign(
          :estimation_form,
          to_form(%{"name" => "", "description" => ""}, as: "estimation")
        )
        |> assign(:source_estimation_id, nil)
      end

    socket =
      socket
      |> assign(:estimation_source, source)
      |> clear_json()

    {:noreply, socket}
  end

  def handle_event("close_estimation_modal", _params, socket) do
    {:noreply, assign(socket, :show_new_estimation_modal, false)}
  end

  def handle_event("validate_estimation", %{"json_input" => json_string} = params, socket)
      when json_string != "" do
    socket = do_validate_json(socket, json_string)
    template_ids = Map.get(params, "template_ids", [])
    currency_id = Map.get(params, "currency_id")

    socket =
      if currency_id && currency_id != "" do
        currency = Enum.find(socket.assigns.currencies, &(to_string(&1.id) == currency_id))

        socket
        |> assign(:modal_currency_id, currency_id)
        |> assign(:modal_currency, currency)
      else
        socket
      end

    {:noreply, assign(socket, :selected_template_ids, template_ids)}
  end

  def handle_event("validate_estimation", params, socket) do
    # Clear JSON state if textarea was emptied
    socket =
      if Map.get(params, "json_input") == "" do
        clear_json(socket)
      else
        socket
      end

    template_ids = Map.get(params, "template_ids", [])
    currency_id = Map.get(params, "currency_id")
    source_estimation_id = Map.get(params, "source_estimation_id")

    socket =
      if currency_id && currency_id != "" do
        currency = Enum.find(socket.assigns.currencies, &(to_string(&1.id) == currency_id))

        socket
        |> assign(:modal_currency_id, currency_id)
        |> assign(:modal_currency, currency)
      else
        socket
      end

    # Handle source estimation change for copy mode
    socket =
      if source_estimation_id && source_estimation_id != "" do
        est = Enum.find(socket.assigns.estimations, &(to_string(&1.id) == source_estimation_id))

        if est do
          socket
          |> assign(:source_estimation_id, source_estimation_id)
          |> assign(
            :estimation_form,
            to_form(%{"name" => "Copy of #{est.name}", "description" => ""}, as: "estimation")
          )
          |> assign(:modal_currency_id, est.currency_id)
          |> assign(
            :modal_currency,
            Enum.find(socket.assigns.currencies, &(&1.id == est.currency_id))
          )
        else
          socket
        end
      else
        socket
      end

    {:noreply, assign(socket, :selected_template_ids, template_ids)}
  end

  def handle_event("create_estimation", %{"estimation" => estimation_params} = params, socket) do
    unless socket.assigns.can_edit_project do
      {:noreply, put_flash(socket, :error, "Not authorized")}
    else
      source = Map.get(params, "source", "fresh")
      project = socket.assigns.project
      org_id = socket.assigns.org_id

      result =
        case source do
          "copy" ->
            source_estimation_id = Map.get(params, "source_estimation_id")
            name = estimation_params["name"]

            if source_estimation_id && name && name != "" do
              source_estimation = EstimationEngine.get_estimation!(source_estimation_id, org_id)
              EstimationEngine.copy_estimation(source_estimation, name, project.id, org_id)
            else
              {:error, :invalid_params}
            end

          "template" ->
            estimation_template_id = Map.get(params, "estimation_template_id")
            template_ids = Map.get(params, "template_ids", [])
            currency_id = Map.get(params, "currency_id", project.currency_id)

            attrs =
              Map.merge(estimation_params, %{
                "project_id" => project.id,
                "currency_id" => currency_id,
                "organization_id" => org_id
              })

            EstimationEngine.create_estimation_from_estimation_template(
              attrs,
              estimation_template_id,
              template_ids,
              currency_id
            )

          "json" ->
            parsed_json = socket.assigns.json_parsed

            if parsed_json do
              template_ids = Map.get(params, "template_ids", [])
              currency_id = Map.get(params, "currency_id", project.currency_id)

              attrs =
                Map.merge(estimation_params, %{
                  "project_id" => project.id,
                  "currency_id" => currency_id,
                  "organization_id" => org_id
                })

              EstimationEngine.create_estimation_from_json(
                attrs,
                parsed_json,
                template_ids,
                currency_id
              )
            else
              {:error, :no_json}
            end

          _ ->
            template_ids = Map.get(params, "template_ids", [])
            currency_id = Map.get(params, "currency_id", project.currency_id)

            attrs =
              Map.merge(estimation_params, %{
                "project_id" => project.id,
                "currency_id" => currency_id
              })

            EstimationEngine.create_estimation_from_templates(attrs, template_ids, currency_id)
        end

      case result do
        {:ok, estimation} ->
          estimations = EstimationEngine.list_estimations(project.id)

          {:noreply,
           socket
           |> put_flash(
             :info,
             if(source == "copy", do: "Estimation copied", else: "Estimation created")
           )
           |> assign(:show_new_estimation_modal, false)
           |> assign(:estimations, estimations)
           |> push_navigate(
             to:
               ~p"/org/#{socket.assigns.org_id}/projects/#{project.id}/estimations/#{estimation.id}/estimator"
           )}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not create estimation")}
      end
    end
  end

  def handle_event("json_file_uploaded", %{"content" => content}, socket) do
    {:noreply, do_validate_json(socket, content)}
  end

  def handle_event("download_json_schema", _params, socket) do
    {:noreply, push_schema_download(socket)}
  end

  def handle_event("set_current_estimation", %{"id" => id}, socket) do
    org_id = socket.assigns.org_id
    estimation = EstimationEngine.get_estimation!(id, org_id)
    {:ok, _} = EstimationEngine.set_current_estimation(estimation)
    estimations = EstimationEngine.list_estimations(socket.assigns.project.id)
    current_estimation = EstimationEngine.get_estimation!(id, org_id)

    {:noreply,
     socket
     |> assign(:estimations, estimations)
     |> assign(:current_estimation, current_estimation)}
  end

  ## Collaborator Events

  def handle_event("collaborator_form_change", params, socket) do
    member_search = Map.get(params, "member_search", socket.assigns.member_search)
    selected_role = Map.get(params, "collaborator_role", socket.assigns.selected_role)

    {:noreply,
     socket
     |> assign(:member_search, member_search)
     |> assign(:selected_role, selected_role)
     |> assign(:show_member_dropdown, member_search != "" || socket.assigns.show_member_dropdown)}
  end

  def handle_event("open_member_dropdown", _params, socket) do
    {:noreply, assign(socket, :show_member_dropdown, true)}
  end

  def handle_event("close_member_dropdown", _params, socket) do
    {:noreply, assign(socket, :show_member_dropdown, false)}
  end

  def handle_event("select_member", %{"user-id" => user_id}, socket) do
    member =
      Enum.find(socket.assigns.available_members, fn m -> m.user.id == user_id end)

    if member do
      {:noreply,
       socket
       |> assign(:selected_member, member.user)
       |> assign(:member_search, member.user.name || member.user.email)
       |> assign(:show_member_dropdown, false)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("clear_selected_member", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_member, nil)
     |> assign(:member_search, "")}
  end

  def handle_event("add_collaborator", _params, socket) do
    if !socket.assigns.can_manage_collaborators do
      {:noreply, put_flash(socket, :error, "Not authorized")}
    else
      member = socket.assigns.selected_member

      if member do
        project_id = socket.assigns.project.id

        case Portfolio.add_collaborator(project_id, member.id, socket.assigns.selected_role) do
          {:ok, _} ->
            {:noreply, reload_collaborators(socket, "Collaborator added")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not add collaborator")}
        end
      else
        {:noreply, socket}
      end
    end
  end

  def handle_event("change_collaborator_role", %{"id" => id, "role" => role}, socket) do
    if !socket.assigns.can_manage_collaborators do
      {:noreply, put_flash(socket, :error, "Not authorized")}
    else
      collab = Enum.find(socket.assigns.collaborators, &(&1.id == id))

      if collab && can_change_role?(socket.assigns, collab) do
        case Portfolio.update_collaborator_role(collab, role) do
          {:ok, _} ->
            {:noreply, reload_collaborators(socket, "Role updated")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not update role")}
        end
      else
        {:noreply, put_flash(socket, :error, "Not authorized")}
      end
    end
  end

  def handle_event("confirm_remove_collaborator", %{"id" => id}, socket) do
    collab = Enum.find(socket.assigns.collaborators, &(&1.id == id))
    {:noreply, assign(socket, :removing_collaborator, collab)}
  end

  def handle_event("cancel_remove_collaborator", _params, socket) do
    {:noreply, assign(socket, :removing_collaborator, nil)}
  end

  def handle_event("remove_collaborator", _params, socket) do
    collab = socket.assigns.removing_collaborator

    cond do
      is_nil(collab) ->
        {:noreply, assign(socket, :removing_collaborator, nil)}

      !can_remove_collaborator?(socket.assigns, collab) ->
        {:noreply,
         socket
         |> put_flash(:error, "Not authorized")
         |> assign(:removing_collaborator, nil)}

      collab.role == "owner" &&
          Enum.count(socket.assigns.collaborators, &(&1.role == "owner")) <= 1 ->
        {:noreply,
         socket
         |> put_flash(:error, "Cannot remove the last project owner")
         |> assign(:removing_collaborator, nil)}

      true ->
        case Portfolio.remove_collaborator(collab) do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(:removing_collaborator, nil)
             |> reload_collaborators("Collaborator removed")}

          {:error, _} ->
            {:noreply,
             socket
             |> put_flash(:error, "Could not remove collaborator")
             |> assign(:removing_collaborator, nil)}
        end
    end
  end

  defp do_validate_json(socket, json_string) do
    socket = validate_json(socket, json_string)

    if socket.assigns.json_parsed do
      parsed = socket.assigns.json_parsed

      # Prefill form from parsed JSON
      form_data = %{
        "name" => parsed.estimation || "",
        "description" => parsed.description || ""
      }

      # Try to resolve currency code
      socket =
        if parsed.currency do
          currency =
            Enum.find(socket.assigns.currencies, fn c ->
              String.upcase(c.code) == String.upcase(parsed.currency)
            end)

          if currency do
            socket
            |> assign(:modal_currency_id, currency.id)
            |> assign(:modal_currency, currency)
          else
            socket
          end
        else
          socket
        end

      assign(socket, :estimation_form, to_form(form_data, as: "estimation"))
    else
      socket
    end
  end

  defp reload_collaborators(socket, flash_msg) do
    project_id = socket.assigns.project.id
    org_id = socket.assigns.org_id
    collaborators = Portfolio.list_collaborators(project_id)
    available = Portfolio.list_available_members(project_id, org_id)

    socket
    |> put_flash(:info, flash_msg)
    |> assign(:collaborators, collaborators)
    |> assign(:available_members, available)
    |> assign(:selected_member, nil)
    |> assign(:member_search, "")
    |> assign(:selected_role, "viewer")
    |> assign(:show_member_dropdown, false)
  end

  ## Helpers

  defp can_remove_collaborator?(assigns, collab) do
    cond do
      collab.user_id == assigns.current_user.id ->
        false

      collab.role == "owner" ->
        assigns.current_collaborator && assigns.current_collaborator.role == "owner"

      true ->
        assigns.can_manage_collaborators
    end
  end

  defp can_change_role?(assigns, collab) do
    assigns.can_manage_collaborators && collab.user_id != assigns.current_user.id
  end

  defp format_hours_h(decimal) do
    if Decimal.compare(decimal, 0) == :eq do
      "0h"
    else
      "#{decimal |> Decimal.round(1) |> Decimal.to_string()}h"
    end
  end

end
