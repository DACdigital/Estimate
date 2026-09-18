defmodule EstimateWeb.TemplatesLive.ShowReorderTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Estimate.TemplatesFixtures
  alias Estimate.Templates

  setup :register_and_log_in_org_owner

  test "a stale reorder flashes and reloads instead of silently reordering a subset", %{
    conn: conn,
    org: org
  } do
    template = template_fixture(org)

    {:ok, e1} =
      Templates.create_template_epic(%{
        "name" => "E1",
        "position" => 0,
        "estimation_template_id" => template.id
      })

    {:ok, e2} =
      Templates.create_template_epic(%{
        "name" => "E2",
        "position" => 1,
        "estimation_template_id" => template.id
      })

    {:ok, lv, _} = live(conn, ~p"/org/#{org.id}/templates/#{template.id}")

    html = render_click(lv, "reorder_epics", %{"ids" => [e2.id]})
    assert html =~ "Order changed elsewhere; reloaded"

    ids = Templates.get_estimation_template!(template.id, org.id).epics |> Enum.map(& &1.id)
    assert ids == [e1.id, e2.id]
  end
end
