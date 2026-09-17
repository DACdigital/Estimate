defmodule EstimateWeb.EstimatorLive.Tasks do
  @moduledoc """
  Task modal (add/edit/validate/save), delete-confirm and reorder handlers.

  Reads: `:estimation`, `:task_form`, `:current_epic_id`, `:deleting_task`, `:can_edit` (via Authz).
  Writes: `:modal`, `:task_form`, `:current_epic_id`, `:deleting_task`, `:estimation` (reload).
  """
  use EstimateWeb, :live_handlers

  import EstimateWeb.EstimatorLive.Authz
  alias Estimate.EstimationEngine

  def add_task(socket, %{"epic-id" => epic_id}) do
    with_edit_auth(socket, fn socket ->
      case find_epic(socket.assigns.estimation, epic_id) do
        nil ->
          not_found(socket)

        epic ->
          changeset = EstimationEngine.Task.changeset(%EstimationEngine.Task{}, %{})

          {:noreply,
           socket
           |> assign(:modal, :task)
           |> assign(:task_form, to_form(changeset))
           |> assign(:current_epic_id, epic.id)}
      end
    end)
  end

  def edit_task(socket, %{"id" => id}) do
    with_edit_auth(socket, fn socket ->
      case find_task(socket.assigns.estimation, id) do
        nil ->
          not_found(socket)

        task ->
          changeset = EstimationEngine.Task.update_changeset(task, %{})

          {:noreply,
           socket
           |> assign(:modal, :task)
           |> assign(:task_form, to_form(changeset))
           |> assign(:current_epic_id, task.epic_id)}
      end
    end)
  end

  # Not edit-gated today (pure form validation, no write). Preserved as-is.
  def validate_task(socket, %{"task" => task_params}) do
    case socket.assigns.task_form do
      nil ->
        not_found(socket)

      task_form ->
        task = task_form.data

        changeset =
          if task.id,
            do: EstimationEngine.Task.update_changeset(task, task_params),
            else: EstimationEngine.Task.changeset(task, task_params)

        {:noreply,
         assign(socket, :task_form, changeset |> Map.put(:action, :validate) |> to_form())}
    end
  end

  def save_task(socket, %{"task" => task_params}) do
    with_edit_auth(socket, fn socket ->
      task = socket.assigns.task_form && socket.assigns.task_form.data
      epic_id = socket.assigns.current_epic_id

      cond do
        is_nil(task) ->
          not_found(socket)

        is_nil(task.id) and is_nil(epic_id) ->
          not_found(socket)

        true ->
          result =
            if task.id do
              EstimationEngine.update_task(task, task_params)
            else
              attrs = Map.put(task_params, "epic_id", epic_id)
              EstimationEngine.create_task(attrs)
            end

          case result do
            {:ok, _task} ->
              {:noreply,
               socket
               |> reload_estimation()
               |> assign(:modal, nil)
               |> assign(:task_form, nil)
               |> assign(:current_epic_id, nil)}

            {:error, changeset} ->
              {:noreply, assign(socket, :task_form, to_form(changeset))}
          end
      end
    end)
  end

  def confirm_delete_task(socket, %{"id" => id}) do
    with_edit_auth(socket, fn socket ->
      case find_task(socket.assigns.estimation, id) do
        nil -> not_found(socket)
        task -> {:noreply, assign(socket, :deleting_task, task)}
      end
    end)
  end

  def cancel_delete_task(socket, _params), do: {:noreply, assign(socket, :deleting_task, nil)}

  def delete_task(socket, _params) do
    with_edit_auth(socket, fn socket ->
      case socket.assigns.deleting_task do
        nil ->
          {:noreply, socket}

        task ->
          {:ok, _} = EstimationEngine.delete_task(task)

          {:noreply,
           socket
           |> reload_estimation()
           |> assign(:deleting_task, nil)}
      end
    end)
  end

  def reorder_tasks(socket, %{"epic_id" => epic_id, "ids" => ids}) do
    with_edit_auth(socket, fn socket ->
      if Enum.any?(socket.assigns.estimation.epics, &(&1.id == epic_id)) do
        EstimationEngine.reorder_tasks(epic_id, ids)
        {:noreply, reload_estimation(socket)}
      else
        {:noreply, socket}
      end
    end)
  end
end
