defmodule Estimate.EstimationEngine.Epics do
  @moduledoc false

  import Ecto.Query
  alias Estimate.Repo
  alias Estimate.EstimationEngine.Epic

  def create_epic(attrs) do
    Repo.ensure_org_context(fn ->
      result =
        %Epic{}
        |> Epic.changeset(attrs)
        |> Repo.insert()

      case result do
        {:ok, epic} ->
          Estimate.EstimationEngine.broadcast(epic.estimation_id, {:epic_created, epic})
          {:ok, epic}

        error ->
          error
      end
    end)
  end

  def update_epic(%Epic{} = epic, attrs) do
    Repo.ensure_org_context(fn ->
      result =
        epic
        |> Epic.changeset(attrs)
        |> Repo.update()

      case result do
        {:ok, epic} ->
          Estimate.EstimationEngine.broadcast(epic.estimation_id, {:epic_updated, epic})
          {:ok, epic}

        error ->
          error
      end
    end)
  end

  def delete_epic(%Epic{} = epic) do
    Repo.ensure_org_context(fn ->
      estimation_id = epic.estimation_id
      result = Repo.delete(epic)

      case result do
        {:ok, epic} ->
          Estimate.EstimationEngine.broadcast(estimation_id, {:epic_deleted, epic})
          {:ok, epic}

        error ->
          error
      end
    end)
  end

  def get_epic!(id, org_id) do
    Repo.ensure_org_context(fn ->
      from(ep in Epic,
        join: e in assoc(ep, :estimation),
        where: ep.id == ^id and e.organization_id == ^org_id
      )
      |> Repo.one!()
    end)
  end

  def reorder_epics(estimation_id, epic_ids) do
    Repo.ensure_org_context(fn ->
      case Repo.transaction(fn ->
             epic_ids
             |> Enum.with_index()
             |> Enum.each(fn {id, position} ->
               from(e in Epic, where: e.id == ^id and e.estimation_id == ^estimation_id)
               |> Repo.update_all(set: [position: position])
             end)
           end) do
        {:ok, _} ->
          Estimate.EstimationEngine.broadcast(estimation_id, {:epics_reordered, epic_ids})
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    end)
  end
end
