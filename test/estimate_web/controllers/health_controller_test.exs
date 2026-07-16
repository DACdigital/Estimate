defmodule EstimateWeb.HealthControllerTest do
  use EstimateWeb.ConnCase, async: true

  test "liveness reports status and revision", %{conn: conn} do
    conn = get(conn, ~p"/healthz")

    assert %{"status" => "ok", "revision" => revision} = json_response(conn, 200)
    assert is_binary(revision)
    assert revision != ""
  end
end
