defmodule Estimate.EstimationEngine.Estimates do
  @moduledoc false

  import Ecto.Query
  alias Estimate.Repo
  alias Estimate.EstimationEngine.{Epic, Task, TaskEstimate}

  def upsert_task_estimate(task_id, role_id, attrs, estimation_id \\ nil) do
    Repo.ensure_org_context(fn ->
      case Repo.get_by(TaskEstimate, task_id: task_id, estimation_role_id: role_id) do
        nil ->
          create_task_estimate(
            Map.merge(attrs, %{task_id: task_id, estimation_role_id: role_id}),
            estimation_id
          )

        estimate ->
          update_task_estimate(estimate, attrs, estimation_id)
      end
    end)
  end

  defp create_task_estimate(attrs, estimation_id) do
    result =
      %TaskEstimate{}
      |> TaskEstimate.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, estimate} ->
        estimation_id = estimation_id || get_estimation_id_for_task(estimate.task_id)
        Estimate.EstimationEngine.broadcast(estimation_id, {:estimate_updated, estimate})
        {:ok, estimate}

      error ->
        error
    end
  end

  defp update_task_estimate(%TaskEstimate{} = estimate, attrs, estimation_id) do
    result =
      estimate
      |> TaskEstimate.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, estimate} ->
        estimation_id = estimation_id || get_estimation_id_for_task(estimate.task_id)
        Estimate.EstimationEngine.broadcast(estimation_id, {:estimate_updated, estimate})
        {:ok, estimate}

      error ->
        error
    end
  end

  defp get_estimation_id_for_task(task_id) do
    from(t in Task,
      join: ep in Epic,
      on: ep.id == t.epic_id,
      where: t.id == ^task_id,
      select: ep.estimation_id
    )
    |> Repo.one!()
  end
end
