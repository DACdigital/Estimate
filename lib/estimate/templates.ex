defmodule Estimate.Templates do
  import Ecto.Query
  alias Estimate.Repo

  alias Estimate.Templates.{
    EstimationTemplate,
    EstimationTemplateEpic,
    EstimationTemplateTask
  }

  ## Estimation Templates

  def list_estimation_templates(org_id) do
    Repo.ensure_org_context(fn ->
      from(t in EstimationTemplate,
        where: t.organization_id == ^org_id,
        order_by: [desc: t.updated_at],
        preload: [epics: :tasks]
      )
      |> Repo.all()
    end)
  end

  def get_estimation_template!(id, org_id) do
    Repo.ensure_org_context(fn ->
      from(t in EstimationTemplate,
        where: t.id == ^id and t.organization_id == ^org_id,
        preload: [
          epics:
            ^from(e in EstimationTemplateEpic,
              order_by: e.position,
              preload: [tasks: ^from(tk in EstimationTemplateTask, order_by: tk.position)]
            )
        ]
      )
      |> Repo.one!()
    end)
  end

  def create_estimation_template(org_id, attrs) do
    Repo.ensure_org_context(fn ->
      %EstimationTemplate{}
      |> EstimationTemplate.changeset(Map.put(attrs, "organization_id", org_id))
      |> Repo.insert()
    end)
  end

  def update_estimation_template(%EstimationTemplate{} = template, attrs) do
    Repo.ensure_org_context(fn ->
      template
      |> EstimationTemplate.changeset(attrs)
      |> Repo.update()
    end)
  end

  def delete_estimation_template(%EstimationTemplate{} = template) do
    Repo.ensure_org_context(fn ->
      Repo.delete(template)
    end)
  end

  ## Template Epics

  def create_template_epic(attrs) do
    Repo.ensure_org_context(fn ->
      %EstimationTemplateEpic{}
      |> EstimationTemplateEpic.changeset(attrs)
      |> Repo.insert()
    end)
  end

  def update_template_epic(%EstimationTemplateEpic{} = epic, attrs) do
    Repo.ensure_org_context(fn ->
      epic
      |> EstimationTemplateEpic.changeset(attrs)
      |> Repo.update()
    end)
  end

  def delete_template_epic(%EstimationTemplateEpic{} = epic) do
    Repo.ensure_org_context(fn ->
      Repo.delete(epic)
    end)
  end

  def reorder_template_epics(template_id, epic_ids) do
    Repo.ensure_org_context(fn ->
      Repo.transaction(fn ->
        epic_ids
        |> Enum.with_index()
        |> Enum.each(fn {id, position} ->
          from(e in EstimationTemplateEpic,
            where: e.id == ^id and e.estimation_template_id == ^template_id
          )
          |> Repo.update_all(set: [position: position])
        end)
      end)

      :ok
    end)
  end

  ## Template Tasks

  def create_template_task(attrs) do
    Repo.ensure_org_context(fn ->
      %EstimationTemplateTask{}
      |> EstimationTemplateTask.changeset(attrs)
      |> Repo.insert()
    end)
  end

  def update_template_task(%EstimationTemplateTask{} = task, attrs) do
    Repo.ensure_org_context(fn ->
      task
      |> EstimationTemplateTask.changeset(attrs)
      |> Repo.update()
    end)
  end

  def delete_template_task(%EstimationTemplateTask{} = task) do
    Repo.ensure_org_context(fn ->
      Repo.delete(task)
    end)
  end

  def reorder_template_tasks(epic_id, task_ids) do
    Repo.ensure_org_context(fn ->
      Repo.transaction(fn ->
        task_ids
        |> Enum.with_index()
        |> Enum.each(fn {id, position} ->
          from(t in EstimationTemplateTask,
            where: t.id == ^id and t.estimation_template_epic_id == ^epic_id
          )
          |> Repo.update_all(set: [position: position])
        end)
      end)

      :ok
    end)
  end

  ## Create from JSON import

  def create_template_from_json(org_id, attrs, parsed_json) do
    epics =
      parsed_json.epics
      |> Enum.with_index()
      |> Enum.map(fn {epic, idx} -> Map.put(epic, :position, idx) end)

    create_template_with_epics(org_id, %{
      name: attrs["name"] || parsed_json.estimation || "Imported Template",
      description: attrs["description"] || parsed_json.description,
      epics: epics
    })
  end

  ## Create from existing estimation

  def create_from_estimation(org_id, name, estimation) do
    create_template_with_epics(org_id, %{
      name: name,
      description: estimation.description,
      epics: estimation.epics
    })
  end

  defp create_template_with_epics(org_id, %{name: name, description: desc, epics: epics}) do
    Repo.ensure_org_context(fn ->
      Ecto.Multi.new()
      |> Ecto.Multi.insert(:template, fn _ ->
        EstimationTemplate.changeset(%EstimationTemplate{}, %{
          name: name,
          description: desc,
          organization_id: org_id
        })
      end)
      |> Ecto.Multi.run(:epics_tasks, fn _repo, %{template: template} ->
        epics
        |> Enum.reduce_while(:ok, fn epic, :ok ->
          position = Map.get(epic, :position) || 0

          with {:ok, new_epic} <-
                 %EstimationTemplateEpic{}
                 |> EstimationTemplateEpic.changeset(%{
                   name: epic.name,
                   description: epic.description,
                   position: position,
                   estimation_template_id: template.id
                 })
                 |> Repo.insert(),
               :ok <- insert_template_tasks(epic.tasks, new_epic.id) do
            {:cont, :ok}
          else
            {:error, changeset} -> {:halt, {:error, changeset}}
          end
        end)
        |> case do
          :ok -> {:ok, :done}
          {:error, changeset} -> {:error, changeset}
        end
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{template: template}} -> {:ok, template}
        {:error, _op, changeset, _} -> {:error, changeset}
      end
    end)
  end

  defp insert_template_tasks(tasks, epic_id) do
    tasks
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {task, position}, :ok ->
      %EstimationTemplateTask{}
      |> EstimationTemplateTask.changeset(%{
        name: task.name,
        description: task.description,
        position: position,
        priority: task.priority,
        estimation_template_epic_id: epic_id
      })
      |> Repo.insert()
      |> case do
        {:ok, _} -> {:cont, :ok}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end
end
