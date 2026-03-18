defmodule Estimate.EstimationEngine.Tasks do
  @moduledoc false

  import Ecto.Query
  alias Estimate.Repo
  alias Estimate.EstimationEngine.{Epic, Task}

  def create_task(attrs) do
    Repo.ensure_org_context(fn ->
      result =
        %Task{}
        |> Task.changeset(attrs)
        |> Repo.insert()

      case result do
        {:ok, task} ->
          epic = Repo.get!(Epic, task.epic_id)
          Estimate.EstimationEngine.broadcast(epic.estimation_id, {:task_created, task})
          Estimate.EstimationEngine.reindex_estimation_async(epic.estimation_id)
          {:ok, task}

        error ->
          error
      end
    end)
  end

  def update_task(%Task{} = task, attrs) do
    Repo.ensure_org_context(fn ->
      result =
        task
        |> Task.changeset(attrs)
        |> Repo.update()

      case result do
        {:ok, task} ->
          epic = Repo.get!(Epic, task.epic_id)
          Estimate.EstimationEngine.broadcast(epic.estimation_id, {:task_updated, task})

          if attrs["name"] || attrs[:name] do
            Estimate.EstimationEngine.reindex_estimation_async(epic.estimation_id)
          end

          {:ok, task}

        error ->
          error
      end
    end)
  end

  def delete_task(%Task{} = task) do
    Repo.ensure_org_context(fn ->
      epic = Repo.get!(Epic, task.epic_id)
      result = Repo.delete(task)

      case result do
        {:ok, task} ->
          Estimate.EstimationEngine.broadcast(epic.estimation_id, {:task_deleted, task})
          Estimate.EstimationEngine.reindex_estimation_async(epic.estimation_id)
          {:ok, task}

        error ->
          error
      end
    end)
  end

  def get_task!(id, org_id) do
    Repo.ensure_org_context(fn ->
      from(t in Task,
        join: ep in assoc(t, :epic),
        join: e in assoc(ep, :estimation),
        where: t.id == ^id and e.organization_id == ^org_id
      )
      |> Repo.one!()
    end)
  end

  def reorder_tasks(epic_id, task_ids) do
    alias Estimate.EstimationEngine.Helpers

    epic = Repo.ensure_org_context(fn -> Repo.get!(Epic, epic_id) end)

    Helpers.reorder_children(Task, :epic_id, epic_id, task_ids, fn ->
      Estimate.EstimationEngine.broadcast(
        epic.estimation_id,
        {:tasks_reordered, epic_id, task_ids}
      )
    end)
  end
end
