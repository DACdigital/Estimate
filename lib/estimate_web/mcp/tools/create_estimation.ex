defmodule EstimateWeb.MCP.Tools.CreateEstimation do
  @moduledoc """
  Create an estimation on a project (org admin or project owner/editor).
  Pass `roles` to define the team explicitly, or omit it to seed the
  organization's role templates (like the app's "new estimation" modal).
  Currency defaults to the project's currency.
  """

  use Anubis.Server.Component, type: :tool

  alias Estimate.{Accounts, EstimationEngine, Portfolio}
  alias EstimateWeb.MCP.{Authz, Serializers, Write}

  schema do
    field :project_id, :string, required: true, description: "Owning project UUID"
    field :name, :string, required: true
    field :description, :string
    field :currency, :string, description: "Currency code; omit to inherit the project currency"

    embeds_many :roles, description: "Team roles; omit to seed org role templates" do
      field :name, :string, required: true

      field :abbreviation, :string,
        required: true,
        description: "1–5 chars; referenced by task efforts"

      field :hourly_rate, {:either, {:float, :integer}}
      field :pm_overhead, {:either, {:float, :integer}}, description: "0–100 (%)"
      field :qa_overhead, {:either, {:float, :integer}}, description: "0–100 (%)"
      field :risk_buffer, {:either, {:float, :integer}}, description: "0–100 (%)"
    end
  end

  @impl true
  def execute(params, frame) do
    gate = fn claims ->
      with {:ok, pid} <- Authz.ensure_project(params.project_id, claims.org_id) do
        Authz.require_can_edit_project(pid, claims)
      end
    end

    Write.execute(frame, gate, fn %{org_id: org_id} ->
      with {:ok, currency_id} <- currency_id(params, org_id),
           attrs = base_attrs(params, currency_id),
           role_attrs = role_attrs(params, org_id, currency_id),
           {:ok, est} <- EstimationEngine.create_estimation_from_templates(attrs, role_attrs) do
        est = EstimationEngine.get_estimation!(est.id, org_id)

        {:ok,
         Serializers.estimation_tree(est)
         |> Map.put(:url, Serializers.estimation_url(org_id, est.project_id, est.id))}
      end
    end)
  end

  defp base_attrs(params, currency_id) do
    %{
      "name" => params.name,
      "description" => params[:description],
      "project_id" => params.project_id,
      "currency_id" => currency_id
    }
  end

  defp currency_id(params, org_id) do
    case Write.resolve_currency(params[:currency], org_id) do
      {:ok, nil} -> {:ok, Portfolio.get_project!(params.project_id, org_id).currency_id}
      other -> other
    end
  end

  defp role_attrs(%{roles: [_ | _] = roles}, _org_id, _currency_id) do
    Enum.map(roles, fn r ->
      %{
        name: r.name,
        abbreviation: r.abbreviation,
        hourly_rate: to_decimal(r[:hourly_rate]),
        pm_overhead: to_decimal(r[:pm_overhead]),
        qa_overhead: to_decimal(r[:qa_overhead]),
        risk_buffer: to_decimal(r[:risk_buffer])
      }
    end)
  end

  defp role_attrs(_params, org_id, currency_id) do
    org_id
    |> Accounts.list_role_templates()
    |> Enum.map(fn t ->
      rate = Enum.find(t.rates, &(&1.currency_id == currency_id))

      %{
        name: t.name,
        abbreviation: t.abbreviation,
        hourly_rate: (rate && rate.hourly_rate) || Decimal.new(0),
        pm_overhead: t.pm_overhead,
        qa_overhead: t.qa_overhead,
        risk_buffer: t.risk_buffer
      }
    end)
  end

  defp to_decimal(nil), do: nil
  defp to_decimal(%Decimal{} = d), do: d
  defp to_decimal(n) when is_integer(n) or is_float(n), do: Decimal.new(to_string(n))
  defp to_decimal(s) when is_binary(s), do: Decimal.new(s)
end
