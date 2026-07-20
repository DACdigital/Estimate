defmodule EstimateWeb.MCP.Tools.AddEstimationRole do
  @moduledoc "Add a role (with hourly rate + optional PM/QA/risk overheads) to an estimation. Task efforts reference roles by their abbreviation."

  use Anubis.Server.Component, type: :tool

  alias Estimate.EstimationEngine
  alias EstimateWeb.MCP.{Authz, Serializers, Write}

  schema do
    field :estimation_id, :string, required: true
    field :name, :string, required: true

    field :abbreviation, :string,
      required: true,
      description: "1–5 chars, referenced by task efforts"

    field :hourly_rate, {:either, {:float, :integer}}
    field :pm_overhead, {:either, {:float, :integer}}, description: "0–100 (%)"
    field :qa_overhead, {:either, {:float, :integer}}, description: "0–100 (%)"
    field :risk_buffer, {:either, {:float, :integer}}, description: "0–100 (%)"
  end

  @impl true
  def execute(params, frame) do
    gate = fn claims ->
      with {:ok, pid} <- Authz.project_id_for(:estimation, params.estimation_id, claims.org_id) do
        Authz.require_can_edit_project(pid, claims)
      end
    end

    Write.execute(frame, gate, fn %{org_id: org_id} ->
      with {:ok, role} <- EstimationEngine.create_role(attrs(params)) do
        pid = EstimationEngine.get_estimation_project_id(params.estimation_id, org_id)

        {:ok,
         Serializers.estimation_role(role)
         |> Map.put(:url, Serializers.estimation_url(org_id, pid, params.estimation_id))}
      end
    end)
  end

  defp attrs(params) do
    %{
      "estimation_id" => params.estimation_id,
      "name" => params.name,
      "abbreviation" => params.abbreviation,
      "position" => 0
    }
    |> put_num("hourly_rate", params[:hourly_rate])
    |> put_num("pm_overhead", params[:pm_overhead])
    |> put_num("qa_overhead", params[:qa_overhead])
    |> put_num("risk_buffer", params[:risk_buffer])
  end

  # Omitted numeric fields must be left out of attrs entirely so the
  # `EstimationRole` schema's `default: Decimal.new(0)` applies on insert —
  # casting an explicit nil into a NOT NULL column crashes uncaught.
  defp put_num(map, _key, nil), do: map
  defp put_num(map, key, n), do: Map.put(map, key, num(n))

  # Anubis hands numeric params in as native floats. `to_string/1` on a float
  # always keeps a `.0` (Elixir never prints a bare integer for a float), and
  # `:decimal` casting preserves that scale verbatim through insert + reload
  # (Postgres `numeric` with no declared scale stores exactly what it's
  # given) — so a whole-number rate would otherwise serialize back as
  # "100.0" instead of "100". Drop the fraction when the value is integral.
  defp num(n) when n == trunc(n), do: n |> trunc() |> to_string()
  defp num(n), do: to_string(n)
end
