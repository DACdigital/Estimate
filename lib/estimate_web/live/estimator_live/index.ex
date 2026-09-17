defmodule EstimateWeb.EstimatorLive.Index do
  use EstimateWeb, :live_view

  alias Estimate.EstimationEngine
  alias Estimate.Portfolio
  alias Estimate.Organizations
  alias Estimate.Organizations.Currencies
  alias EstimateWeb.EstimatorLive.Epics

  import EstimateWeb.EstimatorLive.Helpers
  import EstimateWeb.EstimatorLive.Components.CostBreakdown
  import EstimateWeb.EstimatorLive.Components.EstimatorModals
  import EstimateWeb.EstimatorLive.Components.EstimationTable
  import EstimateWeb.EstimatorLive.Authz

  @impl true
  def render(assigns) do
    ~H"""
    <% epics = filtered_epics(@estimation, @enabled_priorities) %>
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

  def handle_event("add_task", %{"epic-id" => epic_id}, socket) do
    with_edit_auth(socket, fn socket ->
      case find_epic(socket.assigns.estimation, epic_id) do
        nil ->
          not_found(socket)

        epic ->
          changeset = EstimationEngine.Task.changeset(%EstimationEngine.Task{}, %{})

          {:noreply,
           socket
           |> assign(:modal, :task)
           |> assign(:task_form, to_form(changeset))
           |> assign(:current_epic_id, epic.id)}
      end
    end)
  end

  def handle_event("edit_task", %{"id" => id}, socket) do
    with_edit_auth(socket, fn socket ->
      case find_task(socket.assigns.estimation, id) do
        nil ->
          not_found(socket)

        task ->
          changeset = EstimationEngine.Task.update_changeset(task, %{})

          {:noreply,
           socket
           |> assign(:modal, :task)
           |> assign(:task_form, to_form(changeset))
           |> assign(:current_epic_id, task.epic_id)}
      end
    end)
  end

  def handle_event("validate_task", %{"task" => task_params}, socket) do
    case socket.assigns.task_form do
      nil ->
        not_found(socket)

      task_form ->
        task = task_form.data

        changeset =
          if task.id,
            do: EstimationEngine.Task.update_changeset(task, task_params),
            else: EstimationEngine.Task.changeset(task, task_params)

        {:noreply,
         assign(socket, :task_form, changeset |> Map.put(:action, :validate) |> to_form())}
    end
  end

  def handle_event("save_task", %{"task" => task_params}, socket) do
    with_edit_auth(socket, fn socket ->
      task = socket.assigns.task_form && socket.assigns.task_form.data
      epic_id = socket.assigns.current_epic_id

      cond do
        is_nil(task) ->
          not_found(socket)

        is_nil(task.id) and is_nil(epic_id) ->
          not_found(socket)

        true ->
          result =
            if task.id do
              EstimationEngine.update_task(task, task_params)
            else
              attrs = Map.put(task_params, "epic_id", epic_id)
              EstimationEngine.create_task(attrs)
            end

          case result do
            {:ok, _task} ->
              {:noreply,
               socket
               |> reload_estimation()
               |> assign(:modal, nil)
               |> assign(:task_form, nil)
               |> assign(:current_epic_id, nil)}

            {:error, changeset} ->
              {:noreply, assign(socket, :task_form, to_form(changeset))}
          end
      end
    end)
  end

  def handle_event("confirm_delete_task", %{"id" => id}, socket) do
    with_edit_auth(socket, fn socket ->
      case find_task(socket.assigns.estimation, id) do
        nil -> not_found(socket)
        task -> {:noreply, assign(socket, :deleting_task, task)}
      end
    end)
  end

  def handle_event("cancel_delete_task", _params, socket) do
    {:noreply, assign(socket, :deleting_task, nil)}
  end

  def handle_event("delete_task", _params, socket) do
    with_edit_auth(socket, fn socket ->
      case socket.assigns.deleting_task do
        nil ->
          {:noreply, socket}

        task ->
          {:ok, _} = EstimationEngine.delete_task(task)

          {:noreply,
           socket
           |> reload_estimation()
           |> assign(:deleting_task, nil)}
      end
    end)
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:modal, nil)
     |> assign(:epic_form, nil)
     |> assign(:task_form, nil)
     |> assign(:current_epic_id, nil)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, socket |> assign(:editing, nil) |> assign(:editing_rate, nil)}
  end

  def handle_event("edit_estimate", %{"key" => key}, socket) do
    {:noreply, assign(socket, :editing, key)}
  end

  def handle_event("edit_rate", %{"role-id" => role_id}, socket) do
    {:noreply, assign(socket, :editing_rate, role_id)}
  end

  def handle_event("save_rate", %{"role-id" => role_id, "value" => value}, socket) do
    with_edit_auth(socket, fn socket ->
      estimation = socket.assigns.estimation

      if belongs_to_estimation?(estimation, :role, role_id) do
        role = EstimationEngine.get_role!(role_id, socket.assigns.org_id)
        hourly_rate = parse_decimal(value)

        case EstimationEngine.update_role(role, %{hourly_rate: hourly_rate}) do
          {:ok, updated_role} ->
            {:noreply,
             socket
             |> assign(:estimation, update_role_in_memory(estimation, updated_role))
             |> assign(:editing_rate, nil)}

          {:error, _changeset} ->
            {:noreply, assign(socket, :editing_rate, nil)}
        end
      else
        {:noreply, assign(socket, :editing_rate, nil)}
      end
    end)
  end

  def handle_event("save_estimate", params, socket) do
    with_edit_auth(socket, fn socket ->
      %{"task-id" => task_id, "role-id" => role_id, "value" => value} = params
      estimation = socket.assigns.estimation

      if belongs_to_estimation?(estimation, :task, task_id) and
           belongs_to_estimation?(estimation, :role, role_id) do
        hours = parse_decimal(value)

        case EstimationEngine.upsert_task_estimate(
               task_id,
               role_id,
               %{hours: hours},
               estimation.id
             ) do
          {:ok, updated_estimate} ->
            {:noreply,
             socket
             |> assign(:estimation, update_estimate_in_memory(estimation, updated_estimate))
             |> assign(:editing, nil)}

          {:error, _changeset} ->
            {:noreply, assign(socket, :editing, nil)}
        end
      else
        {:noreply, assign(socket, :editing, nil)}
      end
    end)
  end

  def handle_event("reorder_epics", params, socket), do: Epics.reorder_epics(socket, params)

  def handle_event("reorder_tasks", %{"epic_id" => epic_id, "ids" => ids}, socket) do
    with_edit_auth(socket, fn socket ->
      if Enum.any?(socket.assigns.estimation.epics, &(&1.id == epic_id)) do
        EstimationEngine.reorder_tasks(epic_id, ids)
        {:noreply, reload_estimation(socket)}
      else
        {:noreply, socket}
      end
    end)
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
    with_edit_auth(socket, fn socket ->
      {:noreply, assign(socket, :modal, :settings)}
    end)
  end

  def handle_event("open_save_as_template", _params, socket) do
    with_edit_auth(socket, fn socket ->
      {:noreply, assign(socket, :modal, :save_template)}
    end)
  end

  def handle_event("save_as_template", %{"template_name" => name}, socket) when name != "" do
    with_edit_auth(socket, fn socket ->
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
    end)
  end

  def handle_event("save_as_template", _params, socket), do: {:noreply, socket}

  def handle_event(
        "add_estimation_role",
        %{"new_role_name" => name, "new_role_abbr" => abbr},
        socket
      )
      when name != "" and abbr != "" do
    with_edit_auth(socket, fn socket ->
      estimation = socket.assigns.estimation

      attrs = %{
        name: name,
        abbreviation: String.upcase(abbr),
        estimation_id: estimation.id,
        position: length(estimation.roles),
        hourly_rate: Decimal.new(0),
        pm_overhead: Decimal.new(0),
        qa_overhead: Decimal.new(0),
        risk_buffer: Decimal.new(0)
      }

      case EstimationEngine.create_role(attrs) do
        {:ok, _role} ->
          {:noreply, reload_estimation(socket) |> put_flash(:info, "Role added")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not add role")}
      end
    end)
  end

  def handle_event("add_estimation_role", _params, socket), do: {:noreply, socket}

  def handle_event("save_settings", params, socket) do
    with_edit_auth(socket, fn socket ->
      estimation = socket.assigns.estimation
      org_id = socket.assigns.org_id

      attrs = %{
        "name" => params["name"],
        "currency_id" => params["currency_id"]
      }

      roles_params = params["roles"] || %{}

      roles_result =
        Enum.reduce_while(roles_params, :ok, fn {role_id, role_attrs}, :ok ->
          role = EstimationEngine.get_role!(role_id, org_id)

          if role.estimation_id != estimation.id do
            {:halt, {:error, :unauthorized_role}}
          else
            case EstimationEngine.update_role(role, %{
                   name: role_attrs["name"] || role.name,
                   abbreviation: role_attrs["abbreviation"] || role.abbreviation,
                   hourly_rate: parse_decimal(role_attrs["hourly_rate"]),
                   pm_overhead: parse_decimal(role_attrs["pm_overhead"]),
                   qa_overhead: parse_decimal(role_attrs["qa_overhead"]),
                   risk_buffer: parse_decimal(role_attrs["risk_buffer"])
                 }) do
              {:ok, _} -> {:cont, :ok}
              {:error, _} -> {:halt, {:error, :role_update_failed}}
            end
          end
        end)

      case roles_result do
        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Could not update roles")}

        :ok ->
          case EstimationEngine.update_estimation(estimation, attrs) do
            {:ok, _} ->
              {:noreply,
               socket
               |> reload_estimation()
               |> assign(:modal, nil)
               |> put_flash(:info, "Settings saved")}

            {:error, _changeset} ->
              {:noreply, put_flash(socket, :error, "Could not save settings")}
          end
      end
    end)
  end

  def handle_event("confirm_delete_role", %{"id" => role_id}, socket) do
    with_edit_auth(socket, fn socket ->
      {:noreply, assign(socket, :deleting_role_id, role_id)}
    end)
  end

  def handle_event("cancel_delete_role", _params, socket) do
    {:noreply, assign(socket, :deleting_role_id, nil)}
  end

  def handle_event("delete_estimation_role", _params, socket) do
    with_edit_auth(socket, fn socket ->
      case socket.assigns.deleting_role_id do
        nil ->
          {:noreply, socket}

        role_id ->
          role = EstimationEngine.get_role!(role_id, socket.assigns.org_id)

          if role.estimation_id != socket.assigns.estimation.id do
            {:noreply, put_flash(socket, :error, "Not authorized")}
          else
            EstimationEngine.delete_role(role)

            {:noreply,
             socket
             |> reload_estimation()
             |> assign(:deleting_role_id, nil)
             |> put_flash(:info, "Role deleted")}
          end
      end
    end)
  end

  def handle_event("reorder_roles", %{"ids" => ids}, socket) do
    with_edit_auth(socket, fn socket ->
      EstimationEngine.reorder_roles(socket.assigns.estimation.id, ids)
      {:noreply, socket}
    end)
  end

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
