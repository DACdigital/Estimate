defmodule EstimateWeb.EstimatorLive.ViewStateTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import EstimateWeb.EstimatorLiveHelpers

  setup :setup_estimator

  test "toggle_breakdown, toggle_all_in_rates, toggle_descriptions flip their flags", ctx do
    for {event, key} <- [
          {"toggle_breakdown", :show_breakdown},
          {"toggle_all_in_rates", :show_all_in_rates},
          {"toggle_descriptions", :show_descriptions}
        ] do
      refute Map.fetch!(assigns(ctx.lv), key)
      render_click(ctx.lv, event, %{})
      assert Map.fetch!(assigns(ctx.lv), key), event
      render_click(ctx.lv, event, %{})
      refute Map.fetch!(assigns(ctx.lv), key), event
    end
  end

  test "toggle_descriptions shows task descriptions in the grid", ctx do
    render_click(ctx.lv, "edit_task", %{"id" => ctx.task1.id})

    render_submit(ctx.lv, "save_task", %{
      "task" => %{"name" => "T-one", "description" => "hidden-until-toggled"}
    })

    refute render(ctx.lv) =~ "hidden-until-toggled"

    render_click(ctx.lv, "toggle_descriptions", %{})
    assert render(ctx.lv) =~ "hidden-until-toggled"
  end

  test "toggle_priority removes and re-adds a priority and pushes save_priorities", ctx do
    render_click(ctx.lv, "toggle_priority", %{"priority" => "wont"})
    assert assigns(ctx.lv).enabled_priorities == MapSet.new(["must", "should", "could"])
    assert_push_event(ctx.lv, "save_priorities", %{priorities: list})
    assert Enum.sort(list) == ["could", "must", "should"]

    render_click(ctx.lv, "toggle_priority", %{"priority" => "wont"})
    assert assigns(ctx.lv).enabled_priorities == MapSet.new(["must", "should", "could", "wont"])
  end

  test "toggle_priority never removes the last enabled priority", ctx do
    for p <- ["should", "could", "wont"],
        do: render_click(ctx.lv, "toggle_priority", %{"priority" => p})

    assert assigns(ctx.lv).enabled_priorities == MapSet.new(["must"])

    render_click(ctx.lv, "toggle_priority", %{"priority" => "must"})
    assert assigns(ctx.lv).enabled_priorities == MapSet.new(["must"])
  end

  test "priority filter hides tasks (and empty epics) from the grid", ctx do
    render_click(ctx.lv, "edit_task", %{"id" => ctx.task2.id})
    render_submit(ctx.lv, "save_task", %{"task" => %{"name" => "T-two", "priority" => "wont"}})
    assert render(ctx.lv) =~ "T-two"

    render_click(ctx.lv, "toggle_priority", %{"priority" => "wont"})
    html = render(ctx.lv)
    assert html =~ "T-one"
    refute html =~ "T-two"

    # hide everything else too -> the epic disappears with its last visible task
    for p <- ["should", "could"], do: render_click(ctx.lv, "toggle_priority", %{"priority" => p})
    render_click(ctx.lv, "toggle_priority", %{"priority" => "wont"})
    render_click(ctx.lv, "toggle_priority", %{"priority" => "must"})
    assert assigns(ctx.lv).enabled_priorities == MapSet.new(["wont"])
    html = render(ctx.lv)
    assert html =~ "T-two"
    refute html =~ "T-one"
  end

  test "restore_priorities applies a valid subset and ignores unknown or empty input", ctx do
    render_click(ctx.lv, "restore_priorities", %{"priorities" => ["must", "bogus"]})
    assert assigns(ctx.lv).enabled_priorities == MapSet.new(["must"])

    render_click(ctx.lv, "restore_priorities", %{"priorities" => ["bogus"]})
    assert assigns(ctx.lv).enabled_priorities == MapSet.new(["must"])

    render_click(ctx.lv, "restore_priorities", %{"priorities" => ["could", "wont"]})
    assert assigns(ctx.lv).enabled_priorities == MapSet.new(["could", "wont"])
  end

  test "close_modal clears modal, forms and current epic", ctx do
    render_click(ctx.lv, "add_task", %{"epic-id" => ctx.epic.id})
    a = assigns(ctx.lv)
    assert a.modal == :task and a.task_form != nil and a.current_epic_id != nil

    render_click(ctx.lv, "close_modal", %{})
    a = assigns(ctx.lv)

    assert a.modal == nil and a.epic_form == nil and a.task_form == nil and
             a.current_epic_id == nil
  end

  test "viewer can use every view-state toggle", ctx do
    {_u, {:ok, vlv, _}} = mount_as("viewer", ctx)
    render_click(vlv, "toggle_breakdown", %{})
    render_click(vlv, "toggle_all_in_rates", %{})
    render_click(vlv, "toggle_descriptions", %{})
    render_click(vlv, "toggle_priority", %{"priority" => "wont"})
    a = assigns(vlv)
    assert a.show_breakdown and a.show_all_in_rates and a.show_descriptions
    assert a.enabled_priorities == MapSet.new(["must", "should", "could"])
    refute render(vlv) =~ "You don&#39;t have edit access"
  end
end
