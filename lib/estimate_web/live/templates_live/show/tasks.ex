defmodule EstimateWeb.TemplatesLive.Show.Tasks do
  @moduledoc """
  Template task modal, delete-confirm and reorder handlers.

  Reads: `:template`, `:deleting_task`, `:current_membership` (gate, via require_admin).
  Writes: `:modal`, `:current_epic_id`, `:current_task_id`, `:task_form`, `:deleting_task`, `:template` (reload), flash.
  """
  use EstimateWeb, :live_handlers

  import EstimateWeb.TemplatesLive.Show.Authz
  alias Estimate.Templates

  def add_task(socket, %{"epic-id" => epic_id}) do
    require_admin(socket, fn ->
      case find_epic(socket.assigns.template, epic_id) do
        nil ->
          not_found(socket)

        _epic ->
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
    end)
  end

  def add_task(socket, _params), do: require_admin(socket, fn -> not_found(socket) end)

  def edit_task(socket, %{"id" => id, "epic-id" => epic_id}) do
    require_admin(socket, fn ->
      case find_task(socket.assigns.template, epic_id, id) do
        nil ->
          not_found(socket)

        task ->
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
    end)
  end

  def save_task(socket, %{"task_id" => "", "epic_id" => epic_id, "name" => name} = params) do
    require_admin(socket, fn ->
      case find_epic(socket.assigns.template, epic_id) do
        nil ->
          not_found(socket)

        epic ->
          attrs = %{
            "name" => name,
            "description" => params["description"],
            "priority" => params["priority"] || "must",
            "position" => length(epic.tasks),
            "estimation_template_epic_id" => epic_id
          }

          case Templates.create_template_task(attrs) do
            {:ok, _} -> {:noreply, reload_and_close(socket)}
            {:error, _} -> {:noreply, put_flash(socket, :error, "Could not create task")}
          end
      end
    end)
  end

  def save_task(socket, %{"task_id" => id, "epic_id" => epic_id, "name" => name} = params) do
    require_admin(socket, fn ->
      case find_task(socket.assigns.template, epic_id, id) do
        nil ->
          not_found(socket)

        task ->
          attrs = %{
            "name" => name,
            "description" => params["description"],
            "priority" => params["priority"] || task.priority
          }

          case Templates.update_template_task(task, attrs) do
            {:ok, _} -> {:noreply, reload_and_close(socket)}
            {:error, _} -> {:noreply, put_flash(socket, :error, "Could not update task")}
          end
      end
    end)
  end

  def confirm_delete_task(socket, %{"id" => id, "epic-id" => epic_id}) do
    require_admin(socket, fn ->
      case find_task(socket.assigns.template, epic_id, id) do
        nil -> not_found(socket)
        task -> {:noreply, assign(socket, :deleting_task, task)}
      end
    end)
  end

  def delete_task(socket, _params) do
    require_admin(socket, fn ->
      case socket.assigns.deleting_task do
        nil ->
          not_found(socket)

        task ->
          case Templates.delete_template_task(task) do
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
    end)
  end

  def reorder_tasks(socket, %{"epic_id" => epic_id, "ids" => ids}) do
    require_admin(socket, fn ->
      case find_epic(socket.assigns.template, epic_id) do
        nil ->
          not_found(socket)

        _epic ->
          epic_id
          |> Templates.reorder_template_tasks(ids)
          |> after_reorder(socket)
      end
    end)
  end
end
