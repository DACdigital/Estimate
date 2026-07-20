defmodule EstimateWeb.MCP.Tools.UpdateProject do
  @moduledoc "Update a project (org admin or project owner/editor). Only the fields you pass are changed."

  use Anubis.Server.Component, type: :tool

  alias Estimate.Portfolio
  alias EstimateWeb.MCP.{Authz, Serializers, Write}

  schema do
    field :id, :string, required: true, description: "Project UUID"
    field :name, :string
    field :key, :string
    field :short_description, :string
    field :detailed_description, :string
    field :repository_url, :string
    field :status, :enum, values: ["active", "archived", "completed"]
    field :currency, :string, description: "Currency code"
  end

  @impl true
  def execute(params, frame) do
    gate = fn claims ->
      with {:ok, pid} <- Authz.ensure_project(params.id, claims.org_id) do
        Authz.require_can_edit_project(pid, claims)
      end
    end

    Write.execute(frame, gate, fn %{org_id: org_id} ->
      project = Portfolio.get_project!(params.id, org_id)

      with {:ok, attrs} <- change_attrs(params, org_id),
           {:ok, updated} <- Portfolio.update_project(project, attrs) do
        {:ok,
         Serializers.project(updated)
         |> Map.put(:url, Serializers.project_url(org_id, updated.id))}
      end
    end)
  end

  defp change_attrs(params, org_id) do
    with {:ok, currency} <- currency_change(params, org_id) do
      base =
        params
        |> Map.take([
          :name,
          :key,
          :short_description,
          :detailed_description,
          :repository_url,
          :status
        ])
        |> Map.new(fn {k, v} -> {to_string(k), v} end)

      {:ok, Map.merge(base, currency)}
    end
  end

  defp currency_change(params, org_id) do
    case Map.fetch(params, :currency) do
      :error ->
        {:ok, %{}}

      {:ok, code} ->
        with {:ok, id} <- Write.resolve_currency(code, org_id), do: {:ok, %{"currency_id" => id}}
    end
  end
end
