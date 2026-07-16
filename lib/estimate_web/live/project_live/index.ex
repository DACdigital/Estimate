defmodule EstimateWeb.ProjectLive.Index do
  use EstimateWeb, :live_view

  alias Estimate.Portfolio
  alias Estimate.Portfolio.Project
  alias Estimate.CRM
  alias Estimate.Organizations.Currencies

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto">
      <%!-- Page Header --%>
      <div class="flex items-center justify-between mb-8">
        <div>
          <h1 class="text-2xl font-bold text-base-content">Projects</h1>
          <div class="mt-2 inline-flex rounded-lg bg-base-200 p-0.5 text-xs font-medium">
            <.filter_pill label="Active" value="active" active={@status_filter == "active"} />
            <.filter_pill label="All" value="all" active={@status_filter == nil} />
          </div>
        </div>
        <.link
          patch={~p"/org/#{@org_id}/projects/new"}
          class="px-4 py-2 bg-neutral text-neutral-content text-sm rounded-lg hover:bg-neutral/90 transition-colors font-medium"
        >
          New Project
        </.link>
      </div>

      <%!-- Watchtower Filter Banner --%>
      <div
        :if={@watchtower_filter}
        class="mb-4 flex items-center justify-between bg-warning/5 border border-warning/20 rounded-lg px-4 py-2"
      >
        <span class="text-sm text-base-content/70">
          Showing: projects missing descriptions
        </span>
        <.link
          patch={~p"/org/#{@org_id}/projects"}
          class="text-base-content/40 hover:text-base-content/70 transition-colors"
        >
          <.icon name="hero-x-mark" class="w-4 h-4" />
        </.link>
      </div>

      <%!-- Project List --%>
      <div class="bg-base-100 border border-base-300 rounded-xl overflow-hidden">
        <%= if @projects == [] do %>
          <div class="px-6 py-16 text-center">
            <div class="w-12 h-12 mx-auto mb-4 rounded-full bg-base-200 flex items-center justify-center">
              <.icon name="hero-folder" class="w-6 h-6 text-base-content/40" />
            </div>
            <p class="text-sm font-medium text-base-content">No projects yet</p>
            <p class="text-sm text-base-content/60 mt-1">Create your first project to get started.</p>
          </div>
        <% else %>
          <div
            :for={project <- @projects}
            class="px-6 py-5 flex items-center gap-4 border-b border-base-content/10 last:border-b-0 hover:bg-base-200 transition-colors"
          >
            <.link
              navigate={~p"/org/#{@org_id}/projects/#{project.id}"}
              class="flex items-center gap-4 flex-1 min-w-0"
            >
              <.avatar name={project.name} seed={project.id} type={:project} size={:lg} />
              <div class="min-w-0 flex-1">
                <h3 class="text-sm font-medium text-base-content truncate">{project.name}</h3>
                <p :if={project.customer} class="text-sm text-base-content/60 truncate">
                  <span
                    :if={Project.composite_key(project)}
                    class="font-mono text-xs text-base-content/40"
                  >
                    {Project.composite_key(project)} ·
                  </span>
                  {project.customer.name}
                </p>
              </div>
            </.link>
            <div class="flex items-center gap-3 flex-shrink-0">
              <span :if={project.currency} class="text-xs text-base-content/40 font-mono">
                {project.currency.code}
              </span>
              <span class={"text-xs px-2 py-0.5 rounded-full #{project_status_class(project.status)}"}>
                {project.status}
              </span>
              <.link
                patch={~p"/org/#{@org_id}/projects/#{project.id}/edit"}
                class="text-base-content/40 hover:text-base-content/70 transition-colors"
              >
                <.icon name="hero-pencil" class="w-5 h-5" />
              </.link>
            </div>
          </div>
        <% end %>
      </div>

      <%!-- Modal --%>
      <.modal
        :if={@live_action in [:new, :edit]}
        id="project-modal"
        show
        on_cancel={
          JS.patch(
            if @live_action == :new,
              do: ~p"/org/#{@org_id}/projects",
              else: ~p"/org/#{@org_id}/projects/#{@project.id}"
          )
        }
      >
        <h2 class="text-xl font-semibold text-base-content mb-6">
          {if @live_action == :new, do: "New Project", else: "Edit Project"}
        </h2>

        <.form for={@form} id="project-form" phx-submit="save" phx-change="validate">
          <div class="space-y-4">
            <%!-- Customer Selection --%>
            <div>
              <label class="block text-xs font-medium text-base-content/60 mb-1.5">Customer *</label>
              <select
                name={@form[:customer_id].name}
                phx-change="customer_changed"
                required
                disabled={@live_action == :edit}
                class={"w-full px-3 py-2 border border-base-content/20 rounded-lg text-sm #{if @live_action == :edit, do: "bg-base-200 text-base-content/60"}"}
              >
                <option value="">Select a customer</option>
                <%= for customer <- @customers do %>
                  <option
                    value={customer.id}
                    selected={to_string(customer.id) == to_string(@form[:customer_id].value)}
                  >
                    {customer.key} - {customer.name}
                  </option>
                <% end %>
              </select>
            </div>

            <%!-- Project Key (composite display) --%>
            <div>
              <label class="block text-xs font-medium text-base-content/60 mb-1.5">Project Key</label>
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
                  class="flex-1 px-3 py-2 border border-base-content/20 rounded-r-lg text-sm font-mono uppercase"
                />
              </div>
              <p
                :if={@customer_key && @form[:key].value && @form[:key].value != ""}
                class="mt-1 text-xs text-base-content/60"
              >
                Full key:
                <span class="font-mono">
                  {@customer_key}-{String.upcase(@form[:key].value || "")}
                </span>
              </p>
            </div>

            <%!-- Currency --%>
            <div>
              <label class="block text-xs font-medium text-base-content/60 mb-1.5">Currency</label>
              <select
                name={@form[:currency_id].name}
                class="w-full px-3 py-2 border border-base-content/20 rounded-lg text-sm"
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
            </div>

            <%!-- Project Name --%>
            <div>
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
                class="w-full px-3 py-2 border border-base-content/20 rounded-lg text-sm"
              />
            </div>

            <%!-- Status (edit only) --%>
            <div :if={@live_action == :edit}>
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

          <div class="mt-6 flex justify-end gap-3">
            <.link
              patch={
                if @live_action == :new,
                  do: ~p"/org/#{@org_id}/projects",
                  else: ~p"/org/#{@org_id}/projects/#{@project.id}"
              }
              class="px-4 py-2 text-sm text-base-content/70 hover:text-base-content transition-colors"
            >
              Cancel
            </.link>
            <button
              type="submit"
              phx-disable-with="Saving..."
              class="px-4 py-2 bg-neutral text-neutral-content text-sm rounded-lg hover:bg-neutral/90 transition-colors font-medium"
            >
              {if @live_action == :new, do: "Create Project", else: "Save Changes"}
            </button>
          </div>
        </.form>
      </.modal>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    org_id = socket.assigns.org_id
    customers = CRM.list_customers(org_id)
    currencies = Currencies.list_currencies(org_id)

    {:ok,
     socket
     |> assign(:page_title, "Projects")
     |> assign(:active_tab, :projects)
     |> assign(:status_filter, "active")
     |> assign(:watchtower_filter, nil)
     |> assign(:customers, customers)
     |> assign(:currencies, currencies)
     |> assign(:customer_key, nil)
     |> assign(:project, nil)
     |> assign(:form, nil)
     |> fetch_projects()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    changeset = Portfolio.change_project(%Project{})

    socket
    |> assign(:page_title, "New Project")
    |> assign(:project, %Project{})
    |> assign(:customer_key, nil)
    |> assign(:form, to_form(changeset))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    user_id = socket.assigns.current_user.id
    is_admin = admin?(socket.assigns.current_membership)
    is_collaborator = is_admin || Portfolio.get_collaborator(id, user_id) != nil

    unless is_collaborator do
      socket
      |> put_flash(:error, "Not authorized")
      |> push_patch(to: ~p"/org/#{socket.assigns.org_id}/projects")
    else
      project = Portfolio.get_project!(id, socket.assigns.org_id)
      changeset = Portfolio.change_project(project)
      customer_key = if project.customer, do: project.customer.key

      socket
      |> assign(:page_title, "Edit Project")
      |> assign(:project, project)
      |> assign(:customer_key, customer_key)
      |> assign(:form, to_form(changeset))
    end
  end

  defp apply_action(socket, :index, params) do
    is_admin = admin?(socket.assigns.current_membership)
    watchtower = if is_admin, do: params["watchtower"]

    socket =
      if watchtower == "missing_descriptions" do
        socket
        |> assign(:watchtower_filter, watchtower)
        |> assign(:status_filter, nil)
        |> fetch_projects(watchtower: :missing_descriptions)
      else
        socket
        |> assign(:watchtower_filter, nil)
        |> assign(:status_filter, socket.assigns.status_filter || "active")
        |> fetch_projects()
      end

    socket
    |> assign(:page_title, "Projects")
    |> assign(:project, nil)
    |> assign(:customer_key, nil)
    |> assign(:form, nil)
  end

  @impl true
  def handle_event("customer_changed", %{"project" => %{"customer_id" => customer_id}}, socket) do
    customer = Enum.find(socket.assigns.customers, &(to_string(&1.id) == customer_id))

    {customer_key, currency_id} =
      if customer do
        {customer.key, customer.default_currency_id}
      else
        {nil, nil}
      end

    # Update form with inherited currency
    params = %{
      "customer_id" => customer_id,
      "currency_id" => currency_id
    }

    changeset =
      (socket.assigns.project || %Project{})
      |> Portfolio.change_project(params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:customer_key, customer_key)
     |> assign(:form, to_form(changeset))}
  end

  def handle_event("validate", %{"project" => project_params}, socket) do
    # Update customer key if customer changed
    customer_id = project_params["customer_id"]
    customer = Enum.find(socket.assigns.customers, &(to_string(&1.id) == customer_id))
    customer_key = if customer, do: customer.key, else: socket.assigns.customer_key

    changeset =
      (socket.assigns.project || %Project{})
      |> Portfolio.change_project(project_params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:customer_key, customer_key)
     |> assign(:form, to_form(changeset))}
  end

  def handle_event("toggle_filter", %{"filter" => filter}, socket) do
    status_filter = if filter in ~w(active completed archived), do: filter

    {:noreply,
     socket
     |> assign(:status_filter, status_filter)
     |> assign(:watchtower_filter, nil)
     |> fetch_projects()}
  end

  def handle_event("save", %{"project" => project_params}, socket) do
    save_project(socket, socket.assigns.live_action, project_params)
  end

  defp save_project(socket, :new, project_params) do
    customer_id = project_params["customer_id"]
    user_id = socket.assigns.current_user.id
    org_id = socket.assigns.org_id

    case Portfolio.create_project(project_params, customer_id, user_id, org_id) do
      {:ok, project} ->
        {:noreply,
         socket
         |> put_flash(:info, "Project created successfully")
         |> push_navigate(to: ~p"/org/#{socket.assigns.org_id}/projects/#{project.id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_project(socket, :edit, project_params) do
    user_id = socket.assigns.current_user.id
    project_id = socket.assigns.project.id
    is_admin = admin?(socket.assigns.current_membership)
    is_collaborator = is_admin || Portfolio.get_collaborator(project_id, user_id) != nil

    unless is_collaborator do
      {:noreply, put_flash(socket, :error, "Not authorized")}
    else
      case Portfolio.update_project(socket.assigns.project, project_params) do
        {:ok, project} ->
          {:noreply,
           socket
           |> put_flash(:info, "Project updated successfully")
           |> push_navigate(to: ~p"/org/#{socket.assigns.org_id}/projects/#{project.id}")}

        {:error, changeset} ->
          {:noreply, assign(socket, form: to_form(changeset))}
      end
    end
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :active, :boolean, required: true

  defp filter_pill(assigns) do
    ~H"""
    <button
      phx-click="toggle_filter"
      phx-value-filter={@value}
      class={"px-3 py-1 rounded-md transition-colors #{if @active, do: "bg-base-100 text-base-content shadow-sm", else: "text-base-content/50 hover:text-base-content/70"}"}
    >
      {@label}
    </button>
    """
  end

  defp fetch_projects(socket, extra_opts \\ []) do
    %{org_id: org_id, current_user: user, current_membership: %{role: role}, status_filter: sf} =
      socket.assigns

    opts = if sf, do: [status: sf], else: []
    assign(socket, :projects, Portfolio.list_projects(org_id, user.id, role, opts ++ extra_opts))
  end
end
