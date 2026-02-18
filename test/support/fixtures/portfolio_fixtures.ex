defmodule Estimate.PortfolioFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Estimate.Portfolio` context.
  """

  alias Estimate.AccountsFixtures
  alias Estimate.CRMFixtures

  def project_fixture(customer \\ nil, user \\ nil, attrs \\ %{}) do
    result =
      if user do
        membership = Estimate.Repo.get_by(Estimate.Accounts.Membership, user_id: user.id)

        org =
          if membership, do: Estimate.Organizations.get_organization!(membership.organization_id)

        %{user: user, organization: org}
      else
        AccountsFixtures.user_with_organization_fixture()
      end

    customer = customer || CRMFixtures.customer_fixture(result.organization)

    {:ok, project} =
      Estimate.Portfolio.create_project(
        Map.merge(%{"name" => "Test Project #{System.unique_integer()}"}, stringify_keys(attrs)),
        customer.id,
        result.user.id,
        result.organization.id
      )

    # Reload to get organization_id from trigger
    Estimate.Repo.get!(Estimate.Portfolio.Project, project.id)
  end

  defp stringify_keys(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
