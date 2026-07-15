defmodule EstimateWeb.ProjectLive.Components.EstimationsTab do
  use EstimateWeb, :html

  attr :estimations, :list, required: true
  attr :deleting_estimation, :any, default: nil
  attr :can_edit_project, :boolean, required: true
  attr :can_delete_project, :boolean, required: true
  attr :org_id, :string, required: true
  attr :project, :map, required: true
  attr :deleted_estimations, :list, required: true
  attr :show_trash, :boolean, required: true
  attr :permanently_deleting, :any, default: nil

  def estimations_tab(assigns) do
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
end
