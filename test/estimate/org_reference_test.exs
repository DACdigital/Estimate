defmodule Estimate.OrgReferenceTest do
  use Estimate.DataCase, async: true

  import Estimate.{AccountsFixtures, PortfolioFixtures, CRMFixtures, EstimationEngineFixtures}
  alias Estimate.{Portfolio, CRM, EstimationEngine}
  alias Estimate.Organizations.Currencies

  setup do
    %{user: owner_a, organization: org_a} = user_with_organization_fixture()
    %{organization: org_b} = user_with_organization_fixture()
    customer_b = customer_fixture(org_b)
    [currency_b | _] = Currencies.list_currencies(org_b.id)
    project_a = project_fixture(nil, owner_a)
    %{org_a: org_a, org_b: org_b, owner_a: owner_a, customer_b: customer_b, currency_b: currency_b, project_a: project_a}
  end

  test "update_project rejects a customer from another org", ctx do
    {:error, cs} = Portfolio.update_project(ctx.project_a, %{"customer_id" => ctx.customer_b.id})
    assert %{customer_id: ["does not belong to this organization"]} = errors_on(cs)
  end

  test "update_project rejects a currency from another org", ctx do
    {:error, cs} = Portfolio.update_project(ctx.project_a, %{"currency_id" => ctx.currency_b.id})
    assert %{currency_id: ["does not belong to this organization"]} = errors_on(cs)
  end

  test "create_project rejects a foreign currency", ctx do
    customer_a = customer_fixture(ctx.org_a)

    {:error, cs} =
      Portfolio.create_project(
        %{"name" => "P", "currency_id" => ctx.currency_b.id},
        customer_a.id,
        ctx.owner_a.id,
        ctx.org_a.id
      )

    assert %{currency_id: ["does not belong to this organization"]} = errors_on(cs)
  end

  test "create/update_customer reject a foreign default currency", ctx do
    {:error, cs} =
      CRM.create_customer(ctx.org_a.id, %{
        "key" => "AB",
        "name" => "A",
        "default_currency_id" => ctx.currency_b.id
      })

    assert %{default_currency_id: ["does not belong to this organization"]} = errors_on(cs)

    customer_a = customer_fixture(ctx.org_a)
    {:error, cs} = CRM.update_customer(customer_a, %{"default_currency_id" => ctx.currency_b.id})
    assert %{default_currency_id: ["does not belong to this organization"]} = errors_on(cs)
  end

  test "update_estimation rejects a foreign currency", ctx do
    est = estimation_fixture(ctx.project_a)
    {:error, cs} = EstimationEngine.update_estimation(est, %{"currency_id" => ctx.currency_b.id})
    assert %{currency_id: ["does not belong to this organization"]} = errors_on(cs)
  end

  test "same-org references are accepted", ctx do
    [currency_a | _] = Currencies.list_currencies(ctx.org_a.id)
    {:ok, p} = Portfolio.update_project(ctx.project_a, %{"currency_id" => currency_a.id})
    assert p.currency_id == currency_a.id
  end
end
