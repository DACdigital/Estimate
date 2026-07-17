defmodule Estimate.OrganizationsCurrenciesTest do
  use Estimate.DataCase, async: true

  import Estimate.AccountsFixtures

  alias Estimate.Organizations.Currencies

  describe "create_currency/2" do
    # Regression: the LiveView "Add Currency" form sends string-keyed params
    # (all Phoenix form params are). Merging the org id as an atom key made
    # cast/4 raise Ecto.CastError on the mixed-key map for every submit.
    test "accepts string-keyed attrs as sent by the add-currency form" do
      %{organization: org} = user_with_organization_fixture()

      assert {:ok, currency} =
               Currencies.create_currency(org.id, %{
                 "code" => "CHF",
                 "name" => "Swiss Franc",
                 "symbol" => "CHF",
                 "exchange_rate" => "0.9"
               })

      assert currency.code == "CHF"
      assert currency.organization_id == org.id
      refute currency.is_main
    end

    test "invalid attrs return an error changeset, not a raise" do
      %{organization: org} = user_with_organization_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Currencies.create_currency(org.id, %{"code" => "", "name" => "", "symbol" => ""})
    end
  end
end
