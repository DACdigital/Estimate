defmodule EstimateWeb.EstimatorLive.TotalsTest do
  use Estimate.DataCase, async: true

  import Estimate.{AccountsFixtures, PortfolioFixtures, EstimationEngineFixtures}

  alias Estimate.EstimationEngine
  alias Estimate.EstimationEngine.Calculator
  alias EstimateWeb.EstimatorLive.Totals
  import EstimateWeb.EstimatorLive.Helpers, only: [display_roles: 2]

  setup do
    %{user: owner, organization: org} = user_with_organization_fixture()
    project = project_fixture(nil, owner)
    est = estimation_fixture(project)
    e1 = epic_fixture(est, %{name: "E1", position: 0})
    t1 = task_fixture(e1, %{name: "T1", position: 0})
    t2 = task_fixture(e1, %{name: "T2", position: 1})
    est = EstimationEngine.get_estimation!(est.id, org.id)
    [r1, r2 | _] = est.roles

    {:ok, _} =
      EstimationEngine.update_role(r1, %{
        hourly_rate: Decimal.new(100),
        pm_overhead: Decimal.new(10),
        qa_overhead: Decimal.new(5),
        risk_buffer: Decimal.new(0)
      })

    {:ok, _} =
      EstimationEngine.update_role(r2, %{
        hourly_rate: Decimal.new(50),
        pm_overhead: Decimal.new(0),
        qa_overhead: Decimal.new(0),
        risk_buffer: Decimal.new(20)
      })

    {:ok, _} =
      EstimationEngine.upsert_task_estimate(t1.id, r1.id, %{hours: Decimal.new(4)}, est.id)

    {:ok, _} =
      EstimationEngine.upsert_task_estimate(t2.id, r2.id, %{hours: Decimal.new(2)}, est.id)

    est = EstimationEngine.get_estimation!(est.id, org.id)
    %{est: est, epics: est.epics, roles: est.roles, r1: r1, r2: r2}
  end

  defp eq(a, b), do: assert(Decimal.equal?(a, b), "expected #{a} == #{b}")

  test "footer numbers equal the Calculator calls the table makes", %{epics: epics, roles: roles} do
    for all_in <- [false, true] do
      t = Totals.compute(epics, roles, all_in)
      dr = display_roles(roles, all_in)
      refute t.empty?
      eq(t.total_hours, Calculator.calc_total_hours(epics))
      eq(t.base_cost, Calculator.calc_base_cost(epics, dr))
      for role <- roles, do: eq(t.role_hours[role.id], Calculator.role_hours(epics, role.id))
    end
  end

  test "breakdown numbers equal the Calculator calls cost_breakdown makes", %{
    epics: epics,
    roles: roles,
    r1: r1,
    r2: r2
  } do
    b = Totals.compute(epics, roles, false).breakdown
    eq(b.grand_total, Calculator.grand_total_with_overhead(epics, roles))
    eq(b.base_cost, Calculator.total_base_cost(epics, roles))
    eq(b.total_hours, Calculator.calc_total_hours(epics))
    eq(b.pm, Calculator.total_pm_overhead(epics, roles))
    eq(b.qa, Calculator.total_qa_overhead(epics, roles))
    eq(b.risk, Calculator.total_risk_buffer(epics, roles))
    eq(b.avg_pm, Calculator.weighted_avg_overhead(epics, roles, &Calculator.role_pm_overhead/2))
    eq(b.avg_qa, Calculator.weighted_avg_overhead(epics, roles, &Calculator.role_qa_overhead/2))
    eq(b.avg_risk, Calculator.weighted_avg_overhead(epics, roles, &Calculator.role_risk_buffer/2))

    assert Enum.map(b.roles, & &1.role.id) == [r1.id, r2.id]

    for row <- b.roles do
      role = row.role
      eq(row.hours, Calculator.role_hours(epics, role.id))
      eq(row.base, Calculator.role_base_cost(epics, role))
      eq(row.pm, Calculator.role_pm_overhead(epics, role))
      eq(row.qa, Calculator.role_qa_overhead(epics, role))
      eq(row.risk, Calculator.role_risk_buffer(epics, role))

      eq(
        row.total,
        row.base |> Decimal.add(row.pm) |> Decimal.add(row.qa) |> Decimal.add(row.risk)
      )
    end
  end

  test "roles with zero hours are excluded from the breakdown rows; empty epics give empty? totals",
       %{epics: epics, roles: roles} do
    b = Totals.compute(epics, roles, false).breakdown
    assert length(b.roles) == 2

    t = Totals.compute([], roles, false)
    assert t.empty?
    eq(t.total_hours, Decimal.new(0))
    assert t.breakdown.roles == []
  end
end
