defmodule EstimateWeb.ProjectLive.Components.DeleteProjectModal do
  use EstimateWeb, :html

  attr :deleting_project, :boolean, required: true
  attr :delete_impact, :map, required: true
  attr :delete_confirmation_input, :string, required: true
  attr :project, :map, required: true

  def delete_project_modal(assigns) do
    ~H"""
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
    """
  end
end
