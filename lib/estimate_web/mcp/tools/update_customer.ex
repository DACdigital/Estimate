defmodule EstimateWeb.MCP.Tools.UpdateCustomer do
  @moduledoc "Update a customer (org admins only). Only the fields you pass are changed."

  use Anubis.Server.Component, type: :tool

  alias Estimate.CRM
  alias EstimateWeb.MCP.{Authz, Serializers, Write}

  schema do
    field :id, :string, required: true, description: "Customer UUID"
    field :key, :string
    field :name, :string
    field :country, :string
    field :website_url, :string
    field :description, :string
    field :currency, :string, description: "Default currency code, e.g. EUR"
  end

  @impl true
  def execute(params, frame) do
    Write.execute(frame, &Authz.require_org_admin/1, fn %{org_id: org_id} ->
      customer = CRM.get_customer!(params.id, org_id)

      with {:ok, attrs} <- change_attrs(params, org_id),
           {:ok, updated} <- CRM.update_customer(customer, attrs) do
        updated = CRM.get_customer!(updated.id, org_id)

        {:ok,
         Serializers.customer(updated)
         |> Map.put(:url, Serializers.customer_url(org_id, updated.id))}
      end
    end)
  end

  defp change_attrs(params, org_id) do
    with {:ok, currency_id} <- currency_change(params, org_id) do
      base =
        params
        |> Map.take([:key, :name, :country, :website_url, :description])
        |> Map.new(fn {k, v} -> {to_string(k), v} end)

      {:ok, Map.merge(base, currency_id)}
    end
  end

  defp currency_change(params, org_id) do
    case Map.fetch(params, :currency) do
      :error ->
        {:ok, %{}}

      {:ok, code} ->
        with {:ok, id} <- Write.resolve_currency(code, org_id),
             do: {:ok, %{"default_currency_id" => id}}
    end
  end
end
