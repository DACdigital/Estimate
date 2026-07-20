defmodule EstimateWeb.MCP.Tools.UpdateEpic do
  @moduledoc "Update an epic's name/description (org admin or project owner/editor)."

  use Anubis.Server.Component, type: :tool

  alias Estimate.EstimationEngine
  alias EstimateWeb.MCP.{Authz, Serializers, Write}

  schema do
    field :id, :string, required: true, description: "Epic UUID"
    field :name, :string
    field :description, :string
  end

  @impl true
  def execute(params, frame) do
    gate = fn claims ->
      with {:ok, pid} <- Authz.project_id_for(:epic, params.id, claims.org_id) do
        Authz.require_can_edit_project(pid, claims)
      end
    end

    Write.execute(frame, gate, fn %{org_id: org_id} ->
      epic = EstimationEngine.get_epic!(params.id, org_id)

      attrs =
        params |> Map.take([:name, :description]) |> Map.new(fn {k, v} -> {to_string(k), v} end)

      with {:ok, updated} <- EstimationEngine.update_epic(epic, attrs) do
        pid = EstimationEngine.get_estimation_project_id(updated.estimation_id, org_id)

        {:ok,
         %{
           id: updated.id,
           name: updated.name,
           description: updated.description,
           position: updated.position,
           url: Serializers.estimation_url(org_id, pid, updated.estimation_id)
         }}
      end
    end)
  end
end
