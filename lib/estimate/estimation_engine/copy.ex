defmodule Estimate.EstimationEngine.Copy do
  @moduledoc false

  alias Estimate.Repo
  alias Estimate.EstimationEngine.{Estimation, EstimationRole, Epic, Task, TaskEstimate}
  alias Estimate.EstimationEngine.Estimations

  def copy_estimation(%Estimation{} = estimation, new_name, project_id, org_id) do
    Repo.ensure_org_context(fn ->
      estimation = Estimations.get_estimation!(estimation.id, org_id)

      Ecto.Multi.new()
      |> Ecto.Multi.insert(:estimation, fn _ ->
        Estimation.changeset(%Estimation{}, %{
          name: new_name,
          description: estimation.description,
          currency_id: estimation.currency_id,
          project_id: project_id
        })
      end)
      |> Ecto.Multi.run(:roles, fn _repo, %{estimation: new_estimation} ->
        Enum.reduce_while(estimation.roles, {:ok, %{}}, fn old_role, {:ok, acc} ->
          %EstimationRole{}
          |> EstimationRole.changeset(%{
            name: old_role.name,
            abbreviation: old_role.abbreviation,
            hourly_rate: old_role.hourly_rate,
            pm_overhead: old_role.pm_overhead,
            qa_overhead: old_role.qa_overhead,
            risk_buffer: old_role.risk_buffer,
            position: old_role.position,
            estimation_id: new_estimation.id
          })
          |> Repo.insert()
          |> case do
            {:ok, new_role} -> {:cont, {:ok, Map.put(acc, old_role.id, new_role.id)}}
            {:error, changeset} -> {:halt, {:error, changeset}}
          end
        end)
      end)
      |> Ecto.Multi.run(:epics_tasks, fn _repo,
                                         %{estimation: new_estimation, roles: role_mapping} ->
        copy_epics_with_estimates(estimation.epics, new_estimation.id, role_mapping)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{estimation: estimation}} ->
          {:ok, Estimations.get_estimation!(estimation.id, org_id)}

        {:error, _op, changeset, _} ->
          {:error, changeset}
      end
    end)
  end

  defp copy_epics_with_estimates(epics, estimation_id, role_mapping) do
    Enum.reduce_while(epics, {:ok, []}, fn old_epic, {:ok, acc} ->
      case Repo.insert(
             Epic.changeset(%Epic{}, %{
               name: old_epic.name,
               description: old_epic.description,
               position: old_epic.position,
               estimation_id: estimation_id
             })
           ) do
        {:ok, new_epic} ->
          case copy_tasks_with_estimates(old_epic.tasks, new_epic.id, role_mapping) do
            {:ok, _} -> {:cont, {:ok, [new_epic | acc]}}
            {:error, changeset} -> {:halt, {:error, changeset}}
          end

        {:error, changeset} ->
          {:halt, {:error, changeset}}
      end
    end)
  end

  defp copy_tasks_with_estimates(tasks, epic_id, role_mapping) do
    Enum.reduce_while(tasks, {:ok, []}, fn old_task, {:ok, acc} ->
      case Repo.insert(
             Task.changeset(%Task{}, %{
               name: old_task.name,
               description: old_task.description,
               position: old_task.position,
               epic_id: epic_id
             })
           ) do
        {:ok, new_task} ->
          case copy_estimates(old_task.estimates, new_task.id, role_mapping) do
            :ok -> {:cont, {:ok, [new_task | acc]}}
            {:error, changeset} -> {:halt, {:error, changeset}}
          end

        {:error, changeset} ->
          {:halt, {:error, changeset}}
      end
    end)
  end

  defp copy_estimates(estimates, new_task_id, role_mapping) do
    Enum.reduce_while(estimates, :ok, fn old_estimate, :ok ->
      new_role_id = Map.get(role_mapping, old_estimate.estimation_role_id)

      if new_role_id do
        case Repo.insert(
               TaskEstimate.changeset(%TaskEstimate{}, %{
                 hours: old_estimate.hours,
                 task_id: new_task_id,
                 estimation_role_id: new_role_id
               })
             ) do
          {:ok, _} -> {:cont, :ok}
          {:error, changeset} -> {:halt, {:error, changeset}}
        end
      else
        {:cont, :ok}
      end
    end)
  end
end
