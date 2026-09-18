defmodule Estimate.EstimationEngine.Helpers do
  @moduledoc false

  alias Estimate.Repo

  @doc """
  Wraps a repo result with a broadcast on success.
  """
  def with_broadcast(result, estimation_id, event_fn) do
    case result do
      {:ok, record} ->
        Estimate.EstimationEngine.broadcast(estimation_id, event_fn.(record))
        {:ok, record}

      error ->
        error
    end
  end

  @doc """
  Builds and executes a Multi for creating an estimation with roles and optional epics/tasks.
  """
  def build_estimation_multi(attrs, roles_fn, opts \\ []) do
    alias Estimate.EstimationEngine.{Estimation, Estimations}
    alias Estimate.Search

    Repo.ensure_org_context(fn ->
      attrs = Estimations.prepare_estimation_attrs(attrs)

      multi =
        Ecto.Multi.new()
        |> Ecto.Multi.insert(:estimation, Estimation.changeset(%Estimation{}, attrs))
        |> Ecto.Multi.run(:roles, fn _repo, %{estimation: estimation} ->
          roles_fn.(estimation)
        end)

      multi =
        case Keyword.get(opts, :epics_fn) do
          nil ->
            multi

          epics_fn ->
            Ecto.Multi.run(multi, :epics_tasks, fn _repo, %{estimation: estimation} ->
              epics_fn.(estimation)
            end)
        end

      case Repo.transaction(multi) do
        {:ok, %{estimation: estimation}} ->
          estimation = Repo.preload(estimation, project: :customer)
          Search.index_estimation(estimation)
          {:ok, estimation}

        {:error, _op, changeset, _} ->
          {:error, changeset}
      end
    end)
  end
end
