defmodule EstimateWeb.MCP.Tools.UpdateEstimation do
  @moduledoc "Update an estimation's name/description/currency (org admin or project owner/editor)."

  use Anubis.Server.Component, type: :tool

  alias Estimate.EstimationEngine
  alias EstimateWeb.MCP.{Authz, Serializers, Write}

  schema do
    field :id, :string, required: true, description: "Estimation UUID"
    field :name, :string
    field :description, :string
    field :currency, :string, description: "Currency code"
  end

  @impl true
  def execute(params, frame) do
    gate = fn claims ->
      with {:ok, pid} <- Authz.project_id_for(:estimation, params.id, claims.org_id) do
        Authz.require_can_edit_project(pid, claims)
      end
    end

    Write.execute(frame, gate, fn %{org_id: org_id} ->
      est = EstimationEngine.get_estimation!(params.id, org_id)

      with {:ok, attrs} <- change_attrs(params, org_id),
           {:ok, _updated} <- EstimationEngine.update_estimation(est, attrs) do
        est = EstimationEngine.get_estimation!(params.id, org_id)

        {:ok,
         Serializers.estimation_tree(est)
         |> Map.put(:url, Serializers.estimation_url(org_id, est.project_id, est.id))}
      end
    end)
  end

  defp change_attrs(params, org_id) do
    with {:ok, currency} <- currency_change(params, org_id) do
      base =
        params |> Map.take([:name, :description]) |> Map.new(fn {k, v} -> {to_string(k), v} end)

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
