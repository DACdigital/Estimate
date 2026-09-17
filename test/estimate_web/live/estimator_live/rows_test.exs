defmodule EstimateWeb.EstimatorLive.RowsTest do
  use Estimate.DataCase, async: true

  import Estimate.{AccountsFixtures, PortfolioFixtures, EstimationEngineFixtures}

  alias Estimate.EstimationEngine
  alias EstimateWeb.EstimatorLive.Rows

  @all MapSet.new(["must", "should", "could", "wont"])

  setup do
    %{user: owner, organization: org} = user_with_organization_fixture()
    project = project_fixture(nil, owner)
    est = estimation_fixture(project)
    e1 = epic_fixture(est, %{name: "E1", position: 0})
    e2 = epic_fixture(est, %{name: "E2", position: 1})
    t1 = task_fixture(e1, %{name: "T1", position: 0, priority: "must"})
    t2 = task_fixture(e1, %{name: "T2", position: 1, priority: "wont"})
    t3 = task_fixture(e2, %{name: "T3", position: 0, priority: "must"})
    est = EstimationEngine.get_estimation!(est.id, org.id)
    role = hd(est.roles)

    {:ok, _} =
      EstimationEngine.upsert_task_estimate(t1.id, role.id, %{hours: Decimal.new(4)}, est.id)

    est = EstimationEngine.get_estimation!(est.id, org.id)
    %{est: est, e1: e1, e2: e2, t1: t1, t2: t2, t3: t3, role: role}
  end

  defp view(priorities \\ @all, all_in \\ false),
    do: %{enabled_priorities: priorities, show_all_in_rates: all_in}

  test "build/2 emits header, tasks, and a subtotal only for epics with more than one visible task",
       ctx do
    ids = ctx.est |> Rows.build(view()) |> Enum.map(& &1.id)

    assert ids == [
             "epic-#{ctx.e1.id}",
             "task-#{ctx.t1.id}",
             "task-#{ctx.t2.id}",
             "epic-#{ctx.e1.id}-subtotal",
             "epic-#{ctx.e2.id}",
             "task-#{ctx.t3.id}"
           ]
  end

  test "build/2 respects the priority filter and drops emptied epics", ctx do
    ids = ctx.est |> Rows.build(view(MapSet.new(["wont"]))) |> Enum.map(& &1.id)
    assert ids == ["epic-#{ctx.e1.id}", "task-#{ctx.t2.id}"]
  end

  test "task rows carry precomputed totals; all-in rates change the cost", ctx do
    [_, %Rows.Task{} = t1_row | _] = Rows.build(ctx.est, view())
    assert t1_row.epic_id == ctx.e1.id
    assert Decimal.equal?(t1_row.total_hours, Decimal.new(4))
    assert Decimal.equal?(t1_row.total_cost, Decimal.mult(Decimal.new(4), ctx.role.hourly_rate))

    [_, %Rows.Task{} = all_in_row | _] = Rows.build(ctx.est, view(@all, true))

    expected =
      Decimal.mult(Decimal.new(4), Estimate.EstimationEngine.Calculator.all_in_rate(ctx.role))

    assert Decimal.equal?(all_in_row.total_cost, expected)
  end

  test "subtotal rows carry per-role hours and epic totals", ctx do
    subtotal = ctx.est |> Rows.build(view()) |> Enum.find(&match?(%Rows.EpicSubtotal{}, &1))
    assert subtotal.epic_id == ctx.e1.id
    assert Decimal.equal?(subtotal.role_hours[ctx.role.id], Decimal.new(4))
    assert Decimal.equal?(subtotal.epic_hours, Decimal.new(4))
  end

  test "for_task/3 returns the task row and its subtotal when present, nothing when filtered out",
       ctx do
    rows = Rows.for_task(ctx.est, view(), ctx.t1.id)
    assert Enum.map(rows, & &1.id) == ["task-#{ctx.t1.id}", "epic-#{ctx.e1.id}-subtotal"]

    assert Enum.map(Rows.for_task(ctx.est, view(), ctx.t3.id), & &1.id) == ["task-#{ctx.t3.id}"]
    assert Rows.for_task(ctx.est, view(MapSet.new(["must"])), ctx.t2.id) == []
  end

  test "for_epic_header/2 returns the header row or nothing for an unknown epic", ctx do
    assert [%Rows.EpicHeader{id: id, epic: %{name: "E2"}}] =
             Rows.for_epic_header(ctx.est, ctx.e2.id)

    assert id == "epic-#{ctx.e2.id}"
    assert Rows.for_epic_header(ctx.est, Ecto.UUID.generate()) == []
  end
end
