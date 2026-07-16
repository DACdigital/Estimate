defmodule EstimateWeb.MCP.Tools.ListEstimations do
  @moduledoc "List a project's estimations (non-deleted). RLS hides projects the caller cannot see."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias EstimateWeb.MCP.{Scope, Serializers}

  schema do
    field :project_id, :string, required: true, description: "Project UUID"
  end

  @impl true
  def execute(%{project_id: project_id}, frame) do
    case Scope.fetch(frame, fn _claims ->
           Estimate.EstimationEngine.list_estimations(project_id)
         end) do
      {:ok, estimations} ->
        {:reply,
         Response.json(Response.tool(), %{
           estimations: Enum.map(estimations, &Serializers.estimation_summary/1)
         }), frame}

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "project not found"), frame}
    end
  end
end
