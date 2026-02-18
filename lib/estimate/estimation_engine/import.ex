defmodule Estimate.EstimationEngine.Import do
  @moduledoc false

  alias Estimate.Repo
  alias Estimate.EstimationEngine.{Estimation, Epic, Task}
  alias Estimate.EstimationEngine.{Estimations, Roles}
  alias Estimate.Search

  def create_estimation_from_templates(attrs, template_ids, currency_id)
      when is_list(template_ids) do
    Repo.ensure_org_context(fn ->
      attrs = Estimations.prepare_estimation_attrs(attrs)

      Ecto.Multi.new()
      |> Ecto.Multi.insert(:estimation, Estimation.changeset(%Estimation{}, attrs))
      |> Ecto.Multi.run(:roles, fn _repo, %{estimation: estimation} ->
        templates = Estimate.Accounts.list_role_templates_by_ids(template_ids)
        Roles.insert_roles_from_role_templates(estimation.id, templates, currency_id)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{estimation: estimation}} ->
          estimation = Repo.preload(estimation, project: :customer)
          Search.index_estimation(estimation)
          {:ok, estimation}

        {:error, _op, changeset, _} ->
          {:error, changeset}
      end
    end)
  end

  def create_estimation_from_estimation_template(
        attrs,
        estimation_template_id,
        role_template_ids,
        currency_id
      ) do
    Repo.ensure_org_context(fn ->
      attrs = Estimations.prepare_estimation_attrs(attrs)
      org_id = attrs["organization_id"] || attrs[:organization_id]

      est_template =
        Estimate.Templates.get_estimation_template!(estimation_template_id, org_id)

      epics_data =
        Enum.map(est_template.epics, fn tmpl_epic ->
          %{
            name: tmpl_epic.name,
            description: tmpl_epic.description,
            position: tmpl_epic.position,
            tasks:
              Enum.map(tmpl_epic.tasks, fn t ->
                %{
                  name: t.name,
                  description: t.description,
                  position: t.position,
                  priority: t.priority
                }
              end)
          }
        end)

      Ecto.Multi.new()
      |> Ecto.Multi.insert(:estimation, Estimation.changeset(%Estimation{}, attrs))
      |> Ecto.Multi.run(:roles, fn _repo, %{estimation: estimation} ->
        templates = Estimate.Accounts.list_role_templates_by_ids(role_template_ids)
        Roles.insert_roles_from_role_templates(estimation.id, templates, currency_id)
      end)
      |> Ecto.Multi.run(:epics_tasks, fn _repo, %{estimation: estimation} ->
        insert_epics_and_tasks(estimation.id, epics_data)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{estimation: estimation}} ->
          estimation = Repo.preload(estimation, project: :customer)
          Search.index_estimation(estimation)
          {:ok, estimation}

        {:error, _op, changeset, _} ->
          {:error, changeset}
      end
    end)
  end

  def create_estimation_from_json(attrs, parsed_json, role_template_ids, currency_id) do
    Repo.ensure_org_context(fn ->
      attrs = Estimations.prepare_estimation_attrs(attrs)

      epics_data =
        Enum.map(parsed_json.epics, fn epic ->
          %{
            name: epic.name,
            description: epic[:description],
            tasks:
              Enum.map(epic.tasks, fn t ->
                %{name: t.name, description: t[:description], priority: t[:priority] || "must"}
              end)
          }
        end)

      Ecto.Multi.new()
      |> Ecto.Multi.insert(:estimation, Estimation.changeset(%Estimation{}, attrs))
      |> Ecto.Multi.run(:roles, fn _repo, %{estimation: estimation} ->
        templates = Estimate.Accounts.list_role_templates_by_ids(role_template_ids)
        Roles.insert_roles_from_role_templates(estimation.id, templates, currency_id)
      end)
      |> Ecto.Multi.run(:epics_tasks, fn _repo, %{estimation: estimation} ->
        insert_epics_and_tasks(estimation.id, epics_data)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{estimation: estimation}} ->
          estimation = Repo.preload(estimation, project: :customer)
          Search.index_estimation(estimation)
          {:ok, estimation}

        {:error, _op, changeset, _} ->
          {:error, changeset}
      end
    end)
  end

  @doc false
  def insert_epics_and_tasks(estimation_id, epics_data) do
    epics_data
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {epic_data, epic_idx}, {:ok, acc} ->
      epic_attrs = %{
        name: epic_data.name,
        description: epic_data[:description],
        position: epic_data[:position] || epic_idx,
        estimation_id: estimation_id
      }

      case Repo.insert(Epic.changeset(%Epic{}, epic_attrs)) do
        {:ok, new_epic} ->
          case insert_tasks(new_epic.id, epic_data.tasks) do
            {:ok, _} -> {:cont, {:ok, [new_epic | acc]}}
            {:error, changeset} -> {:halt, {:error, changeset}}
          end

        {:error, changeset} ->
          {:halt, {:error, changeset}}
      end
    end)
  end

  defp insert_tasks(epic_id, tasks) do
    tasks
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {task_data, task_idx}, {:ok, acc} ->
      task_attrs = %{
        name: task_data.name,
        description: task_data[:description],
        position: task_data[:position] || task_idx,
        priority: task_data[:priority] || "must",
        epic_id: epic_id
      }

      case Repo.insert(Task.changeset(%Task{}, task_attrs)) do
        {:ok, task} -> {:cont, {:ok, [task | acc]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end
end
