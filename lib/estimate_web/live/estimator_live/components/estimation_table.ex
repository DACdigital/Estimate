defmodule EstimateWeb.EstimatorLive.Components.EstimationTable do
  use EstimateWeb, :html

  import EstimateWeb.EstimatorLive.Helpers
  import EstimateWeb.EstimatorLive.Components.EstimateCell

  alias EstimateWeb.EstimatorLive.Rows

  attr :estimation, :map, required: true
  attr :rows, :any, required: true, doc: "the :rows stream"
  attr :totals, :map, required: true
  attr :grid_empty?, :boolean, required: true
  attr :editing, :string, default: nil
  attr :editing_rate, :string, default: nil
  attr :can_edit, :boolean, required: true
  attr :show_all_in_rates, :boolean, required: true
  attr :show_descriptions, :boolean, required: true

  def estimation_table(assigns) do
    ~H"""
    <div class="bg-base-100 border border-base-300 rounded-xl">
      <div class="overflow-auto max-h-[calc(100vh-12rem)] rounded-xl">
        <table class="w-full">
          <thead class="sticky top-0 z-20">
            <tr class="bg-base-200 border-b border-base-content/10">
              <th class="px-6 py-2.5 text-left text-xs font-medium text-base-content/60 uppercase tracking-wider w-72 min-w-72 sticky left-0 z-30 bg-base-200">
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
          <tbody
            id="epics-container"
            phx-update="stream"
            phx-hook={if @can_edit, do: "Sortable"}
            data-group="epics"
          >
            <.grid_row
              :for={{dom_id, row} <- @rows}
              id={dom_id}
              row={row}
              roles={@estimation.roles}
              currency={@estimation.currency}
              editing={@editing}
              can_edit={@can_edit}
              show_descriptions={@show_descriptions}
            />
          </tbody>
          <tfoot class="sticky bottom-0 z-20">
            <tr class="bg-neutral text-neutral-content">
              <td class="px-6 py-3 text-right font-semibold sticky left-0 z-10 bg-neutral">
                Total
              </td>
              <td :for={role <- @estimation.roles} class="px-3 py-3 text-center text-sm font-mono">
                {format_hours(Map.get(@totals.role_hours, role.id, Decimal.new(0)))}
              </td>
              <td class="px-4 py-3 text-center font-mono font-bold">
                {format_hours(@totals.total_hours)}
              </td>
              <td class="px-4 py-3 text-center font-mono font-bold">
                {format_cost(@totals.base_cost, @estimation.currency)}
              </td>
            </tr>
          </tfoot>
        </table>
      </div>

      <%!-- Empty State --%>
      <div :if={@grid_empty?} class="px-6 py-16 text-center border-t border-base-300">
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
    </div>
    """
  end

  attr :id, :string, required: true
  attr :row, :any, required: true
  attr :roles, :list, required: true
  attr :currency, :map, required: true
  attr :editing, :string, default: nil
  attr :can_edit, :boolean, required: true
  attr :show_descriptions, :boolean, required: true

  # One <tr> per stream item. The three clauses dispatch on the row struct.
  def grid_row(%{row: %Rows.EpicHeader{}} = assigns) do
    ~H"""
    <tr id={@id} class="bg-base-200 border-t border-base-content/10" data-id={@row.epic.id}>
      <td class="px-6 py-3 sticky left-0 z-10 bg-base-200 w-72 min-w-72">
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
              phx-value-id={@row.epic.id}
            >
              {@row.epic.name}
            </span>
          <% else %>
            <span class="font-semibold text-base-content">{@row.epic.name}</span>
          <% end %>
        </div>
      </td>
      <td colspan={length(@roles) + 2} class="px-6 py-3 bg-base-200 text-right">
        <div :if={@can_edit} class="flex items-center justify-end gap-3">
          <button
            phx-click="add_task"
            phx-value-epic-id={@row.epic.id}
            class="text-sm text-base-content/60 hover:text-base-content transition-colors"
          >
            + Add Task
          </button>
          <button
            phx-click="confirm_delete_epic"
            phx-value-id={@row.epic.id}
            class="text-sm text-base-content/40 hover:text-error transition-colors"
          >
            <.icon name="hero-trash" class="w-4 h-4" />
          </button>
        </div>
      </td>
    </tr>
    """
  end

  def grid_row(%{row: %Rows.Task{}} = assigns) do
    ~H"""
    <tr id={@id} class="group" data-id={@row.task.id} data-epic-id={@row.epic_id}>
      <td class="px-6 py-1.5 sticky left-0 z-10 bg-base-100">
        <div class="flex items-start gap-3">
          <span
            :if={@can_edit}
            class="cursor-move text-base-content/30 hover:text-base-content/60 drag-handle opacity-0 group-hover:opacity-100 transition-opacity mt-1"
          >
            <.icon name="hero-bars-3" class="w-3 h-3" />
          </span>
          <span class="relative group/priority flex items-center mt-0.5">
            <span class={"w-5 h-5 flex items-center justify-center text-[10px] rounded font-medium cursor-help #{priority_class(@row.task.priority)}"}>
              {String.first(priority_label(@row.task.priority))}
            </span>
            <span class="pointer-events-none absolute left-0 bottom-full mb-2 w-48 px-3 py-2 bg-neutral text-neutral-content text-xs rounded-lg shadow-lg opacity-0 group-hover/priority:opacity-100 transition-opacity z-50">
              <span class="font-semibold">{priority_label(@row.task.priority)}</span>
              <span class="block mt-1 text-neutral-content/60 leading-relaxed">
                {priority_description(@row.task.priority)}
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
                  phx-value-id={@row.task.id}
                >
                  {@row.task.name}
                </span>
                <button
                  phx-click="confirm_delete_task"
                  phx-value-id={@row.task.id}
                  class="flex items-center text-base-content/30 hover:text-error opacity-0 group-hover:opacity-100 transition-opacity"
                >
                  <.icon name="hero-trash" class="w-4 h-4" />
                </button>
              <% else %>
                <span class="text-sm text-base-content/80">{@row.task.name}</span>
              <% end %>
            </div>
            <p
              :if={@show_descriptions && @row.task.description && @row.task.description != ""}
              class="text-xs text-base-content/40 leading-snug mt-0.5"
            >
              {@row.task.description}
            </p>
          </div>
        </div>
      </td>
      <td :for={role <- @roles} class="px-2 py-1.5 text-center">
        <.estimate_cell
          task_id={@row.task.id}
          role_id={role.id}
          estimates={@row.task.estimates}
          editing={@editing}
          can_edit={@can_edit}
        />
      </td>
      <td class="px-4 py-1.5 text-center text-sm font-mono text-base-content/70">
        {format_hours(@row.total_hours)}
      </td>
      <td class="px-4 py-1.5 text-center text-sm font-mono text-base-content/70">
        {format_cost(@row.total_cost, @currency)}
      </td>
    </tr>
    """
  end

  def grid_row(%{row: %Rows.EpicSubtotal{}} = assigns) do
    ~H"""
    <tr id={@id} class="border-t border-base-content/10">
      <td class="px-6 py-1.5 text-right text-xs text-base-content/40 sticky left-0 z-10 bg-base-100">
        Subtotal
      </td>
      <td
        :for={role <- @roles}
        class="px-3 py-1.5 text-center text-xs font-mono text-base-content/40"
      >
        {format_hours(Map.get(@row.role_hours, role.id, Decimal.new(0)))}
      </td>
      <td class="px-4 py-1.5 text-center text-sm font-mono text-base-content/60">
        {format_hours(@row.epic_hours)}
      </td>
      <td class="px-4 py-1.5 text-center text-sm font-mono text-base-content/60">
        {format_cost(@row.epic_total_cost, @currency)}
      </td>
    </tr>
    """
  end
end
