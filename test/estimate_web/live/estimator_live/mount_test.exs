defmodule EstimateWeb.EstimatorLive.MountTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ExUnit.CaptureLog
  import EstimateWeb.EstimatorLiveHelpers
  import Estimate.AccountsFixtures

  setup :setup_estimator

  test "owner mounts with can_edit and full default view state", ctx do
    a = assigns(ctx.lv)
    assert a.can_edit
    assert a.estimation.id == ctx.est.id
    assert a.project.id == ctx.project.id
    assert a.page_title == "Estimator - #{ctx.est.name}"
    assert a.active_tab == :projects
    assert a.modal == nil and a.editing == nil and a.editing_rate == nil
    assert a.epic_form == nil and a.task_form == nil and a.current_epic_id == nil
    assert a.deleting_epic == nil and a.deleting_task == nil and a.deleting_role_id == nil
    refute a.show_breakdown or a.show_all_in_rates or a.show_descriptions
    assert a.enabled_priorities == MapSet.new(["must", "should", "could", "wont"])
    assert a.ai_loading == nil
    refute a.ai_configured
  end

  test "editor collaborator can edit; viewer cannot", ctx do
    {_u, {:ok, editor_lv, _}} = mount_as("editor", ctx)
    assert assigns(editor_lv).can_edit

    {_u, {:ok, viewer_lv, _}} = mount_as("viewer", ctx)
    refute assigns(viewer_lv).can_edit
  end

  test "org admin who is not a collaborator can edit", ctx do
    admin = user_fixture()
    _ = membership_fixture(admin, ctx.org, "admin")

    {:ok, lv, _} =
      live(log_in_user(build_conn(), admin), estimator_path(ctx.org, ctx.project, ctx.est))

    assert assigns(lv).can_edit
  end

  test "org member who is not a collaborator is redirected with a flash", ctx do
    {_u, result} = mount_as(nil, ctx)
    assert {:error, {:redirect, %{to: to, flash: flash}}} = result
    assert to == "/org/#{ctx.org.id}/projects"
    assert flash["error"] == "You don't have access to this project."
  end

  test "an estimation from another project under this project's URL raises NoResultsError", ctx do
    %{estimation: other} = other_estimation(ctx.owner, ctx.org)

    # the LV process crashes by design; capture its crash report so test output stays pristine
    capture_log(fn ->
      assert_raise Ecto.NoResultsError, fn ->
        live(ctx.conn, estimator_path(ctx.org, ctx.project, other))
      end
    end)
  end

  test "mount renders the seeded epic and tasks", ctx do
    html = render(ctx.lv)
    assert html =~ "Alpha"
    assert html =~ "T-one"
    assert html =~ "T-two"
  end
end
