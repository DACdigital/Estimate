defmodule EstimateWeb.RolesLive.IndexReorderTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  alias Estimate.Accounts

  setup :register_and_log_in_org_owner

  test "a stale reorder flashes and reloads instead of silently reordering a subset", %{
    conn: conn,
    org: org
  } do
    ids = Accounts.list_role_templates(org.id) |> Enum.map(& &1.id)
    assert length(ids) >= 4

    {:ok, lv, _} = live(conn, ~p"/org/#{org.id}/roles")

    html = render_click(lv, "reorder_roles", %{"ids" => [hd(ids)]})
    assert html =~ "Order changed elsewhere; reloaded"

    assert Accounts.list_role_templates(org.id) |> Enum.map(& &1.id) == ids
  end

  test "a full reorder persists the new order", %{conn: conn, org: org} do
    ids = Accounts.list_role_templates(org.id) |> Enum.map(& &1.id)
    assert length(ids) >= 4

    [a, b | rest] = ids
    new_order = [b, a | rest]

    {:ok, lv, _} = live(conn, ~p"/org/#{org.id}/roles")

    html = render_click(lv, "reorder_roles", %{"ids" => new_order})
    refute html =~ "Order changed elsewhere; reloaded"
    refute html =~ "Could not reorder"

    assert Accounts.list_role_templates(org.id) |> Enum.map(& &1.id) == new_order
  end
end
