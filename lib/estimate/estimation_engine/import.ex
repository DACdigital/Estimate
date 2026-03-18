defmodule Estimate.EstimationEngine.Import do
  @moduledoc false

  alias Estimate.Repo
  alias Estimate.EstimationEngine.{Epic, Task}
  alias Estimate.EstimationEngine.{Roles, Helpers}

  def create_estimation_from_templates(attrs, role_attrs) when is_list(role_attrs) do
    Helpers.build_estimation_multi(attrs, fn estimation ->
      Roles.insert_roles_from_attrs(estimation.id, role_attrs)
    end)
  end

  def create_estimation_from_estimation_template(attrs, estimation_template_id, role_attrs)
      when is_list(role_attrs) do
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

    Helpers.build_estimation_multi(
      attrs,
      fn estimation -> Roles.insert_roles_from_attrs(estimation.id, role_attrs) end,
      epics_fn: fn estimation -> insert_epics_and_tasks(estimation.id, epics_data) end
    )
  end

  def create_estimation_from_json(attrs, parsed_json, role_attrs) when is_list(role_attrs) do
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

    Helpers.build_estimation_multi(
      attrs,
      fn estimation -> Roles.insert_roles_from_attrs(estimation.id, role_attrs) end,
      epics_fn: fn estimation -> insert_epics_and_tasks(estimation.id, epics_data) end
    )
  end

  defp insert_epics_and_tasks(estimation_id, epics_data) do
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
