defmodule EstimateWeb.MCP.Tools.ListCurrencies do
  @moduledoc "List the organization's currencies with exchange rates (main currency first)."

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias EstimateWeb.MCP.{Scope, Serializers}

  schema do
  end

  @impl true
  def execute(_params, frame) do
    currencies =
      Scope.with_scope(frame, fn %{org_id: org_id} ->
        Estimate.Organizations.Currencies.list_currencies(org_id)
      end)
      |> Enum.map(&Serializers.currency/1)

    {:reply, Response.json(Response.tool(), %{currencies: currencies}), frame}
  end
end
