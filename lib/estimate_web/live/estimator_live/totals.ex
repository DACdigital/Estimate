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
    # Computed once, shared with the breakdown's per-role rows below instead
    # of calling Calculator.role_hours/2 a second time per role.
    role_hours = Map.new(roles, &{&1.id, Calculator.role_hours(epics, &1.id)})

    %__MODULE__{
      empty?: epics == [],
      total_hours: Calculator.calc_total_hours(epics),
      base_cost: Calculator.calc_base_cost(epics, dr),
      role_hours: role_hours,
      breakdown: breakdown(epics, roles, role_hours)
    }
  end

  defp breakdown(epics, roles, role_hours) do
    # base/pm/qa/risk computed once each; grand_total is their sum rather
    # than a separate Calculator.grand_total_with_overhead/2 call, which
    # would otherwise recompute all four internally. Decimal.add is exact
    # (no rounding), so the sum is byte-identical to that call.
    base_cost = Calculator.total_base_cost(epics, roles)
    pm = Calculator.total_pm_overhead(epics, roles)
    qa = Calculator.total_qa_overhead(epics, roles)
    risk = Calculator.total_risk_buffer(epics, roles)

    %{
      grand_total: base_cost |> Decimal.add(pm) |> Decimal.add(qa) |> Decimal.add(risk),
      base_cost: base_cost,
      total_hours: Calculator.calc_total_hours(epics),
      pm: pm,
      qa: qa,
      risk: risk,
      avg_pm: Calculator.weighted_avg_overhead(epics, roles, &Calculator.role_pm_overhead/2),
      avg_qa: Calculator.weighted_avg_overhead(epics, roles, &Calculator.role_qa_overhead/2),
      avg_risk: Calculator.weighted_avg_overhead(epics, roles, &Calculator.role_risk_buffer/2),
      roles:
        for role <- roles,
            hours = Map.fetch!(role_hours, role.id),
            Decimal.compare(hours, 0) == :gt do
          role_base = Calculator.role_base_cost(epics, role)
          role_pm = Calculator.role_pm_overhead(epics, role)
          role_qa = Calculator.role_qa_overhead(epics, role)
          role_risk = Calculator.role_risk_buffer(epics, role)

          %{
            role: role,
            hours: hours,
            base: role_base,
            pm: role_pm,
            qa: role_qa,
            risk: role_risk,
            total:
              role_base |> Decimal.add(role_pm) |> Decimal.add(role_qa) |> Decimal.add(role_risk)
          }
        end
    }
  end
end
