defmodule EstimateWeb.MCP.Tools.UpdateEstimationRole do
  @moduledoc "Update an estimation role's name/abbreviation/rate/overheads (org admin or project owner/editor)."

  use Anubis.Server.Component, type: :tool

  alias Estimate.EstimationEngine
  alias EstimateWeb.MCP.{Authz, Serializers, Write}

  schema do
    field :id, :string, required: true, description: "Estimation role UUID"
    field :name, :string
    field :abbreviation, :string
    field :hourly_rate, {:either, {:float, :integer}}
    field :pm_overhead, {:either, {:float, :integer}}
    field :qa_overhead, {:either, {:float, :integer}}
    field :risk_buffer, {:either, {:float, :integer}}
  end

  @impl true
  def execute(params, frame) do
    gate = fn claims ->
      with {:ok, pid} <- Authz.project_id_for(:role, params.id, claims.org_id) do
        Authz.require_can_edit_project(pid, claims)
      end
    end

    Write.execute(frame, gate, fn %{org_id: org_id} ->
      role = EstimationEngine.get_role!(params.id, org_id)

      with {:ok, updated} <- EstimationEngine.update_role(role, attrs(params)) do
        pid = EstimationEngine.get_estimation_project_id(updated.estimation_id, org_id)

        {:ok,
         Serializers.estimation_role(updated)
         |> Map.put(:url, Serializers.estimation_url(org_id, pid, updated.estimation_id))}
      end
    end)
  end

  @numeric_fields [:hourly_rate, :pm_overhead, :qa_overhead, :risk_buffer]

  defp attrs(params) do
    params
    |> Map.take([:name, :abbreviation | @numeric_fields])
    # Drop nil numeric fields entirely (never cast as an explicit nil into a
    # NOT NULL column) rather than changing the value — an omitted/nil
    # numeric field means "leave it unchanged" on update.
    |> Enum.reject(fn {k, v} -> is_nil(v) and k in @numeric_fields end)
    |> Map.new(fn
      {k, v} when k in @numeric_fields ->
        {to_string(k), num(v)}

      {k, v} ->
        {to_string(k), v}
    end)
  end

  # See EstimateWeb.MCP.Tools.AddEstimationRole.num/1 — whole-number floats
  # need their `.0` dropped before the `:decimal` cast, or the unconstrained
  # `hourly_rate` column round-trips it verbatim (e.g. "100.0" not "100").
  defp num(n) when n == trunc(n), do: n |> trunc() |> to_string()
  defp num(n), do: to_string(n)
end
