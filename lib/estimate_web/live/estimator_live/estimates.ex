defmodule EstimateWeb.EstimatorLive.Estimates do
  @moduledoc """
  Inline cell (hours) and rate editing. Successful writes patch `@estimation`
  in memory so the originating LiveView does not depend on a reload. Note:
  today the write's own PubSub broadcast still reaches this LiveView and
  `Index.handle_info/2` performs a full reload; batch 3C (C1, `broadcast_from`)
  removes that round trip.

  Reads: `:estimation`, `:org_id`, `:can_edit` (via Authz).
  Writes: `:editing`, `:editing_rate`, `:estimation` (in-memory patch).
  """
  use EstimateWeb, :live_handlers

  import EstimateWeb.EstimatorLive.Authz
  import EstimateWeb.EstimatorLive.Helpers, only: [parse_decimal: 1]
  alias Estimate.EstimationEngine

  def cancel_edit(socket, _params),
    do: {:noreply, socket |> assign(:editing, nil) |> assign(:editing_rate, nil)}

  def edit_estimate(socket, %{"key" => key}), do: {:noreply, assign(socket, :editing, key)}

  def edit_rate(socket, %{"role-id" => role_id}),
    do: {:noreply, assign(socket, :editing_rate, role_id)}

  def save_rate(socket, %{"role-id" => role_id, "value" => value}) do
    with_edit_auth(socket, fn socket ->
      estimation = socket.assigns.estimation

      if belongs_to_estimation?(estimation, :role, role_id) do
        role = EstimationEngine.get_role!(role_id, socket.assigns.org_id)
        hourly_rate = parse_decimal(value)

        case EstimationEngine.update_role(role, %{hourly_rate: hourly_rate}) do
          {:ok, updated_role} ->
            {:noreply,
             socket
             |> assign(:estimation, update_role_in_memory(estimation, updated_role))
             |> assign(:editing_rate, nil)}

          {:error, _changeset} ->
            {:noreply, assign(socket, :editing_rate, nil)}
        end
      else
        {:noreply, assign(socket, :editing_rate, nil)}
      end
    end)
  end

  def save_estimate(socket, params) do
    with_edit_auth(socket, fn socket ->
      %{"task-id" => task_id, "role-id" => role_id, "value" => value} = params
      estimation = socket.assigns.estimation

      if belongs_to_estimation?(estimation, :task, task_id) and
           belongs_to_estimation?(estimation, :role, role_id) do
        hours = parse_decimal(value)

        case EstimationEngine.upsert_task_estimate(
               task_id,
               role_id,
               %{hours: hours},
               estimation.id
             ) do
          {:ok, updated_estimate} ->
            {:noreply,
             socket
             |> assign(:estimation, update_estimate_in_memory(estimation, updated_estimate))
             |> assign(:editing, nil)}

          {:error, _changeset} ->
            {:noreply, assign(socket, :editing, nil)}
        end
      else
        {:noreply, assign(socket, :editing, nil)}
      end
    end)
  end

  @doc false
  def update_estimate_in_memory(estimation, updated_estimate) do
    epics =
      Enum.map(estimation.epics, fn epic ->
        tasks =
          Enum.map(epic.tasks, fn task ->
            if task.id == updated_estimate.task_id do
              estimates =
                case Enum.find_index(task.estimates, &(&1.id == updated_estimate.id)) do
                  nil -> [updated_estimate | task.estimates]
                  idx -> List.replace_at(task.estimates, idx, updated_estimate)
                end

              %{task | estimates: estimates}
            else
              task
            end
          end)

        %{epic | tasks: tasks}
      end)

    %{estimation | epics: epics}
  end

  @doc false
  def update_role_in_memory(estimation, updated_role) do
    roles =
      Enum.map(estimation.roles, fn role ->
        if role.id == updated_role.id, do: updated_role, else: role
      end)

    %{estimation | roles: roles}
  end
end
