defmodule EstimateWeb.EstimatorLive.Totals do
  @moduledoc """
  Every number the estimator footer and cost-breakdown panel show, computed
  once per change (never at render). `base_cost`/`role_hours`/`total_hours`
  feed the table footer and use display roles (all-in when toggled); the
  `breakdown` map feeds `cost_breakdown/1` and uses raw roles, exactly as the
  pre-streams templates did.
  """
  alias Estimate.EstimationEngine.Calculator
  import EstimateWeb.EstimatorLive.Helpers, only: [display_roles: 2]

  defstruct empty?: true,
            total_hours: Decimal.new(0),
            base_cost: Decimal.new(0),
            role_hours: %{},
            breakdown: %{}

  @spec compute([map()], [map()], boolean()) :: %__MODULE__{}
  def compute(epics, roles, show_all_in_rates) do
    dr = display_roles(roles, show_all_in_rates)

    %__MODULE__{
      empty?: epics == [],
      total_hours: Calculator.calc_total_hours(epics),
      base_cost: Calculator.calc_base_cost(epics, dr),
      role_hours: Map.new(roles, &{&1.id, Calculator.role_hours(epics, &1.id)}),
      breakdown: breakdown(epics, roles)
    }
  end

  defp breakdown(epics, roles) do
    %{
      grand_total: Calculator.grand_total_with_overhead(epics, roles),
      base_cost: Calculator.total_base_cost(epics, roles),
      total_hours: Calculator.calc_total_hours(epics),
      pm: Calculator.total_pm_overhead(epics, roles),
      qa: Calculator.total_qa_overhead(epics, roles),
      risk: Calculator.total_risk_buffer(epics, roles),
      avg_pm: Calculator.weighted_avg_overhead(epics, roles, &Calculator.role_pm_overhead/2),
      avg_qa: Calculator.weighted_avg_overhead(epics, roles, &Calculator.role_qa_overhead/2),
      avg_risk: Calculator.weighted_avg_overhead(epics, roles, &Calculator.role_risk_buffer/2),
      roles:
        for role <- roles,
            hours = Calculator.role_hours(epics, role.id),
            Decimal.compare(hours, 0) == :gt do
          base = Calculator.role_base_cost(epics, role)
          pm = Calculator.role_pm_overhead(epics, role)
          qa = Calculator.role_qa_overhead(epics, role)
          risk = Calculator.role_risk_buffer(epics, role)

          %{
            role: role,
            hours: hours,
            base: base,
            pm: pm,
            qa: qa,
            risk: risk,
            total: base |> Decimal.add(pm) |> Decimal.add(qa) |> Decimal.add(risk)
          }
        end
    }
  end
end
