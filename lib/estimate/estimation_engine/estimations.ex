defmodule Estimate.EstimationEngine.Estimations do
  @moduledoc false

  import Ecto.Query
  alias Estimate.Repo
  alias Estimate.EstimationEngine.{Estimation, EstimationRole}
  alias Estimate.Search

  def count_estimations_for_org(org_id) do
    Repo.ensure_org_context(fn ->
      from(e in Estimation,
        where: e.organization_id == ^org_id and is_nil(e.deleted_at)
      )
      |> Repo.aggregate(:count)
    end)
  end

  def list_estimations_for_org(org_id, opts \\ []) do
    order_field = Keyword.get(opts, :order_by, :updated_at)
    limit = Keyword.get(opts, :limit, 5)

    Repo.ensure_org_context(fn ->
      from(e in Estimation,
        where: e.organization_id == ^org_id and is_nil(e.deleted_at),
        order_by: [{:desc, field(e, ^order_field)}],
        limit: ^limit,
        preload: [:currency, project: [:customer, :currency]]
      )
      |> Repo.all()
    end)
  end

  def list_recent_estimations_for_org(org_id, limit \\ 5),
    do: list_estimations_for_org(org_id, order_by: :updated_at, limit: limit)

  def list_newest_estimations_for_org(org_id, limit \\ 5),
    do: list_estimations_for_org(org_id, order_by: :inserted_at, limit: limit)

  def list_estimations(project_id) do
    Repo.ensure_org_context(fn ->
      from(e in Estimation,
        where: e.project_id == ^project_id and is_nil(e.deleted_at),
        order_by: [desc: e.updated_at],
        preload: [:roles, :currency]
      )
      |> Repo.all()
    end)
  end

  def get_estimation!(id, org_id) do
    Repo.ensure_org_context(fn ->
      from(e in Estimation,
        where: e.id == ^id and e.organization_id == ^org_id and is_nil(e.deleted_at),
        preload: [
          :currency,
          roles: ^from(r in EstimationRole, order_by: r.position),
          epics:
            ^from(ep in Estimate.EstimationEngine.Epic,
              order_by: ep.position,
              preload: [
                tasks:
                  ^from(t in Estimate.EstimationEngine.Task,
                    order_by: t.position,
                    preload: [:estimates]
                  )
              ]
            )
        ]
      )
      |> Repo.one!()
    end)
  end

  def create_estimation(attrs) do
    alias Estimate.EstimationEngine.Helpers

    Helpers.build_estimation_multi(attrs, fn estimation ->
      EstimationRole.default_roles()
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, []}, fn {role_attrs, idx}, {:ok, acc} ->
        %EstimationRole{}
        |> EstimationRole.changeset(
          Map.merge(role_attrs, %{estimation_id: estimation.id, position: idx})
        )
        |> Repo.insert()
        |> case do
          {:ok, role} -> {:cont, {:ok, [role | acc]}}
          {:error, changeset} -> {:halt, {:error, changeset}}
        end
      end)
    end)
  end

  def create_estimation_with_roles(attrs, role_ids) when is_list(role_ids) do
    alias Estimate.EstimationEngine.{Roles, Helpers}

    Helpers.build_estimation_multi(attrs, fn estimation ->
      project_roles = Estimate.Portfolio.list_project_roles_by_ids(role_ids)
      Roles.insert_roles_from_project_roles(estimation.id, project_roles)
    end)
  end

  def update_estimation(%Estimation{} = estimation, attrs) do
    Repo.ensure_org_context(fn ->
      result =
        estimation
        |> Estimation.changeset(attrs)
        |> Repo.update()

      case result do
        {:ok, estimation} ->
          Estimate.EstimationEngine.broadcast(estimation.id, {:estimation_updated, estimation})
          estimation = Repo.preload(estimation, [project: :customer], force: true)
          Search.index_estimation(estimation)
          {:ok, estimation}

        error ->
          error
      end
    end)
  end

  def soft_delete_estimation(%Estimation{} = estimation) do
    Repo.ensure_org_context(fn ->
      result =
        estimation
        |> Estimation.soft_delete_changeset()
        |> Repo.update()

      case result do
        {:ok, estimation} ->
          Search.remove_index("estimation", estimation.id)
          {:ok, estimation}

        error ->
          error
      end
    end)
  end

  def set_current_estimation(%Estimation{} = estimation) do
    Repo.ensure_org_context(fn ->
      Ecto.Multi.new()
      |> Ecto.Multi.update(:set_current, Estimation.changeset(estimation, %{is_current: true}))
      |> Ecto.Multi.update_all(
        :unset_others,
        fn _ ->
          from(e in Estimation,
            where:
              e.project_id == ^estimation.project_id and e.id != ^estimation.id and
                e.is_current == true
          )
        end,
        set: [is_current: false]
      )
      |> Repo.transaction()
      |> case do
        {:ok, %{set_current: estimation}} -> {:ok, estimation}
        {:error, _op, changeset, _} -> {:error, changeset}
      end
    end)
  end

  def restore_estimation(%Estimation{deleted_at: nil}), do: {:error, :not_deleted}

  def restore_estimation(%Estimation{} = estimation) do
    Repo.ensure_org_context(fn ->
      Ecto.Multi.new()
      |> Ecto.Multi.update(:restore, Ecto.Changeset.change(estimation, deleted_at: nil))
      |> Ecto.Multi.run(:auto_current, fn _repo, %{restore: restored} ->
        maybe_auto_set_current(restored)
        {:ok, :done}
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{restore: estimation}} ->
          estimation = Repo.preload(estimation, [project: :customer], force: true)
          Search.index_estimation(estimation)
          {:ok, estimation}

        {:error, _op, changeset, _} ->
          {:error, changeset}
      end
    end)
  end

  def hard_delete_estimation(%Estimation{deleted_at: nil}), do: {:error, :not_deleted}

  def hard_delete_estimation(%Estimation{} = estimation) do
    Repo.ensure_org_context(fn ->
      result = Repo.delete(estimation)

      case result do
        {:ok, estimation} ->
          Search.remove_index("estimation", estimation.id)
          {:ok, estimation}

        error ->
          error
      end
    end)
  end

  def list_deleted_estimations(project_id) do
    Repo.ensure_org_context(fn ->
      from(e in Estimation,
        where: e.project_id == ^project_id and not is_nil(e.deleted_at),
        order_by: [desc: e.deleted_at],
        preload: [:roles, :currency]
      )
      |> Repo.all()
    end)
  end

  def list_deleted_estimations_for_org(org_id, limit \\ 10) do
    Repo.ensure_org_context(fn ->
      from(e in Estimation,
        where: e.organization_id == ^org_id and not is_nil(e.deleted_at),
        order_by: [desc: e.deleted_at],
        limit: ^limit,
        preload: [:currency, project: [:customer]]
      )
      |> Repo.all()
    end)
  end

  def count_deleted_estimations_for_org(org_id) do
    Repo.ensure_org_context(fn ->
      from(e in Estimation,
        where: e.organization_id == ^org_id and not is_nil(e.deleted_at)
      )
      |> Repo.aggregate(:count)
    end)
  end

  def change_estimation(%Estimation{} = estimation, attrs \\ %{}) do
    Estimation.changeset(estimation, attrs)
  end

  @doc false
  def prepare_estimation_attrs(attrs) do
    project_id = attrs["project_id"] || attrs[:project_id]
    is_first = count_estimations_for_project(project_id) == 0
    if is_first, do: Map.put(attrs, "is_current", true), else: attrs
  end

  defp count_estimations_for_project(project_id) do
    Repo.ensure_org_context(fn ->
      from(e in Estimation, where: e.project_id == ^project_id and is_nil(e.deleted_at))
      |> Repo.aggregate(:count)
    end)
  end

  defp maybe_auto_set_current(%Estimation{} = estimation) do
    has_current =
      from(e in Estimation,
        where:
          e.project_id == ^estimation.project_id and
            e.is_current == true and
            is_nil(e.deleted_at)
      )
      |> Repo.exists?()

    unless has_current do
      estimation
      |> Ecto.Changeset.change(is_current: true)
      |> Repo.update()
    end
  end
end
