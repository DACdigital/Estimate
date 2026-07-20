defmodule EstimateWeb.MCP.Tools.CreateProject do
  @moduledoc "Create a project under a customer. Any org member may create one and becomes its owner. Currency defaults to the customer's default."

  use Anubis.Server.Component, type: :tool

  alias Estimate.Portfolio
  alias EstimateWeb.MCP.{Serializers, Write}

  schema do
    field :customer_id, :string, required: true, description: "Owning customer UUID"
    field :name, :string, required: true
    field :key, :string, description: "2–10 uppercase letters/numbers, unique per customer"
    field :short_description, :string
    field :detailed_description, :string
    field :repository_url, :string, description: "http(s):// URL"
    field :status, :enum, values: ["active", "archived", "completed"], default: "active"
    field :currency, :string, description: "Currency code; omit to inherit the customer default"
  end

  @impl true
  def execute(params, frame) do
    Write.execute(frame, fn _claims -> :ok end, fn %{org_id: org_id, user_id: user_id} ->
      with {:ok, currency_id} <- Write.resolve_currency(params[:currency], org_id),
           {:ok, project} <-
             Portfolio.create_project(
               attrs(params, currency_id),
               params.customer_id,
               user_id,
               org_id
             ) do
        {:ok,
         Serializers.project(project)
         |> Map.put(:url, Serializers.project_url(org_id, project.id))}
      end
    end)
  end

  defp attrs(params, currency_id) do
    %{
      "name" => params.name,
      "key" => params[:key],
      "short_description" => params[:short_description],
      "detailed_description" => params[:detailed_description],
      "repository_url" => params[:repository_url],
      "status" => params[:status] || "active",
      "currency_id" => currency_id
    }
  end
end
