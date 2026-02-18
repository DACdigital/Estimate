defmodule Estimate.EstimationEngine.Roles do
  @moduledoc false

  import Ecto.Query
  alias Estimate.Repo
  alias Estimate.EstimationEngine.EstimationRole

  def create_role(attrs) do
    Repo.ensure_org_context(fn ->
      result =
        %EstimationRole{}
        |> EstimationRole.changeset(attrs)
        |> Repo.insert()

      case result do
        {:ok, role} ->
          Estimate.EstimationEngine.broadcast(role.estimation_id, {:role_created, role})
          {:ok, role}

        error ->
          error
      end
    end)
  end

  def update_role(%EstimationRole{} = role, attrs) do
    Repo.ensure_org_context(fn ->
      result =
        role
        |> EstimationRole.changeset(attrs)
        |> Repo.update()

      case result do
        {:ok, role} ->
          Estimate.EstimationEngine.broadcast(role.estimation_id, {:role_updated, role})
          {:ok, role}

        error ->
          error
      end
    end)
  end

  def delete_role(%EstimationRole{} = role) do
    Repo.ensure_org_context(fn ->
      result = Repo.delete(role)

      case result do
        {:ok, role} ->
          Estimate.EstimationEngine.broadcast(role.estimation_id, {:role_deleted, role})
          {:ok, role}

        error ->
          error
      end
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

  def update_role_rate(%EstimationRole{} = role, hourly_rate, _org_id) do
    Repo.ensure_org_context(fn ->
      result =
        role
        |> EstimationRole.changeset(%{hourly_rate: hourly_rate})
        |> Repo.update()

      case result do
        {:ok, updated_role} ->
          Estimate.EstimationEngine.broadcast(
            updated_role.estimation_id,
            {:role_updated, updated_role}
          )

          {:ok, updated_role}

        error ->
          error
      end
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
  end
end
