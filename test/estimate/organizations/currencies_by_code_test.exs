defmodule Estimate.Organizations.CurrenciesByCodeTest do
  use Estimate.DataCase, async: false

  import Estimate.AccountsFixtures
  alias Estimate.Organizations.Currencies

  setup do
    %{organization: org} = user_with_organization_fixture()
    %{org: org}
  end

  test "finds a seeded currency by code, case-insensitively", %{org: org} do
    assert %{code: "EUR"} = Currencies.get_currency_by_code(org.id, "EUR")
    assert %{code: "EUR"} = Currencies.get_currency_by_code(org.id, "eur")
  end

  test "returns nil for an unknown code", %{org: org} do
    assert Currencies.get_currency_by_code(org.id, "ZZZ") == nil
  end

  test "does not leak another org's currency", %{org: org} do
    %{organization: other} = user_with_organization_fixture()

    {:ok, _} =
      Currencies.create_currency(other.id, %{
        "code" => "CHF",
        "name" => "Swiss Franc",
        "symbol" => "CHF",
        "exchange_rate" => "0.9",
        "is_main" => false
      })

    assert Currencies.get_currency_by_code(org.id, "CHF") == nil
  end
end
