defmodule EstimateWeb.MCP.Tools.CreateCustomer do
  @moduledoc "Create a customer in the caller's organization (org admins only). Requires a unique key and a name."

  use Anubis.Server.Component, type: :tool

  alias Estimate.CRM
  alias EstimateWeb.MCP.{Authz, Serializers, Write}

  schema do
    field :key, :string,
      required: true,
      description: "Short unique key, 2–20 chars (e.g. ACME). Uppercased."

    field :name, :string, required: true
    field :country, :string, description: "2-letter ISO code, e.g. US, DE"
    field :website_url, :string, description: "http(s):// URL"
    field :description, :string
    field :currency, :string, description: "Default currency code, e.g. EUR"
  end

  @impl true
  def execute(params, frame) do
    Write.execute(frame, &Authz.require_org_admin/1, fn %{org_id: org_id} ->
      with {:ok, currency_id} <- Write.resolve_currency(params[:currency], org_id),
           {:ok, customer} <- CRM.create_customer(org_id, attrs(params, currency_id)) do
        customer = CRM.get_customer!(customer.id, org_id)

        {:ok,
         Serializers.customer(customer)
         |> Map.put(:url, Serializers.customer_url(org_id, customer.id))}
      end
    end)
  end

  defp attrs(params, currency_id) do
    %{
      "key" => params.key,
      "name" => params.name,
      "country" => params[:country],
      "website_url" => params[:website_url],
      "description" => params[:description],
      "default_currency_id" => currency_id
    }
  end
end
