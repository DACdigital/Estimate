defmodule EstimateWeb.MCP.Tools.Search do
  @moduledoc "Full-text search across customers, projects and estimations the caller can see."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias EstimateWeb.MCP.{Scope, Serializers}

  schema do
    field :query, :string, required: true, min_length: 2, max_length: 200
    field :limit, :integer, min: 1, max: 50, default: 8

    field :types, {:list, :string},
      description: ~s(Optional filter: any of "customer", "project", "estimation")
  end

  @impl true
  def execute(params, frame) do
    opts =
      [limit: params.limit] ++
        case params[:types] do
          nil -> []
          types -> [types: types]
        end

    results =
      Scope.with_scope(frame, fn %{org_id: org_id} ->
        Estimate.Search.search(org_id, params.query, opts)
      end)

    {:reply,
     Response.json(Response.tool(), %{results: Enum.map(results, &Serializers.search_hit/1)}),
     frame}
  end
end
