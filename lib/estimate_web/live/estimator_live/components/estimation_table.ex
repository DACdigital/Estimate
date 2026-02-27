defmodule EstimateWeb.EstimatorLive.Components.EstimationTable do
  use EstimateWeb, :html

  alias Estimate.EstimationEngine.Calculator

  import EstimateWeb.EstimatorLive.Helpers
  import EstimateWeb.EstimatorLive.Components.EstimateCell

  attr :estimation, :map, required: true
  attr :epics, :list, required: true
  attr :editing, :map, default: nil
  attr :editing_rate, :string, default: nil
  attr :can_edit, :boolean, required: true
  attr :show_all_in_rates, :boolean, required: true
  attr :show_descriptions, :boolean, required: true

  def estimation_table(assigns) do
    ~H"""
    <div class="bg-base-100 border border-base-300 rounded-xl overflow-hidden">
      <div class="overflow-x-auto">
        <table class="w-full">
          <thead>
            <tr class="bg-base-200 border-b border-base-content/10">
              <th class="px-6 py-2.5 text-left text-xs font-medium text-base-content/60 uppercase tracking-wider w-72 min-w-72">
                Task
              </th>
              <th
                :for={role <- @estimation.roles}
                class="px-3 py-2.5 text-center text-xs font-medium text-base-content/60 uppercase tracking-wider w-24 min-w-24"
              >
                <div class="relative group/role">
                  <div>{role.abbreviation}</div>
                  <span class="pointer-events-none absolute left-1/2 -translate-x-1/2 top-full mt-1 px-2 py-1 bg-neutral text-neutral-content text-[10px] font-normal normal-case rounded shadow-lg opacity-0 group-hover/role:opacity-100 transition-opacity whitespace-nowrap z-50">
                    {role.name}
                  </span>
                </div>
                <.rate_cell
                  role={role}
                  currency={@estimation.currency}
                  editing_rate={@editing_rate}
                  show_all_in_rates={@show_all_in_rates}
                  can_edit={@can_edit}
                />
              </th>
              <th class="px-4 py-2.5 text-center text-xs font-medium text-base-content/60 uppercase tracking-wider w-24">
                Hours
              </th>
              <th class="px-4 py-2.5 text-center text-xs font-medium text-base-content/60 uppercase tracking-wider w-28">
                Cost
              </th>
            </tr>
          </thead>
          <tbody id="epics-container" phx-hook={if @can_edit, do: "Sortable"} data-group="epics">
            <%= for epic <- @epics do %>
              <%!-- Epic Header Row --%>
              <tr class="bg-base-200 border-t border-base-content/10" data-id={epic.id}>
                <td colspan={length(@estimation.roles) + 3} class="px-6 py-3">
                  <div class="flex items-center justify-between">
                    <div class="flex items-center gap-3">
                      <span
                        :if={@can_edit}
                        class="cursor-move text-base-content/40 hover:text-base-content/70 drag-handle"
                      >
                        <.icon name="hero-bars-3" class="w-4 h-4" />
                      </span>
                      <%= if @can_edit do %>
                        <span
                          class="font-semibold text-base-content cursor-pointer hover:text-base-content/70"
                          phx-click="edit_epic"
                          phx-value-id={epic.id}
                        >
                          {epic.name}
                        </span>
                      <% else %>
                        <span class="font-semibold text-base-content">{epic.name}</span>
                      <% end %>
                    </div>
                    <div :if={@can_edit} class="flex items-center gap-3">
                      <button
                        phx-click="add_task"
                        phx-value-epic-id={epic.id}
                        class="text-sm text-base-content/60 hover:text-base-content transition-colors"
                      >
                        + Add Task
                      </button>
                      <button
                        phx-click="confirm_delete_epic"
                        phx-value-id={epic.id}
                        class="text-sm text-base-content/40 hover:text-error transition-colors"
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
                    <span
                      :if={@can_edit}
                      class="cursor-move text-base-content/30 hover:text-base-content/60 drag-handle opacity-0 group-hover:opacity-100 transition-opacity mt-1"
                    >
                      <.icon name="hero-bars-3" class="w-3 h-3" />
                    </span>
                    <span class="relative group/priority flex items-center mt-0.5">
                      <span class={"w-5 h-5 flex items-center justify-center text-[10px] rounded font-medium cursor-help #{priority_class(task.priority)}"}>
                        {String.first(priority_label(task.priority))}
                      </span>
                      <span class="pointer-events-none absolute left-0 bottom-full mb-2 w-48 px-3 py-2 bg-neutral text-neutral-content text-xs rounded-lg shadow-lg opacity-0 group-hover/priority:opacity-100 transition-opacity z-50">
                        <span class="font-semibold">{priority_label(task.priority)}</span>
                        <span class="block mt-1 text-neutral-content/60 leading-relaxed">
                          {priority_description(task.priority)}
                        </span>
                        <span class="absolute top-full left-3 border-4 border-transparent border-t-neutral">
                        </span>
                      </span>
                    </span>
                    <div class="min-w-0 flex-1">
                      <div class="flex items-center gap-2">
                        <%= if @can_edit do %>
                          <span
                            class="text-sm text-base-content/80 cursor-pointer hover:text-base-content"
                            phx-click="edit_task"
                            phx-value-id={task.id}
                          >
                            {task.name}
                          </span>
                          <button
                            phx-click="confirm_delete_task"
                            phx-value-id={task.id}
                            class="flex items-center text-base-content/30 hover:text-error opacity-0 group-hover:opacity-100 transition-opacity"
                          >
                            <.icon name="hero-trash" class="w-4 h-4" />
                          </button>
                        <% else %>
                          <span class="text-sm text-base-content/80">{task.name}</span>
                        <% end %>
                      </div>
                      <p
                        :if={@show_descriptions && task.description && task.description != ""}
                        class="text-xs text-base-content/40 leading-snug mt-0.5"
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
                    can_edit={@can_edit}
                  />
                </td>
                <td class="px-4 py-1.5 text-center text-sm font-mono text-base-content/70">
                  {format_hours(Calculator.task_total_hours(task))}
                </td>
                <td class="px-4 py-1.5 text-center text-sm font-mono text-base-content/70">
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
              <tr :if={length(epic.tasks) > 1} class="border-t border-base-content/10">
                <td class="px-6 py-1.5 text-right text-xs text-base-content/40">
                  Subtotal
                </td>
                <td
                  :for={role <- @estimation.roles}
                  class="px-3 py-1.5 text-center text-xs font-mono text-base-content/40"
                >
                  {format_hours(Calculator.epic_role_hours(epic, role.id))}
                </td>
                <td class="px-4 py-1.5 text-center text-sm font-mono text-base-content/60">
                  {format_hours(Calculator.epic_hours(epic))}
                </td>
                <td class="px-4 py-1.5 text-center text-sm font-mono text-base-content/60">
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
            <tr class="bg-neutral text-neutral-content">
              <td class="px-6 py-3 text-right font-semibold">
                Total
              </td>
              <td :for={role <- @estimation.roles} class="px-3 py-3 text-center text-sm font-mono">
                {format_hours(Calculator.role_hours(@epics, role.id))}
              </td>
              <td class="px-4 py-3 text-center font-mono font-bold">
                {format_hours(Calculator.calc_total_hours(@epics))}
              </td>
              <td class="px-4 py-3 text-center font-mono font-bold">
                {format_cost(
                  Calculator.calc_base_cost(
                    @epics,
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
      <%= if Enum.empty?(@epics) do %>
        <div class="px-6 py-16 text-center border-t border-base-300">
          <.icon name="hero-rectangle-stack" class="w-12 h-12 text-base-content/30 mx-auto" />
          <p class="mt-3 text-base-content/60">No epics yet</p>
          <p class="text-sm text-base-content/40 mt-1">Add your first epic to start estimating</p>
          <button
            :if={@can_edit}
            phx-click="add_epic"
            class="mt-4 px-4 py-2 bg-neutral text-neutral-content text-sm rounded-lg hover:bg-neutral/90 transition-colors font-medium"
          >
            Add Epic
          </button>
        </div>
      <% end %>
    </div>
    """
  end

  defp display_roles(roles, true), do: Calculator.roles_with_all_in_rates(roles)
  defp display_roles(roles, false), do: roles
end
