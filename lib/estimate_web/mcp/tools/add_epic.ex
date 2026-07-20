defmodule EstimateWeb.MCP.Tools.AddEpic do
  @moduledoc "Add an epic (workstream) to an estimation (org admin or project owner/editor)."

  use Anubis.Server.Component, type: :tool

  alias Estimate.EstimationEngine
  alias EstimateWeb.MCP.{Authz, Serializers, Write}

  schema do
    field :estimation_id, :string, required: true
    field :name, :string, required: true
    field :description, :string
    field :position, :integer, min: 0, description: "Sort order; defaults to 0"
  end

  @impl true
  def execute(params, frame) do
    gate = fn claims ->
      with {:ok, pid} <- Authz.project_id_for(:estimation, params.estimation_id, claims.org_id) do
        Authz.require_can_edit_project(pid, claims)
      end
    end

    Write.execute(frame, gate, fn %{org_id: org_id} ->
      attrs = %{
        "estimation_id" => params.estimation_id,
        "name" => params.name,
        "description" => params[:description],
        "position" => params[:position] || 0
      }

      with {:ok, epic} <- EstimationEngine.create_epic(attrs) do
        pid = EstimationEngine.get_estimation_project_id(params.estimation_id, org_id)

        {:ok,
         %{
           id: epic.id,
           name: epic.name,
           description: epic.description,
           position: epic.position,
           url: Serializers.estimation_url(org_id, pid, params.estimation_id)
         }}
      end
    end)
  end
end
