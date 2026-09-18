defmodule Estimate.EstimationEngine.Copy do
  @moduledoc false

  alias Estimate.Repo
  alias Estimate.EstimationEngine.{Estimation, EstimationRole, Epic, Task, TaskEstimate}
  alias Estimate.EstimationEngine.Estimations

  @dialyzer :no_opaque

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
        estimation.roles
        |> Repo.insert_each(fn old_role ->
          EstimationRole.changeset(%EstimationRole{}, %{
            name: old_role.name,
            abbreviation: old_role.abbreviation,
            hourly_rate: old_role.hourly_rate,
            pm_overhead: old_role.pm_overhead,
            qa_overhead: old_role.qa_overhead,
            risk_buffer: old_role.risk_buffer,
            position: old_role.position,
            estimation_id: new_estimation.id
          })
        end)
        |> case do
          {:ok, new_roles} ->
            {:ok, Map.new(Enum.zip(estimation.roles, new_roles), fn {o, n} -> {o.id, n.id} end)}

          error ->
            error
        end
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
    with {:ok, new_epics} <-
           Repo.insert_each(epics, fn old_epic ->
             Epic.changeset(%Epic{}, %{
               name: old_epic.name,
               description: old_epic.description,
               position: old_epic.position,
               estimation_id: estimation_id
             })
           end) do
      epics
      |> Enum.zip(new_epics)
      |> Enum.reduce_while({:ok, new_epics}, fn {old_epic, new_epic}, acc ->
        case copy_tasks_with_estimates(old_epic.tasks, new_epic.id, role_mapping) do
          {:ok, _} -> {:cont, acc}
          {:error, changeset} -> {:halt, {:error, changeset}}
        end
      end)
    end
  end

  defp copy_tasks_with_estimates(tasks, epic_id, role_mapping) do
    with {:ok, new_tasks} <-
           Repo.insert_each(tasks, fn old_task ->
             Task.changeset(%Task{}, %{
               name: old_task.name,
               description: old_task.description,
               position: old_task.position,
               epic_id: epic_id
             })
           end) do
      tasks
      |> Enum.zip(new_tasks)
      |> Enum.reduce_while({:ok, new_tasks}, fn {old_task, new_task}, acc ->
        case copy_estimates(old_task.estimates, new_task.id, role_mapping) do
          {:ok, _} -> {:cont, acc}
          {:error, changeset} -> {:halt, {:error, changeset}}
        end
      end)
    end
  end

  # Estimates whose role was not copied (no mapping) are skipped, as before.
  defp copy_estimates(estimates, new_task_id, role_mapping) do
    estimates
    |> Enum.filter(&Map.has_key?(role_mapping, &1.estimation_role_id))
    |> Repo.insert_each(fn old_estimate ->
      TaskEstimate.changeset(%TaskEstimate{}, %{
        hours: old_estimate.hours,
        task_id: new_task_id,
        estimation_role_id: Map.fetch!(role_mapping, old_estimate.estimation_role_id)
      })
    end)
  end
end
