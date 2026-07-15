defmodule EstimateWeb.ProjectLive.Show do
  use EstimateWeb, :live_view

  alias Estimate.Portfolio
  alias Estimate.Portfolio.Project
  alias Estimate.EstimationEngine
  alias Estimate.Accounts
  alias Estimate.Organizations.Currencies
  import EstimateWeb.ProjectLive.Show.Authz
  import EstimateWeb.JsonImportHelpers
  import EstimateWeb.ProjectLive.Components.EstimationDashboard
  import EstimateWeb.ProjectLive.Components.NewEstimationModal
  import EstimateWeb.ProjectLive.Components.CollaboratorsTab

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
          <.avatar name={@project.name} seed={@project.id} size={:xl} />
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
          <.tab_overview {assigns} />
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
          <.tab_estimations {assigns} />
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

      <%!-- Delete Project Modal --%>
      <.modal
        :if={@deleting_project}
        id="delete-project-modal"
        show
        on_cancel={JS.push("cancel_delete_project")}
      >
        <div>
          <div class="w-12 h-12 rounded-full bg-error/10 flex items-center justify-center mx-auto mb-4">
            <.icon name="hero-exclamation-triangle" class="w-6 h-6 text-error" />
          </div>
          <h3 class="text-lg font-semibold text-base-content mb-2 text-center">Delete Project</h3>
          <p class="text-sm text-base-content/60 mb-4 text-center">
            This will permanently delete:
          </p>
          <ul class="text-sm text-base-content/60 mb-4 space-y-1 pl-4">
            <li>
              <span class="font-medium text-base-content">{@delete_impact.estimation_count}</span>
              estimations (including trash)
            </li>
            <li>
              <span class="font-medium text-base-content">{@delete_impact.task_count}</span>
              tasks across all estimations
            </li>
            <li>
              <span class="font-medium text-base-content">{@delete_impact.collaborator_count}</span>
              collaborator assignments
            </li>
          </ul>
          <p class="text-sm text-base-content/60 mb-2">
            Type <span class="font-medium text-base-content">{@project.name}</span> to confirm:
          </p>
          <input
            type="text"
            phx-keyup="validate_delete_confirmation"
            value={@delete_confirmation_input}
            class="w-full px-3 py-2 border border-base-content/20 rounded-lg text-sm mb-4"
            placeholder={@project.name}
            autocomplete="off"
          />
          <div class="flex gap-3 justify-center">
            <button
              phx-click="cancel_delete_project"
              class="px-4 py-2 text-sm text-base-content/70 hover:text-base-content"
            >
              Cancel
            </button>
            <button
              phx-click="delete_project"
              disabled={@delete_confirmation_input != @project.name}
              class={"px-4 py-2 text-sm rounded-lg font-medium #{if @delete_confirmation_input == @project.name, do: "bg-error text-neutral-content hover:bg-error/90", else: "bg-base-300 text-base-content/30 cursor-not-allowed"}"}
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
          <div class="w-12 h-12 rounded-full bg-error/10 flex items-center justify-center mx-auto mb-4">
            <.icon name="hero-exclamation-triangle" class="w-6 h-6 text-error" />
          </div>
          <h3 class="text-lg font-semibold text-base-content mb-2">Remove Collaborator</h3>
          <p class="text-sm text-base-content/60 mb-6">
            Are you sure you want to remove
            <span class="font-medium text-base-content">
              {@removing_collaborator.user.name || @removing_collaborator.user.email}
            </span>
            from this project?
          </p>
          <div class="flex gap-3 justify-center">
            <button
              phx-click="cancel_remove_collaborator"
              class="px-4 py-2 text-sm text-base-content/70 hover:text-base-content transition-colors"
            >
              Cancel
            </button>
            <button
              phx-click="remove_collaborator"
              class="px-4 py-2 bg-error text-neutral-content text-sm rounded-lg hover:bg-error/90 transition-colors font-medium"
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
          org_id={@org_id}
          project={@project}
        />
      <% else %>
        <div class="bg-base-100 border border-base-300 rounded-xl p-8 text-center">
          <.icon name="hero-calculator" class="w-12 h-12 text-base-content/30 mx-auto" />
          <p class="mt-3 text-base-content/60">No estimations yet</p>
          <.link
            :if={@can_edit_project}
            navigate={~p"/org/#{@org_id}/projects/#{@project.id}/estimations/new"}
            class="mt-4 inline-block px-4 py-2 bg-neutral text-neutral-content text-sm rounded-lg hover:bg-neutral/90 transition-colors font-medium"
          >
            Create Estimation
          </.link>
        </div>
      <% end %>

      <%!-- Project Details Card --%>
      <.form for={@form} id="project-form" phx-submit="save" phx-change="validate">
        <div class="bg-base-100 border border-base-300 rounded-xl overflow-hidden">
          <div class="p-6 space-y-4">
            <h2 class="text-lg font-semibold text-base-content">Project Details</h2>

            <%!-- Top row: Name, Key, Status --%>
            <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
              <div class="md:col-span-1">
                <label class="block text-xs font-medium text-base-content/60 mb-1.5">
                  Project Name *
                </label>
                <input
                  type="text"
                  name={@form[:name].name}
                  value={@form[:name].value}
                  placeholder="Website Redesign"
                  required
                  class="w-full px-3 py-2 border border-base-content/20 rounded-lg text-sm"
                />
              </div>

              <div>
                <label class="block text-xs font-medium text-base-content/60 mb-1.5">
                  Project Key
                </label>
                <div class="flex items-center gap-1">
                  <span class="px-3 py-2 bg-base-200 border border-base-content/20 rounded-l-lg text-sm text-base-content/60 font-mono">
                    {@customer_key || "---"}
                  </span>
                  <span class="text-base-content/40">-</span>
                  <input
                    type="text"
                    name={@form[:key].name}
                    value={@form[:key].value}
                    placeholder="PROJ"
                    maxlength="10"
                    class="w-full px-3 py-2 border border-base-content/20 rounded-r-lg text-sm font-mono uppercase"
                  />
                </div>
              </div>

              <div>
                <label class="block text-xs font-medium text-base-content/60 mb-1.5">Status</label>
                <select
                  name={@form[:status].name}
                  class="w-full px-3 py-2 border border-base-content/20 rounded-lg text-sm"
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
              <label class="block text-xs font-medium text-base-content/60 mb-1.5">
                Default Currency
              </label>
              <select
                name={@form[:currency_id].name}
                class="w-full max-w-md px-3 py-2 border border-base-content/20 rounded-lg text-sm"
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
              <p class="text-xs text-base-content/40 mt-1">Used as default for new estimations</p>
            </div>

            <%!-- Short Description --%>
            <div>
              <label class="block text-xs font-medium text-base-content/60 mb-1.5">
                Short Description
              </label>
              <input
                type="text"
                name={@form[:short_description].name}
                value={@form[:short_description].value}
                placeholder="One-liner about the project"
                class="w-full px-3 py-2 border border-base-content/20 rounded-lg text-sm"
              />
            </div>

            <%!-- Detailed Description --%>
            <div>
              <label class="block text-xs font-medium text-base-content/60 mb-1.5">
                Detailed Description
              </label>
              <textarea
                name={@form[:detailed_description].name}
                rows="4"
                placeholder="Comprehensive scope and details..."
                class="w-full px-3 py-2 border border-base-content/20 rounded-lg text-sm resize-none"
              ><%= @form[:detailed_description].value %></textarea>
            </div>

            <%!-- Repository URL --%>
            <div>
              <label class="block text-xs font-medium text-base-content/60 mb-1.5">
                Repository URL
              </label>
              <input
                type="url"
                name={@form[:repository_url].name}
                value={@form[:repository_url].value}
                placeholder="https://github.com/org/repo"
                class="w-full max-w-md px-3 py-2 border border-base-content/20 rounded-lg text-sm"
              />
            </div>

            <%!-- Customer (readonly) --%>
            <div>
              <label class="block text-xs font-medium text-base-content/60 mb-1.5">Customer</label>
              <%= if @project.customer do %>
                <.link
                  navigate={~p"/org/#{@org_id}/customers/#{@project.customer.id}"}
                  class="inline-flex items-center gap-1 text-sm text-info hover:text-info"
                >
                  {@project.customer.name}
                  <.icon name="hero-arrow-top-right-on-square" class="w-3.5 h-3.5" />
                </.link>
              <% else %>
                <span class="text-sm text-base-content/40">Not set</span>
              <% end %>
            </div>
          </div>

          <div
            :if={@can_edit_project}
            class="px-6 py-3 bg-base-200 border-t border-base-300 flex justify-end"
          >
            <button
              type="submit"
              phx-disable-with="Saving..."
              class="px-4 py-1.5 bg-neutral text-neutral-content text-sm rounded-md hover:bg-neutral/90 transition-colors font-medium"
            >
              Save
            </button>
          </div>
        </div>
      </.form>

      <%!-- Danger Zone --%>
      <div
        :if={@can_delete_project}
        class="bg-base-100 border border-error/30 rounded-xl overflow-hidden"
      >
        <div class="p-6">
          <h2 class="text-lg font-semibold text-error">Danger Zone</h2>
          <p class="text-sm text-base-content/60 mt-1">
            Permanently delete this project and all its data.
          </p>
          <button
            phx-click="confirm_delete_project"
            class="mt-4 px-4 py-2 border border-error/30 text-error text-sm rounded-lg hover:bg-error/10 transition-colors font-medium"
          >
            Delete Project
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp tab_estimations(assigns) do
    ~H"""
    <div class="bg-base-100 border border-base-300 rounded-xl overflow-hidden">
      <div class="px-6 py-4 border-b border-base-content/10 flex items-center justify-between">
        <h2 class="text-lg font-semibold text-base-content">Estimations</h2>
        <button
          :if={@can_edit_project}
          phx-click="open_estimation_modal"
          class="px-3 py-1.5 bg-neutral text-neutral-content text-sm rounded-lg hover:bg-neutral/90 transition-colors font-medium"
        >
          New Estimation
        </button>
      </div>

      <%= if @estimations == [] do %>
        <div class="px-6 py-12 text-center">
          <div class="w-12 h-12 mx-auto mb-4 rounded-full bg-base-200 flex items-center justify-center">
            <.icon name="hero-calculator" class="w-6 h-6 text-base-content/40" />
          </div>
          <p class="text-sm font-medium text-base-content">No estimations yet</p>
          <p class="text-sm text-base-content/60 mt-1">
            Create your first estimation to get started.
          </p>
        </div>
      <% else %>
        <%= for estimation <- @estimations do %>
          <%= if @deleting_estimation == estimation.id do %>
            <div class="flex items-center justify-between px-6 py-4 bg-error/5 border-b border-base-content/10 last:border-b-0">
              <span class="text-sm text-error font-medium">
                Delete "{estimation.name}"?
              </span>
              <div class="flex items-center gap-2">
                <button
                  phx-click="cancel_delete_estimation"
                  class="text-xs text-base-content/60 hover:text-base-content px-2 py-1"
                >
                  Cancel
                </button>
                <button
                  phx-click="delete_estimation"
                  phx-value-id={estimation.id}
                  class="text-xs text-error font-medium px-2 py-1"
                >
                  Delete
                </button>
              </div>
            </div>
          <% else %>
            <div class="flex items-center border-b border-base-content/10 last:border-b-0">
              <.link
                navigate={
                  ~p"/org/#{@org_id}/projects/#{@project.id}/estimations/#{estimation.id}/estimator"
                }
                class="flex-1 px-6 py-4 hover:bg-base-200 transition-colors"
              >
                <h3 class="text-sm font-medium text-base-content">{estimation.name}</h3>
                <p class="text-xs text-base-content/60 mt-0.5">
                  {length(estimation.roles)} roles · Updated {Calendar.strftime(
                    estimation.updated_at,
                    "%b %d, %Y"
                  )}
                </p>
              </.link>
              <div class="flex items-center justify-end gap-2 px-4 pr-6 shrink-0 self-stretch">
                <button
                  :if={!estimation.is_current}
                  phx-click="set_current_estimation"
                  phx-value-id={estimation.id}
                  class="text-xs text-base-content/40 hover:text-base-content/70 px-2 py-1 rounded hover:bg-base-300"
                  title="Set as current"
                >
                  Set current
                </button>
                <span
                  :if={estimation.is_current}
                  class="text-[10px] px-1.5 py-0.5 bg-success/10 text-success rounded font-medium"
                >
                  Current
                </span>
                <button
                  :if={!estimation.is_current && @can_delete_project}
                  phx-click="confirm_delete_estimation"
                  phx-value-id={estimation.id}
                  class="text-base-content/40 hover:text-error transition-colors"
                  title="Delete estimation"
                >
                  <.icon name="hero-trash" class="w-4 h-4" />
                </button>
              </div>
            </div>
          <% end %>
        <% end %>
      <% end %>
    </div>

    <%!-- Trash Section --%>
    <div :if={@deleted_estimations != []} class="mt-6">
      <button
        phx-click="toggle_trash"
        class="flex items-center gap-2 text-sm text-base-content/40 hover:text-base-content/60 transition-colors mb-3"
      >
        <.icon name="hero-trash" class="w-4 h-4" />
        <span>Trash ({length(@deleted_estimations)})</span>
        <.icon
          name={if @show_trash, do: "hero-chevron-up-mini", else: "hero-chevron-down-mini"}
          class="w-4 h-4"
        />
      </button>

      <div
        :if={@show_trash}
        class="bg-base-100 border border-base-300 rounded-xl overflow-hidden"
      >
        <%= for estimation <- @deleted_estimations do %>
          <%= if @permanently_deleting == estimation.id do %>
            <div class="flex items-center justify-between px-6 py-4 bg-error/5 border-b border-base-content/10 last:border-b-0">
              <span class="text-sm text-error font-medium">
                Permanently delete "{estimation.name}"?
              </span>
              <div class="flex items-center gap-2">
                <button
                  phx-click="cancel_permanent_delete"
                  class="text-xs text-base-content/60 hover:text-base-content px-2 py-1"
                >
                  Cancel
                </button>
                <button
                  phx-click="permanent_delete_estimation"
                  phx-value-id={estimation.id}
                  class="text-xs text-error font-medium px-2 py-1"
                >
                  Delete Forever
                </button>
              </div>
            </div>
          <% else %>
            <div class="flex items-center border-b border-base-content/10 last:border-b-0">
              <div class="flex-1 px-6 py-4">
                <h3 class="text-sm font-medium text-base-content/50">{estimation.name}</h3>
                <p class="text-xs text-base-content/40 mt-0.5">
                  Deleted {Calendar.strftime(estimation.deleted_at, "%b %d, %Y")} · {length(
                    estimation.roles
                  )} roles
                </p>
              </div>
              <div :if={@can_delete_project} class="flex items-center gap-2 px-4 pr-6 shrink-0">
                <button
                  phx-click="restore_estimation"
                  phx-value-id={estimation.id}
                  class="text-base-content/40 hover:text-info transition-colors"
                  title="Restore estimation"
                >
                  <.icon name="hero-arrow-uturn-left" class="w-4 h-4" />
                </button>
                <button
                  phx-click="confirm_permanent_delete"
                  phx-value-id={estimation.id}
                  class="text-base-content/40 hover:text-error transition-colors"
                  title="Delete forever"
                >
                  <.icon name="hero-trash" class="w-4 h-4" />
                </button>
              </div>
            </div>
          <% end %>
        <% end %>
      </div>
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
     |> init_modal_assigns(project, role_templates, estimation_templates)
     |> init_permissions(current_collaborator, socket.assigns.current_membership)
     |> init_collaborator_assigns()
     |> init_json_assigns()}
  end

  defp init_modal_assigns(socket, project, role_templates, estimation_templates) do
    socket
    |> assign(:show_new_estimation_modal, false)
    |> assign(:estimation_form, to_form(%{}, as: "estimation"))
    |> assign(:modal_currency_id, project.currency_id)
    |> assign(:modal_currency, project.currency)
    |> assign(:modal_roles, build_modal_roles_from_templates(role_templates, project.currency_id))
    |> assign(:estimation_source, "fresh")
    |> assign(:source_estimation_id, nil)
    |> assign(
      :selected_estimation_template_id,
      if(estimation_templates != [], do: hd(estimation_templates).id)
    )
  end

  defp init_permissions(socket, current_collaborator, membership) do
    is_org_admin = admin?(membership)
    collab_role = current_collaborator && current_collaborator.role

    socket
    |> assign(:current_collaborator, current_collaborator)
    |> assign(:can_edit_project, is_org_admin || collab_role in ["owner", "editor"])
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
  def handle_event("validate", %{"project" => project_params}, socket) do
    changeset =
      socket.assigns.project
      |> Portfolio.change_project(project_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save", %{"project" => project_params}, socket) do
    require_can_edit(socket, fn ->
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
    end)
  end

  def handle_event("confirm_delete_project", _params, socket) do
    impact = Portfolio.deletion_impact(socket.assigns.project)

    {:noreply,
     socket
     |> assign(:deleting_project, true)
     |> assign(:delete_impact, impact)
     |> assign(:delete_confirmation_input, "")}
  end

  def handle_event("cancel_delete_project", _params, socket) do
    {:noreply,
     socket
     |> assign(:deleting_project, false)
     |> assign(:delete_confirmation_input, "")}
  end

  def handle_event("validate_delete_confirmation", %{"value" => value}, socket) do
    {:noreply, assign(socket, :delete_confirmation_input, value)}
  end

  def handle_event("delete_project", _params, socket) do
    require_can_delete(socket, [deleting_project: false], fn ->
      if socket.assigns.delete_confirmation_input == socket.assigns.project.name do
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
      else
        {:noreply,
         socket
         |> put_flash(:error, "Not authorized")
         |> assign(:deleting_project, false)}
      end
    end)
  end

  @allowed_dashboard_tabs ~w(by_role by_epic by_priority)
  def handle_event("set_dashboard_tab", %{"tab" => tab}, socket)
      when tab in @allowed_dashboard_tabs do
    {:noreply, assign(socket, :dashboard_tab, String.to_existing_atom(tab))}
  end

  def handle_event("set_dashboard_tab", _params, socket), do: {:noreply, socket}

  ## Estimation Events

  def handle_event("open_estimation_modal", _params, socket) do
    project = socket.assigns.project
    estimations = socket.assigns.estimations
    first_estimation_id = if Enum.any?(estimations), do: hd(estimations).id, else: nil

    {:noreply,
     socket
     |> assign(:show_new_estimation_modal, true)
     |> assign(:estimation_form, to_form(%{"name" => "", "description" => ""}, as: "estimation"))
     |> assign(:modal_currency_id, project.currency_id)
     |> assign(:modal_currency, project.currency)
     |> assign(
       :modal_roles,
       build_modal_roles_from_templates(socket.assigns.role_templates, project.currency_id)
     )
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
    socket
    |> do_validate_json(json_string)
    |> maybe_assign_modal_currency(params)
    |> update_modal_roles_from_params(params)
    |> then(&{:noreply, &1})
  end

  def handle_event("validate_estimation", params, socket) do
    socket =
      if Map.get(params, "json_input") == "" do
        clear_json(socket)
      else
        socket
      end

    source_estimation_id = Map.get(params, "source_estimation_id")

    socket =
      socket
      |> maybe_assign_modal_currency(params)
      |> maybe_apply_copy_source(source_estimation_id)
      |> update_modal_roles_from_params(params)

    {:noreply, socket}
  end

  def handle_event("remove_modal_role", %{"temp-id" => temp_id}, socket) do
    temp_id = String.to_integer(temp_id)
    roles = Enum.reject(socket.assigns.modal_roles, &(&1.temp_id == temp_id))
    {:noreply, assign(socket, :modal_roles, roles)}
  end

  def handle_event("add_modal_role", _params, socket) do
    new_role = %{
      temp_id: System.unique_integer([:positive]),
      name: "",
      abbreviation: "",
      hourly_rate: Decimal.new(0),
      pm_overhead: Decimal.new(0),
      qa_overhead: Decimal.new(0),
      risk_buffer: Decimal.new(0),
      template_id: nil
    }

    {:noreply, assign(socket, :modal_roles, socket.assigns.modal_roles ++ [new_role])}
  end

  def handle_event("reorder_modal_roles", %{"ids" => ids}, socket) do
    id_order = Enum.map(ids, &String.to_integer/1)
    roles_by_id = Map.new(socket.assigns.modal_roles, &{&1.temp_id, &1})
    reordered = Enum.map(id_order, &Map.fetch!(roles_by_id, &1))
    {:noreply, assign(socket, :modal_roles, reordered)}
  end

  def handle_event("reset_modal_roles", _params, socket) do
    roles =
      build_modal_roles_from_templates(
        socket.assigns.role_templates,
        socket.assigns.modal_currency_id
      )

    {:noreply, assign(socket, :modal_roles, roles)}
  end

  def handle_event("create_estimation", %{"estimation" => estimation_params} = params, socket) do
    socket = update_modal_roles_from_params(socket, params)

    require_can_edit(socket, fn ->
      source = Map.get(params, "source", "fresh")

      if source != "copy" && !roles_valid?(socket.assigns.modal_roles) do
        {:noreply, put_flash(socket, :error, "All roles must have a name and abbreviation")}
      else
        project = socket.assigns.project
        org_id = socket.assigns.org_id

        result = dispatch_create(source, estimation_params, params, socket, project, org_id)

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
    end)
  end

  def handle_event("json_file_uploaded", %{"content" => content}, socket) do
    {:noreply, do_validate_json(socket, content)}
  end

  def handle_event("download_json_schema", _params, socket) do
    {:noreply, push_schema_download(socket)}
  end

  def handle_event("copy_agent_prompt", _params, socket) do
    {:noreply, socket |> push_agent_prompt_copy() |> put_flash(:info, "Agent prompt copied")}
  end

  def handle_event("set_current_estimation", %{"id" => id}, socket) do
    require_can_edit(socket, fn ->
      case fetch_authorized_estimation(socket, id) do
        {:ok, estimation} ->
          case EstimationEngine.set_current_estimation(estimation) do
            {:ok, _} ->
              estimations = EstimationEngine.list_estimations(socket.assigns.project.id)
              current = EstimationEngine.get_estimation!(estimation.id, socket.assigns.org_id)

              {:noreply,
               socket
               |> assign(:estimations, estimations)
               |> assign(:current_estimation, current)}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Could not set current estimation")}
          end

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Not authorized")}
      end
    end)
  end

  def handle_event("confirm_delete_estimation", %{"id" => id}, socket) do
    {:noreply, assign(socket, :deleting_estimation, id)}
  end

  def handle_event("cancel_delete_estimation", _params, socket) do
    {:noreply, assign(socket, :deleting_estimation, nil)}
  end

  def handle_event("delete_estimation", %{"id" => id}, socket) do
    require_can_delete(socket, [deleting_estimation: nil], fn ->
      case fetch_authorized_estimation(socket, id) do
        {:ok, estimation} ->
          if estimation.is_current do
            {:noreply,
             socket
             |> put_flash(:error, "Cannot delete current estimation")
             |> assign(:deleting_estimation, nil)}
          else
            case EstimationEngine.soft_delete_estimation(estimation) do
              {:ok, _} ->
                project_id = socket.assigns.project.id
                estimations = EstimationEngine.list_estimations(project_id)
                deleted = EstimationEngine.list_deleted_estimations(project_id)

                {:noreply,
                 socket
                 |> assign(:estimations, estimations)
                 |> assign(:deleted_estimations, deleted)
                 |> assign(:deleting_estimation, nil)
                 |> put_flash(:info, "Estimation moved to trash")}

              {:error, _} ->
                {:noreply,
                 socket
                 |> put_flash(:error, "Could not delete estimation")
                 |> assign(:deleting_estimation, nil)}
            end
          end

        {:error, _} ->
          {:noreply,
           socket
           |> put_flash(:error, "Not authorized")
           |> assign(:deleting_estimation, nil)}
      end
    end)
  end

  ## Trash Events

  def handle_event("toggle_trash", _params, socket) do
    {:noreply, assign(socket, :show_trash, !socket.assigns.show_trash)}
  end

  def handle_event("restore_estimation", %{"id" => id}, socket) do
    require_can_delete(socket, fn ->
      org_id = socket.assigns.org_id
      project_id = socket.assigns.project.id

      case find_deleted_estimation(socket, id) do
        {:ok, estimation} ->
          case EstimationEngine.restore_estimation(estimation) do
            {:ok, _} ->
              estimations = EstimationEngine.list_estimations(project_id)
              deleted = EstimationEngine.list_deleted_estimations(project_id)

              current_estimation =
                case Enum.find(estimations, & &1.is_current) do
                  nil -> nil
                  est -> EstimationEngine.get_estimation!(est.id, org_id)
                end

              {:noreply,
               socket
               |> assign(:estimations, estimations)
               |> assign(:deleted_estimations, deleted)
               |> assign(:current_estimation, current_estimation)
               |> put_flash(:info, "Estimation restored")}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Could not restore estimation")}
          end

        :error ->
          {:noreply, put_flash(socket, :error, "Estimation not found")}
      end
    end)
  end

  def handle_event("confirm_permanent_delete", %{"id" => id}, socket) do
    {:noreply, assign(socket, :permanently_deleting, id)}
  end

  def handle_event("cancel_permanent_delete", _params, socket) do
    {:noreply, assign(socket, :permanently_deleting, nil)}
  end

  def handle_event("permanent_delete_estimation", %{"id" => id}, socket) do
    require_can_delete(socket, [permanently_deleting: nil], fn ->
      case find_deleted_estimation(socket, id) do
        {:ok, estimation} ->
          case EstimationEngine.hard_delete_estimation(estimation) do
            {:ok, _} ->
              deleted = EstimationEngine.list_deleted_estimations(socket.assigns.project.id)

              {:noreply,
               socket
               |> assign(:deleted_estimations, deleted)
               |> assign(:permanently_deleting, nil)
               |> put_flash(:info, "Estimation permanently deleted")}

            {:error, _} ->
              {:noreply,
               socket
               |> put_flash(:error, "Could not delete estimation")
               |> assign(:permanently_deleting, nil)}
          end

        :error ->
          {:noreply,
           socket
           |> put_flash(:error, "Estimation not found")
           |> assign(:permanently_deleting, nil)}
      end
    end)
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
    require_can_manage(socket, fn ->
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
    end)
  end

  def handle_event("change_collaborator_role", %{"id" => id, "role" => role}, socket) do
    require_can_manage(socket, fn ->
      collab = Enum.find(socket.assigns.collaborators, &(&1.id == id))

      if collab &&
           can_change_role?(
             socket.assigns.can_manage_collaborators,
             socket.assigns.current_user,
             collab
           ) do
        case Portfolio.update_collaborator_role(collab, role) do
          {:ok, _} ->
            {:noreply, reload_collaborators(socket, "Role updated")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not update role")}
        end
      else
        {:noreply, put_flash(socket, :error, "Not authorized")}
      end
    end)
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

      !can_remove_collaborator?(
        socket.assigns.can_manage_collaborators,
        socket.assigns.current_user,
        socket.assigns.current_collaborator,
        collab
      ) ->
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

  ## Modal Roles Helpers

  defp build_modal_roles_from_templates(role_templates, currency_id) do
    Enum.map(role_templates, fn template ->
      rate =
        Enum.find(template.rates, fn r -> to_string(r.currency_id) == to_string(currency_id) end)

      %{
        temp_id: System.unique_integer([:positive]),
        name: template.name,
        abbreviation: template.abbreviation,
        hourly_rate: if(rate, do: rate.hourly_rate, else: Decimal.new(0)),
        pm_overhead: template.pm_overhead,
        qa_overhead: template.qa_overhead,
        risk_buffer: template.risk_buffer,
        template_id: template.id
      }
    end)
  end

  defp dispatch_create("copy", estimation_params, params, socket, project, org_id) do
    source_estimation_id = Map.get(params, "source_estimation_id")
    name = estimation_params["name"]

    if source_estimation_id && name && name != "" do
      case fetch_authorized_estimation(socket, source_estimation_id) do
        {:ok, source_estimation} ->
          EstimationEngine.copy_estimation(source_estimation, name, project.id, org_id)

        {:error, _} ->
          {:error, :unauthorized}
      end
    else
      {:error, :invalid_params}
    end
  end

  defp dispatch_create("template", estimation_params, params, socket, project, org_id) do
    estimation_template_id = Map.get(params, "estimation_template_id")
    role_attrs = collect_role_attrs(socket.assigns.modal_roles)
    attrs = build_estimation_attrs(estimation_params, params, project, org_id)

    EstimationEngine.create_estimation_from_estimation_template(
      attrs,
      estimation_template_id,
      role_attrs
    )
  end

  defp dispatch_create("json", estimation_params, params, socket, project, org_id) do
    case socket.assigns.json_parsed do
      nil ->
        {:error, :no_json}

      parsed_json ->
        role_attrs = collect_role_attrs(socket.assigns.modal_roles)
        attrs = build_estimation_attrs(estimation_params, params, project, org_id)
        EstimationEngine.create_estimation_from_json(attrs, parsed_json, role_attrs)
    end
  end

  defp dispatch_create(_fresh, estimation_params, params, socket, project, org_id) do
    role_attrs = collect_role_attrs(socket.assigns.modal_roles)
    attrs = build_estimation_attrs(estimation_params, params, project, org_id)
    EstimationEngine.create_estimation_from_templates(attrs, role_attrs)
  end

  defp build_estimation_attrs(estimation_params, params, project, org_id) do
    currency_id = Map.get(params, "currency_id", project.currency_id)

    Map.merge(estimation_params, %{
      "project_id" => project.id,
      "currency_id" => currency_id,
      "organization_id" => org_id
    })
  end

  defp maybe_assign_modal_currency(socket, params) do
    currency_id = Map.get(params, "currency_id")

    if currency_id && currency_id != "" do
      currency = Enum.find(socket.assigns.currencies, &(to_string(&1.id) == currency_id))
      old_currency_id = socket.assigns.modal_currency_id

      socket
      |> assign(:modal_currency_id, currency_id)
      |> assign(:modal_currency, currency)
      |> maybe_update_modal_role_rates(old_currency_id, currency_id)
    else
      socket
    end
  end

  defp maybe_apply_copy_source(socket, source_estimation_id)
       when is_nil(source_estimation_id) or source_estimation_id == "",
       do: socket

  defp maybe_apply_copy_source(socket, source_estimation_id) do
    case Enum.find(socket.assigns.estimations, &(to_string(&1.id) == source_estimation_id)) do
      nil ->
        socket

      est ->
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
    end
  end

  defp update_modal_roles_from_params(socket, params) do
    case Map.get(params, "roles") do
      nil ->
        socket

      roles_params when is_map(roles_params) ->
        updated =
          Enum.map(socket.assigns.modal_roles, fn role ->
            case Map.get(roles_params, to_string(role.temp_id)) do
              nil ->
                role

              fields ->
                role
                |> Map.put(:name, Map.get(fields, "name", role.name))
                |> Map.put(:abbreviation, Map.get(fields, "abbreviation", role.abbreviation))
                |> Map.put(
                  :hourly_rate,
                  parse_decimal(Map.get(fields, "hourly_rate"), role.hourly_rate)
                )
            end
          end)

        assign(socket, :modal_roles, updated)
    end
  end

  defp maybe_update_modal_role_rates(socket, old_currency_id, new_currency_id)
       when old_currency_id == new_currency_id,
       do: socket

  defp maybe_update_modal_role_rates(socket, _old, new_currency_id) do
    templates_by_id =
      Map.new(socket.assigns.role_templates, &{&1.id, &1})

    updated =
      Enum.map(socket.assigns.modal_roles, fn role ->
        case role.template_id && Map.get(templates_by_id, role.template_id) do
          nil ->
            role

          template ->
            rate =
              Enum.find(template.rates, fn r ->
                to_string(r.currency_id) == to_string(new_currency_id)
              end)

            %{role | hourly_rate: if(rate, do: rate.hourly_rate, else: Decimal.new(0))}
        end
      end)

    assign(socket, :modal_roles, updated)
  end

  defp collect_role_attrs(modal_roles) do
    Enum.map(modal_roles, fn role ->
      %{
        name: role.name,
        abbreviation: role.abbreviation,
        hourly_rate: role.hourly_rate,
        pm_overhead: role[:pm_overhead] || Decimal.new(0),
        qa_overhead: role[:qa_overhead] || Decimal.new(0),
        risk_buffer: role[:risk_buffer] || Decimal.new(0)
      }
    end)
  end

  defp roles_valid?(roles) do
    Enum.all?(roles, fn role ->
      String.trim(role.name || "") != "" && String.trim(role.abbreviation || "") != ""
    end)
  end

  defp parse_decimal(nil, default), do: default
  defp parse_decimal("", default), do: default

  defp parse_decimal(value, default) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, _} -> decimal
      :error -> default
    end
  end

  defp parse_decimal(value, _default), do: value
end
