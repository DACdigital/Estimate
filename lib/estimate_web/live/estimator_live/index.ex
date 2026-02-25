defmodule EstimateWeb.EstimatorLive.Index do
  use EstimateWeb, :live_view

  alias Estimate.EstimationEngine
  alias Estimate.EstimationEngine.Calculator
  alias Estimate.Portfolio
  alias Estimate.Organizations
  alias Estimate.Organizations.Currencies

  import EstimateWeb.EstimatorLive.Helpers
  import EstimateWeb.EstimatorLive.Components.EstimateCell
  import EstimateWeb.EstimatorLive.Components.CostBreakdown
  import EstimateWeb.EstimatorLive.Components.EstimatorModals

  @impl true
  def render(assigns) do
    ~H"""
    <% epics = filtered_epics(@estimation, @enabled_priorities) %>
    <div class="max-w-7xl mx-auto">
      <%!-- Breadcrumb --%>
      <nav class="flex items-center space-x-2 text-sm text-base-content/60 mb-6">
        <.link navigate={~p"/org/#{@org_id}/customers/#{@customer.id}"} class="hover:text-base-content">
          {@customer.name}
        </.link>
        <span class="text-base-content/30">›</span>
        <.link navigate={~p"/org/#{@org_id}/projects/#{@project.id}"} class="hover:text-base-content">
          {@project.name}
        </.link>
        <span class="text-base-content/30">›</span>
        <span class="text-base-content font-medium">{@estimation.name}</span>
        <span :if={@estimation.currency} class="text-base-content/30 ml-2">•</span>
        <span :if={@estimation.currency} class="text-base-content/40">{@estimation.currency.code}</span>
        <button
          :if={@can_edit}
          phx-click="open_settings"
          class="ml-2 p-1 text-base-content/40 hover:text-base-content/70 hover:bg-base-300 rounded transition-colors"
          title="Estimation settings"
        >
          <.icon name="hero-cog-6-tooth" class="w-4 h-4" />
        </button>
      </nav>

      <%!-- Actions --%>
      <div class="flex items-center justify-end gap-4 mb-4">
        <button
          phx-click="copy_json"
          class="text-xs text-base-content/60 hover:text-base-content/80 flex items-center gap-1.5"
          title="Copy as JSON"
        >
          <.icon name="hero-clipboard-document" class="w-4 h-4" /> Copy JSON
        </button>
        <button
          :if={@can_edit}
          phx-click="open_save_as_template"
          class="text-xs text-base-content/60 hover:text-base-content/80 flex items-center gap-1.5"
          title="Save as estimation template"
        >
          <.icon name="hero-rectangle-stack" class="w-4 h-4" /> Save as Template
        </button>
        <button
          phx-click="toggle_all_in_rates"
          class="text-xs text-base-content/60 hover:text-base-content/80 flex items-center gap-1.5"
        >
          <span
            :if={@show_all_in_rates}
            class="w-4 h-4 rounded bg-neutral flex items-center justify-center"
          >
            <.icon name="hero-check" class="w-3 h-3 text-neutral-content" />
          </span>
          <span :if={!@show_all_in_rates} class="w-4 h-4 rounded border border-base-content/20"></span>
          All-in rates
        </button>
        <button
          phx-click="toggle_descriptions"
          class="text-xs text-base-content/60 hover:text-base-content/80 flex items-center gap-1.5"
        >
          <span
            :if={@show_descriptions}
            class="w-4 h-4 rounded bg-neutral flex items-center justify-center"
          >
            <.icon name="hero-check" class="w-3 h-3 text-neutral-content" />
          </span>
          <span :if={!@show_descriptions} class="w-4 h-4 rounded border border-base-content/20"></span>
          Show details
        </button>
        <div
          class="flex items-center gap-1"
          id="priority-filter"
          phx-hook="PriorityFilter"
          data-estimation-id={@estimation.id}
        >
          <button
            :for={
              {priority, label, active_cls, inactive_cls} <- [
                {"must", "M", "bg-error text-error-content",
                  "bg-error/10 dark:bg-error/20 text-error/30 dark:text-error/60"},
                {"should", "S", "bg-warning text-warning-content",
                  "bg-warning/10 dark:bg-warning/20 text-warning/30 dark:text-warning/60"},
                {"could", "C", "bg-info text-info-content",
                  "bg-info/10 dark:bg-info/20 text-info/30 dark:text-info/60"},
                {"wont", "W", "bg-neutral text-neutral-content", "bg-base-300 text-base-content/40"}
              ]
            }
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
          :if={@can_edit}
          phx-click="add_epic"
          class="px-4 py-2 bg-neutral text-neutral-content text-sm rounded-lg hover:bg-neutral/90 transition-colors font-medium"
        >
          Add Epic
        </button>
      </div>

      <%!-- Estimation Table Card --%>
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
              <%= for epic <- epics do %>
                <%!-- Epic Header Row --%>
                <tr class="bg-base-200 border-t border-base-content/10" data-id={epic.id}>
                  <td colspan={length(@estimation.roles) + 3} class="px-6 py-3">
                    <div class="flex items-center justify-between">
                      <div class="flex items-center gap-3">
                        <span :if={@can_edit} class="cursor-move text-base-content/40 hover:text-base-content/70 drag-handle">
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
                      <span :if={@can_edit} class="cursor-move text-base-content/30 hover:text-base-content/60 drag-handle opacity-0 group-hover:opacity-100 transition-opacity mt-1">
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
                              <.icon name="hero-x-mark" class="w-4 h-4" />
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

      <%!-- Cost Breakdown Panel (hidden when all-in rates enabled) --%>
      <.cost_breakdown
        :if={not Enum.empty?(epics) and not @show_all_in_rates}
        epics={epics}
        roles={@estimation.roles}
        currency={@estimation.currency}
        show_breakdown={@show_breakdown}
      />

      <.estimator_modals
        modal={@modal}
        epic_form={@epic_form}
        task_form={@task_form}
        settings_form={@settings_form}
        deleting_epic={@deleting_epic}
        deleting_task={@deleting_task}
        estimation={@estimation}
        currencies={@currencies}
        ai_configured={@ai_configured}
        ai_loading={@ai_loading}
      />
    </div>
    """
  end

  @impl true
  def mount(%{"project_id" => project_id, "id" => id}, _session, socket) do
    org_id = socket.assigns.org_id
    user_id = socket.assigns.current_user.id
    collaborator = Portfolio.get_collaborator(project_id, user_id)

    unless admin?(socket.assigns.current_membership) or collaborator do
      {:ok,
       socket
       |> Phoenix.LiveView.put_flash(:error, "You don't have access to this project.")
       |> Phoenix.LiveView.redirect(to: ~p"/org/#{org_id}/projects")}
    else
      project = Portfolio.get_project!(project_id, org_id)
      estimation = EstimationEngine.get_estimation!(id, org_id)
      currencies = Currencies.list_currencies(org_id)
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
       |> assign(:enabled_priorities, MapSet.new(["must", "should", "could", "wont"]))
       |> assign(:ai_configured, socket.assigns.current_organization.encrypted_openrouter_api_key != nil)
       |> assign(:ai_loading, nil)}
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
    valid =
      MapSet.intersection(MapSet.new(priorities), MapSet.new(["must", "should", "could", "wont"]))

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

  def handle_event("save_settings", params, socket) do
    case authorize_edit(socket) do
      {:unauthorized, socket} ->
        {:noreply, socket}

      :ok ->
        estimation = socket.assigns.estimation
        org_id = socket.assigns.org_id

        attrs = %{
          "name" => params["name"],
          "currency_id" => params["currency_id"]
        }

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
  end

  def handle_event("ai_enhance_description", %{"description" => desc, "name" => name, "target" => target}, socket) do
    org = socket.assigns.current_organization
    api_key = Organizations.get_decrypted_api_key(org)

    if api_key do
      pid = self()
      model = org.openrouter_model || "openai/gpt-4o-mini"
      system_prompt = org.openrouter_system_prompt

      Task.start(fn ->
        result = Estimate.AI.OpenRouter.enhance_description(api_key, model, system_prompt, name, desc)
        send(pid, {:ai_result, target, result})
      end)

      {:noreply, assign(socket, :ai_loading, target)}
    else
      {:noreply, put_flash(socket, :error, "AI not configured")}
    end
  end

  @impl true
  def handle_info({:ai_result, target, {:ok, enhanced}}, socket) do
    {:noreply,
     socket
     |> assign(:ai_loading, nil)
     |> push_event("ai_set_description", %{text: enhanced, target: target})}
  end

  def handle_info({:ai_result, _target, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:ai_loading, nil)
     |> put_flash(:error, "AI error: #{reason}")}
  end

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
        %{
          epic
          | tasks:
              Enum.filter(epic.tasks, &MapSet.member?(enabled_priorities, &1.priority || "must"))
        }
      end)
      |> Enum.reject(&Enum.empty?(&1.tasks))
    end
  end

  defp can_edit?(collaborator, membership) do
    collab_role = if collaborator, do: collaborator.role, else: nil
    collab_role in ["owner", "editor"] or admin?(membership)
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
