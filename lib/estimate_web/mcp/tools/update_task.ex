defmodule EstimateWeb.MCP.Tools.UpdateTask do
  @moduledoc "Update a task's name/description/priority (org admin or project owner/editor). Use set_task_effort to change hours."

  use Anubis.Server.Component, type: :tool

  alias Estimate.EstimationEngine
  alias EstimateWeb.MCP.{Authz, Serializers, Write}

  schema do
    field :id, :string, required: true, description: "Task UUID"
    field :name, :string
    field :description, :string
    field :priority, :enum, values: ["must", "should", "could", "wont"]
  end

  @impl true
  def execute(params, frame) do
    gate = fn claims ->
      with {:ok, pid} <- Authz.project_id_for(:task, params.id, claims.org_id) do
        Authz.require_can_edit_project(pid, claims)
      end
    end

    Write.execute(frame, gate, fn %{org_id: org_id} ->
      task = EstimationEngine.get_task!(params.id, org_id)

      attrs =
        params
        |> Map.take([:name, :description, :priority])
        |> Map.new(fn {k, v} -> {to_string(k), v} end)

      with {:ok, updated} <- EstimationEngine.update_task(task, attrs) do
        updated = Estimate.Repo.preload(updated, :estimates)
        epic = EstimationEngine.get_epic!(updated.epic_id, org_id)
        pid = EstimationEngine.get_estimation_project_id(epic.estimation_id, org_id)

        {:ok,
         Serializers.task(updated)
         |> Map.put(:url, Serializers.estimation_url(org_id, pid, epic.estimation_id))}
      end
    end)
  end
end
