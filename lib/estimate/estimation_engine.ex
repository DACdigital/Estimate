defmodule Estimate.EstimationEngine do
  require Logger

  @moduledoc """
  The EstimationEngine context for managing estimations, roles, epics, tasks, and estimates.
  Supports real-time collaboration via PubSub.

  All public functions that touch RLS-protected tables are wrapped with
  `Repo.ensure_org_context/1`, which automatically checks out a connection
  and sets SET ROLE + org context if the calling process has an org_id
  stored (via `Repo.put_org_id/1` in LiveView mount).
  """

  import Ecto.Query
  alias Estimate.Repo
  alias Estimate.EstimationEngine.{Estimation, EstimationRole, Epic, Task, TaskEstimate}
  alias Estimate.Portfolio
  alias Estimate.Search

  @pubsub Estimate.PubSub
  @topic_prefix "estimation:"

  ## PubSub

  def subscribe(estimation_id) do
    Phoenix.PubSub.subscribe(@pubsub, topic(estimation_id))
  end

  def broadcast(estimation_id, event) do
    Phoenix.PubSub.broadcast(@pubsub, topic(estimation_id), event)
  end

  defp topic(estimation_id), do: @topic_prefix <> estimation_id

  ## Estimations

  def count_estimations_for_org(org_id) do
    Repo.ensure_org_context(fn ->
      from(e in Estimation,
        where: e.organization_id == ^org_id and is_nil(e.deleted_at)
      )
      |> Repo.aggregate(:count)
    end)
  end

  def list_recent_estimations_for_org(org_id, limit \\ 5) do
    Repo.ensure_org_context(fn ->
      from(e in Estimation,
        where: e.organization_id == ^org_id and is_nil(e.deleted_at),
        order_by: [desc: e.updated_at],
        limit: ^limit,
        preload: [:currency, project: [:customer, :currency]]
      )
      |> Repo.all()
    end)
  end

  def list_newest_estimations_for_org(org_id, limit \\ 5) do
    Repo.ensure_org_context(fn ->
      from(e in Estimation,
        where: e.organization_id == ^org_id and is_nil(e.deleted_at),
        order_by: [desc: e.inserted_at],
        limit: ^limit,
        preload: [:currency, project: [:customer, :currency]]
      )
      |> Repo.all()
    end)
  end

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
            ^from(ep in Epic,
              order_by: ep.position,
              preload: [tasks: ^from(t in Task, order_by: t.position, preload: [:estimates])]
            )
        ]
      )
      |> Repo.one!()
    end)
  end

  def create_estimation(attrs) do
    Repo.ensure_org_context(fn ->
      Ecto.Multi.new()
      |> Ecto.Multi.insert(:estimation, Estimation.changeset(%Estimation{}, attrs))
      |> Ecto.Multi.run(:roles, fn _repo, %{estimation: estimation} ->
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
      |> Repo.transaction()
      |> case do
        {:ok, %{estimation: estimation}} -> {:ok, estimation}
        {:error, _op, changeset, _} -> {:error, changeset}
      end
    end)
  end

  @doc """
  Creates estimation with selected project roles instead of default roles.
  role_ids should be a list of ProjectRole IDs to include.
  Auto-sets is_current=true if this is the first estimation for the project.
  """
  def create_estimation_with_roles(attrs, role_ids) when is_list(role_ids) do
    Repo.ensure_org_context(fn ->
      attrs = prepare_estimation_attrs(attrs)

      Ecto.Multi.new()
      |> Ecto.Multi.insert(:estimation, Estimation.changeset(%Estimation{}, attrs))
      |> Ecto.Multi.run(:roles, fn _repo, %{estimation: estimation} ->
        project_roles = Portfolio.list_project_roles_by_ids(role_ids)
        insert_roles_from_project_roles(estimation.id, project_roles)
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

  defp count_estimations_for_project(project_id) do
    from(e in Estimation, where: e.project_id == ^project_id and is_nil(e.deleted_at))
    |> Repo.aggregate(:count)
  end

  @doc """
  Creates estimation from org role templates.
  template_ids - list of RoleTemplate IDs to include
  currency_id - the currency to use for rates (looks up rate from template)
  Auto-sets is_current=true if first estimation for project.
  """
  def create_estimation_from_templates(attrs, template_ids, currency_id)
      when is_list(template_ids) do
    Repo.ensure_org_context(fn ->
      attrs = prepare_estimation_attrs(attrs)

      Ecto.Multi.new()
      |> Ecto.Multi.insert(:estimation, Estimation.changeset(%Estimation{}, attrs))
      |> Ecto.Multi.run(:roles, fn _repo, %{estimation: estimation} ->
        templates = Estimate.Accounts.list_role_templates_by_ids(template_ids)
        insert_roles_from_role_templates(estimation.id, templates, currency_id)
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

  @doc """
  Creates estimation from an estimation template (epic/task structure)
  plus role templates (roles with rates).
  """
  def create_estimation_from_estimation_template(
        attrs,
        estimation_template_id,
        role_template_ids,
        currency_id
      ) do
    Repo.ensure_org_context(fn ->
      attrs = prepare_estimation_attrs(attrs)
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
        insert_roles_from_role_templates(estimation.id, templates, currency_id)
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

  @doc """
  Creates estimation from parsed JSON import data + role templates.
  parsed_json comes from JsonImport.parse_and_validate/1.
  """
  def create_estimation_from_json(attrs, parsed_json, role_template_ids, currency_id) do
    Repo.ensure_org_context(fn ->
      attrs = prepare_estimation_attrs(attrs)

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
        insert_roles_from_role_templates(estimation.id, templates, currency_id)
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

  def update_estimation(%Estimation{} = estimation, attrs) do
    Repo.ensure_org_context(fn ->
      result =
        estimation
        |> Estimation.changeset(attrs)
        |> Repo.update()

      case result do
        {:ok, estimation} ->
          broadcast(estimation.id, {:estimation_updated, estimation})
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
      |> Ecto.Multi.update(:set_current, Estimation.changeset(estimation, %{is_current: true}))
      |> Repo.transaction()
      |> case do
        {:ok, %{set_current: estimation}} -> {:ok, estimation}
        {:error, _op, changeset, _} -> {:error, changeset}
      end
    end)
  end

  def change_estimation(%Estimation{} = estimation, attrs \\ %{}) do
    Estimation.changeset(estimation, attrs)
  end

  ## Deep Copy

  def copy_estimation(%Estimation{} = estimation, new_name, project_id, org_id) do
    Repo.ensure_org_context(fn ->
      estimation = get_estimation!(estimation.id, org_id)

      Ecto.Multi.new()
      |> Ecto.Multi.insert(:estimation, fn _ ->
        Estimation.changeset(%Estimation{}, %{
          name: new_name,
          description: estimation.description,
          currency_id: estimation.currency_id,
          project_id: project_id
        })
      end)
      |> Ecto.Multi.run(:roles, fn _repo, %{estimation: new_estimation} ->
        Enum.reduce_while(estimation.roles, {:ok, %{}}, fn old_role, {:ok, acc} ->
          %EstimationRole{}
          |> EstimationRole.changeset(%{
            name: old_role.name,
            abbreviation: old_role.abbreviation,
            hourly_rate: old_role.hourly_rate,
            pm_overhead: old_role.pm_overhead,
            qa_overhead: old_role.qa_overhead,
            risk_buffer: old_role.risk_buffer,
            position: old_role.position,
            estimation_id: new_estimation.id
          })
          |> Repo.insert()
          |> case do
            {:ok, new_role} -> {:cont, {:ok, Map.put(acc, old_role.id, new_role.id)}}
            {:error, changeset} -> {:halt, {:error, changeset}}
          end
        end)
      end)
      |> Ecto.Multi.run(:epics_tasks, fn _repo,
                                         %{estimation: new_estimation, roles: role_mapping} ->
        copy_epics_with_estimates(estimation.epics, new_estimation.id, role_mapping)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{estimation: estimation}} -> {:ok, get_estimation!(estimation.id, org_id)}
        {:error, _op, changeset, _} -> {:error, changeset}
      end
    end)
  end

  ## Roles

  def create_role(attrs) do
    Repo.ensure_org_context(fn ->
      result =
        %EstimationRole{}
        |> EstimationRole.changeset(attrs)
        |> Repo.insert()

      case result do
        {:ok, role} ->
          broadcast(role.estimation_id, {:role_created, role})
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
          broadcast(role.estimation_id, {:role_updated, role})
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
          broadcast(role.estimation_id, {:role_deleted, role})
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
          broadcast(updated_role.estimation_id, {:role_updated, updated_role})
          {:ok, updated_role}

        error ->
          error
      end
    end)
  end

  ## Epics

  def create_epic(attrs) do
    Repo.ensure_org_context(fn ->
      result =
        %Epic{}
        |> Epic.changeset(attrs)
        |> Repo.insert()

      case result do
        {:ok, epic} ->
          broadcast(epic.estimation_id, {:epic_created, epic})
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
          broadcast(epic.estimation_id, {:epic_updated, epic})
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
          broadcast(estimation_id, {:epic_deleted, epic})
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
          broadcast(estimation_id, {:epics_reordered, epic_ids})
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    end)
  end

  ## Tasks

  def create_task(attrs) do
    Repo.ensure_org_context(fn ->
      result =
        %Task{}
        |> Task.changeset(attrs)
        |> Repo.insert()

      case result do
        {:ok, task} ->
          epic = Repo.get!(Epic, task.epic_id)
          broadcast(epic.estimation_id, {:task_created, task})
          reindex_estimation_async(epic.estimation_id)
          {:ok, task}

        error ->
          error
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
          epic = Repo.get!(Epic, task.epic_id)
          broadcast(epic.estimation_id, {:task_updated, task})

          if attrs["name"] || attrs[:name] do
            reindex_estimation_async(epic.estimation_id)
          end

          {:ok, task}

        error ->
          error
      end
    end)
  end

  def delete_task(%Task{} = task) do
    Repo.ensure_org_context(fn ->
      epic = Repo.get!(Epic, task.epic_id)
      result = Repo.delete(task)

      case result do
        {:ok, task} ->
          broadcast(epic.estimation_id, {:task_deleted, task})
          reindex_estimation_async(epic.estimation_id)
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
    Repo.ensure_org_context(fn ->
      epic = Repo.get!(Epic, epic_id)

      case Repo.transaction(fn ->
             task_ids
             |> Enum.with_index()
             |> Enum.each(fn {id, position} ->
               from(t in Task, where: t.id == ^id and t.epic_id == ^epic_id)
               |> Repo.update_all(set: [position: position])
             end)
           end) do
        {:ok, _} ->
          broadcast(epic.estimation_id, {:tasks_reordered, epic_id, task_ids})
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    end)
  end

  ## Task Estimates

  def upsert_task_estimate(task_id, role_id, attrs, estimation_id \\ nil) do
    Repo.ensure_org_context(fn ->
      case Repo.get_by(TaskEstimate, task_id: task_id, estimation_role_id: role_id) do
        nil ->
          create_task_estimate(
            Map.merge(attrs, %{task_id: task_id, estimation_role_id: role_id}),
            estimation_id
          )

        estimate ->
          update_task_estimate(estimate, attrs, estimation_id)
      end
    end)
  end

  defp create_task_estimate(attrs, estimation_id) do
    result =
      %TaskEstimate{}
      |> TaskEstimate.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, estimate} ->
        estimation_id = estimation_id || get_estimation_id_for_task(estimate.task_id)
        broadcast(estimation_id, {:estimate_updated, estimate})
        {:ok, estimate}

      error ->
        error
    end
  end

  defp update_task_estimate(%TaskEstimate{} = estimate, attrs, estimation_id) do
    result =
      estimate
      |> TaskEstimate.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, estimate} ->
        estimation_id = estimation_id || get_estimation_id_for_task(estimate.task_id)
        broadcast(estimation_id, {:estimate_updated, estimate})
        {:ok, estimate}

      error ->
        error
    end
  end

  defp get_estimation_id_for_task(task_id) do
    from(t in Task,
      join: ep in Epic,
      on: ep.id == t.epic_id,
      where: t.id == ^task_id,
      select: ep.estimation_id
    )
    |> Repo.one!()
  end

  ## Private helpers — role & epic insertion

  defp prepare_estimation_attrs(attrs) do
    project_id = attrs["project_id"] || attrs[:project_id]
    is_first = count_estimations_for_project(project_id) == 0
    if is_first, do: Map.put(attrs, "is_current", true), else: attrs
  end

  defp insert_roles_from_role_templates(estimation_id, templates, currency_id) do
    templates
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {template, idx}, {:ok, acc} ->
      rate = Enum.find(template.rates, fn r -> r.currency_id == currency_id end)
      hourly_rate = if rate, do: rate.hourly_rate, else: Decimal.new(0)

      %EstimationRole{}
      |> EstimationRole.changeset(%{
        name: template.name,
        abbreviation: template.abbreviation,
        hourly_rate: hourly_rate,
        pm_overhead: template.pm_overhead,
        qa_overhead: template.qa_overhead,
        risk_buffer: template.risk_buffer,
        position: idx,
        estimation_id: estimation_id
      })
      |> Repo.insert()
      |> case do
        {:ok, role} -> {:cont, {:ok, [role | acc]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  defp insert_roles_from_project_roles(estimation_id, project_roles) do
    project_roles
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {project_role, idx}, {:ok, acc} ->
      %EstimationRole{}
      |> EstimationRole.changeset(%{
        name: project_role.name,
        abbreviation: project_role.abbreviation,
        hourly_rate: project_role.hourly_rate,
        pm_overhead: project_role.pm_overhead,
        qa_overhead: project_role.qa_overhead,
        risk_buffer: project_role.risk_buffer,
        position: idx,
        estimation_id: estimation_id,
        project_role_id: project_role.id
      })
      |> Repo.insert()
      |> case do
        {:ok, role} -> {:cont, {:ok, [role | acc]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
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
          case insert_tasks(new_epic.id, epic_data.tasks, epic_idx) do
            {:ok, _} -> {:cont, {:ok, [new_epic | acc]}}
            {:error, changeset} -> {:halt, {:error, changeset}}
          end

        {:error, changeset} ->
          {:halt, {:error, changeset}}
      end
    end)
  end

  defp insert_tasks(epic_id, tasks, _epic_idx) do
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

  defp copy_epics_with_estimates(epics, estimation_id, role_mapping) do
    Enum.reduce_while(epics, {:ok, []}, fn old_epic, {:ok, acc} ->
      case Repo.insert(
             Epic.changeset(%Epic{}, %{
               name: old_epic.name,
               description: old_epic.description,
               position: old_epic.position,
               estimation_id: estimation_id
             })
           ) do
        {:ok, new_epic} ->
          case copy_tasks_with_estimates(old_epic.tasks, new_epic.id, role_mapping) do
            {:ok, _} -> {:cont, {:ok, [new_epic | acc]}}
            {:error, changeset} -> {:halt, {:error, changeset}}
          end

        {:error, changeset} ->
          {:halt, {:error, changeset}}
      end
    end)
  end

  defp copy_tasks_with_estimates(tasks, epic_id, role_mapping) do
    Enum.reduce_while(tasks, {:ok, []}, fn old_task, {:ok, acc} ->
      case Repo.insert(
             Task.changeset(%Task{}, %{
               name: old_task.name,
               description: old_task.description,
               position: old_task.position,
               epic_id: epic_id
             })
           ) do
        {:ok, new_task} ->
          case copy_estimates(old_task.estimates, new_task.id, role_mapping) do
            :ok -> {:cont, {:ok, [new_task | acc]}}
            {:error, changeset} -> {:halt, {:error, changeset}}
          end

        {:error, changeset} ->
          {:halt, {:error, changeset}}
      end
    end)
  end

  defp copy_estimates(estimates, new_task_id, role_mapping) do
    Enum.reduce_while(estimates, :ok, fn old_estimate, :ok ->
      new_role_id = Map.get(role_mapping, old_estimate.estimation_role_id)

      if new_role_id do
        case Repo.insert(
               TaskEstimate.changeset(%TaskEstimate{}, %{
                 hours: old_estimate.hours,
                 task_id: new_task_id,
                 estimation_role_id: new_role_id
               })
             ) do
          {:ok, _} -> {:cont, :ok}
          {:error, changeset} -> {:halt, {:error, changeset}}
        end
      else
        {:cont, :ok}
      end
    end)
  end

  ## Search reindexing

  defp reindex_estimation_async(estimation_id) do
    task_fn = fn ->
      # System task — bypass RLS to read estimation for reindexing.
      Repo.without_rls(fn ->
        estimation =
          from(e in Estimation,
            where: e.id == ^estimation_id and is_nil(e.deleted_at),
            preload: [project: :customer]
          )
          |> Repo.one()

        if estimation, do: Search.index_estimation(estimation)
      end)
    end

    if Application.get_env(:estimate, :env) == :test do
      task_fn.()
    else
      try do
        Elixir.Task.Supervisor.start_child(Estimate.TaskSupervisor, task_fn)
      catch
        kind, reason ->
          Logger.warning("Search reindex skipped: #{inspect(kind)} #{inspect(reason)}")
      end
    end
  end
end
