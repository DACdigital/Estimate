defmodule EstimateWeb.MCP.Tools.GetCustomer do
  @moduledoc "Fetch one customer by id."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias EstimateWeb.MCP.{Scope, Serializers}

  schema do
    field :id, :string, required: true, description: "Customer UUID"
  end

  @impl true
  def execute(%{id: id}, frame) do
    case Scope.fetch(frame, fn %{org_id: org_id} -> Estimate.CRM.get_customer!(id, org_id) end) do
      {:ok, customer} ->
        {:reply, Response.json(Response.tool(), Serializers.customer(customer)), frame}

      {:error, :not_found} ->
        {:reply, Response.error(Response.tool(), "customer not found"), frame}
    end
  end
end
