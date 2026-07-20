defmodule Estimate.EstimationEngine do
  require Logger

  @moduledoc """
  The EstimationEngine context for managing estimations, roles, epics, tasks, and estimates.
  Supports real-time collaboration via PubSub.

  Implementation split across sub-modules; this module re-exports the public API.
  """

  import Ecto.Query
  alias Estimate.Repo

  alias Estimate.EstimationEngine.{
    Estimation,
    Estimations,
    Roles,
    Epics,
    Tasks,
    Estimates,
    Import,
    Copy
  }

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
  defdelegate count_estimations_for_org(org_id), to: Estimations
  defdelegate list_recent_estimations_for_org(org_id, limit \\ 5), to: Estimations
  defdelegate list_newest_estimations_for_org(org_id, limit \\ 5), to: Estimations
  defdelegate list_estimations(project_id, org_id), to: Estimations
  defdelegate get_estimation!(id, org_id), to: Estimations
  defdelegate get_estimation_project_id(id, org_id), to: Estimations
  defdelegate create_estimation(attrs), to: Estimations
  defdelegate create_estimation_with_roles(attrs, role_ids), to: Estimations
  defdelegate update_estimation(estimation, attrs), to: Estimations
  defdelegate soft_delete_estimation(estimation), to: Estimations
  defdelegate restore_estimation(estimation), to: Estimations
  defdelegate hard_delete_estimation(estimation), to: Estimations
  defdelegate list_deleted_estimations(project_id), to: Estimations
  defdelegate list_deleted_estimations_for_org(org_id, limit \\ 10), to: Estimations
  defdelegate count_deleted_estimations_for_org(org_id), to: Estimations
  defdelegate set_current_estimation(estimation), to: Estimations
  defdelegate change_estimation(estimation, attrs \\ %{}), to: Estimations

  ## Roles
  defdelegate create_role(attrs), to: Roles
  defdelegate update_role(role, attrs), to: Roles
  defdelegate delete_role(role), to: Roles
  defdelegate get_role!(id, org_id), to: Roles
  defdelegate reorder_roles(estimation_id, role_ids), to: Roles
  defdelegate insert_roles_from_attrs(estimation_id, role_attrs_list), to: Roles

  ## Epics
  defdelegate create_epic(attrs), to: Epics
  defdelegate update_epic(epic, attrs), to: Epics
  defdelegate delete_epic(epic), to: Epics
  defdelegate get_epic!(id, org_id), to: Epics
  defdelegate reorder_epics(estimation_id, epic_ids), to: Epics

  ## Tasks
  defdelegate create_task(attrs), to: Tasks
  defdelegate update_task(task, attrs), to: Tasks
  defdelegate delete_task(task), to: Tasks
  defdelegate get_task!(id, org_id), to: Tasks
  defdelegate reorder_tasks(epic_id, task_ids), to: Tasks

  ## Task Estimates
  defdelegate upsert_task_estimate(task_id, role_id, attrs, estimation_id \\ nil), to: Estimates

  ## Import
  defdelegate create_estimation_from_templates(attrs, role_attrs), to: Import

  defdelegate create_estimation_from_estimation_template(attrs, template_id, role_attrs),
    to: Import

  defdelegate create_estimation_from_json(attrs, parsed_json, role_attrs), to: Import

  ## Copy
  defdelegate copy_estimation(estimation, new_name, project_id, org_id), to: Copy

  ## Search reindexing (called by sub-modules)

  @doc false
  def reindex_estimation_async(estimation_id) do
    task_fn = fn ->
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
