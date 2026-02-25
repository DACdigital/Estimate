defmodule EstimateWeb.SettingsLive.Components.ReassignmentModal do
  use EstimateWeb, :html

  attr :removing_member, :map, required: true
  attr :sole_owned_projects, :list, required: true
  attr :eligible_members, :list, required: true
  attr :reassign_tab, :atom, required: true
  attr :reassignments, :map, required: true

  def reassignment_modal(assigns) do
    member_name = assigns.removing_member.user.name || assigns.removing_member.user.email
    project_count = length(assigns.sole_owned_projects)
    all_assigned? = reassignments_complete?(assigns)

    assigns =
      assigns
      |> assign(:member_name, member_name)
      |> assign(:project_count, project_count)
      |> assign(:all_assigned?, all_assigned?)

    ~H"""
    <.modal id="reassign-modal" show on_cancel={JS.push("cancel_remove_member")}>
      <div>
        <div class="flex items-center gap-3 mb-4">
          <div class="w-10 h-10 rounded-full bg-warning/10 flex items-center justify-center">
            <.icon name="hero-exclamation-triangle" class="w-5 h-5 text-warning" />
          </div>
          <div>
            <h3 class="text-lg font-semibold text-base-content">Remove Member</h3>
            <p class="text-sm text-base-content/60">
              {@member_name} is the sole owner of {@project_count}
              {ngettext("project", "projects", @project_count)}. Reassign ownership before removing.
            </p>
          </div>
        </div>

        <%!-- Tabs --%>
        <div class="border-b border-base-300 mb-4">
          <div class="flex gap-4">
            <button
              :for={
                {tab, label} <- [
                  {:all, "All"},
                  {:per_customer, "Per customer"},
                  {:per_project, "Per project"}
                ]
              }
              phx-click="switch_reassign_tab"
              phx-value-tab={tab}
              class={[
                "pb-2 text-sm font-medium border-b-2 transition-colors",
                @reassign_tab == tab && "border-base-content text-base-content",
                @reassign_tab != tab &&
                  "border-transparent text-base-content/60 hover:text-base-content/80"
              ]}
            >
              {label}
            </button>
          </div>
        </div>

        <%!-- Tab content --%>
        <div class="max-h-80 overflow-y-auto">
          <.reassign_all_tab
            :if={@reassign_tab == :all}
            eligible_members={@eligible_members}
            reassignments={@reassignments}
            sole_owned_projects={@sole_owned_projects}
          />
          <.reassign_per_customer_tab
            :if={@reassign_tab == :per_customer}
            eligible_members={@eligible_members}
            reassignments={@reassignments}
            sole_owned_projects={@sole_owned_projects}
          />
          <.reassign_per_project_tab
            :if={@reassign_tab == :per_project}
            eligible_members={@eligible_members}
            reassignments={@reassignments}
            sole_owned_projects={@sole_owned_projects}
          />
        </div>

        <%!-- Footer --%>
        <div class="flex gap-3 justify-end mt-6 pt-4 border-t border-base-300">
          <button
            phx-click="cancel_remove_member"
            class="px-4 py-2 text-sm text-base-content/70 hover:text-base-content transition-colors"
          >
            Cancel
          </button>
          <button
            phx-click="remove_member"
            disabled={!@all_assigned?}
            class={[
              "px-4 py-2 text-sm rounded-lg font-medium transition-colors",
              @all_assigned? && "bg-error text-error-content hover:bg-error/90",
              !@all_assigned? && "bg-base-200 text-base-content/30 cursor-not-allowed"
            ]}
          >
            Remove & Reassign
          </button>
        </div>
      </div>
    </.modal>
    """
  end

  defp reassign_all_tab(assigns) do
    project_ids = Enum.map(assigns.sole_owned_projects, fn {p, _} -> p.id end)
    values = assigns.reassignments |> Map.take(project_ids) |> Map.values() |> Enum.uniq()
    selected = if length(values) == 1, do: hd(values), else: nil
    assigns = assign(assigns, :selected, selected)

    ~H"""
    <div class="space-y-2">
      <label class="block text-xs font-medium text-base-content/60 mb-1">
        New owner for all {@sole_owned_projects |> length()}
        {ngettext("project", "projects", length(@sole_owned_projects))}
      </label>
      <.member_select
        eligible_members={@eligible_members}
        selected={@selected}
        event="reassign_all"
        field="user_id"
      />
    </div>
    """
  end

  defp reassign_per_customer_tab(assigns) do
    groups =
      assigns.sole_owned_projects
      |> Enum.group_by(fn {p, _} -> p.customer end)
      |> Enum.sort_by(fn {c, _} -> c.name end)

    assigns = assign(assigns, :groups, groups)

    ~H"""
    <div class="space-y-4">
      <div :for={{customer, projects} <- @groups} class="space-y-2">
        <div class="flex items-center justify-between">
          <span class="text-sm font-medium text-base-content">{customer.name}</span>
          <span class="text-xs text-base-content/40">
            {length(projects)} {ngettext("project", "projects", length(projects))}
          </span>
        </div>
        <% project_ids = Enum.map(projects, fn {p, _} -> p.id end)
        values = @reassignments |> Map.take(project_ids) |> Map.values() |> Enum.uniq()
        selected = if length(values) == 1, do: hd(values), else: nil %>
        <.member_select
          eligible_members={@eligible_members}
          selected={selected}
          event="reassign_customer"
          field="user_id"
          extra_values={%{"customer_id" => customer.id}}
        />
      </div>
    </div>
    """
  end

  defp reassign_per_project_tab(assigns) do
    ~H"""
    <div class="space-y-3">
      <div :for={{project, est_count} <- @sole_owned_projects} class="space-y-1">
        <div class="flex items-center justify-between">
          <span class="text-sm font-medium text-base-content">{project.name}</span>
          <span class="text-xs text-base-content/40">
            {est_count} {ngettext("estimation", "estimations", est_count)}
          </span>
        </div>
        <.member_select
          eligible_members={@eligible_members}
          selected={Map.get(@reassignments, project.id)}
          event="reassign_project"
          field="user_id"
          extra_values={%{"project_id" => project.id}}
        />
      </div>
    </div>
    """
  end

  defp member_select(assigns) do
    assigns = assign_new(assigns, :extra_values, fn -> %{} end)

    ~H"""
    <select
      phx-change={@event}
      name={@field}
      {@extra_values |> Enum.map(fn {k, v} -> {"phx-value-#{k}", v} end)}
      class="w-full px-3 py-2 border border-base-300 rounded-lg text-sm"
    >
      <option value="">Select member...</option>
      <option
        :for={m <- @eligible_members}
        value={m.user_id}
        selected={@selected == m.user_id}
      >
        {m.user.name || m.user.email}
      </option>
    </select>
    """
  end

  defp reassignments_complete?(assigns) do
    eligible_ids = MapSet.new(assigns.eligible_members, & &1.user_id)

    Enum.all?(assigns.sole_owned_projects, fn {p, _} ->
      case Map.get(assigns.reassignments, p.id) do
        nil -> false
        "" -> false
        uid -> MapSet.member?(eligible_ids, uid)
      end
    end)
  end
end
