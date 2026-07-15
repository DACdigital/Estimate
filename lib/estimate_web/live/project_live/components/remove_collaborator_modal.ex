defmodule EstimateWeb.ProjectLive.Components.RemoveCollaboratorModal do
  use EstimateWeb, :html

  attr :removing_collaborator, :map, default: nil

  def remove_collaborator_modal(assigns) do
    ~H"""
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
    """
  end
end
