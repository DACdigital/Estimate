defmodule EstimateWeb.EstimatorLive.EstimatesTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import EstimateWeb.EstimatorLiveHelpers

  alias Estimate.EstimationEngine

  setup :setup_estimator

  defp hours_for(estimation, task_id, role_id) do
    estimation.epics
    |> Enum.flat_map(& &1.tasks)
    |> Enum.find(&(&1.id == task_id))
    |> Map.fetch!(:estimates)
    |> Enum.find(&(&1.estimation_role_id == role_id))
    |> case do
      nil -> nil
      est -> est.hours
    end
  end

  test "edit_estimate sets the editing key and renders the input", ctx do
    key = "#{ctx.task1.id}-#{ctx.role.id}"
    render_click(ctx.lv, "edit_estimate", %{"key" => key})
    assert assigns(ctx.lv).editing == key
    assert render(ctx.lv) =~ ~s(id="hours-#{key}")
  end

  test "cancel_edit clears editing and editing_rate", ctx do
    render_click(ctx.lv, "edit_estimate", %{"key" => "#{ctx.task1.id}-#{ctx.role.id}"})
    render_click(ctx.lv, "edit_rate", %{"role-id" => ctx.role.id})
    assert assigns(ctx.lv).editing != nil and assigns(ctx.lv).editing_rate != nil

    render_click(ctx.lv, "cancel_edit", %{})
    a = assigns(ctx.lv)
    assert a.editing == nil and a.editing_rate == nil
  end

  test "save_estimate upserts hours in the DB and patches the in-memory estimation", ctx do
    render_click(ctx.lv, "edit_estimate", %{"key" => "#{ctx.task1.id}-#{ctx.role.id}"})

    render_click(ctx.lv, "save_estimate", %{
      "task-id" => ctx.task1.id,
      "role-id" => ctx.role.id,
      "value" => "12.5"
    })

    a = assigns(ctx.lv)
    assert a.editing == nil
    assert Decimal.equal?(hours_for(a.estimation, ctx.task1.id, ctx.role.id), Decimal.new("12.5"))

    assert Decimal.equal?(
             hours_for(refetch(ctx.est, ctx.org), ctx.task1.id, ctx.role.id),
             Decimal.new("12.5")
           )

    # second save on the same cell replaces, not appends
    render_click(ctx.lv, "save_estimate", %{
      "task-id" => ctx.task1.id,
      "role-id" => ctx.role.id,
      "value" => "3"
    })

    a = assigns(ctx.lv)
    task = a.estimation.epics |> hd() |> Map.fetch!(:tasks) |> Enum.find(&(&1.id == ctx.task1.id))
    assert Enum.count(task.estimates, &(&1.estimation_role_id == ctx.role.id)) == 1
    assert Decimal.equal?(hours_for(a.estimation, ctx.task1.id, ctx.role.id), Decimal.new(3))
  end

  test "save_estimate for a task or role outside this estimation is ignored", ctx do
    %{estimation: other, task: other_task} = other_estimation(ctx.owner, ctx.org)
    other_role = hd(other.roles)

    render_click(ctx.lv, "save_estimate", %{
      "task-id" => other_task.id,
      "role-id" => ctx.role.id,
      "value" => "9"
    })

    render_click(ctx.lv, "save_estimate", %{
      "task-id" => ctx.task1.id,
      "role-id" => other_role.id,
      "value" => "9"
    })

    assert assigns(ctx.lv).editing == nil
    assert hours_for(refetch(other, ctx.org), other_task.id, ctx.role.id) == nil
    assert hours_for(refetch(ctx.est, ctx.org), ctx.task1.id, other_role.id) == nil
  end

  test "edit_rate sets editing_rate and renders the rate input", ctx do
    render_click(ctx.lv, "edit_rate", %{"role-id" => ctx.role.id})
    assert assigns(ctx.lv).editing_rate == ctx.role.id
    assert render(ctx.lv) =~ ~s(id="rate-#{ctx.role.id}")
  end

  test "save_rate updates the role in the DB and in memory", ctx do
    render_click(ctx.lv, "edit_rate", %{"role-id" => ctx.role.id})
    render_click(ctx.lv, "save_rate", %{"role-id" => ctx.role.id, "value" => "150"})

    a = assigns(ctx.lv)
    assert a.editing_rate == nil
    in_memory = Enum.find(a.estimation.roles, &(&1.id == ctx.role.id))
    assert Decimal.equal?(in_memory.hourly_rate, Decimal.new(150))

    assert Decimal.equal?(
             EstimationEngine.get_role!(ctx.role.id, ctx.org.id).hourly_rate,
             Decimal.new(150)
           )
  end

  test "save_rate for a role outside this estimation is ignored", ctx do
    %{estimation: other} = other_estimation(ctx.owner, ctx.org)
    other_role = hd(other.roles)
    before = EstimationEngine.get_role!(other_role.id, ctx.org.id).hourly_rate

    render_click(ctx.lv, "save_rate", %{"role-id" => other_role.id, "value" => "999"})
    assert assigns(ctx.lv).editing_rate == nil

    assert Decimal.equal?(
             EstimationEngine.get_role!(other_role.id, ctx.org.id).hourly_rate,
             before
           )
  end

  describe "viewer" do
    setup ctx do
      {_u, {:ok, lv, _}} = mount_as("viewer", ctx)
      %{vlv: lv}
    end

    test "save_estimate and save_rate are denied; edit_estimate still only toggles state", ctx do
      html =
        render_click(ctx.vlv, "save_estimate", %{
          "task-id" => ctx.task1.id,
          "role-id" => ctx.role.id,
          "value" => "5"
        })

      assert html =~ "You don&#39;t have edit access"
      assert hours_for(refetch(ctx.est, ctx.org), ctx.task1.id, ctx.role.id) == nil

      html = render_click(ctx.vlv, "save_rate", %{"role-id" => ctx.role.id, "value" => "5"})
      assert html =~ "You don&#39;t have edit access"

      # Clear the denial flash left by the two calls above so the refute below
      # actually pins "edit_estimate/edit_rate don't (re)trigger it", instead of
      # trivially passing/failing on stale flash state from this test's setup.
      render_click(ctx.vlv, "lv:clear-flash", %{})

      key = "#{ctx.task1.id}-#{ctx.role.id}"
      render_click(ctx.vlv, "edit_estimate", %{"key" => key})
      assert assigns(ctx.vlv).editing == key
      render_click(ctx.vlv, "edit_rate", %{"role-id" => ctx.role.id})
      assert assigns(ctx.vlv).editing_rate == ctx.role.id
      refute render(ctx.vlv) =~ "You don&#39;t have edit access"
    end
  end
end
