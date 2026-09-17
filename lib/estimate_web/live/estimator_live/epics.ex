defmodule EstimateWeb.EstimatorLive.Epics do
  @moduledoc """
  Epic modal + delete-confirm + reorder handlers.

  Reads: `:estimation`, `:epic_form`, `:deleting_epic`, `:can_edit` (via Authz).
  Writes: `:modal`, `:epic_form`, `:deleting_epic`, `:estimation` (reload).
  """
  use EstimateWeb, :live_handlers

  import EstimateWeb.EstimatorLive.Authz
  alias Estimate.EstimationEngine

  def add_epic(socket, _params) do
    with_edit_auth(socket, fn socket ->
      changeset = EstimationEngine.Epic.changeset(%EstimationEngine.Epic{}, %{})

      {:noreply,
       socket
       |> assign(:modal, :epic)
       |> assign(:epic_form, to_form(changeset))}
    end)
  end

  def edit_epic(socket, %{"id" => id}) do
    with_edit_auth(socket, fn socket ->
      case find_epic(socket.assigns.estimation, id) do
        nil ->
          not_found(socket)

        epic ->
          changeset = EstimationEngine.Epic.update_changeset(epic, %{})

          {:noreply,
           socket
           |> assign(:modal, :epic)
           |> assign(:epic_form, to_form(changeset))}
      end
    end)
  end

  def save_epic(socket, %{"epic" => epic_params}) do
    with_edit_auth(socket, fn socket ->
      case socket.assigns.epic_form do
        nil ->
          not_found(socket)

        epic_form ->
          epic = epic_form.data
          estimation = socket.assigns.estimation

          result =
            if epic.id do
              EstimationEngine.update_epic(epic, epic_params)
            else
              attrs = Map.put(epic_params, "estimation_id", estimation.id)
              EstimationEngine.create_epic(attrs)
            end

          case result do
            {:ok, _epic} ->
              {:noreply,
               socket
               |> reload_estimation()
               |> assign(:modal, nil)
               |> assign(:epic_form, nil)}

            {:error, changeset} ->
              {:noreply, assign(socket, :epic_form, to_form(changeset))}
          end
      end
    end)
  end

  def confirm_delete_epic(socket, %{"id" => id}) do
    with_edit_auth(socket, fn socket ->
      case find_epic(socket.assigns.estimation, id) do
        nil -> not_found(socket)
        epic -> {:noreply, assign(socket, :deleting_epic, epic)}
      end
    end)
  end

  def cancel_delete_epic(socket, _params), do: {:noreply, assign(socket, :deleting_epic, nil)}

  def delete_epic(socket, _params) do
    with_edit_auth(socket, fn socket ->
      case socket.assigns.deleting_epic do
        nil ->
          {:noreply, socket}

        epic ->
          {:ok, _} = EstimationEngine.delete_epic(epic)

          {:noreply,
           socket
           |> reload_estimation()
           |> assign(:deleting_epic, nil)}
      end
    end)
  end

  def reorder_epics(socket, %{"ids" => ids}) do
    with_edit_auth(socket, fn socket ->
      EstimationEngine.reorder_epics(socket.assigns.estimation.id, ids)
      {:noreply, reload_estimation(socket)}
    end)
  end
end
