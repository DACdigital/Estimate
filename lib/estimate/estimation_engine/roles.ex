defmodule Estimate.EstimationEngine.Roles do
  @moduledoc false

  import Ecto.Query
  alias Estimate.Repo
  alias Estimate.EstimationEngine.EstimationRole

  alias Estimate.EstimationEngine.Helpers

  def create_role(attrs) do
    Repo.ensure_org_context(fn ->
      result =
        %EstimationRole{}
        |> EstimationRole.changeset(attrs)
        |> Repo.insert()

      Helpers.with_broadcast(result, result_estimation_id(result), &{:role_created, &1})
    end)
  end

  defp result_estimation_id({:ok, record}), do: record.estimation_id
  defp result_estimation_id(_), do: nil

  def update_role(%EstimationRole{} = role, attrs) do
    Repo.ensure_org_context(fn ->
      role
      |> EstimationRole.update_changeset(attrs)
      |> Repo.update()
      |> Helpers.with_broadcast(role.estimation_id, &{:role_updated, &1})
    end)
  end

  def delete_role(%EstimationRole{} = role) do
    Repo.ensure_org_context(fn ->
      Repo.delete(role)
      |> Helpers.with_broadcast(role.estimation_id, &{:role_deleted, &1})
    end)
  end

  def reorder_roles(estimation_id, role_ids) do
    alias Estimate.EstimationEngine.Helpers

    Helpers.reorder_children(EstimationRole, :estimation_id, estimation_id, role_ids, fn ->
      Estimate.EstimationEngine.broadcast(estimation_id, {:roles_reordered, role_ids})
    end)
  end

  def get_role!(id, org_id) do
    Repo.ensure_org_context(fn ->
      from(er in EstimationRole,
        join: e in assoc(er, :estimation),
        where: er.id == ^id and e.organization_id == ^org_id
      )
      |> Repo.one!()
    end)
  end

  @doc false
  def insert_roles_from_attrs(estimation_id, role_attrs_list) do
    insert_roles(role_attrs_list, fn attrs, idx ->
      %{
        name: attrs.name,
        abbreviation: attrs.abbreviation,
        hourly_rate: attrs.hourly_rate || Decimal.new(0),
        pm_overhead: attrs.pm_overhead || Decimal.new(0),
        qa_overhead: attrs.qa_overhead || Decimal.new(0),
        risk_buffer: attrs.risk_buffer || Decimal.new(0),
        position: idx,
        estimation_id: estimation_id
      }
    end)
  end

  @doc false
  def insert_roles_from_role_templates(estimation_id, templates, currency_id) do
    insert_roles(templates, fn template, idx ->
      rate = Enum.find(template.rates, fn r -> r.currency_id == currency_id end)
      hourly_rate = if rate, do: rate.hourly_rate, else: Decimal.new(0)

      %{
        name: template.name,
        abbreviation: template.abbreviation,
        hourly_rate: hourly_rate,
        pm_overhead: template.pm_overhead,
        qa_overhead: template.qa_overhead,
        risk_buffer: template.risk_buffer,
        position: idx,
        estimation_id: estimation_id
      }
    end)
  end

  @doc false
  def insert_roles_from_project_roles(estimation_id, project_roles) do
    insert_roles(project_roles, fn project_role, idx ->
      %{
        name: project_role.name,
        abbreviation: project_role.abbreviation,
        hourly_rate: project_role.hourly_rate,
        pm_overhead: project_role.pm_overhead,
        qa_overhead: project_role.qa_overhead,
        risk_buffer: project_role.risk_buffer,
        position: idx,
        estimation_id: estimation_id,
        project_role_id: project_role.id
      }
    end)
  end

  defp insert_roles(items, attrs_fn) do
    items
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {item, idx}, {:ok, acc} ->
      %EstimationRole{}
      |> EstimationRole.changeset(attrs_fn.(item, idx))
      |> Repo.insert()
      |> case do
        {:ok, role} -> {:cont, {:ok, [role | acc]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
    |> case do
      {:ok, roles} -> {:ok, Enum.reverse(roles)}
      error -> error
    end
  end
end
