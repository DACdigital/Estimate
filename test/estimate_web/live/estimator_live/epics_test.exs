defmodule EstimateWeb.EstimatorLive.EpicsTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import EstimateWeb.EstimatorLiveHelpers

  alias Estimate.Repo
  alias Estimate.EstimationEngine.Epic

  setup :setup_estimator

  test "add_epic opens the epic modal with an empty form", ctx do
    render_click(ctx.lv, "add_epic", %{})
    a = assigns(ctx.lv)
    assert a.modal == :epic
    assert a.epic_form.data.id == nil
    assert render(ctx.lv) =~ ~s(id="epic-form")
  end

  test "edit_epic opens the modal with the epic loaded", ctx do
    render_click(ctx.lv, "edit_epic", %{"id" => ctx.epic.id})
    a = assigns(ctx.lv)
    assert a.modal == :epic
    assert a.epic_form.data.id == ctx.epic.id
  end

  test "save_epic creates a new epic, reloads and closes the modal", ctx do
    render_click(ctx.lv, "add_epic", %{})
    render_submit(ctx.lv, "save_epic", %{"epic" => %{"name" => "Beta"}})
    a = assigns(ctx.lv)
    assert a.modal == nil and a.epic_form == nil
    # NOTE: characterizes current behaviour; see report. save_epic never assigns a
    # position on create (Epic.changeset/2 defaults :position to 0), so a newly
    # created epic ties with the seeded one at position 0 and get_estimation!'s
    # `order_by: ep.position` has no deterministic tiebreaker between them -
    # asserting a set, not an exact order, to avoid flakiness.
    assert Enum.sort(Enum.map(a.estimation.epics, & &1.name)) == ["Alpha", "Beta"]
    assert Repo.get_by(Epic, estimation_id: ctx.est.id, name: "Beta")
  end

  test "save_epic updates an existing epic", ctx do
    render_click(ctx.lv, "edit_epic", %{"id" => ctx.epic.id})
    render_submit(ctx.lv, "save_epic", %{"epic" => %{"name" => "Alpha-2"}})
    assert Repo.get!(Epic, ctx.epic.id).name == "Alpha-2"
    assert assigns(ctx.lv).modal == nil
  end

  test "save_epic with an invalid name keeps the modal open with errors", ctx do
    render_click(ctx.lv, "add_epic", %{})
    render_submit(ctx.lv, "save_epic", %{"epic" => %{"name" => ""}})
    a = assigns(ctx.lv)
    assert a.modal == :epic
    assert a.epic_form.errors[:name]
    refute Repo.get_by(Epic, estimation_id: ctx.est.id, name: "")
  end

  test "confirm_delete_epic / cancel_delete_epic toggle deleting_epic", ctx do
    render_click(ctx.lv, "confirm_delete_epic", %{"id" => ctx.epic.id})
    assert assigns(ctx.lv).deleting_epic.id == ctx.epic.id
    assert render(ctx.lv) =~ ~s(id="delete-epic-modal")

    render_click(ctx.lv, "cancel_delete_epic", %{})
    assert assigns(ctx.lv).deleting_epic == nil
  end

  test "delete_epic deletes the confirmed epic and reloads", ctx do
    render_click(ctx.lv, "confirm_delete_epic", %{"id" => ctx.epic.id})
    render_click(ctx.lv, "delete_epic", %{})
    a = assigns(ctx.lv)
    assert a.deleting_epic == nil
    assert a.estimation.epics == []
    refute Repo.get(Epic, ctx.epic.id)
  end

  test "delete_epic with nothing confirmed is a no-op", ctx do
    render_click(ctx.lv, "delete_epic", %{})
    assert Repo.get(Epic, ctx.epic.id)
  end

  test "reorder_epics persists the new order and reloads", ctx do
    render_click(ctx.lv, "add_epic", %{})
    render_submit(ctx.lv, "save_epic", %{"epic" => %{"name" => "Beta"}})
    epics = assigns(ctx.lv).estimation.epics
    # NOTE: characterizes current behaviour; see report. Beta is created with the
    # same default position (0) as Alpha (Epic.changeset/2), so the two are not
    # reliably returned in creation order - find by name instead of destructuring.
    alpha = Enum.find(epics, &(&1.name == "Alpha"))
    beta = Enum.find(epics, &(&1.name == "Beta"))

    render_click(ctx.lv, "reorder_epics", %{"ids" => [beta.id, alpha.id]})
    assert Enum.map(assigns(ctx.lv).estimation.epics, & &1.name) == ["Beta", "Alpha"]
    assert Enum.map(refetch(ctx.est, ctx.org).epics, & &1.name) == ["Beta", "Alpha"]
  end

  describe "viewer" do
    setup ctx do
      {_u, {:ok, lv, _}} = mount_as("viewer", ctx)
      %{vlv: lv}
    end

    test "add_epic, edit_epic, save_epic, delete_epic, reorder_epics are denied", ctx do
      for {event, params} <- [
            {"add_epic", %{}},
            {"edit_epic", %{"id" => ctx.epic.id}},
            {"save_epic", %{"epic" => %{"name" => "X"}}},
            {"confirm_delete_epic", %{"id" => ctx.epic.id}},
            {"delete_epic", %{}},
            {"reorder_epics", %{"ids" => [ctx.epic.id]}}
          ] do
        html = render_click(ctx.vlv, event, params)
        assert html =~ "You don&#39;t have edit access", event
      end

      a = assigns(ctx.vlv)
      assert a.modal == nil and a.epic_form == nil and a.deleting_epic == nil
      assert Repo.get(Epic, ctx.epic.id)
    end
  end
end
