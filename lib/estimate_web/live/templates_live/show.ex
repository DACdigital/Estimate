defmodule EstimateWeb.TemplatesLive.Show do
  use EstimateWeb, :live_view

  alias Estimate.Templates

  import EstimateWeb.EstimatorLive.Helpers, only: [priority_label: 1, priority_class: 1]

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-5xl mx-auto">
      <%!-- Breadcrumb --%>
      <nav class="flex items-center space-x-2 text-sm text-gray-500 mb-6">
        <.link navigate={~p"/org/#{@org_id}/templates"} class="hover:text-gray-900">
          Templates
        </.link>
        <span class="text-gray-300">&rsaquo;</span>
        <span class="text-gray-900 font-medium">{@template.name}</span>
      </nav>

      <%!-- Header --%>
      <div class="mb-6">
        <%= if @is_admin do %>
          <form phx-change="update_template" phx-debounce="500">
            <input
              type="text"
              name="name"
              value={@template.name}
              class="text-2xl font-bold text-gray-900 bg-transparent border-0 border-b-2 border-transparent hover:border-gray-200 focus:border-gray-900 focus:ring-0 p-0 pb-1 w-full transition-colors"
            />
            <textarea
              name="description"
              rows="1"
              placeholder="Add description..."
              class="mt-2 text-sm text-gray-500 bg-transparent border-0 border-b-2 border-transparent hover:border-gray-200 focus:border-gray-900 focus:ring-0 p-0 pb-1 w-full resize-none transition-colors"
            >{@template.description}</textarea>
          </form>
        <% else %>
          <h1 class="text-2xl font-bold text-gray-900">{@template.name}</h1>
          <p :if={@template.description} class="mt-2 text-sm text-gray-500">
            {@template.description}
          </p>
        <% end %>
      </div>

      <%!-- Actions --%>
      <div :if={@is_admin} class="flex items-center justify-end gap-4 mb-4">
        <button
          phx-click="add_epic"
          class="px-4 py-2 bg-gray-900 text-white text-sm rounded-lg hover:bg-gray-800 transition-colors font-medium"
        >
          Add Epic
        </button>
      </div>

      <%!-- Template Structure --%>
      <div class="bg-white border border-gray-200 rounded-xl overflow-hidden">
        <div id="epics-container" phx-hook="TemplateSortable" data-group="epics" data-sort-key="epics">
          <%= for epic <- @template.epics do %>
            <div
              id={"epic-#{epic.id}"}
              data-id={epic.id}
              class="border-b border-gray-100 last:border-b-0"
            >
              <%!-- Epic Row --%>
              <div class="flex items-center gap-3 px-4 py-3 bg-gray-50 group">
                <div class="drag-handle cursor-grab text-gray-300 hover:text-gray-500">
                  <.icon name="hero-bars-3" class="w-4 h-4" />
                </div>
                <div class="flex-1 min-w-0">
                  <span class="font-semibold text-sm text-gray-900">{epic.name}</span>
                  <button
                    :if={epic.description}
                    phx-click="edit_epic"
                    phx-value-id={epic.id}
                    class="ml-1.5 text-gray-400 hover:text-gray-600"
                    title={epic.description}
                  >
                    <.icon name="hero-document-text" class="w-3.5 h-3.5" />
                  </button>
                </div>
                <div :if={@is_admin} class="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                  <button
                    phx-click="edit_epic"
                    phx-value-id={epic.id}
                    class="p-1 text-gray-400 hover:text-gray-600 rounded"
                    title="Edit epic"
                  >
                    <.icon name="hero-pencil" class="w-3.5 h-3.5" />
                  </button>
                  <button
                    phx-click="add_task"
                    phx-value-epic-id={epic.id}
                    class="p-1 text-gray-400 hover:text-gray-600 rounded"
                    title="Add task"
                  >
                    <.icon name="hero-plus" class="w-3.5 h-3.5" />
                  </button>
                  <button
                    phx-click="confirm_delete_epic"
                    phx-value-id={epic.id}
                    class="p-1 text-gray-400 hover:text-red-600 rounded"
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
                class="divide-y divide-gray-50"
              >
                <%= for task <- epic.tasks do %>
                  <div
                    id={"task-#{task.id}"}
                    data-id={task.id}
                    class="flex items-center gap-3 px-4 py-2.5 pl-10 group/task hover:bg-gray-50/50"
                  >
                    <div class="drag-handle cursor-grab text-gray-200 hover:text-gray-400">
                      <.icon name="hero-bars-3" class="w-3.5 h-3.5" />
                    </div>
                    <span class={"inline-flex px-1.5 py-0.5 text-xs font-medium rounded #{priority_class(task.priority)}"}>
                      {priority_label(task.priority)}
                    </span>
                    <span class="text-sm text-gray-700 flex-1 min-w-0 truncate">{task.name}</span>
                    <button
                      :if={task.description}
                      phx-click="edit_task"
                      phx-value-id={task.id}
                      phx-value-epic-id={epic.id}
                      class="text-gray-300 hover:text-gray-500"
                      title={task.description}
                    >
                      <.icon name="hero-document-text" class="w-3.5 h-3.5" />
                    </button>
                    <div :if={@is_admin} class="flex items-center gap-1 opacity-0 group-hover/task:opacity-100 transition-opacity">
                      <button
                        phx-click="edit_task"
                        phx-value-id={task.id}
                        phx-value-epic-id={epic.id}
                        class="p-1 text-gray-400 hover:text-gray-600 rounded"
                        title="Edit task"
                      >
                        <.icon name="hero-pencil" class="w-3.5 h-3.5" />
                      </button>
                      <button
                        phx-click="confirm_delete_task"
                        phx-value-id={task.id}
                        phx-value-epic-id={epic.id}
                        class="p-1 text-gray-400 hover:text-red-600 rounded"
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
            <.icon name="hero-rectangle-stack" class="w-12 h-12 text-gray-300 mx-auto" />
            <p class="mt-2 text-gray-500">No epics yet</p>
            <p class="text-sm text-gray-400 mt-1">Click "Add Epic" to get started</p>
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
        <h3 class="text-lg font-semibold text-gray-900 mb-4">
          {if @current_epic_id, do: "Edit Epic", else: "New Epic"}
        </h3>
        <.form for={@epic_form} phx-submit="save_epic">
          <input type="hidden" name="epic_id" value={@current_epic_id} />
          <div class="space-y-4">
            <div>
              <label class="block text-xs font-medium text-gray-500 mb-1.5">Name *</label>
              <input
                type="text"
                name="name"
                value={@epic_form[:name].value}
                required
                autofocus
                class="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent"
              />
            </div>
            <div>
              <label class="block text-xs font-medium text-gray-500 mb-1.5">Description</label>
              <textarea
                name="description"
                rows="3"
                class="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent resize-none"
              ><%= @epic_form[:description].value %></textarea>
            </div>
            <div class="flex justify-end gap-3 pt-2">
              <button
                type="button"
                phx-click="close_modal"
                class="px-4 py-2 text-sm text-gray-600 hover:text-gray-900"
              >
                Cancel
              </button>
              <button
                type="submit"
                class="px-4 py-2 bg-gray-900 text-white text-sm rounded-lg hover:bg-gray-800 font-medium"
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
        <h3 class="text-lg font-semibold text-gray-900 mb-4">
          {if @current_task_id, do: "Edit Task", else: "New Task"}
        </h3>
        <.form for={@task_form} phx-submit="save_task">
          <input type="hidden" name="task_id" value={@current_task_id} />
          <input type="hidden" name="epic_id" value={@current_epic_id} />
          <div class="space-y-4">
            <div>
              <label class="block text-xs font-medium text-gray-500 mb-1.5">Name *</label>
              <input
                type="text"
                name="name"
                value={@task_form[:name].value}
                required
                autofocus
                class="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent"
              />
            </div>
            <div>
              <label class="block text-xs font-medium text-gray-500 mb-1.5">Description</label>
              <textarea
                name="description"
                rows="3"
                class="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent resize-none"
              ><%= @task_form[:description].value %></textarea>
            </div>
            <div>
              <label class="block text-xs font-medium text-gray-500 mb-1.5">Priority</label>
              <select
                name="priority"
                class="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-gray-900 focus:border-transparent"
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
                class="px-4 py-2 text-sm text-gray-600 hover:text-gray-900"
              >
                Cancel
              </button>
              <button
                type="submit"
                class="px-4 py-2 bg-gray-900 text-white text-sm rounded-lg hover:bg-gray-800 font-medium"
              >
                Save
              </button>
            </div>
          </div>
        </.form>
      </.modal>

      <%!-- Delete Epic Confirmation --%>
      <.modal
        :if={@deleting_epic}
        id="delete-epic-modal"
        show
        on_cancel={JS.push("cancel_delete")}
      >
        <div class="text-center">
          <div class="w-12 h-12 rounded-full bg-red-100 flex items-center justify-center mx-auto mb-4">
            <.icon name="hero-exclamation-triangle" class="w-6 h-6 text-red-600" />
          </div>
          <h3 class="text-lg font-semibold text-gray-900 mb-2">Delete Epic</h3>
          <p class="text-sm text-gray-500 mb-6">
            Delete <span class="font-medium text-gray-900">{@deleting_epic.name}</span>
            and all its tasks?
          </p>
          <div class="flex gap-3 justify-center">
            <button
              phx-click="cancel_delete"
              class="px-4 py-2 text-sm text-gray-600 hover:text-gray-900"
            >
              Cancel
            </button>
            <button
              phx-click="delete_epic"
              class="px-4 py-2 bg-red-600 text-white text-sm rounded-lg hover:bg-red-700 font-medium"
            >
              Delete
            </button>
          </div>
        </div>
      </.modal>

      <%!-- Delete Task Confirmation --%>
      <.modal
        :if={@deleting_task}
        id="delete-task-modal"
        show
        on_cancel={JS.push("cancel_delete")}
      >
        <div class="text-center">
          <div class="w-12 h-12 rounded-full bg-red-100 flex items-center justify-center mx-auto mb-4">
            <.icon name="hero-exclamation-triangle" class="w-6 h-6 text-red-600" />
          </div>
          <h3 class="text-lg font-semibold text-gray-900 mb-2">Delete Task</h3>
          <p class="text-sm text-gray-500 mb-6">
            Delete <span class="font-medium text-gray-900">{@deleting_task.name}</span>?
          </p>
          <div class="flex gap-3 justify-center">
            <button
              phx-click="cancel_delete"
              class="px-4 py-2 text-sm text-gray-600 hover:text-gray-900"
            >
              Cancel
            </button>
            <button
              phx-click="delete_task"
              class="px-4 py-2 bg-red-600 text-white text-sm rounded-lg hover:bg-red-700 font-medium"
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
  def handle_event("update_template", params, socket) do
    unless socket.assigns.is_admin do
      {:noreply, put_flash(socket, :error, "Not authorized")}
    else
      attrs = %{
        "name" => params["name"],
        "description" => params["description"]
      }

      case Templates.update_estimation_template(socket.assigns.template, attrs) do
        {:ok, template} ->
          template = Templates.get_estimation_template!(template.id, socket.assigns.org_id)
          {:noreply, assign(socket, :template, template)}

        {:error, _} ->
          {:noreply, socket}
      end
    end
  end

  ## Epic events

  def handle_event("add_epic", _params, socket) do
    {:noreply,
     socket
     |> assign(:modal, :epic)
     |> assign(:current_epic_id, nil)
     |> assign(:epic_form, to_form(%{"name" => "", "description" => ""}, as: "epic"))}
  end

  def handle_event("edit_epic", %{"id" => id}, socket) do
    epic = find_epic(socket.assigns.template, id)

    {:noreply,
     socket
     |> assign(:modal, :epic)
     |> assign(:current_epic_id, id)
     |> assign(
       :epic_form,
       to_form(%{"name" => epic.name, "description" => epic.description || ""}, as: "epic")
     )}
  end

  def handle_event("save_epic", %{"epic_id" => "", "name" => name} = params, socket) do
    unless socket.assigns.is_admin do
      {:noreply, put_flash(socket, :error, "Not authorized")}
    else
      position = length(socket.assigns.template.epics)

      attrs = %{
        "name" => name,
        "description" => params["description"],
        "position" => position,
        "estimation_template_id" => socket.assigns.template.id
      }

      case Templates.create_template_epic(attrs) do
        {:ok, _} ->
          {:noreply, reload_and_close(socket)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not create epic")}
      end
    end
  end

  def handle_event("save_epic", %{"epic_id" => id, "name" => name} = params, socket) do
    unless socket.assigns.is_admin do
      {:noreply, put_flash(socket, :error, "Not authorized")}
    else
      epic = find_epic(socket.assigns.template, id)

      case Templates.update_template_epic(epic, %{
             "name" => name,
             "description" => params["description"]
           }) do
        {:ok, _} ->
          {:noreply, reload_and_close(socket)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not update epic")}
      end
    end
  end

  def handle_event("confirm_delete_epic", %{"id" => id}, socket) do
    epic = find_epic(socket.assigns.template, id)
    {:noreply, assign(socket, :deleting_epic, epic)}
  end

  def handle_event("delete_epic", _params, socket) do
    unless socket.assigns.is_admin do
      {:noreply, put_flash(socket, :error, "Not authorized")}
    else
      case Templates.delete_template_epic(socket.assigns.deleting_epic) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(:deleting_epic, nil)
           |> reload_template()
           |> put_flash(:info, "Epic deleted")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not delete epic")}
      end
    end
  end

  ## Task events

  def handle_event("add_task", %{"epic-id" => epic_id}, socket) do
    {:noreply,
     socket
     |> assign(:modal, :task)
     |> assign(:current_epic_id, epic_id)
     |> assign(:current_task_id, nil)
     |> assign(
       :task_form,
       to_form(%{"name" => "", "description" => "", "priority" => "must"}, as: "task")
     )}
  end

  def handle_event("edit_task", %{"id" => id, "epic-id" => epic_id}, socket) do
    task = find_task(socket.assigns.template, epic_id, id)

    {:noreply,
     socket
     |> assign(:modal, :task)
     |> assign(:current_epic_id, epic_id)
     |> assign(:current_task_id, id)
     |> assign(
       :task_form,
       to_form(
         %{
           "name" => task.name,
           "description" => task.description || "",
           "priority" => task.priority
         },
         as: "task"
       )
     )}
  end

  def handle_event(
        "save_task",
        %{"task_id" => "", "epic_id" => epic_id, "name" => name} = params,
        socket
      ) do
    unless socket.assigns.is_admin do
      {:noreply, put_flash(socket, :error, "Not authorized")}
    else
      epic = find_epic(socket.assigns.template, epic_id)
      position = length(epic.tasks)

      attrs = %{
        "name" => name,
        "description" => params["description"],
        "priority" => params["priority"] || "must",
        "position" => position,
        "estimation_template_epic_id" => epic_id
      }

      case Templates.create_template_task(attrs) do
        {:ok, _} ->
          {:noreply, reload_and_close(socket)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not create task")}
      end
    end
  end

  def handle_event(
        "save_task",
        %{"task_id" => id, "epic_id" => epic_id, "name" => name} = params,
        socket
      ) do
    unless socket.assigns.is_admin do
      {:noreply, put_flash(socket, :error, "Not authorized")}
    else
      task = find_task(socket.assigns.template, epic_id, id)

      attrs = %{
        "name" => name,
        "description" => params["description"],
        "priority" => params["priority"] || task.priority
      }

      case Templates.update_template_task(task, attrs) do
        {:ok, _} ->
          {:noreply, reload_and_close(socket)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not update task")}
      end
    end
  end

  def handle_event("confirm_delete_task", %{"id" => id, "epic-id" => epic_id}, socket) do
    task = find_task(socket.assigns.template, epic_id, id)
    {:noreply, assign(socket, :deleting_task, task)}
  end

  def handle_event("delete_task", _params, socket) do
    unless socket.assigns.is_admin do
      {:noreply, put_flash(socket, :error, "Not authorized")}
    else
      case Templates.delete_template_task(socket.assigns.deleting_task) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(:deleting_task, nil)
           |> reload_template()
           |> put_flash(:info, "Task deleted")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not delete task")}
      end
    end
  end

  ## Reorder events

  def handle_event("reorder_epics", %{"ids" => ids}, socket) do
    unless socket.assigns.is_admin do
      {:noreply, put_flash(socket, :error, "Not authorized")}
    else
      Templates.reorder_template_epics(socket.assigns.template.id, ids)
      {:noreply, reload_template(socket)}
    end
  end

  def handle_event("reorder_tasks", %{"epic_id" => epic_id, "ids" => ids}, socket) do
    unless socket.assigns.is_admin do
      {:noreply, put_flash(socket, :error, "Not authorized")}
    else
      Templates.reorder_template_tasks(epic_id, ids)
      {:noreply, reload_template(socket)}
    end
  end

  ## Common events

  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, :modal, nil)}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply,
     socket
     |> assign(:deleting_epic, nil)
     |> assign(:deleting_task, nil)}
  end

  ## Helpers

  defp reload_template(socket) do
    template =
      Templates.get_estimation_template!(socket.assigns.template.id, socket.assigns.org_id)

    assign(socket, :template, template)
  end

  defp reload_and_close(socket) do
    socket
    |> reload_template()
    |> assign(:modal, nil)
  end

  defp find_epic(template, id) do
    Enum.find(template.epics, &(&1.id == id))
  end

  defp find_task(template, epic_id, task_id) do
    epic = find_epic(template, epic_id)
    Enum.find(epic.tasks, &(&1.id == task_id))
  end
end
