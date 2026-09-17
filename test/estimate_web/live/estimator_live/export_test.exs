defmodule EstimateWeb.EstimatorLive.ExportTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import EstimateWeb.EstimatorLiveHelpers

  alias Estimate.Templates

  setup :setup_estimator

  test "copy_json pushes the JSON export and flashes Copied!", ctx do
    html = render_click(ctx.lv, "copy_json", %{})
    assert html =~ "Copied!"
    assert_push_event(ctx.lv, "copy_to_clipboard", %{text: json})
    decoded = Jason.decode!(json)
    assert decoded["project"] == ctx.project.name
    assert decoded["estimation"] == ctx.est.name
    [epic] = decoded["epics"]
    assert epic["name"] == "Alpha"
    assert Enum.map(epic["tasks"], & &1["name"]) == ["T-one", "T-two"]
  end

  test "copy_json respects the priority filter", ctx do
    render_click(ctx.lv, "edit_task", %{"id" => ctx.task2.id})
    render_submit(ctx.lv, "save_task", %{"task" => %{"name" => "T-two", "priority" => "wont"}})
    render_click(ctx.lv, "toggle_priority", %{"priority" => "wont"})

    render_click(ctx.lv, "copy_json", %{})
    assert_push_event(ctx.lv, "copy_to_clipboard", %{text: json})
    [epic] = Jason.decode!(json)["epics"]
    assert Enum.map(epic["tasks"], & &1["name"]) == ["T-one"]
  end

  test "open_save_as_template opens the template modal", ctx do
    render_click(ctx.lv, "open_save_as_template", %{})
    assert assigns(ctx.lv).modal == :save_template
    assert render(ctx.lv) =~ ~s(id="template-form")
  end

  test "save_as_template creates a template from the estimation and closes the modal", ctx do
    render_click(ctx.lv, "open_save_as_template", %{})
    html = render_submit(ctx.lv, "save_as_template", %{"template_name" => "From Alpha"})

    assert html =~ "Template saved"
    assert assigns(ctx.lv).modal == nil
    assert [%{name: "From Alpha"}] = Templates.list_estimation_templates(ctx.org.id)
  end

  test "save_as_template with an empty name is a no-op", ctx do
    render_click(ctx.lv, "open_save_as_template", %{})
    render_submit(ctx.lv, "save_as_template", %{"template_name" => ""})
    assert assigns(ctx.lv).modal == :save_template
    assert Templates.list_estimation_templates(ctx.org.id) == []
  end

  test "viewer can copy JSON but cannot save a template", ctx do
    {_u, {:ok, vlv, _}} = mount_as("viewer", ctx)

    assert render_click(vlv, "copy_json", %{}) =~ "Copied!"

    html = render_click(vlv, "open_save_as_template", %{})
    assert html =~ "You don&#39;t have edit access"
    assert assigns(vlv).modal == nil

    render_submit(vlv, "save_as_template", %{"template_name" => "Nope"})
    assert Templates.list_estimation_templates(ctx.org.id) == []
  end
end
