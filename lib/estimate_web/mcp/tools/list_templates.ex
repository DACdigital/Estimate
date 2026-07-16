defmodule EstimateWeb.MCP.Tools.ListTemplates do
  @moduledoc "List the organization's estimation templates."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias EstimateWeb.MCP.{Scope, Serializers}

  schema do
    field :limit, :integer, min: 1, max: 200, default: 50
  end

  @impl true
  def execute(params, frame) do
    templates =
      Scope.with_scope(frame, fn %{org_id: org_id} ->
        Estimate.Templates.list_estimation_templates(org_id)
      end)
      |> Enum.take(params.limit)
      |> Enum.map(&Serializers.template_summary/1)

    {:reply, Response.json(Response.tool(), %{templates: templates}), frame}
  end
end
