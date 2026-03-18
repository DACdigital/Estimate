defmodule Estimate.EstimationEngine.Epics do
  @moduledoc false

  import Ecto.Query
  alias Estimate.Repo
  alias Estimate.EstimationEngine.Epic

  alias Estimate.EstimationEngine.Helpers

  def create_epic(attrs) do
    Repo.ensure_org_context(fn ->
      result =
        %Epic{}
        |> Epic.changeset(attrs)
        |> Repo.insert()

      case result do
        {:ok, epic} -> Helpers.with_broadcast(result, epic.estimation_id, &{:epic_created, &1})
        error -> error
      end
    end)
  end

  def update_epic(%Epic{} = epic, attrs) do
    Repo.ensure_org_context(fn ->
      epic
      |> Epic.changeset(attrs)
      |> Repo.update()
      |> Helpers.with_broadcast(epic.estimation_id, &{:epic_updated, &1})
    end)
  end

  def delete_epic(%Epic{} = epic) do
    estimation_id = epic.estimation_id

    Repo.ensure_org_context(fn ->
      Repo.delete(epic)
      |> Helpers.with_broadcast(estimation_id, &{:epic_deleted, &1})
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
    alias Estimate.EstimationEngine.Helpers

    Helpers.reorder_children(Epic, :estimation_id, estimation_id, epic_ids, fn ->
      Estimate.EstimationEngine.broadcast(estimation_id, {:epics_reordered, epic_ids})
    end)
  end
end
