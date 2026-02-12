defmodule EstimateWeb.TemplatesLive.Index do
  use EstimateWeb, :live_view

  alias Estimate.Templates

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto">
      <div class="flex items-center justify-between mb-6">
        <div>
          <h1 class="text-2xl font-bold text-gray-900">Estimation Templates</h1>
          <p class="text-sm text-gray-500 mt-1">
            Reusable epic & task structures for new estimations
          </p>
        </div>
      </div>

      <%!-- Template Cards --%>
      <div class="grid gap-4 mb-6">
        <%= for template <- @templates do %>
          <div class="bg-white border border-gray-200 rounded-xl p-5 hover:border-gray-300 transition-colors group">
            <div class="flex items-start justify-between">
              <.link
                navigate={~p"/org/#{@org_id}/templates/#{template.id}"}
                class="flex-1 min-w-0"
              >
                <h3 class="text-base font-semibold text-gray-900 group-hover:text-gray-700">
                  {template.name}
                </h3>
                <p :if={template.description} class="text-sm text-gray-500 mt-1 line-clamp-2">
                  {template.description}
                </p>
                <div class="flex items-center gap-4 mt-3 text-xs text-gray-400">
                  <span class="flex items-center gap-1">
                    <.icon name="hero-rectangle-stack" class="w-3.5 h-3.5" />
                    {length(template.epics)} epics
                  </span>
                  <span class="flex items-center gap-1">
                    <.icon name="hero-list-bullet" class="w-3.5 h-3.5" />
                    {Enum.sum(Enum.map(template.epics, fn e -> length(e.tasks) end))} tasks
                  </span>
                </div>
              </.link>
              <button
                :if={@is_admin}
                phx-click="confirm_delete"
                phx-value-id={template.id}
                class="p-1.5 text-gray-400 hover:text-red-600 opacity-0 group-hover:opacity-100 transition-all"
              >
                <.icon name="hero-trash" class="w-4 h-4" />
              </button>
            </div>
          </div>
        <% end %>

        <%= if Enum.empty?(@templates) do %>
          <div class="bg-white border border-gray-200 rounded-xl p-12 text-center">
            <.icon name="hero-rectangle-stack" class="w-12 h-12 text-gray-300 mx-auto" />
            <p class="mt-3 text-gray-500">No templates yet</p>
            <p class="text-sm text-gray-400 mt-1">Create one below to get started</p>
          </div>
        <% end %>
      </div>

      <%!-- New Template Bar --%>
      <div class="bg-white border border-gray-200 rounded-xl">
        <form phx-submit="create_template" class="px-6 py-4">
          <div class="flex items-center gap-3">
            <input
              type="text"
              name="name"
              value=""
              placeholder="New template name..."
              required
              class="flex-1 px-3 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent"
            />
            <button
              type="submit"
              class="px-4 py-2 bg-gray-900 text-white text-sm rounded-lg hover:bg-gray-800 transition-colors font-medium"
            >
              Create Template
            </button>
          </div>
        </form>
      </div>

      <%!-- Delete Confirmation Modal --%>
      <.modal
        :if={@deleting_template}
        id="delete-template-modal"
        show
        on_cancel={JS.push("cancel_delete")}
      >
        <div class="text-center">
          <div class="w-12 h-12 rounded-full bg-red-100 flex items-center justify-center mx-auto mb-4">
            <.icon name="hero-exclamation-triangle" class="w-6 h-6 text-red-600" />
          </div>
          <h3 class="text-lg font-semibold text-gray-900 mb-2">Delete Template</h3>
          <p class="text-sm text-gray-500 mb-6">
            Are you sure you want to delete <span class="font-medium text-gray-900">{@deleting_template.name}</span>?
            This action cannot be undone.
          </p>
          <div class="flex gap-3 justify-center">
            <button
              phx-click="cancel_delete"
              class="px-4 py-2 text-sm text-gray-600 hover:text-gray-900 transition-colors"
            >
              Cancel
            </button>
            <button
              phx-click="delete_template"
              class="px-4 py-2 bg-red-600 text-white text-sm rounded-lg hover:bg-red-700 transition-colors font-medium"
            >
              Delete
            </button>
          </div>
        </div>
      </.modal>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    templates = Templates.list_estimation_templates(socket.assigns.org_id)

    {:ok,
     socket
     |> assign(:page_title, "Templates")
     |> assign(:active_tab, :templates)
     |> assign(:templates, templates)
     |> assign(:is_admin, socket.assigns.current_membership.role in ["owner", "admin"])
     |> assign(:deleting_template, nil)}
  end

  @impl true
  def handle_event("create_template", %{"name" => name}, socket) when name != "" do
    case Templates.create_estimation_template(socket.assigns.org_id, %{"name" => name}) do
      {:ok, template} ->
        {:noreply,
         socket
         |> push_navigate(to: ~p"/org/#{socket.assigns.org_id}/templates/#{template.id}")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not create template")}
    end
  end

  def handle_event("create_template", _params, socket), do: {:noreply, socket}

  def handle_event("confirm_delete", %{"id" => id}, socket) do
    template = Templates.get_estimation_template!(id, socket.assigns.org_id)
    {:noreply, assign(socket, :deleting_template, template)}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :deleting_template, nil)}
  end

  def handle_event("delete_template", _params, socket) do
    unless socket.assigns.is_admin do
      {:noreply,
       socket
       |> put_flash(:error, "Not authorized")
       |> assign(:deleting_template, nil)}
    else
      template = socket.assigns.deleting_template

      case Templates.delete_estimation_template(template) do
        {:ok, _} ->
          templates = Templates.list_estimation_templates(socket.assigns.org_id)

          {:noreply,
           socket
           |> put_flash(:info, "Template deleted")
           |> assign(:templates, templates)
           |> assign(:deleting_template, nil)}

        {:error, _} ->
          {:noreply,
           socket
           |> put_flash(:error, "Could not delete template")
           |> assign(:deleting_template, nil)}
      end
    end
  end
end
