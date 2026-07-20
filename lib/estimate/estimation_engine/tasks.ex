defmodule Estimate.EstimationEngine.Tasks do
  @moduledoc false

  import Ecto.Query
  alias Estimate.Repo
  alias Estimate.EstimationEngine.{Epic, Task, TaskEstimate}

  def create_task(attrs) do
    Repo.ensure_org_context(fn ->
      result =
        %Task{}
        |> Task.changeset(attrs)
        |> Repo.insert()

      case result do
        {:ok, task} ->
          epic = get_epic_for_task!(task)
          Estimate.EstimationEngine.broadcast(epic.estimation_id, {:task_created, task})
          Estimate.EstimationEngine.reindex_estimation_async(epic.estimation_id)
          {:ok, task}

        error ->
          error
      end
    end)
  end

  def create_task_with_estimates(epic_id, task_attrs, effort_by_role_id)
      when is_map(effort_by_role_id) do
    Repo.ensure_org_context(fn ->
      Ecto.Multi.new()
      |> Ecto.Multi.insert(
        :task,
        Task.changeset(%Task{}, Map.put(task_attrs, "epic_id", epic_id))
      )
      |> Ecto.Multi.run(:estimates, fn _repo, %{task: task} ->
        Enum.reduce_while(effort_by_role_id, {:ok, []}, fn {role_id, hours}, {:ok, acc} ->
          %TaskEstimate{}
          |> TaskEstimate.changeset(%{
            "task_id" => task.id,
            "estimation_role_id" => role_id,
            "hours" => to_string(hours)
          })
          |> Ecto.Changeset.foreign_key_constraint(:estimation_role_id)
          |> Repo.insert()
          |> case do
            {:ok, te} -> {:cont, {:ok, [te | acc]}}
            {:error, cs} -> {:halt, {:error, cs}}
          end
        end)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{task: task}} ->
          task = Repo.preload(task, :estimates)
          epic = Repo.get!(Epic, epic_id)
          Estimate.EstimationEngine.broadcast(epic.estimation_id, {:task_created, task})
          {:ok, task}

        {:error, _op, changeset, _} ->
          {:error, changeset}
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
          epic = get_epic_for_task!(task)
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
      epic = get_epic_for_task!(task)
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

  defp get_epic_for_task!(%Task{epic_id: epic_id}) do
    from(ep in Epic,
      join: e in assoc(ep, :estimation),
      where: ep.id == ^epic_id,
      select: ep
    )
    |> Repo.one!()
  end
end
