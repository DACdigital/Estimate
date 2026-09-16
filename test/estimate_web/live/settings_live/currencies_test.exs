defmodule EstimateWeb.SettingsLive.CurrenciesTest do
  use EstimateWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Estimate.{PortfolioFixtures, EstimationEngineFixtures}
  alias Estimate.Organizations.Currencies
  alias Estimate.Repo

  setup :register_and_log_in_org_owner

  test "update_field refuses non-whitelisted fields", %{conn: conn, org: org} do
    [_main, eur | _] = Currencies.list_currencies(org.id)
    {:ok, lv, _} = live(conn, ~p"/org/#{org.id}/settings/currencies")

    html =
      render_click(lv, "update_field", %{"id" => eur.id, "field" => "is_main", "value" => "true"})

    assert html =~ "Not authorized"
    refute Repo.reload!(eur).is_main

    html =
      render_click(lv, "update_field", %{
        "id" => eur.id,
        "field" => "exchange_rate",
        "value" => "0"
      })

    assert html =~ "Not authorized"
  end

  test "update_field still edits a whitelisted field", %{conn: conn, org: org} do
    [_main, eur | _] = Currencies.list_currencies(org.id)
    {:ok, lv, _} = live(conn, ~p"/org/#{org.id}/settings/currencies")
    render_click(lv, "update_field", %{"id" => eur.id, "field" => "name", "value" => "Euro (EU)"})
    assert Repo.reload!(eur).name == "Euro (EU)"
  end

  test "deleting a currency in use flashes the reason", %{conn: conn, org: org, user: owner} do
    [_main, eur | _] = Currencies.list_currencies(org.id)
    project = project_fixture(nil, owner)
    _ = estimation_fixture(project, %{"currency_id" => eur.id})
    {:ok, lv, _} = live(conn, ~p"/org/#{org.id}/settings/currencies")
    render_click(lv, "confirm_delete", %{"id" => eur.id})
    html = render_click(lv, "delete_currency", %{})
    assert html =~ "is used by estimations"
    assert Repo.get(Estimate.Accounts.Currency, eur.id)
  end
end
