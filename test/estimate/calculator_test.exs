defmodule Estimate.EstimationEngine.CalculatorTest do
  use ExUnit.Case, async: true

  alias Estimate.EstimationEngine.Calculator

  defp make_role(id, rate, opts \\ []) do
    %{
      id: id,
      hourly_rate: Decimal.new(rate),
      pm_overhead: Decimal.new(Keyword.get(opts, :pm, 0)),
      qa_overhead: Decimal.new(Keyword.get(opts, :qa, 0)),
      risk_buffer: Decimal.new(Keyword.get(opts, :risk, 0))
    }
  end

  defp make_estimate(role_id, hours) do
    %{
      id: "est-#{role_id}-#{hours}",
      estimation_role_id: role_id,
      hours: Decimal.new(hours)
    }
  end

  defp make_task(id, estimates) do
    %{id: id, estimates: estimates}
  end

  defp make_epic(id, tasks) do
    %{id: id, tasks: tasks}
  end

  describe "task_total_hours/1" do
    test "sums all estimate hours" do
      task = make_task("t1", [make_estimate("r1", 3), make_estimate("r2", 5)])
      assert Decimal.equal?(Calculator.task_total_hours(task), Decimal.new(8))
    end

    test "returns 0 for empty estimates" do
      task = make_task("t1", [])
      assert Decimal.equal?(Calculator.task_total_hours(task), Decimal.new(0))
    end
  end

  describe "task_total_cost/2" do
    test "multiplies hours by role rate" do
      roles = [make_role("r1", 100), make_role("r2", 200)]
      task = make_task("t1", [make_estimate("r1", 3), make_estimate("r2", 2)])

      # 3*100 + 2*200 = 700
      assert Decimal.equal?(Calculator.task_total_cost(task, roles), Decimal.new(700))
    end

    test "ignores estimates with unknown role" do
      roles = [make_role("r1", 100)]
      task = make_task("t1", [make_estimate("r1", 3), make_estimate("unknown", 5)])

      assert Decimal.equal?(Calculator.task_total_cost(task, roles), Decimal.new(300))
    end
  end

  describe "epic_hours/1" do
    test "sums hours across all tasks" do
      epic =
        make_epic("e1", [
          make_task("t1", [make_estimate("r1", 3)]),
          make_task("t2", [make_estimate("r1", 5), make_estimate("r2", 2)])
        ])

      assert Decimal.equal?(Calculator.epic_hours(epic), Decimal.new(10))
    end
  end

  describe "epic_role_hours/2" do
    test "sums hours for a specific role" do
      epic =
        make_epic("e1", [
          make_task("t1", [make_estimate("r1", 3), make_estimate("r2", 1)]),
          make_task("t2", [make_estimate("r1", 5)])
        ])

      assert Decimal.equal?(Calculator.epic_role_hours(epic, "r1"), Decimal.new(8))
      assert Decimal.equal?(Calculator.epic_role_hours(epic, "r2"), Decimal.new(1))
    end
  end

  describe "calc_total_hours/1" do
    test "sums hours across all epics" do
      epics = [
        make_epic("e1", [make_task("t1", [make_estimate("r1", 3)])]),
        make_epic("e2", [make_task("t2", [make_estimate("r1", 7)])])
      ]

      assert Decimal.equal?(Calculator.calc_total_hours(epics), Decimal.new(10))
    end
  end

  describe "calc_base_cost/2" do
    test "computes total cost across epics" do
      roles = [make_role("r1", 100), make_role("r2", 50)]

      epics = [
        make_epic("e1", [make_task("t1", [make_estimate("r1", 2), make_estimate("r2", 4)])]),
        make_epic("e2", [make_task("t2", [make_estimate("r1", 3)])])
      ]

      # 2*100 + 4*50 + 3*100 = 200 + 200 + 300 = 700
      assert Decimal.equal?(Calculator.calc_base_cost(epics, roles), Decimal.new(700))
    end
  end

  describe "all_in_rate/1" do
    test "includes overhead in rate" do
      role = make_role("r1", 100, pm: 10, qa: 5, risk: 15)
      # 100 * (1 + 0.1 + 0.05 + 0.15) = 100 * 1.30 = 130
      assert Decimal.equal?(Calculator.all_in_rate(role), Decimal.new(130))
    end

    test "returns base rate when no overhead" do
      role = make_role("r1", 100)
      assert Decimal.equal?(Calculator.all_in_rate(role), Decimal.new(100))
    end
  end

  describe "has_overhead?/1" do
    test "true when any role has overhead" do
      roles = [make_role("r1", 100, pm: 10), make_role("r2", 50)]
      assert Calculator.has_overhead?(roles)
    end

    test "false when no overhead" do
      roles = [make_role("r1", 100), make_role("r2", 50)]
      refute Calculator.has_overhead?(roles)
    end
  end

  describe "grand_total_with_overhead/2" do
    test "adds all overhead components" do
      roles = [make_role("r1", 100, pm: 10, qa: 5, risk: 5)]

      epics = [
        make_epic("e1", [make_task("t1", [make_estimate("r1", 10)])])
      ]

      # base: 10*100 = 1000
      # pm: 1000*0.10 = 100
      # qa: 1000*0.05 = 50
      # risk: 1000*0.05 = 50
      # total: 1200
      assert Decimal.equal?(
               Calculator.grand_total_with_overhead(epics, roles),
               Decimal.new(1200)
             )
    end
  end

  describe "roles_with_all_in_rates/1" do
    test "replaces hourly_rate with all-in rate" do
      roles = [make_role("r1", 100, pm: 20)]
      [updated] = Calculator.roles_with_all_in_rates(roles)
      assert Decimal.equal?(updated.hourly_rate, Decimal.new(120))
    end
  end
end
