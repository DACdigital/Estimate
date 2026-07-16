defmodule EstimateWeb.MCP.Tools.GetEstimation do
  @moduledoc "Fetch one estimation with the full epic → task → per-role hours tree plus calculated totals."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias EstimateWeb.MCP.{Scope, Serializers}

  schema do
    field :id, :string, required: true, description: "Estimation UUID"
  end

  @impl true
  def execute(%{id: id}, frame) do
    case Scope.fetch(frame, fn %{org_id: org_id} ->
           Estimate.EstimationEngine.get_estimation!(id, org_id)
         end) do
      {:ok, estimation} ->
        {:reply, Response.json(Response.tool(), Serializers.estimation_tree(estimation)), frame}

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "estimation not found"), frame}
    end
  end
end
