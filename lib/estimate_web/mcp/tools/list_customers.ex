defmodule EstimateWeb.MCP.Tools.ListCustomers do
  @moduledoc "List the organization's customers: name, key, currency, project count. Optional case-insensitive name filter."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias EstimateWeb.MCP.{Scope, Serializers}

  schema do
    field :search, :string, description: "Case-insensitive substring filter on customer name"
    field :limit, :integer, min: 1, max: 200, default: 50
  end

  @impl true
  def execute(params, frame) do
    customers =
      Scope.with_scope(frame, fn %{org_id: org_id} ->
        Estimate.CRM.list_customers(org_id)
      end)
      |> filter_search(params[:search])
      |> Enum.take(params.limit)
      |> Enum.map(&Serializers.customer/1)

    {:reply, Response.json(Response.tool(), %{customers: customers}), frame}
  end

  defp filter_search(customers, nil), do: customers

  defp filter_search(customers, search) do
    down = String.downcase(search)
    Enum.filter(customers, &String.contains?(String.downcase(&1.name), down))
  end
end
