defmodule EstimateWeb.MCP.Tools.GetTemplate do
  @moduledoc "Fetch one estimation template with its epics and tasks."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias EstimateWeb.MCP.{Scope, Serializers}

  schema do
    field :id, :string, required: true, description: "Template UUID"
  end

  @impl true
  def execute(%{id: id}, frame) do
    case Scope.fetch(frame, fn %{org_id: org_id} ->
           Estimate.Templates.get_estimation_template!(id, org_id)
         end) do
      {:ok, template} ->
        {:reply, Response.json(Response.tool(), Serializers.template_tree(template)), frame}

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "template not found"), frame}
    end
  end
end
