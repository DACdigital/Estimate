defmodule Estimate.CRMTest do
  use Estimate.DataCase, async: true

  alias Estimate.CRM

  import Estimate.AccountsFixtures
  import Estimate.CRMFixtures
  import Estimate.PortfolioFixtures

  describe "list_customers/1,2 project_count" do
    setup do
      %{user: user, organization: org} = user_with_organization_fixture()
      %{org: org, user: user}
    end

    test "counts projects per customer, 0 when none", %{org: org, user: user} do
      alpha = customer_fixture(org, %{"name" => "Alpha"})
      beta = customer_fixture(org, %{"name" => "Beta"})
      project_fixture(alpha, user)
      project_fixture(alpha, user)

      assert [%{id: alpha_id, project_count: 2}, %{id: beta_id, project_count: 0}] =
               CRM.list_customers(org.id)

      assert alpha_id == alpha.id
      assert beta_id == beta.id
    end

    test "keeps name ordering and default_currency preload", %{org: org} do
      customer_fixture(org, %{"name" => "Zed"})
      customer_fixture(org, %{"name" => "Ann"})

      assert [%{name: "Ann"} = ann, %{name: "Zed"}] = CRM.list_customers(org.id)
      # preload intact (nil default currency loads as nil, not %Ecto.Association.NotLoaded{})
      refute match?(%Ecto.Association.NotLoaded{}, ann.default_currency)
    end

    test "watchtower filter still applies and keeps counts", %{org: org, user: user} do
      no_desc = customer_fixture(org, %{"name" => "NoDesc"})
      customer_fixture(org, %{"name" => "HasDesc", "description" => "desc"})
      project_fixture(no_desc, user)

      assert [%{name: "NoDesc", project_count: 1}] =
               CRM.list_customers(org.id, watchtower: :missing_description)
    end
  end
end
