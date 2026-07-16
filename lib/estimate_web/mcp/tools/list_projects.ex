defmodule EstimateWeb.MCP.Tools.ListProjects do
  @moduledoc "List projects visible to the caller (admins: all; members: only projects they collaborate on)."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias EstimateWeb.MCP.{Scope, Serializers}

  schema do
    field :status, :enum, values: ["active", "archived", "completed"]
    field :customer_id, :string, description: "Filter by customer UUID"
    field :limit, :integer, min: 1, max: 200, default: 50
  end

  @impl true
  def execute(params, frame) do
    opts = if params[:status], do: [status: params.status], else: []

    projects =
      Scope.with_scope(frame, fn %{org_id: org_id, user_id: user_id, role: role} ->
        Estimate.Portfolio.list_projects(org_id, user_id, role, opts)
      end)
      |> filter_customer(params[:customer_id])
      |> Enum.take(params.limit)
      |> Enum.map(&Serializers.project/1)

    {:reply, Response.json(Response.tool(), %{projects: projects}), frame}
  end

  defp filter_customer(projects, nil), do: projects

  defp filter_customer(projects, customer_id) do
    Enum.filter(projects, &(&1.customer_id == customer_id))
  end
end
