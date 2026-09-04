defmodule Estimate.OrganizationsCurrenciesTest do
  use Estimate.DataCase, async: true

  import Estimate.{AccountsFixtures, PortfolioFixtures, EstimationEngineFixtures}

  alias Estimate.Organizations.Currencies
  alias Estimate.Repo

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

  describe "delete_currency/1" do
    test "deleting a currency used by an estimation returns a changeset error, not a crash" do
      %{user: owner, organization: org} = user_with_organization_fixture()
      [_main, eur | _] = Estimate.Organizations.Currencies.list_currencies(org.id)
      project = project_fixture(nil, owner)
      _est = estimation_fixture(project, %{"currency_id" => eur.id})

      assert {:error, %Ecto.Changeset{} = cs} = Estimate.Organizations.Currencies.delete_currency(eur)
      assert %{id: ["is used by estimations"]} = errors_on(cs)
      assert Repo.get(Estimate.Accounts.Currency, eur.id)
    end
  end
end
