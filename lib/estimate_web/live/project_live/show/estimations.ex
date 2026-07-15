defmodule EstimateWeb.ProjectLive.Show.Estimations do
  @moduledoc """
  Estimation list (set-current, soft-delete) and trash (restore, permanent-delete)
  handlers for the estimations tab.

  Reads: `:project`, `:org_id`, `:deleted_estimations`, `:show_trash`,
  `:can_edit_project` (via `Show.Authz.require_can_edit/2`), `:can_delete_project`
  (via `Show.Authz.require_can_delete/2,3`).
  Writes: `:estimations`, `:current_estimation`, `:deleting_estimation`,
  `:deleted_estimations`, `:show_trash`, `:permanently_deleting`.
  """
  use EstimateWeb, :live_handlers

  import EstimateWeb.ProjectLive.Show.Authz
  alias Estimate.EstimationEngine

  ## Estimation List Events

  def set_current_estimation(socket, %{"id" => id}) do
    require_can_edit(socket, fn ->
      case fetch_authorized_estimation(socket, id) do
        {:ok, estimation} ->
          case EstimationEngine.set_current_estimation(estimation) do
            {:ok, _} ->
              estimations = EstimationEngine.list_estimations(socket.assigns.project.id)
              current = EstimationEngine.get_estimation!(estimation.id, socket.assigns.org_id)

              {:noreply,
               socket
               |> assign(:estimations, estimations)
               |> assign(:current_estimation, current)}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Could not set current estimation")}
          end

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Not authorized")}
      end
    end)
  end

  def confirm_delete_estimation(socket, %{"id" => id}) do
    {:noreply, assign(socket, :deleting_estimation, id)}
  end

  def cancel_delete_estimation(socket, _params) do
    {:noreply, assign(socket, :deleting_estimation, nil)}
  end

  def delete_estimation(socket, %{"id" => id}) do
    require_can_delete(socket, [deleting_estimation: nil], fn ->
      case fetch_authorized_estimation(socket, id) do
        {:ok, estimation} ->
          if estimation.is_current do
            {:noreply,
             socket
             |> put_flash(:error, "Cannot delete current estimation")
             |> assign(:deleting_estimation, nil)}
          else
            case EstimationEngine.soft_delete_estimation(estimation) do
              {:ok, _} ->
                project_id = socket.assigns.project.id
                estimations = EstimationEngine.list_estimations(project_id)
                deleted = EstimationEngine.list_deleted_estimations(project_id)

                {:noreply,
                 socket
                 |> assign(:estimations, estimations)
                 |> assign(:deleted_estimations, deleted)
                 |> assign(:deleting_estimation, nil)
                 |> put_flash(:info, "Estimation moved to trash")}

              {:error, _} ->
                {:noreply,
                 socket
                 |> put_flash(:error, "Could not delete estimation")
                 |> assign(:deleting_estimation, nil)}
            end
          end

        {:error, _} ->
          {:noreply,
           socket
           |> put_flash(:error, "Not authorized")
           |> assign(:deleting_estimation, nil)}
      end
    end)
  end

  ## Trash Events

  def toggle_trash(socket, _params) do
    {:noreply, assign(socket, :show_trash, !socket.assigns.show_trash)}
  end

  def restore_estimation(socket, %{"id" => id}) do
    require_can_delete(socket, fn ->
      org_id = socket.assigns.org_id
      project_id = socket.assigns.project.id

      case find_deleted_estimation(socket, id) do
        {:ok, estimation} ->
          case EstimationEngine.restore_estimation(estimation) do
            {:ok, _} ->
              estimations = EstimationEngine.list_estimations(project_id)
              deleted = EstimationEngine.list_deleted_estimations(project_id)

              current_estimation =
                case Enum.find(estimations, & &1.is_current) do
                  nil -> nil
                  est -> EstimationEngine.get_estimation!(est.id, org_id)
                end

              {:noreply,
               socket
               |> assign(:estimations, estimations)
               |> assign(:deleted_estimations, deleted)
               |> assign(:current_estimation, current_estimation)
               |> put_flash(:info, "Estimation restored")}

            {:error, _} ->
              {:noreply, put_flash(socket, :error, "Could not restore estimation")}
          end

        :error ->
          {:noreply, put_flash(socket, :error, "Estimation not found")}
      end
    end)
  end

  def confirm_permanent_delete(socket, %{"id" => id}) do
    {:noreply, assign(socket, :permanently_deleting, id)}
  end

  def cancel_permanent_delete(socket, _params) do
    {:noreply, assign(socket, :permanently_deleting, nil)}
  end

  def permanent_delete_estimation(socket, %{"id" => id}) do
    require_can_delete(socket, [permanently_deleting: nil], fn ->
      case find_deleted_estimation(socket, id) do
        {:ok, estimation} ->
          case EstimationEngine.hard_delete_estimation(estimation) do
            {:ok, _} ->
              deleted = EstimationEngine.list_deleted_estimations(socket.assigns.project.id)

              {:noreply,
               socket
               |> assign(:deleted_estimations, deleted)
               |> assign(:permanently_deleting, nil)
               |> put_flash(:info, "Estimation permanently deleted")}

            {:error, _} ->
              {:noreply,
               socket
               |> put_flash(:error, "Could not delete estimation")
               |> assign(:permanently_deleting, nil)}
          end

        :error ->
          {:noreply,
           socket
           |> put_flash(:error, "Estimation not found")
           |> assign(:permanently_deleting, nil)}
      end
    end)
  end
end
