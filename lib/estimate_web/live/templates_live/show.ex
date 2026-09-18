defmodule EstimateWeb.TemplatesLive.Show do
  use EstimateWeb, :live_view

  alias Estimate.Templates
  alias EstimateWeb.TemplatesLive.Show.{Epics, Tasks, Template}

  import EstimateWeb.EstimatorLive.Helpers, only: [priority_label: 1, priority_class: 1]

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto">
      <%!-- Breadcrumb --%>
      <nav class="flex items-center space-x-2 text-sm text-base-content/60 mb-6">
        <.link navigate={~p"/org/#{@org_id}/templates"} class="hover:text-base-content">
          Templates
        </.link>
        <span class="text-base-content/30">&rsaquo;</span>
        <span class="text-base-content font-medium">{@template.name}</span>
      </nav>

      <%!-- Header --%>
      <div class="mb-6">
        <%= if @is_admin do %>
          <form phx-change="update_template" phx-debounce="500">
            <input
              type="text"
              name="name"
              value={@template.name}
              class="text-2xl font-bold text-base-content bg-transparent border-0 border-b-2 border-transparent hover:border-base-300 focus:border-base-content focus:ring-0 p-0 pb-1 w-full transition-colors"
            />
            <textarea
              name="description"
              rows="1"
              placeholder="Add description..."
              class="mt-2 text-sm text-base-content/60 bg-transparent border-0 border-b-2 border-transparent hover:border-base-300 focus:border-base-content focus:ring-0 p-0 pb-1 w-full resize-none transition-colors"
            >{@template.description}</textarea>
          </form>
        <% else %>
          <h1 class="text-2xl font-bold text-base-content">{@template.name}</h1>
          <p :if={@template.description} class="mt-2 text-sm text-base-content/60">
            {@template.description}
          </p>
        <% end %>
      </div>

      <%!-- Actions --%>
      <div :if={@is_admin} class="flex items-center justify-end gap-4 mb-4">
        <button
          phx-click="add_epic"
          class="px-4 py-2 bg-neutral text-neutral-content text-sm rounded-lg hover:bg-neutral/90 transition-colors font-medium"
        >
          Add Epic
        </button>
      </div>

      <%!-- Template Structure --%>
      <div class="bg-base-100 border border-base-300 rounded-xl overflow-hidden">
        <div id="epics-container" phx-hook="TemplateSortable" data-group="epics" data-sort-key="epics">
          <%= for epic <- @template.epics do %>
            <div
              id={"epic-#{epic.id}"}
              data-id={epic.id}
              class="border-b border-base-content/10 last:border-b-0"
            >
              <%!-- Epic Row --%>
              <div class="flex items-center gap-3 px-4 py-3 bg-base-200 group">
                <div class="drag-handle cursor-grab text-base-content/30 hover:text-base-content/60">
                  <.icon name="hero-bars-3" class="w-4 h-4" />
                </div>
                <div class="flex-1 min-w-0">
                  <span class="font-semibold text-sm text-base-content">{epic.name}</span>
                  <button
                    :if={epic.description}
                    phx-click="edit_epic"
                    phx-value-id={epic.id}
                    class="ml-1.5 text-base-content/40 hover:text-base-content/70"
                    title={epic.description}
                  >
                    <.icon name="hero-document-text" class="w-3.5 h-3.5" />
                  </button>
                </div>
                <div
                  :if={@is_admin}
                  class="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity"
                >
                  <button
                    phx-click="edit_epic"
                    phx-value-id={epic.id}
                    class="p-1 text-base-content/40 hover:text-base-content/70 rounded"
                    title="Edit epic"
                  >
                    <.icon name="hero-pencil" class="w-3.5 h-3.5" />
                  </button>
                  <button
                    phx-click="add_task"
                    phx-value-epic-id={epic.id}
                    class="p-1 text-base-content/40 hover:text-base-content/70 rounded"
                    title="Add task"
                  >
                    <.icon name="hero-plus" class="w-3.5 h-3.5" />
                  </button>
                  <button
                    phx-click="confirm_delete_epic"
                    phx-value-id={epic.id}
                    class="p-1 text-base-content/40 hover:text-error rounded"
                    title="Delete epic"
                  >
                    <.icon name="hero-trash" class="w-3.5 h-3.5" />
                  </button>
                </div>
              </div>

              <%!-- Tasks --%>
              <div
                id={"tasks-#{epic.id}"}
                phx-hook="TemplateSortable"
                data-group={"tasks-#{epic.id}"}
                data-sort-key={"tasks-#{epic.id}"}
                data-epic-id={epic.id}
                class="divide-y divide-base-content/5"
              >
                <%= for task <- epic.tasks do %>
                  <div
                    id={"task-#{task.id}"}
                    data-id={task.id}
                    class="flex items-center gap-3 px-4 py-2.5 pl-10 group/task hover:bg-base-200/50"
                  >
                    <div class="drag-handle cursor-grab text-base-content/20 hover:text-base-content/40">
                      <.icon name="hero-bars-3" class="w-3.5 h-3.5" />
                    </div>
                    <span class={"inline-flex px-1.5 py-0.5 text-xs font-medium rounded #{priority_class(task.priority)}"}>
                      {priority_label(task.priority)}
                    </span>
                    <span class="text-sm text-base-content/80 flex-1 min-w-0 truncate">
                      {task.name}
                    </span>
                    <button
                      :if={task.description}
                      phx-click="edit_task"
                      phx-value-id={task.id}
                      phx-value-epic-id={epic.id}
                      class="text-base-content/30 hover:text-base-content/60"
                      title={task.description}
                    >
                      <.icon name="hero-document-text" class="w-3.5 h-3.5" />
                    </button>
                    <div
                      :if={@is_admin}
                      class="flex items-center gap-1 opacity-0 group-hover/task:opacity-100 transition-opacity"
                    >
                      <button
                        phx-click="edit_task"
                        phx-value-id={task.id}
                        phx-value-epic-id={epic.id}
                        class="p-1 text-base-content/40 hover:text-base-content/70 rounded"
                        title="Edit task"
                      >
                        <.icon name="hero-pencil" class="w-3.5 h-3.5" />
                      </button>
                      <button
                        phx-click="confirm_delete_task"
                        phx-value-id={task.id}
                        phx-value-epic-id={epic.id}
                        class="p-1 text-base-content/40 hover:text-error rounded"
                        title="Delete task"
                      >
                        <.icon name="hero-trash" class="w-3.5 h-3.5" />
                      </button>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>

        <%= if Enum.empty?(@template.epics) do %>
          <div class="px-6 py-12 text-center">
            <.icon name="hero-rectangle-stack" class="w-12 h-12 text-base-content/30 mx-auto" />
            <p class="mt-2 text-base-content/60">No epics yet</p>
            <p class="text-sm text-base-content/40 mt-1">Click "Add Epic" to get started</p>
          </div>
        <% end %>
      </div>

      <%!-- Epic Modal --%>
      <.modal
        :if={@modal == :epic}
        id="epic-modal"
        show
        on_cancel={JS.push("close_modal")}
      >
        <h3 class="text-lg font-semibold text-base-content mb-4">
          {if @current_epic_id, do: "Edit Epic", else: "New Epic"}
        </h3>
        <.form for={@epic_form} phx-submit="save_epic">
          <input type="hidden" name="epic_id" value={@current_epic_id} />
          <div class="space-y-4">
            <div>
              <label class="block text-xs font-medium text-base-content/60 mb-1.5">Name *</label>
              <input
                type="text"
                name="name"
                value={@epic_form[:name].value}
                required
                autofocus
                class="w-full px-3 py-2 border border-base-content/20 rounded-lg text-sm"
              />
            </div>
            <div>
              <label class="block text-xs font-medium text-base-content/60 mb-1.5">Description</label>
              <textarea
                name="description"
                rows="3"
                class="w-full px-3 py-2 border border-base-content/20 rounded-lg text-sm resize-none"
              ><%= @epic_form[:description].value %></textarea>
            </div>
            <div class="flex justify-end gap-3 pt-2">
              <button
                type="button"
                phx-click="close_modal"
                class="px-4 py-2 text-sm text-base-content/70 hover:text-base-content"
              >
                Cancel
              </button>
              <button
                type="submit"
                class="px-4 py-2 bg-neutral text-neutral-content text-sm rounded-lg hover:bg-neutral/90 font-medium"
              >
                Save
              </button>
            </div>
          </div>
        </.form>
      </.modal>

      <%!-- Task Modal --%>
      <.modal
        :if={@modal == :task}
        id="task-modal"
        show
        on_cancel={JS.push("close_modal")}
      >
        <h3 class="text-lg font-semibold text-base-content mb-4">
          {if @current_task_id, do: "Edit Task", else: "New Task"}
        </h3>
        <.form for={@task_form} phx-submit="save_task">
          <input type="hidden" name="task_id" value={@current_task_id} />
          <input type="hidden" name="epic_id" value={@current_epic_id} />
          <div class="space-y-4">
            <div>
              <label class="block text-xs font-medium text-base-content/60 mb-1.5">Name *</label>
              <input
                type="text"
                name="name"
                value={@task_form[:name].value}
                required
                autofocus
                class="w-full px-3 py-2 border border-base-content/20 rounded-lg text-sm"
              />
            </div>
            <div>
              <label class="block text-xs font-medium text-base-content/60 mb-1.5">Description</label>
              <textarea
                name="description"
                rows="3"
                class="w-full px-3 py-2 border border-base-content/20 rounded-lg text-sm resize-none"
              ><%= @task_form[:description].value %></textarea>
            </div>
            <div>
              <label class="block text-xs font-medium text-base-content/60 mb-1.5">Priority</label>
              <select
                name="priority"
                class="w-full px-3 py-2 border border-base-content/20 rounded-lg text-sm"
              >
                <%= for p <- ~w(must should could wont) do %>
                  <option value={p} selected={@task_form[:priority].value == p}>
                    {priority_label(p)}
                  </option>
                <% end %>
              </select>
            </div>
            <div class="flex justify-end gap-3 pt-2">
              <button
                type="button"
                phx-click="close_modal"
                class="px-4 py-2 text-sm text-base-content/70 hover:text-base-content"
              >
                Cancel
              </button>
              <button
                type="submit"
                class="px-4 py-2 bg-neutral text-neutral-content text-sm rounded-lg hover:bg-neutral/90 font-medium"
              >
                Save
              </button>
            </div>
          </div>
        </.form>
      </.modal>

      <.confirm_modal
        :if={@deleting_epic}
        id="delete-epic-modal"
        title="Delete Epic"
        message={"Delete #{@deleting_epic.name} and all its tasks?"}
        confirm_event="delete_epic"
        cancel_event="cancel_delete"
      />

      <.confirm_modal
        :if={@deleting_task}
        id="delete-task-modal"
        title="Delete Task"
        item_name={@deleting_task.name}
        confirm_event="delete_task"
        cancel_event="cancel_delete"
      />
    </div>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    org_id = socket.assigns.org_id
    template = Templates.get_estimation_template!(id, org_id)

    {:ok,
     socket
     |> assign(:page_title, template.name)
     |> assign(:active_tab, :templates)
     |> assign(:template, template)
     |> assign(:is_admin, admin?(socket.assigns.current_membership))
     |> assign(:modal, nil)
     |> assign(:epic_form, to_form(%{}, as: "epic"))
     |> assign(:task_form, to_form(%{}, as: "task"))
     |> assign(:current_epic_id, nil)
     |> assign(:current_task_id, nil)
     |> assign(:deleting_epic, nil)
     |> assign(:deleting_task, nil)}
  end

  @impl true
  def handle_event("update_template", params, socket),
    do: Template.update_template(socket, params)

  def handle_event("add_epic", params, socket), do: Epics.add_epic(socket, params)
  def handle_event("edit_epic", params, socket), do: Epics.edit_epic(socket, params)
  def handle_event("save_epic", params, socket), do: Epics.save_epic(socket, params)

  def handle_event("confirm_delete_epic", params, socket),
    do: Epics.confirm_delete_epic(socket, params)

  def handle_event("delete_epic", params, socket), do: Epics.delete_epic(socket, params)
  def handle_event("add_task", params, socket), do: Tasks.add_task(socket, params)
  def handle_event("edit_task", params, socket), do: Tasks.edit_task(socket, params)
  def handle_event("save_task", params, socket), do: Tasks.save_task(socket, params)

  def handle_event("confirm_delete_task", params, socket),
    do: Tasks.confirm_delete_task(socket, params)

  def handle_event("delete_task", params, socket), do: Tasks.delete_task(socket, params)
  def handle_event("reorder_epics", params, socket), do: Epics.reorder_epics(socket, params)
  def handle_event("reorder_tasks", params, socket), do: Tasks.reorder_tasks(socket, params)
  def handle_event("close_modal", params, socket), do: Template.close_modal(socket, params)
  def handle_event("cancel_delete", params, socket), do: Template.cancel_delete(socket, params)
end
