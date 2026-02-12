defmodule EstimateWeb.EstimatorLive.Index do
  use EstimateWeb, :live_view

  alias Estimate.EstimationEngine
  alias Estimate.EstimationEngine.Calculator
  alias Estimate.Portfolio
  alias Estimate.Accounts

  import EstimateWeb.EstimatorLive.Helpers

  @impl true
  def render(assigns) do
    ~H"""
    <% epics = filtered_epics(@estimation, @enabled_priorities) %>
    <div class="max-w-7xl mx-auto">
      <%!-- Breadcrumb --%>
      <nav class="flex items-center space-x-2 text-sm text-gray-500 mb-6">
        <.link navigate={~p"/org/#{@org_id}/customers/#{@customer.id}"} class="hover:text-gray-900">
          {@customer.name}
        </.link>
        <span class="text-gray-300">›</span>
        <.link navigate={~p"/org/#{@org_id}/projects/#{@project.id}"} class="hover:text-gray-900">
          {@project.name}
        </.link>
        <span class="text-gray-300">›</span>
        <span class="text-gray-900 font-medium">{@estimation.name}</span>
        <span :if={@estimation.currency} class="text-gray-300 ml-2">•</span>
        <span :if={@estimation.currency} class="text-gray-400">{@estimation.currency.code}</span>
        <button
          phx-click="open_settings"
          class="ml-2 p-1 text-gray-400 hover:text-gray-600 hover:bg-gray-100 rounded transition-colors"
          title="Estimation settings"
        >
          <.icon name="hero-cog-6-tooth" class="w-4 h-4" />
        </button>
      </nav>

      <%!-- Actions --%>
      <div class="flex items-center justify-end gap-4 mb-4">
        <button
          phx-click="copy_json"
          class="text-xs text-gray-500 hover:text-gray-700 flex items-center gap-1.5"
          title="Copy as JSON"
        >
          <.icon name="hero-clipboard-document" class="w-4 h-4" /> Copy JSON
        </button>
        <button
          phx-click="open_save_as_template"
          class="text-xs text-gray-500 hover:text-gray-700 flex items-center gap-1.5"
          title="Save as estimation template"
        >
          <.icon name="hero-rectangle-stack" class="w-4 h-4" /> Save as Template
        </button>
        <button
          phx-click="toggle_all_in_rates"
          class="text-xs text-gray-500 hover:text-gray-700 flex items-center gap-1.5"
        >
          <span
            :if={@show_all_in_rates}
            class="w-4 h-4 rounded bg-gray-900 flex items-center justify-center"
          >
            <.icon name="hero-check" class="w-3 h-3 text-white" />
          </span>
          <span :if={!@show_all_in_rates} class="w-4 h-4 rounded border border-gray-300"></span>
          All-in rates
        </button>
        <button
          phx-click="toggle_descriptions"
          class="text-xs text-gray-500 hover:text-gray-700 flex items-center gap-1.5"
        >
          <span
            :if={@show_descriptions}
            class="w-4 h-4 rounded bg-gray-900 flex items-center justify-center"
          >
            <.icon name="hero-check" class="w-3 h-3 text-white" />
          </span>
          <span :if={!@show_descriptions} class="w-4 h-4 rounded border border-gray-300"></span>
          Show details
        </button>
        <div class="flex items-center gap-1" id="priority-filter" phx-hook="PriorityFilter" data-estimation-id={@estimation.id}>
          <button
            :for={{priority, label, active_cls, inactive_cls} <- [
              {"must", "M", "bg-red-600 text-white", "bg-red-100 text-red-300"},
              {"should", "S", "bg-amber-500 text-white", "bg-amber-100 text-amber-300"},
              {"could", "C", "bg-blue-600 text-white", "bg-blue-100 text-blue-300"},
              {"wont", "W", "bg-gray-600 text-white", "bg-gray-200 text-gray-400"}
            ]}
            phx-click="toggle_priority"
            phx-value-priority={priority}
            class={"w-6 h-6 rounded text-[10px] font-bold transition-all " <>
              if(MapSet.member?(@enabled_priorities, priority), do: active_cls, else: inactive_cls)}
            title={priority_label(priority)}
          >
            {label}
          </button>
        </div>
        <button
          phx-click="add_epic"
          class="px-4 py-2 bg-gray-900 text-white text-sm rounded-lg hover:bg-gray-800 transition-colors font-medium"
        >
          Add Epic
        </button>
      </div>

      <%!-- Estimation Table Card --%>
      <div class="bg-white border border-gray-200 rounded-xl overflow-hidden">
        <div class="overflow-x-auto">
          <table class="w-full">
            <thead>
              <tr class="bg-gray-50 border-b border-gray-100">
                <th class="px-6 py-2.5 text-left text-xs font-medium text-gray-500 uppercase tracking-wider w-72 min-w-72">
                  Task
                </th>
                <th
                  :for={role <- @estimation.roles}
                  class="px-3 py-2.5 text-center text-xs font-medium text-gray-500 uppercase tracking-wider w-24 min-w-24"
                >
                  <div class="relative group/role">
                    <div>{role.abbreviation}</div>
                    <span class="pointer-events-none absolute left-1/2 -translate-x-1/2 top-full mt-1 px-2 py-1 bg-gray-900 text-white text-[10px] font-normal normal-case rounded shadow-lg opacity-0 group-hover/role:opacity-100 transition-opacity whitespace-nowrap z-50">
                      {role.name}
                    </span>
                  </div>
                  <.rate_cell
                    role={role}
                    currency={@estimation.currency}
                    editing_rate={@editing_rate}
                    show_all_in_rates={@show_all_in_rates}
                  />
                </th>
                <th class="px-4 py-2.5 text-center text-xs font-medium text-gray-500 uppercase tracking-wider w-24">
                  Hours
                </th>
                <th class="px-4 py-2.5 text-center text-xs font-medium text-gray-500 uppercase tracking-wider w-28">
                  Cost
                </th>
              </tr>
            </thead>
            <tbody id="epics-container" phx-hook="Sortable" data-group="epics">
              <%= for epic <- epics do %>
                <%!-- Epic Header Row --%>
                <tr class="bg-gray-50 border-t border-gray-100" data-id={epic.id}>
                  <td colspan={length(@estimation.roles) + 3} class="px-6 py-3">
                    <div class="flex items-center justify-between">
                      <div class="flex items-center gap-3">
                        <span class="cursor-move text-gray-400 hover:text-gray-600 drag-handle">
                          <.icon name="hero-bars-3" class="w-4 h-4" />
                        </span>
                        <span
                          class="font-semibold text-gray-900 cursor-pointer hover:text-gray-600"
                          phx-click="edit_epic"
                          phx-value-id={epic.id}
                        >
                          {epic.name}
                        </span>
                      </div>
                      <div class="flex items-center gap-3">
                        <button
                          phx-click="add_task"
                          phx-value-epic-id={epic.id}
                          class="text-sm text-gray-500 hover:text-gray-900 transition-colors"
                        >
                          + Add Task
                        </button>
                        <button
                          phx-click="confirm_delete_epic"
                          phx-value-id={epic.id}
                          class="text-sm text-gray-400 hover:text-red-600 transition-colors"
                        >
                          <.icon name="hero-trash" class="w-4 h-4" />
                        </button>
                      </div>
                    </div>
                  </td>
                </tr>
                <%!-- Task Rows --%>
                <tr
                  :for={task <- epic.tasks}
                  class="group"
                  data-id={task.id}
                  data-epic-id={epic.id}
                >
                  <td class="px-6 py-1.5">
                    <div class="flex items-start gap-3">
                      <span class="cursor-move text-gray-300 hover:text-gray-500 drag-handle opacity-0 group-hover:opacity-100 transition-opacity mt-1">
                        <.icon name="hero-bars-3" class="w-3 h-3" />
                      </span>
                      <span class="relative group/priority flex items-center mt-0.5">
                        <span class={"w-5 h-5 flex items-center justify-center text-[10px] rounded font-medium cursor-help #{priority_class(task.priority)}"}>
                          {String.first(priority_label(task.priority))}
                        </span>
                        <span class="pointer-events-none absolute left-0 bottom-full mb-2 w-48 px-3 py-2 bg-gray-900 text-white text-xs rounded-lg shadow-lg opacity-0 group-hover/priority:opacity-100 transition-opacity z-50">
                          <span class="font-semibold">{priority_label(task.priority)}</span>
                          <span class="block mt-1 text-gray-300 leading-relaxed">
                            {priority_description(task.priority)}
                          </span>
                          <span class="absolute top-full left-3 border-4 border-transparent border-t-gray-900">
                          </span>
                        </span>
                      </span>
                      <div class="min-w-0 flex-1">
                        <div class="flex items-center gap-2">
                          <span
                            class="text-sm text-gray-700 cursor-pointer hover:text-gray-900"
                            phx-click="edit_task"
                            phx-value-id={task.id}
                          >
                            {task.name}
                          </span>
                          <button
                            phx-click="confirm_delete_task"
                            phx-value-id={task.id}
                            class="flex items-center text-gray-300 hover:text-red-500 opacity-0 group-hover:opacity-100 transition-opacity"
                          >
                            <.icon name="hero-x-mark" class="w-4 h-4" />
                          </button>
                        </div>
                        <p
                          :if={@show_descriptions && task.description && task.description != ""}
                          class="text-xs text-gray-400 leading-snug mt-0.5"
                        >
                          {task.description}
                        </p>
                      </div>
                    </div>
                  </td>
                  <td :for={role <- @estimation.roles} class="px-2 py-1.5 text-center">
                    <.estimate_cell
                      task_id={task.id}
                      role_id={role.id}
                      estimates={task.estimates}
                      editing={@editing}
                    />
                  </td>
                  <td class="px-4 py-1.5 text-center text-sm font-mono text-gray-600">
                    {format_hours(Calculator.task_total_hours(task))}
                  </td>
                  <td class="px-4 py-1.5 text-center text-sm font-mono text-gray-600">
                    {format_cost(
                      Calculator.task_total_cost(
                        task,
                        display_roles(@estimation.roles, @show_all_in_rates)
                      ),
                      @estimation.currency
                    )}
                  </td>
                </tr>
                <%!-- Epic Total Row (only shown if 2+ tasks) --%>
                <tr :if={length(epic.tasks) > 1} class="border-t border-gray-100">
                  <td class="px-6 py-1.5 text-right text-xs text-gray-400">
                    Subtotal
                  </td>
                  <td
                    :for={role <- @estimation.roles}
                    class="px-3 py-1.5 text-center text-xs font-mono text-gray-400"
                  >
                    {format_hours(Calculator.epic_role_hours(epic, role.id))}
                  </td>
                  <td class="px-4 py-1.5 text-center text-sm font-mono text-gray-500">
                    {format_hours(Calculator.epic_hours(epic))}
                  </td>
                  <td class="px-4 py-1.5 text-center text-sm font-mono text-gray-500">
                    {format_cost(
                      Calculator.epic_total_cost(
                        epic,
                        display_roles(@estimation.roles, @show_all_in_rates)
                      ),
                      @estimation.currency
                    )}
                  </td>
                </tr>
              <% end %>
            </tbody>
            <tfoot>
              <tr class="bg-gray-900 text-white">
                <td class="px-6 py-3 text-right font-semibold">
                  Total
                </td>
                <td :for={role <- @estimation.roles} class="px-3 py-3 text-center text-sm font-mono">
                  {format_hours(Calculator.role_hours(epics, role.id))}
                </td>
                <td class="px-4 py-3 text-center font-mono font-bold">
                  {format_hours(Calculator.calc_total_hours(epics))}
                </td>
                <td class="px-4 py-3 text-center font-mono font-bold">
                  {format_cost(
                    Calculator.calc_base_cost(
                      epics,
                      display_roles(@estimation.roles, @show_all_in_rates)
                    ),
                    @estimation.currency
                  )}
                </td>
              </tr>
            </tfoot>
          </table>
        </div>

        <%!-- Empty State --%>
        <%= if Enum.empty?(epics) do %>
          <div class="px-6 py-16 text-center border-t border-gray-200">
            <.icon name="hero-rectangle-stack" class="w-12 h-12 text-gray-300 mx-auto" />
            <p class="mt-3 text-gray-500">No epics yet</p>
            <p class="text-sm text-gray-400 mt-1">Add your first epic to start estimating</p>
            <button
              phx-click="add_epic"
              class="mt-4 px-4 py-2 bg-gray-900 text-white text-sm rounded-lg hover:bg-gray-800 transition-colors font-medium"
            >
              Add Epic
            </button>
          </div>
        <% end %>
      </div>

      <%!-- Cost Breakdown Panel (hidden when all-in rates enabled) --%>
      <%= if not Enum.empty?(epics) and not @show_all_in_rates do %>
        <div class="mt-6 bg-white border border-gray-200 rounded-xl overflow-hidden">
          <%!-- Collapsed state: single row with Grand Total --%>
          <div
            :if={!@show_breakdown}
            class="p-4 flex items-center justify-between cursor-pointer hover:bg-gray-50 transition-colors"
            phx-click="toggle_breakdown"
          >
            <span class="text-sm text-gray-500">Total with overheads</span>
            <div class="flex items-center gap-4">
              <span class="text-xl font-bold text-gray-900">
                {format_cost(
                  Calculator.grand_total_with_overhead(epics, @estimation.roles),
                  @estimation.currency
                )}
              </span>
              <.icon name="hero-chevron-down" class="w-5 h-5 text-gray-400" />
            </div>
          </div>

          <%!-- Expanded state: full breakdown --%>
          <div :if={@show_breakdown}>
            <div
              class="px-6 py-3 border-b border-gray-100 bg-gray-50 flex items-center justify-between cursor-pointer"
              phx-click="toggle_breakdown"
            >
              <h3 class="text-sm font-semibold text-gray-900">Cost Breakdown</h3>
              <.icon name="hero-chevron-up" class="w-5 h-5 text-gray-400" />
            </div>
            <div class="p-6">
              <div class="grid grid-cols-2 md:grid-cols-5 gap-4">
                <%!-- Base Cost --%>
                <div class="bg-gray-50 rounded-lg p-4">
                  <p class="text-xs font-medium text-gray-500 uppercase tracking-wide mb-1">
                    Base Cost
                  </p>
                  <p class="text-xl font-bold text-gray-900">
                    {format_cost(
                      Calculator.total_base_cost(epics, @estimation.roles),
                      @estimation.currency
                    )}
                  </p>
                  <p class="text-xs text-gray-400 mt-1">
                    {format_hours(Calculator.calc_total_hours(epics))} hours
                  </p>
                </div>

                <%!-- PM Overhead --%>
                <div class="bg-blue-50 rounded-lg p-4">
                  <p class="text-xs font-medium text-blue-600 uppercase tracking-wide mb-1">
                    PM Overhead
                  </p>
                  <p class="text-xl font-bold text-blue-900">
                    {format_cost(
                      Calculator.total_pm_overhead(epics, @estimation.roles),
                      @estimation.currency
                    )}
                  </p>
                  <p class="text-xs text-blue-400 mt-1">
                    ~{Calculator.weighted_avg_overhead(
                      epics,
                      @estimation.roles,
                      &Calculator.role_pm_overhead/2
                    )}%
                  </p>
                </div>

                <%!-- QA Overhead --%>
                <div class="bg-purple-50 rounded-lg p-4">
                  <p class="text-xs font-medium text-purple-600 uppercase tracking-wide mb-1">
                    QA Overhead
                  </p>
                  <p class="text-xl font-bold text-purple-900">
                    {format_cost(
                      Calculator.total_qa_overhead(epics, @estimation.roles),
                      @estimation.currency
                    )}
                  </p>
                  <p class="text-xs text-purple-400 mt-1">
                    ~{Calculator.weighted_avg_overhead(
                      epics,
                      @estimation.roles,
                      &Calculator.role_qa_overhead/2
                    )}%
                  </p>
                </div>

                <%!-- Risk Buffer --%>
                <div class="bg-amber-50 rounded-lg p-4">
                  <p class="text-xs font-medium text-amber-600 uppercase tracking-wide mb-1">
                    Risk Buffer
                  </p>
                  <p class="text-xl font-bold text-amber-900">
                    {format_cost(
                      Calculator.total_risk_buffer(epics, @estimation.roles),
                      @estimation.currency
                    )}
                  </p>
                  <p class="text-xs text-amber-400 mt-1">
                    ~{Calculator.weighted_avg_overhead(
                      epics,
                      @estimation.roles,
                      &Calculator.role_risk_buffer/2
                    )}%
                  </p>
                </div>

                <%!-- Grand Total --%>
                <div class="bg-gray-900 rounded-lg p-4">
                  <p class="text-xs font-medium text-gray-400 uppercase tracking-wide mb-1">
                    Grand Total
                  </p>
                  <p class="text-xl font-bold text-white">
                    {format_cost(
                      Calculator.grand_total_with_overhead(epics, @estimation.roles),
                      @estimation.currency
                    )}
                  </p>
                  <p class="text-xs text-gray-500 mt-1">incl. overheads</p>
                </div>
              </div>

              <%!-- Role breakdown table --%>
              <div class="mt-6 overflow-x-auto">
                <table class="w-full text-sm">
                  <thead>
                    <tr class="border-b border-gray-200">
                      <th class="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        Role
                      </th>
                      <th class="px-3 py-2 text-right text-xs font-medium text-gray-500 uppercase">
                        Hours
                      </th>
                      <th class="px-3 py-2 text-right text-xs font-medium text-gray-500 uppercase">
                        Base
                      </th>
                      <th class="px-3 py-2 text-right text-xs font-medium text-blue-500 uppercase">
                        PM %
                      </th>
                      <th class="px-3 py-2 text-right text-xs font-medium text-purple-500 uppercase">
                        QA %
                      </th>
                      <th class="px-3 py-2 text-right text-xs font-medium text-amber-500 uppercase">
                        Risk %
                      </th>
                      <th class="px-3 py-2 text-right text-xs font-medium text-gray-900 uppercase">
                        Total
                      </th>
                    </tr>
                  </thead>
                  <tbody class="divide-y divide-gray-100">
                    <%= for role <- @estimation.roles, Decimal.compare(Calculator.role_hours(epics, role.id), 0) == :gt do %>
                      <tr class="hover:bg-gray-50">
                        <td class="px-3 py-2 text-gray-900 font-medium">{role.name}</td>
                        <td class="px-3 py-2 text-right font-mono text-gray-600">
                          {format_hours(Calculator.role_hours(epics, role.id))}
                        </td>
                        <td class="px-3 py-2 text-right font-mono text-gray-600">
                          {format_cost(
                            Calculator.role_base_cost(epics, role),
                            @estimation.currency
                          )}
                        </td>
                        <td class="px-3 py-2 text-right font-mono text-blue-600">
                          <span class="text-gray-400 text-xs">{role.pm_overhead}%</span>
                          {format_cost(
                            Calculator.role_pm_overhead(epics, role),
                            @estimation.currency
                          )}
                        </td>
                        <td class="px-3 py-2 text-right font-mono text-purple-600">
                          <span class="text-gray-400 text-xs">{role.qa_overhead}%</span>
                          {format_cost(
                            Calculator.role_qa_overhead(epics, role),
                            @estimation.currency
                          )}
                        </td>
                        <td class="px-3 py-2 text-right font-mono text-amber-600">
                          <span class="text-gray-400 text-xs">{role.risk_buffer}%</span>
                          {format_cost(
                            Calculator.role_risk_buffer(epics, role),
                            @estimation.currency
                          )}
                        </td>
                        <td class="px-3 py-2 text-right font-mono font-semibold text-gray-900">
                          {format_cost(
                            Calculator.role_base_cost(epics, role)
                            |> Decimal.add(Calculator.role_pm_overhead(epics, role))
                            |> Decimal.add(Calculator.role_qa_overhead(epics, role))
                            |> Decimal.add(Calculator.role_risk_buffer(epics, role)),
                            @estimation.currency
                          )}
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                  <tfoot>
                    <tr class="border-t-2 border-gray-300 bg-gray-50 font-semibold">
                      <td class="px-3 py-2 text-gray-900">Total</td>
                      <td class="px-3 py-2 text-right font-mono text-gray-900">
                        {format_hours(Calculator.calc_total_hours(epics))}
                      </td>
                      <td class="px-3 py-2 text-right font-mono text-gray-900">
                        {format_cost(
                          Calculator.total_base_cost(epics, @estimation.roles),
                          @estimation.currency
                        )}
                      </td>
                      <td class="px-3 py-2 text-right font-mono text-blue-700">
                        {format_cost(
                          Calculator.total_pm_overhead(epics, @estimation.roles),
                          @estimation.currency
                        )}
                      </td>
                      <td class="px-3 py-2 text-right font-mono text-purple-700">
                        {format_cost(
                          Calculator.total_qa_overhead(epics, @estimation.roles),
                          @estimation.currency
                        )}
                      </td>
                      <td class="px-3 py-2 text-right font-mono text-amber-700">
                        {format_cost(
                          Calculator.total_risk_buffer(epics, @estimation.roles),
                          @estimation.currency
                        )}
                      </td>
                      <td class="px-3 py-2 text-right font-mono text-gray-900">
                        {format_cost(
                          Calculator.grand_total_with_overhead(epics, @estimation.roles),
                          @estimation.currency
                        )}
                      </td>
                    </tr>
                  </tfoot>
                </table>
              </div>
            </div>
          </div>
        </div>
      <% end %>

      <.modal :if={@modal == :epic} id="epic-modal" show on_cancel={JS.push("close_modal")}>
        <h2 class="text-xl font-semibold text-gray-900 mb-6">
          {if @epic_form.data.id, do: "Edit Epic", else: "New Epic"}
        </h2>
        <.form for={@epic_form} id="epic-form" phx-submit="save_epic">
          <div class="space-y-4">
            <div>
              <label class="block text-xs font-medium text-gray-500 mb-1.5">Epic Name *</label>
              <input
                type="text"
                name={@epic_form[:name].name}
                value={@epic_form[:name].value}
                placeholder="e.g. User Authentication"
                required
                class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent text-sm"
              />
            </div>
            <div>
              <label class="block text-xs font-medium text-gray-500 mb-1.5">Description</label>
              <textarea
                name={@epic_form[:description].name}
                rows="3"
                placeholder="Optional description..."
                class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent text-sm resize-none"
              ><%= @epic_form[:description].value %></textarea>
            </div>
          </div>
          <div class="mt-6 flex justify-end gap-3">
            <button
              type="button"
              phx-click="close_modal"
              class="px-4 py-2 text-sm text-gray-600 hover:text-gray-900 transition-colors"
            >
              Cancel
            </button>
            <button
              type="submit"
              phx-disable-with="Saving..."
              class="px-4 py-2 bg-gray-900 text-white text-sm rounded-lg hover:bg-gray-800 transition-colors font-medium"
            >
              {if @epic_form.data.id, do: "Save Changes", else: "Create Epic"}
            </button>
          </div>
        </.form>
      </.modal>

      <.modal :if={@modal == :task} id="task-modal" show on_cancel={JS.push("close_modal")}>
        <h2 class="text-xl font-semibold text-gray-900 mb-6">
          {if @task_form.data.id, do: "Edit Task", else: "New Task"}
        </h2>
        <.form for={@task_form} id="task-form" phx-submit="save_task" phx-change="validate_task">
          <div class="space-y-4">
            <div>
              <label class="block text-xs font-medium text-gray-500 mb-1.5">Task Name *</label>
              <input
                type="text"
                name={@task_form[:name].name}
                value={@task_form[:name].value}
                placeholder="e.g. Implement login form"
                required
                class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent text-sm"
              />
            </div>
            <div>
              <label class="block text-xs font-medium text-gray-500 mb-1.5">Priority (MoSCoW)</label>
              <div class="flex gap-2">
                <%= for p <- ["must", "should", "could", "wont"] do %>
                  <label class={"flex-1 text-center py-2 px-3 text-sm rounded-lg border cursor-pointer transition-colors #{if (@task_form[:priority].value || "must") == p, do: "bg-gray-900 text-white border-gray-900", else: "bg-white text-gray-600 border-gray-300 hover:border-gray-400"}"}>
                    <input
                      type="radio"
                      name={@task_form[:priority].name}
                      value={p}
                      checked={(@task_form[:priority].value || "must") == p}
                      class="sr-only"
                    />
                    {priority_label(p)}
                  </label>
                <% end %>
              </div>
            </div>
            <div>
              <label class="block text-xs font-medium text-gray-500 mb-1.5">Description</label>
              <textarea
                name={@task_form[:description].name}
                rows="2"
                placeholder="Optional description..."
                class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent text-sm resize-none"
              ><%= @task_form[:description].value %></textarea>
            </div>
          </div>
          <div class="mt-6 flex justify-end gap-3">
            <button
              type="button"
              phx-click="close_modal"
              class="px-4 py-2 text-sm text-gray-600 hover:text-gray-900 transition-colors"
            >
              Cancel
            </button>
            <button
              type="submit"
              phx-disable-with="Saving..."
              class="px-4 py-2 bg-gray-900 text-white text-sm rounded-lg hover:bg-gray-800 transition-colors font-medium"
            >
              {if @task_form.data.id, do: "Save Changes", else: "Create Task"}
            </button>
          </div>
        </.form>
      </.modal>

      <%!-- Delete Epic Modal --%>
      <.modal
        :if={@deleting_epic}
        id="delete-epic-modal"
        show
        on_cancel={JS.push("cancel_delete_epic")}
      >
        <div class="text-center">
          <div class="w-12 h-12 rounded-full bg-red-100 flex items-center justify-center mx-auto mb-4">
            <.icon name="hero-exclamation-triangle" class="w-6 h-6 text-red-600" />
          </div>
          <h3 class="text-lg font-semibold text-gray-900 mb-2">Delete Epic</h3>
          <p class="text-sm text-gray-500 mb-6">
            Are you sure you want to delete <span class="font-medium text-gray-900"><%= @deleting_epic.name %></span>?
            This will also delete all its tasks and estimates.
          </p>
          <div class="flex gap-3 justify-center">
            <button
              phx-click="cancel_delete_epic"
              class="px-4 py-2 text-sm text-gray-600 hover:text-gray-900 transition-colors"
            >
              Cancel
            </button>
            <button
              phx-click="delete_epic"
              class="px-4 py-2 bg-red-600 text-white text-sm rounded-lg hover:bg-red-700 transition-colors font-medium"
            >
              Delete
            </button>
          </div>
        </div>
      </.modal>

      <%!-- Delete Task Modal --%>
      <.modal
        :if={@deleting_task}
        id="delete-task-modal"
        show
        on_cancel={JS.push("cancel_delete_task")}
      >
        <div class="text-center">
          <div class="w-12 h-12 rounded-full bg-red-100 flex items-center justify-center mx-auto mb-4">
            <.icon name="hero-exclamation-triangle" class="w-6 h-6 text-red-600" />
          </div>
          <h3 class="text-lg font-semibold text-gray-900 mb-2">Delete Task</h3>
          <p class="text-sm text-gray-500 mb-6">
            Are you sure you want to delete <span class="font-medium text-gray-900"><%= @deleting_task.name %></span>?
          </p>
          <div class="flex gap-3 justify-center">
            <button
              phx-click="cancel_delete_task"
              class="px-4 py-2 text-sm text-gray-600 hover:text-gray-900 transition-colors"
            >
              Cancel
            </button>
            <button
              phx-click="delete_task"
              class="px-4 py-2 bg-red-600 text-white text-sm rounded-lg hover:bg-red-700 transition-colors font-medium"
            >
              Delete
            </button>
          </div>
        </div>
      </.modal>

      <%!-- Settings Modal --%>
      <.modal
        :if={@modal == :settings}
        id="settings-modal"
        show
        on_cancel={JS.push("close_modal")}
      >
        <h2 class="text-xl font-semibold text-gray-900 mb-6">Estimation Settings</h2>
        <.form for={@settings_form} id="settings-form" phx-submit="save_settings">
          <div class="space-y-6">
            <div class="grid grid-cols-2 gap-4">
              <div>
                <label class="block text-xs font-medium text-gray-500 mb-1.5">Estimation Name</label>
                <input
                  type="text"
                  name="name"
                  value={@estimation.name}
                  class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent text-sm"
                />
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
                      selected={@estimation.currency && currency.id == @estimation.currency.id}
                    >
                      {currency.code} - {currency.name} ({currency.symbol})
                    </option>
                  <% end %>
                </select>
              </div>
            </div>

            <%!-- Roles & Overheads --%>
            <div>
              <label class="block text-xs font-medium text-gray-500 mb-2">Roles & Overheads</label>
              <div class="border border-gray-200 rounded-lg overflow-hidden">
                <table class="w-full text-sm">
                  <thead>
                    <tr class="bg-gray-50 text-[11px] font-medium text-gray-500 uppercase tracking-wider">
                      <th class="px-3 py-2 text-left">Role</th>
                      <th class="px-3 py-2 text-right w-20">Rate</th>
                      <th class="px-3 py-2 text-right w-16">PM %</th>
                      <th class="px-3 py-2 text-right w-16">QA %</th>
                      <th class="px-3 py-2 text-right w-16">Risk %</th>
                    </tr>
                  </thead>
                  <tbody class="divide-y divide-gray-100">
                    <%= for role <- @estimation.roles do %>
                      <tr class="hover:bg-gray-50">
                        <td class="px-3 py-2">
                          <div class="flex items-center gap-2">
                            <span class="w-6 h-6 rounded bg-gradient-to-br from-indigo-500 to-purple-600 flex items-center justify-center text-white font-semibold text-[10px]">
                              {role.abbreviation}
                            </span>
                            <span class="text-gray-900">{role.name}</span>
                          </div>
                        </td>
                        <td class="px-3 py-2">
                          <input
                            type="number"
                            step="1"
                            min="0"
                            name={"roles[#{role.id}][hourly_rate]"}
                            value={format_percent(role.hourly_rate)}
                            class="w-full px-2 py-1 border border-gray-200 rounded text-sm font-mono text-right focus:outline-none focus:ring-1 focus:ring-gray-900 hover:border-gray-300"
                          />
                        </td>
                        <td class="px-3 py-2">
                          <input
                            type="number"
                            step="1"
                            min="0"
                            max="100"
                            name={"roles[#{role.id}][pm_overhead]"}
                            value={format_percent(role.pm_overhead)}
                            class="w-full px-2 py-1 border border-gray-200 rounded text-sm font-mono text-right focus:outline-none focus:ring-1 focus:ring-gray-900 hover:border-gray-300"
                          />
                        </td>
                        <td class="px-3 py-2">
                          <input
                            type="number"
                            step="1"
                            min="0"
                            max="100"
                            name={"roles[#{role.id}][qa_overhead]"}
                            value={format_percent(role.qa_overhead)}
                            class="w-full px-2 py-1 border border-gray-200 rounded text-sm font-mono text-right focus:outline-none focus:ring-1 focus:ring-gray-900 hover:border-gray-300"
                          />
                        </td>
                        <td class="px-3 py-2">
                          <input
                            type="number"
                            step="1"
                            min="0"
                            max="100"
                            name={"roles[#{role.id}][risk_buffer]"}
                            value={format_percent(role.risk_buffer)}
                            class="w-full px-2 py-1 border border-gray-200 rounded text-sm font-mono text-right focus:outline-none focus:ring-1 focus:ring-gray-900 hover:border-gray-300"
                          />
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>

              <%!-- Add Role Form --%>
              <div class="mt-3 flex items-center gap-2">
                <input
                  type="text"
                  name="new_role_name"
                  placeholder="Role name"
                  phx-keydown="add_estimation_role"
                  phx-key="Enter"
                  class="flex-1 px-2 py-1.5 border border-gray-200 rounded text-sm focus:outline-none focus:ring-1 focus:ring-gray-900 hover:border-gray-300"
                />
                <input
                  type="text"
                  name="new_role_abbr"
                  placeholder="ABBR"
                  maxlength="5"
                  phx-keydown="add_estimation_role"
                  phx-key="Enter"
                  class="w-16 px-2 py-1.5 border border-gray-200 rounded text-sm font-mono uppercase text-center focus:outline-none focus:ring-1 focus:ring-gray-900 hover:border-gray-300"
                />
                <button
                  type="button"
                  phx-click="add_estimation_role"
                  class="px-3 py-1.5 bg-gray-900 text-white text-sm rounded hover:bg-gray-800 transition-colors"
                >
                  Add
                </button>
              </div>

              <p class="text-xs text-gray-400 mt-1.5">
                Changes apply only to this estimation
              </p>
            </div>
          </div>
          <div class="mt-6 flex justify-end gap-3">
            <button
              type="button"
              phx-click="close_modal"
              class="px-4 py-2 text-sm text-gray-600 hover:text-gray-900 transition-colors"
            >
              Cancel
            </button>
            <button
              type="submit"
              phx-disable-with="Saving..."
              class="px-4 py-2 bg-gray-900 text-white text-sm rounded-lg hover:bg-gray-800 transition-colors font-medium"
            >
              Save
            </button>
          </div>
        </.form>
      </.modal>

      <%!-- Save as Template Modal --%>
      <.modal
        :if={@modal == :save_template}
        id="save-template-modal"
        show
        on_cancel={JS.push("close_modal")}
      >
        <h2 class="text-xl font-semibold text-gray-900 mb-4">Save as Template</h2>
        <p class="text-sm text-gray-500 mb-4">
          Save the epic & task structure as a reusable template. No hours or roles will be included.
        </p>
        <form phx-submit="save_as_template">
          <div>
            <label class="block text-xs font-medium text-gray-500 mb-1.5">Template Name *</label>
            <input
              type="text"
              name="template_name"
              value={@estimation.name}
              required
              autofocus
              class="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent"
            />
          </div>
          <div class="mt-6 flex justify-end gap-3">
            <button
              type="button"
              phx-click="close_modal"
              class="px-4 py-2 text-sm text-gray-600 hover:text-gray-900 transition-colors"
            >
              Cancel
            </button>
            <button
              type="submit"
              phx-disable-with="Saving..."
              class="px-4 py-2 bg-gray-900 text-white text-sm rounded-lg hover:bg-gray-800 transition-colors font-medium"
            >
              Save Template
            </button>
          </div>
        </form>
      </.modal>
    </div>
    """
  end

  attr :task_id, :string, required: true
  attr :role_id, :string, required: true
  attr :estimates, :list, required: true
  attr :editing, :map, required: true

  defp estimate_cell(assigns) do
    estimate = Enum.find(assigns.estimates, &(&1.estimation_role_id == assigns.role_id))
    hours = if estimate, do: estimate.hours, else: Decimal.new(0)

    editing_key = "#{assigns.task_id}-#{assigns.role_id}"
    is_editing = assigns.editing == editing_key

    assigns =
      assigns
      |> assign(:hours, hours)
      |> assign(:is_editing, is_editing)
      |> assign(:editing_key, editing_key)

    ~H"""
    <%= if @is_editing do %>
      <input
        type="number"
        step="0.5"
        min="0"
        value={if Decimal.compare(@hours, 0) == :eq, do: "", else: @hours}
        placeholder="0"
        phx-blur="save_estimate"
        phx-keydown="save_estimate"
        phx-key="Enter"
        phx-value-task-id={@task_id}
        phx-value-role-id={@role_id}
        phx-mounted={JS.focus()}
        class="w-16 h-8 text-center text-sm font-mono rounded bg-emerald-50 text-emerald-900 focus:outline-none"
        id={"hours-#{@editing_key}"}
      />
    <% else %>
      <button
        phx-click="edit_estimate"
        phx-value-key={@editing_key}
        class={"w-16 h-8 inline-flex items-center justify-center align-middle text-sm font-mono rounded cursor-pointer transition-colors #{if Decimal.compare(@hours, 0) == :eq, do: "text-gray-400 hover:bg-gray-50 hover:text-gray-500", else: "text-gray-900 bg-gray-50 hover:bg-gray-100"}"}
      >
        {format_hours(@hours)}
      </button>
    <% end %>
    """
  end

  attr :role, :map, required: true
  attr :currency, :map, required: true
  attr :editing_rate, :string, required: true
  attr :show_all_in_rates, :boolean, required: true

  defp rate_cell(assigns) do
    is_editing = assigns.editing_rate == assigns.role.id

    display_rate =
      if assigns.show_all_in_rates do
        Calculator.all_in_rate(assigns.role)
      else
        assigns.role.hourly_rate
      end

    assigns =
      assigns
      |> assign(:is_editing, is_editing)
      |> assign(:display_rate, display_rate)

    ~H"""
    <%= if @is_editing do %>
      <input
        type="number"
        step="1"
        min="0"
        value={@role.hourly_rate}
        phx-blur="save_rate"
        phx-keydown="save_rate"
        phx-key="Enter"
        phx-value-role-id={@role.id}
        class="w-12 text-center text-[10px] font-mono border border-gray-400 rounded bg-white focus:outline-none focus:border-gray-900"
        id={"rate-#{@role.id}"}
        autofocus
      />
    <% else %>
      <button
        phx-click="edit_rate"
        phx-value-role-id={@role.id}
        class={"text-[10px] font-mono font-normal normal-case hover:text-gray-600 cursor-pointer #{if @show_all_in_rates, do: "text-emerald-600", else: "text-gray-400"}"}
      >
        {format_rate(@display_rate, @currency)}
      </button>
    <% end %>
    """
  end

  @impl true
  def mount(%{"project_id" => project_id, "id" => id}, _session, socket) do
    org_id = socket.assigns.org_id
    user_id = socket.assigns.current_user.id
    membership_role = socket.assigns.current_membership.role

    collaborator = Portfolio.get_collaborator(project_id, user_id)

    unless membership_role in ["owner", "admin"] or collaborator do
      {:ok,
       socket
       |> Phoenix.LiveView.put_flash(:error, "You don't have access to this project.")
       |> Phoenix.LiveView.redirect(to: ~p"/org/#{org_id}/projects")}
    else
      project = Portfolio.get_project!(project_id, org_id)
      estimation = EstimationEngine.get_estimation!(id, org_id)
      currencies = Accounts.list_currencies(org_id)
      can_edit = can_edit?(collaborator, socket.assigns.current_membership)

      if connected?(socket) do
        EstimationEngine.subscribe(id)
      end

      {:ok,
       socket
       |> assign(:page_title, "Estimator - #{estimation.name}")
       |> assign(:active_tab, :projects)
       |> assign(:customer, project.customer)
       |> assign(:project, project)
       |> assign(:estimation, estimation)
       |> assign(:currencies, currencies)
       |> assign(:can_edit, can_edit)
       |> assign(:editing, nil)
       |> assign(:editing_rate, nil)
       |> assign(:modal, nil)
       |> assign(:settings_form, to_form(%{}))
       |> assign(:epic_form, nil)
       |> assign(:task_form, nil)
       |> assign(:current_epic_id, nil)
       |> assign(:deleting_epic, nil)
       |> assign(:deleting_task, nil)
       |> assign(:show_breakdown, false)
       |> assign(:show_all_in_rates, false)
       |> assign(:show_descriptions, false)
       |> assign(:enabled_priorities, MapSet.new(["must", "should", "could", "wont"]))}
    end
  end

  @impl true
  def handle_event("add_epic", _params, socket) do
    case authorize_edit(socket) do
      :ok ->
        changeset = EstimationEngine.Epic.changeset(%EstimationEngine.Epic{}, %{})

        {:noreply,
         socket
         |> assign(:modal, :epic)
         |> assign(:epic_form, to_form(changeset))}

      {:unauthorized, socket} ->
        {:noreply, socket}
    end
  end

  def handle_event("edit_epic", %{"id" => id}, socket) do
    epic = EstimationEngine.get_epic!(id, socket.assigns.org_id)
    changeset = EstimationEngine.Epic.changeset(epic, %{})

    {:noreply,
     socket
     |> assign(:modal, :epic)
     |> assign(:epic_form, to_form(changeset))}
  end

  def handle_event("save_epic", %{"epic" => epic_params}, socket) do
    case authorize_edit(socket) do
      :ok ->
        epic = socket.assigns.epic_form.data
        estimation = socket.assigns.estimation

        result =
          if epic.id do
            EstimationEngine.update_epic(epic, epic_params)
          else
            attrs = Map.put(epic_params, "estimation_id", estimation.id)
            EstimationEngine.create_epic(attrs)
          end

        case result do
          {:ok, _epic} ->
            estimation = EstimationEngine.get_estimation!(estimation.id, socket.assigns.org_id)

            {:noreply,
             socket
             |> assign(:estimation, estimation)
             |> assign(:modal, nil)
             |> assign(:epic_form, nil)}

          {:error, changeset} ->
            {:noreply, assign(socket, :epic_form, to_form(changeset))}
        end

      {:unauthorized, socket} ->
        {:noreply, socket}
    end
  end

  def handle_event("confirm_delete_epic", %{"id" => id}, socket) do
    epic = EstimationEngine.get_epic!(id, socket.assigns.org_id)
    {:noreply, assign(socket, :deleting_epic, epic)}
  end

  def handle_event("cancel_delete_epic", _params, socket) do
    {:noreply, assign(socket, :deleting_epic, nil)}
  end

  def handle_event("delete_epic", _params, socket) do
    case authorize_edit(socket) do
      :ok ->
        epic = socket.assigns.deleting_epic
        {:ok, _} = EstimationEngine.delete_epic(epic)

        estimation =
          EstimationEngine.get_estimation!(socket.assigns.estimation.id, socket.assigns.org_id)

        {:noreply,
         socket
         |> assign(:estimation, estimation)
         |> assign(:deleting_epic, nil)}

      {:unauthorized, socket} ->
        {:noreply, socket}
    end
  end

  def handle_event("add_task", %{"epic-id" => epic_id}, socket) do
    changeset = EstimationEngine.Task.changeset(%EstimationEngine.Task{}, %{})

    {:noreply,
     socket
     |> assign(:modal, :task)
     |> assign(:task_form, to_form(changeset))
     |> assign(:current_epic_id, epic_id)}
  end

  def handle_event("edit_task", %{"id" => id}, socket) do
    task = EstimationEngine.get_task!(id, socket.assigns.org_id)
    changeset = EstimationEngine.Task.changeset(task, %{})

    {:noreply,
     socket
     |> assign(:modal, :task)
     |> assign(:task_form, to_form(changeset))
     |> assign(:current_epic_id, task.epic_id)}
  end

  def handle_event("validate_task", %{"task" => task_params}, socket) do
    task = socket.assigns.task_form.data
    changeset = EstimationEngine.Task.changeset(task, task_params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, :task_form, to_form(changeset))}
  end

  def handle_event("save_task", %{"task" => task_params}, socket) do
    case authorize_edit(socket) do
      :ok ->
        task = socket.assigns.task_form.data
        epic_id = socket.assigns.current_epic_id

        result =
          if task.id do
            EstimationEngine.update_task(task, task_params)
          else
            attrs = Map.put(task_params, "epic_id", epic_id)
            EstimationEngine.create_task(attrs)
          end

        case result do
          {:ok, _task} ->
            estimation =
              EstimationEngine.get_estimation!(
                socket.assigns.estimation.id,
                socket.assigns.org_id
              )

            {:noreply,
             socket
             |> assign(:estimation, estimation)
             |> assign(:modal, nil)
             |> assign(:task_form, nil)
             |> assign(:current_epic_id, nil)}

          {:error, changeset} ->
            {:noreply, assign(socket, :task_form, to_form(changeset))}
        end

      {:unauthorized, socket} ->
        {:noreply, socket}
    end
  end

  def handle_event("confirm_delete_task", %{"id" => id}, socket) do
    task = EstimationEngine.get_task!(id, socket.assigns.org_id)
    {:noreply, assign(socket, :deleting_task, task)}
  end

  def handle_event("cancel_delete_task", _params, socket) do
    {:noreply, assign(socket, :deleting_task, nil)}
  end

  def handle_event("delete_task", _params, socket) do
    case authorize_edit(socket) do
      :ok ->
        task = socket.assigns.deleting_task
        {:ok, _} = EstimationEngine.delete_task(task)

        estimation =
          EstimationEngine.get_estimation!(socket.assigns.estimation.id, socket.assigns.org_id)

        {:noreply,
         socket
         |> assign(:estimation, estimation)
         |> assign(:deleting_task, nil)}

      {:unauthorized, socket} ->
        {:noreply, socket}
    end
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:modal, nil)
     |> assign(:epic_form, nil)
     |> assign(:task_form, nil)
     |> assign(:current_epic_id, nil)}
  end

  def handle_event("edit_estimate", %{"key" => key}, socket) do
    {:noreply, assign(socket, :editing, key)}
  end

  def handle_event("edit_rate", %{"role-id" => role_id}, socket) do
    {:noreply, assign(socket, :editing_rate, role_id)}
  end

  def handle_event("save_rate", %{"role-id" => role_id, "value" => value}, socket) do
    case authorize_edit(socket) do
      :ok ->
        org_id = socket.assigns.org_id
        role = EstimationEngine.get_role!(role_id, org_id)
        hourly_rate = parse_decimal(value)

        {:ok, updated_role} = EstimationEngine.update_role_rate(role, hourly_rate, org_id)

        estimation = update_role_in_memory(socket.assigns.estimation, updated_role)

        {:noreply,
         socket
         |> assign(:estimation, estimation)
         |> assign(:editing_rate, nil)}

      {:unauthorized, socket} ->
        {:noreply, assign(socket, :editing_rate, nil)}
    end
  end

  def handle_event("save_estimate", params, socket) do
    case authorize_edit(socket) do
      :ok ->
        %{"task-id" => task_id, "role-id" => role_id, "value" => value} = params

        hours = parse_decimal(value)

        {:ok, updated_estimate} =
          EstimationEngine.upsert_task_estimate(
            task_id,
            role_id,
            %{hours: hours},
            socket.assigns.estimation.id
          )

        estimation = update_estimate_in_memory(socket.assigns.estimation, updated_estimate)

        {:noreply,
         socket
         |> assign(:estimation, estimation)
         |> assign(:editing, nil)}

      {:unauthorized, socket} ->
        {:noreply, assign(socket, :editing, nil)}
    end
  end

  def handle_event("reorder_epics", %{"ids" => ids}, socket) do
    case authorize_edit(socket) do
      :ok ->
        EstimationEngine.reorder_epics(socket.assigns.estimation.id, ids)

        estimation =
          EstimationEngine.get_estimation!(socket.assigns.estimation.id, socket.assigns.org_id)

        {:noreply, assign(socket, :estimation, estimation)}

      {:unauthorized, socket} ->
        {:noreply, socket}
    end
  end

  def handle_event("reorder_tasks", %{"epic_id" => epic_id, "ids" => ids}, socket) do
    case authorize_edit(socket) do
      :ok ->
        EstimationEngine.reorder_tasks(epic_id, ids)

        estimation =
          EstimationEngine.get_estimation!(socket.assigns.estimation.id, socket.assigns.org_id)

        {:noreply, assign(socket, :estimation, estimation)}

      {:unauthorized, socket} ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_breakdown", _params, socket) do
    {:noreply, assign(socket, :show_breakdown, !socket.assigns.show_breakdown)}
  end

  def handle_event("copy_json", _params, socket) do
    estimation = socket.assigns.estimation
    dr = display_roles(estimation.roles, socket.assigns.show_all_in_rates)
    filtered = filtered_epics(estimation, socket.assigns.enabled_priorities)

    json =
      build_json_export(
        %{estimation | epics: filtered},
        dr,
        socket.assigns.customer,
        socket.assigns.project
      )

    {:noreply,
     socket
     |> push_event("copy_to_clipboard", %{text: json})
     |> put_flash(:info, "Copied!")}
  end

  def handle_event("toggle_all_in_rates", _params, socket) do
    {:noreply, assign(socket, :show_all_in_rates, !socket.assigns.show_all_in_rates)}
  end

  def handle_event("toggle_descriptions", _params, socket) do
    {:noreply, assign(socket, :show_descriptions, !socket.assigns.show_descriptions)}
  end

  def handle_event("toggle_priority", %{"priority" => priority}, socket) do
    current = socket.assigns.enabled_priorities

    updated =
      if MapSet.member?(current, priority) and MapSet.size(current) > 1,
        do: MapSet.delete(current, priority),
        else: MapSet.put(current, priority)

    {:noreply,
     socket
     |> assign(:enabled_priorities, updated)
     |> push_event("save_priorities", %{priorities: MapSet.to_list(updated)})}
  end

  def handle_event("restore_priorities", %{"priorities" => priorities}, socket) do
    valid = MapSet.intersection(MapSet.new(priorities), MapSet.new(["must", "should", "could", "wont"]))

    if MapSet.size(valid) > 0,
      do: {:noreply, assign(socket, :enabled_priorities, valid)},
      else: {:noreply, socket}
  end

  def handle_event("open_settings", _params, socket) do
    {:noreply, assign(socket, :modal, :settings)}
  end

  def handle_event("open_save_as_template", _params, socket) do
    {:noreply, assign(socket, :modal, :save_template)}
  end

  def handle_event("save_as_template", %{"template_name" => name}, socket) when name != "" do
    estimation = socket.assigns.estimation
    org_id = socket.assigns.org_id

    case Estimate.Templates.create_from_estimation(org_id, name, estimation) do
      {:ok, _template} ->
        {:noreply,
         socket
         |> assign(:modal, nil)
         |> put_flash(:info, "Template saved")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not save template")}
    end
  end

  def handle_event("save_as_template", _params, socket), do: {:noreply, socket}

  def handle_event(
        "add_estimation_role",
        %{"new_role_name" => name, "new_role_abbr" => abbr},
        socket
      )
      when name != "" and abbr != "" do
    case authorize_edit(socket) do
      :ok ->
        estimation = socket.assigns.estimation
        position = length(estimation.roles)

        attrs = %{
          name: name,
          abbreviation: String.upcase(abbr),
          estimation_id: estimation.id,
          position: position,
          hourly_rate: Decimal.new(0),
          pm_overhead: Decimal.new(0),
          qa_overhead: Decimal.new(0),
          risk_buffer: Decimal.new(0)
        }

        case EstimationEngine.create_role(attrs) do
          {:ok, _role} ->
            estimation = EstimationEngine.get_estimation!(estimation.id, socket.assigns.org_id)

            {:noreply, assign(socket, :estimation, estimation) |> put_flash(:info, "Role added")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not add role")}
        end

      {:unauthorized, socket} ->
        {:noreply, socket}
    end
  end

  def handle_event("add_estimation_role", _params, socket), do: {:noreply, socket}

  def handle_event("save_settings", _params, %{assigns: %{can_edit: false}} = socket) do
    {:noreply, put_flash(socket, :error, "You don't have edit access")}
  end

  def handle_event("save_settings", params, socket) do
    estimation = socket.assigns.estimation
    org_id = socket.assigns.org_id

    # Update estimation attrs
    attrs = %{
      "name" => params["name"],
      "currency_id" => params["currency_id"]
    }

    # Update each role's rate and overheads
    roles_params = params["roles"] || %{}

    Enum.each(roles_params, fn {role_id, role_attrs} ->
      role = EstimationEngine.get_role!(role_id, org_id)

      EstimationEngine.update_role(role, %{
        hourly_rate: parse_decimal(role_attrs["hourly_rate"]),
        pm_overhead: parse_decimal(role_attrs["pm_overhead"]),
        qa_overhead: parse_decimal(role_attrs["qa_overhead"]),
        risk_buffer: parse_decimal(role_attrs["risk_buffer"])
      })
    end)

    case EstimationEngine.update_estimation(estimation, attrs) do
      {:ok, _} ->
        estimation = EstimationEngine.get_estimation!(estimation.id, org_id)

        {:noreply,
         socket
         |> assign(:estimation, estimation)
         |> assign(:modal, nil)
         |> put_flash(:info, "Settings saved")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not save settings")}
    end
  end

  @impl true
  def handle_info({:estimation_updated, _estimation}, socket) do
    estimation =
      EstimationEngine.get_estimation!(socket.assigns.estimation.id, socket.assigns.org_id)

    {:noreply, assign(socket, :estimation, estimation)}
  end

  def handle_info({:tasks_reordered, _epic_id, _task_ids}, socket) do
    estimation =
      EstimationEngine.get_estimation!(socket.assigns.estimation.id, socket.assigns.org_id)

    {:noreply, assign(socket, :estimation, estimation)}
  end

  def handle_info({event, _data}, socket)
      when event in [
             :epic_created,
             :epic_updated,
             :epic_deleted,
             :epics_reordered,
             :task_created,
             :task_updated,
             :task_deleted,
             :estimate_updated,
             :role_created,
             :role_updated,
             :role_deleted
           ] do
    estimation =
      EstimationEngine.get_estimation!(socket.assigns.estimation.id, socket.assigns.org_id)

    {:noreply, assign(socket, :estimation, estimation)}
  end

  defp filtered_epics(estimation, enabled_priorities) do
    if MapSet.size(enabled_priorities) == 4 do
      estimation.epics
    else
      estimation.epics
      |> Enum.map(fn epic ->
        %{epic | tasks: Enum.filter(epic.tasks, &MapSet.member?(enabled_priorities, &1.priority || "must"))}
      end)
      |> Enum.reject(&Enum.empty?(&1.tasks))
    end
  end

  defp can_edit?(collaborator, membership) do
    collab_role = if collaborator, do: collaborator.role, else: nil
    membership_role = if membership, do: membership.role, else: nil

    collab_role in ["owner", "editor"] or membership_role in ["owner", "admin"]
  end

  defp authorize_edit(socket) do
    if socket.assigns.can_edit do
      :ok
    else
      {:unauthorized, put_flash(socket, :error, "You don't have edit access")}
    end
  end

  defp display_roles(roles, true), do: Calculator.roles_with_all_in_rates(roles)
  defp display_roles(roles, false), do: roles

  defp update_estimate_in_memory(estimation, updated_estimate) do
    epics =
      Enum.map(estimation.epics, fn epic ->
        tasks =
          Enum.map(epic.tasks, fn task ->
            if task.id == updated_estimate.task_id do
              estimates =
                case Enum.find_index(task.estimates, &(&1.id == updated_estimate.id)) do
                  nil -> [updated_estimate | task.estimates]
                  idx -> List.replace_at(task.estimates, idx, updated_estimate)
                end

              %{task | estimates: estimates}
            else
              task
            end
          end)

        %{epic | tasks: tasks}
      end)

    %{estimation | epics: epics}
  end

  defp update_role_in_memory(estimation, updated_role) do
    roles =
      Enum.map(estimation.roles, fn role ->
        if role.id == updated_role.id, do: updated_role, else: role
      end)

    %{estimation | roles: roles}
  end
end
