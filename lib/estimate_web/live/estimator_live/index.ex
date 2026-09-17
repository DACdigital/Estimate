defmodule EstimateWeb.EstimatorLive.Index do
  use EstimateWeb, :live_view

  alias Estimate.EstimationEngine
  alias Estimate.Portfolio
  alias Estimate.Organizations
  alias Estimate.Organizations.Currencies
  alias EstimateWeb.EstimatorLive.{Epics, Estimates, Export, Settings, Tasks, ViewState}

  import EstimateWeb.EstimatorLive.Helpers
  import EstimateWeb.EstimatorLive.Components.CostBreakdown
  import EstimateWeb.EstimatorLive.Components.EstimatorModals
  import EstimateWeb.EstimatorLive.Components.EstimationTable
  import EstimateWeb.EstimatorLive.Authz

  @impl true
  def render(assigns) do
    ~H"""
    <% epics = ViewState.filtered_epics(@estimation, @enabled_priorities) %>
    <div class="max-w-7xl mx-auto">
      <%!-- Breadcrumb --%>
      <nav class="flex items-center space-x-2 text-sm text-base-content/60 mb-6">
        <.link
          navigate={~p"/org/#{@org_id}/customers/#{@customer.id}"}
          class="hover:text-base-content"
        >
          {@customer.name}
        </.link>
        <span class="text-base-content/30">›</span>
        <.link navigate={~p"/org/#{@org_id}/projects/#{@project.id}"} class="hover:text-base-content">
          {@project.name}
        </.link>
        <span class="text-base-content/30">›</span>
        <span class="text-base-content font-medium">{@estimation.name}</span>
        <span :if={@estimation.currency} class="text-base-content/30 ml-2">•</span>
        <span :if={@estimation.currency} class="text-base-content/40">
          {@estimation.currency.code}
        </span>
        <button
          :if={@can_edit}
          phx-click="open_settings"
          class="ml-2 text-base-content/40 hover:text-base-content/70 transition-colors"
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
          <span :if={!@show_all_in_rates} class="w-4 h-4 rounded border border-base-content/20">
          </span>
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
          <span :if={!@show_descriptions} class="w-4 h-4 rounded border border-base-content/20">
          </span>
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

      <.estimation_table
        estimation={@estimation}
        epics={epics}
        editing={@editing}
        editing_rate={@editing_rate}
        can_edit={@can_edit}
        show_all_in_rates={@show_all_in_rates}
        show_descriptions={@show_descriptions}
      />

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
        deleting_role_id={@deleting_role_id}
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

      unless estimation.project_id == project_id do
        raise Ecto.NoResultsError, queryable: Estimate.EstimationEngine.Estimation
      end

      currencies = Currencies.list_currencies(org_id)
      can_edit = can_edit_project?(socket.assigns.current_membership, collaborator)

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
       |> assign(:deleting_role_id, nil)
       |> assign(:show_breakdown, false)
       |> assign(:show_all_in_rates, false)
       |> assign(:show_descriptions, false)
       |> assign(:enabled_priorities, MapSet.new(["must", "should", "could", "wont"]))
       |> assign(
         :ai_configured,
         socket.assigns.current_organization.encrypted_openrouter_api_key != nil
       )
       |> assign(:ai_loading, nil)}
    end
  end

  @impl true
  def handle_event("add_epic", params, socket), do: Epics.add_epic(socket, params)
  def handle_event("edit_epic", params, socket), do: Epics.edit_epic(socket, params)
  def handle_event("save_epic", params, socket), do: Epics.save_epic(socket, params)

  def handle_event("confirm_delete_epic", params, socket),
    do: Epics.confirm_delete_epic(socket, params)

  def handle_event("cancel_delete_epic", params, socket),
    do: Epics.cancel_delete_epic(socket, params)

  def handle_event("delete_epic", params, socket), do: Epics.delete_epic(socket, params)

  def handle_event("add_task", params, socket), do: Tasks.add_task(socket, params)

  def handle_event("edit_task", params, socket), do: Tasks.edit_task(socket, params)

  def handle_event("validate_task", params, socket), do: Tasks.validate_task(socket, params)

  def handle_event("save_task", params, socket), do: Tasks.save_task(socket, params)

  def handle_event("confirm_delete_task", params, socket),
    do: Tasks.confirm_delete_task(socket, params)

  def handle_event("cancel_delete_task", params, socket),
    do: Tasks.cancel_delete_task(socket, params)

  def handle_event("delete_task", params, socket), do: Tasks.delete_task(socket, params)

  def handle_event("close_modal", params, socket), do: ViewState.close_modal(socket, params)

  def handle_event("cancel_edit", params, socket), do: Estimates.cancel_edit(socket, params)

  def handle_event("edit_estimate", params, socket), do: Estimates.edit_estimate(socket, params)

  def handle_event("edit_rate", params, socket), do: Estimates.edit_rate(socket, params)

  def handle_event("save_rate", params, socket), do: Estimates.save_rate(socket, params)

  def handle_event("save_estimate", params, socket), do: Estimates.save_estimate(socket, params)

  def handle_event("reorder_epics", params, socket), do: Epics.reorder_epics(socket, params)

  def handle_event("reorder_tasks", params, socket), do: Tasks.reorder_tasks(socket, params)

  def handle_event("toggle_breakdown", params, socket),
    do: ViewState.toggle_breakdown(socket, params)

  def handle_event("copy_json", params, socket), do: Export.copy_json(socket, params)

  def handle_event("toggle_all_in_rates", params, socket),
    do: ViewState.toggle_all_in_rates(socket, params)

  def handle_event("toggle_descriptions", params, socket),
    do: ViewState.toggle_descriptions(socket, params)

  def handle_event("toggle_priority", params, socket),
    do: ViewState.toggle_priority(socket, params)

  def handle_event("restore_priorities", params, socket),
    do: ViewState.restore_priorities(socket, params)

  def handle_event("open_settings", params, socket), do: Settings.open_settings(socket, params)

  def handle_event("open_save_as_template", params, socket),
    do: Export.open_save_as_template(socket, params)

  def handle_event("save_as_template", params, socket),
    do: Export.save_as_template(socket, params)

  def handle_event("add_estimation_role", params, socket),
    do: Settings.add_estimation_role(socket, params)

  def handle_event("save_settings", params, socket), do: Settings.save_settings(socket, params)

  def handle_event("confirm_delete_role", params, socket),
    do: Settings.confirm_delete_role(socket, params)

  def handle_event("cancel_delete_role", params, socket),
    do: Settings.cancel_delete_role(socket, params)

  def handle_event("delete_estimation_role", params, socket),
    do: Settings.delete_estimation_role(socket, params)

  def handle_event("reorder_roles", params, socket), do: Settings.reorder_roles(socket, params)

  def handle_event(
        "ai_enhance_description",
        %{"description" => desc, "name" => name, "target" => target},
        socket
      ) do
    with_edit_auth(socket, fn socket ->
      org = socket.assigns.current_organization
      api_key = Organizations.get_decrypted_api_key(org)

      if api_key do
        model = org.openrouter_model || "openai/gpt-4o-mini"
        system_prompt = org.openrouter_system_prompt
        enhancer = Application.get_env(:estimate, :ai_enhancer, Estimate.AI.OpenRouter)

        {:noreply,
         socket
         |> assign(:ai_loading, target)
         |> start_async({:ai_enhance, target}, fn ->
           enhancer.enhance_description(api_key, model, system_prompt, name, desc)
         end)}
      else
        {:noreply, put_flash(socket, :error, "AI not configured")}
      end
    end)
  end

  @impl true
  def handle_async({:ai_enhance, target}, {:ok, {:ok, enhanced}}, socket) do
    {:noreply,
     socket
     |> assign(:ai_loading, nil)
     |> push_event("ai_set_description", %{text: enhanced, target: target})}
  end

  def handle_async({:ai_enhance, _target}, {:ok, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:ai_loading, nil)
     |> put_flash(:error, "AI error: #{reason}")}
  end

  def handle_async({:ai_enhance, _target}, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:ai_loading, nil)
     |> put_flash(:error, "AI request failed")}
  end

  # All broadcast events trigger a full reload
  @impl true
  def handle_info({:tasks_reordered, _epic_id, _task_ids}, socket) do
    {:noreply, reload_estimation(socket)}
  end

  def handle_info({event, _data}, socket)
      when event in [
             :estimation_updated,
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
             :role_deleted,
             :roles_reordered
           ] do
    {:noreply, reload_estimation(socket)}
  end
end
