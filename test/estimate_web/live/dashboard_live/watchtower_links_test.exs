defmodule EstimateWeb.DashboardLive.WatchtowerLinksTest do
  use EstimateWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Estimate.PortfolioFixtures
  import Estimate.EstimationEngineFixtures

  alias Estimate.EstimationEngine

  setup :register_and_log_in_org_owner

  # Regression guard: these deep links were accidentally widened to /settings
  # once (b219aa2). They must keep pointing at their subpages, and they live in
  # the dashboard content, NOT the sidebar (#app-sidebar) or rail.
  #
  # Both watchtower_card/1 clauses matter here: count == 0 renders a plain
  # (linkless) "all clear" div, so the deep link only shows up once the count
  # is nonzero. The whole Watchtower section is also `:if={@is_admin}`.
  #   - Members Without 2FA: the freshly-registered owner has no
  #     totp_enabled_at, so they count as one member without 2FA -- no extra
  #     fixture needed, this card always has a nonzero count for a fresh org.
  #   - Deleted Estimations: a fresh org has none, so we create + soft-delete
  #     one to push the count above zero and get the card past its zero-state.
  test "watchtower cards deep-link to settings subpages", %{conn: conn, org: org, user: user} do
    project = project_fixture(nil, user)
    estimation = estimation_fixture(project)
    {:ok, _} = EstimationEngine.soft_delete_estimation(estimation)

    {:ok, view, _html} = live(conn, ~p"/org/#{org.id}")

    assert has_element?(view, ~s(main a[href="/org/#{org.id}/settings/members"]))
    assert has_element?(view, ~s(main a[href="/org/#{org.id}/settings/trash"]))
  end
end
