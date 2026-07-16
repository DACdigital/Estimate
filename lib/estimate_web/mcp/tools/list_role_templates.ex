defmodule EstimateWeb.MCP.Tools.ListRoleTemplates do
  @moduledoc "List the organization's role templates with per-currency hourly rates."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias EstimateWeb.MCP.{Scope, Serializers}

  schema do
  end

  @impl true
  def execute(_params, frame) do
    role_templates =
      Scope.with_scope(frame, fn %{org_id: org_id} ->
        Estimate.Accounts.list_role_templates(org_id)
      end)
      |> Enum.map(&Serializers.role_template/1)

    {:reply, Response.json(Response.tool(), %{role_templates: role_templates}), frame}
  end
end
