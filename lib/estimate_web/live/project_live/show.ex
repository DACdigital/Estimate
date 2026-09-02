defmodule EstimateWeb.ProjectLive.Show do
  use EstimateWeb, :live_view

  alias Estimate.Portfolio
  alias Estimate.Portfolio.Project
  alias Estimate.EstimationEngine
  alias Estimate.Accounts
  alias Estimate.Organizations.Currencies

  alias EstimateWeb.ProjectLive.Show.{
    Details,
    DangerZone,
    Dashboard,
    EstimationModal,
    Estimations,
    Collaborators
  }

  import EstimateWeb.JsonImportHelpers
  import EstimateWeb.ProjectLive.Components.NewEstimationModal
  import EstimateWeb.ProjectLive.Components.CollaboratorsTab
  import EstimateWeb.ProjectLive.Components.OverviewTab
  import EstimateWeb.ProjectLive.Components.EstimationsTab
  import EstimateWeb.ProjectLive.Components.DeleteProjectModal
  import EstimateWeb.ProjectLive.Components.RemoveCollaboratorModal

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto">
      <%!-- Breadcrumb --%>
      <nav class="flex items-center space-x-2 text-sm text-base-content/60 mb-6">
        <.link
          :if={@project.customer}
          navigate={~p"/org/#{@org_id}/customers/#{@project.customer.id}"}
          class="hover:text-base-content"
        >
          {@project.customer.name}
        </.link>
        <span class="text-base-content/30">›</span>
        <span class="text-base-content font-medium">{@project.name}</span>
        <span
          :if={@current_estimation && @current_estimation.currency}
          class="text-base-content/30 ml-2"
        >
          •
        </span>
        <span :if={@current_estimation && @current_estimation.currency} class="text-base-content/40">
          {@current_estimation.currency.code}
        </span>
      </nav>

      <%!-- Header --%>
      <div class="flex items-start justify-between mb-6">
        <div class="flex items-center gap-4">
          <.avatar name={@project.name} seed={@project.id} type={:project} size={:xl} />
          <div>
            <div class="flex items-center gap-3">
              <h1 class="text-2xl font-bold text-base-content">{@project.name}</h1>
              <span class={"text-xs px-2 py-0.5 rounded-full #{project_status_class(@project.status)}"}>
                {@project.status}
              </span>
            </div>
            <div class="flex items-center gap-3 mt-1">
              <span
                :if={Project.composite_key(@project)}
                class="text-sm font-mono text-base-content/40"
              >
                {Project.composite_key(@project)}
              </span>
            </div>
          </div>
        </div>
      </div>

      <%!-- Tabs --%>
      <div class="border-b border-base-300 mb-6">
        <nav class="flex gap-6">
          <.link
            patch={~p"/org/#{@org_id}/projects/#{@project.id}"}
            class={"pb-3 px-1 text-sm font-medium border-b-2 transition-colors #{if @tab == :overview, do: "border-base-content text-base-content", else: "border-transparent text-base-content/60 hover:text-base-content/80"}"}
          >
            Overview
          </.link>
          <.link
            patch={~p"/org/#{@org_id}/projects/#{@project.id}/collaborators"}
            class={"pb-3 px-1 text-sm font-medium border-b-2 transition-colors #{if @tab == :collaborators, do: "border-base-content text-base-content", else: "border-transparent text-base-content/60 hover:text-base-content/80"}"}
          >
            Collaborators
          </.link>
          <.link
            patch={~p"/org/#{@org_id}/projects/#{@project.id}/estimations"}
            class={"pb-3 px-1 text-sm font-medium border-b-2 transition-colors #{if @tab == :estimations, do: "border-base-content text-base-content", else: "border-transparent text-base-content/60 hover:text-base-content/80"}"}
          >
            Estimations
          </.link>
        </nav>
      </div>

      <%!-- Tab Content --%>
      <%= case @tab do %>
        <% :overview -> %>
          <.overview_tab
            project={@project}
            form={@form}
            current_estimation={@current_estimation}
            dashboard_tab={@dashboard_tab}
            org_id={@org_id}
            can_edit_project={@can_edit_project}
            can_delete_project={@can_delete_project}
            currencies={@currencies}
            customer_key={@customer_key}
          />
        <% :collaborators -> %>
          <.tab_collaborators
            collaborators={@collaborators}
            available_members={@available_members}
            current_user={@current_user}
            current_collaborator={@current_collaborator}
            can_manage_collaborators={@can_manage_collaborators}
            member_search={@member_search}
            show_member_dropdown={@show_member_dropdown}
            selected_member={@selected_member}
            selected_role={@selected_role}
            filtered_members={filtered_members(@available_members, @member_search)}
          />
        <% :estimations -> %>
          <.estimations_tab
            estimations={@estimations}
            deleting_estimation={@deleting_estimation}
            can_edit_project={@can_edit_project}
            can_delete_project={@can_delete_project}
            org_id={@org_id}
            project={@project}
            deleted_estimations={@deleted_estimations}
            show_trash={@show_trash}
            permanently_deleting={@permanently_deleting}
          />
      <% end %>

      <.new_estimation_modal
        show_new_estimation_modal={@show_new_estimation_modal}
        estimation_form={@estimation_form}
        estimation_source={@estimation_source}
        estimations={@estimations}
        estimation_templates={@estimation_templates}
        source_estimation_id={@source_estimation_id}
        selected_estimation_template_id={@selected_estimation_template_id}
        modal_roles={@modal_roles}
        currencies={@currencies}
        modal_currency_id={@modal_currency_id}
        modal_currency={@modal_currency}
        org_id={@org_id}
        json_input={@json_input}
        json_error={@json_error}
        json_parsed={@json_parsed}
      />

      <.delete_project_modal
        deleting_project={@deleting_project}
        delete_impact={@delete_impact}
        delete_confirmation_input={@delete_confirmation_input}
        project={@project}
      />

      <.remove_collaborator_modal removing_collaborator={@removing_collaborator} />
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
    estimations = EstimationEngine.list_estimations(id, org_id)
    role_templates = Accounts.list_role_templates(org_id)
    estimation_templates = Estimate.Templates.list_estimation_templates(org_id)
    currencies = Currencies.list_currencies(org_id)

    current_estimation =
      case Enum.find(estimations, & &1.is_current) do
        nil -> nil
        est -> EstimationEngine.get_estimation!(est.id, org_id)
      end

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
     |> assign(:form, to_form(Portfolio.change_project(project)))
     |> assign(:deleting_project, false)
     |> assign(:delete_impact, %{estimation_count: 0, task_count: 0, collaborator_count: 0})
     |> assign(:delete_confirmation_input, "")
     |> assign(:deleting_estimation, nil)
     |> assign(:deleted_estimations, [])
     |> assign(:show_trash, false)
     |> assign(:permanently_deleting, nil)
     |> assign(:estimation_templates, estimation_templates)
     |> EstimationModal.init_modal_assigns(project, role_templates, estimation_templates)
     |> init_permissions(current_collaborator, socket.assigns.current_membership)
     |> init_collaborator_assigns()
     |> init_json_assigns()}
  end

  defp init_permissions(socket, current_collaborator, membership) do
    is_org_admin = admin?(membership)
    collab_role = current_collaborator && current_collaborator.role

    socket
    |> assign(:current_collaborator, current_collaborator)
    |> assign(:can_edit_project, can_edit_project?(membership, current_collaborator))
    |> assign(:can_delete_project, is_org_admin || collab_role == "owner")
    |> assign(
      :can_manage_collaborators,
      is_org_admin || (current_collaborator && current_collaborator.role == "owner")
    )
  end

  defp init_collaborator_assigns(socket) do
    socket
    |> assign(:collaborators, [])
    |> assign(:available_members, [])
    |> assign(:member_search, "")
    |> assign(:show_member_dropdown, false)
    |> assign(:selected_member, nil)
    |> assign(:selected_role, "viewer")
    |> assign(:removing_collaborator, nil)
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
    deleted = EstimationEngine.list_deleted_estimations(socket.assigns.project.id)

    socket
    |> assign(:tab, :estimations)
    |> assign(:deleted_estimations, deleted)
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
  def handle_event("validate", params, socket), do: Details.validate(socket, params)
  def handle_event("save", params, socket), do: Details.save(socket, params)

  def handle_event("confirm_delete_project", params, socket),
    do: DangerZone.confirm_delete_project(socket, params)

  def handle_event("cancel_delete_project", params, socket),
    do: DangerZone.cancel_delete_project(socket, params)

  def handle_event("validate_delete_confirmation", params, socket),
    do: DangerZone.validate_delete_confirmation(socket, params)

  def handle_event("delete_project", params, socket),
    do: DangerZone.delete_project(socket, params)

  def handle_event("set_dashboard_tab", params, socket),
    do: Dashboard.set_dashboard_tab(socket, params)

  ## Estimation Events

  def handle_event("open_estimation_modal", params, socket),
    do: EstimationModal.open_estimation_modal(socket, params)

  def handle_event("set_estimation_source", params, socket),
    do: EstimationModal.set_estimation_source(socket, params)

  def handle_event("close_estimation_modal", params, socket),
    do: EstimationModal.close_estimation_modal(socket, params)

  def handle_event("validate_estimation", params, socket),
    do: EstimationModal.validate_estimation(socket, params)

  def handle_event("remove_modal_role", params, socket),
    do: EstimationModal.remove_modal_role(socket, params)

  def handle_event("add_modal_role", params, socket),
    do: EstimationModal.add_modal_role(socket, params)

  def handle_event("reorder_modal_roles", params, socket),
    do: EstimationModal.reorder_modal_roles(socket, params)

  def handle_event("reset_modal_roles", params, socket),
    do: EstimationModal.reset_modal_roles(socket, params)

  def handle_event("create_estimation", params, socket),
    do: EstimationModal.create_estimation(socket, params)

  def handle_event("json_file_uploaded", params, socket),
    do: EstimationModal.json_file_uploaded(socket, params)

  def handle_event("download_json_schema", params, socket),
    do: EstimationModal.download_json_schema(socket, params)

  def handle_event("copy_agent_prompt", params, socket),
    do: EstimationModal.copy_agent_prompt(socket, params)

  def handle_event("set_current_estimation", params, socket),
    do: Estimations.set_current_estimation(socket, params)

  def handle_event("confirm_delete_estimation", params, socket),
    do: Estimations.confirm_delete_estimation(socket, params)

  def handle_event("cancel_delete_estimation", params, socket),
    do: Estimations.cancel_delete_estimation(socket, params)

  def handle_event("delete_estimation", params, socket),
    do: Estimations.delete_estimation(socket, params)

  ## Trash Events

  def handle_event("toggle_trash", params, socket),
    do: Estimations.toggle_trash(socket, params)

  def handle_event("restore_estimation", params, socket),
    do: Estimations.restore_estimation(socket, params)

  def handle_event("confirm_permanent_delete", params, socket),
    do: Estimations.confirm_permanent_delete(socket, params)

  def handle_event("cancel_permanent_delete", params, socket),
    do: Estimations.cancel_permanent_delete(socket, params)

  def handle_event("permanent_delete_estimation", params, socket),
    do: Estimations.permanent_delete_estimation(socket, params)

  ## Collaborator Events

  def handle_event("collaborator_form_change", params, socket),
    do: Collaborators.collaborator_form_change(socket, params)

  def handle_event("open_member_dropdown", params, socket),
    do: Collaborators.open_member_dropdown(socket, params)

  def handle_event("close_member_dropdown", params, socket),
    do: Collaborators.close_member_dropdown(socket, params)

  def handle_event("select_member", params, socket),
    do: Collaborators.select_member(socket, params)

  def handle_event("clear_selected_member", params, socket),
    do: Collaborators.clear_selected_member(socket, params)

  def handle_event("add_collaborator", params, socket),
    do: Collaborators.add_collaborator(socket, params)

  def handle_event("change_collaborator_role", params, socket),
    do: Collaborators.change_collaborator_role(socket, params)

  def handle_event("confirm_remove_collaborator", params, socket),
    do: Collaborators.confirm_remove_collaborator(socket, params)

  def handle_event("cancel_remove_collaborator", params, socket),
    do: Collaborators.cancel_remove_collaborator(socket, params)

  def handle_event("remove_collaborator", params, socket),
    do: Collaborators.remove_collaborator(socket, params)

  ## Helpers

  defp filtered_members(available_members, "") do
    available_members
  end

  defp filtered_members(available_members, search) do
    term = String.downcase(search)

    Enum.filter(available_members, fn m ->
      String.contains?(String.downcase(m.user.name || ""), term) ||
        String.contains?(String.downcase(m.user.email), term)
    end)
  end
end
