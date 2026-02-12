defmodule Estimate.CRMFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Estimate.CRM` context.
  """

  alias Estimate.AccountsFixtures

  def customer_fixture(organization \\ nil, attrs \\ %{}) do
    organization = organization || AccountsFixtures.organization_fixture()
    unique = System.unique_integer([:positive])

    {:ok, customer} =
      Estimate.CRM.create_customer(
        organization.id,
        Map.merge(
          %{
            "key" => "CUST#{unique}",
            "name" => "Test Customer #{unique}"
          },
          stringify_keys(attrs)
        )
      )

    customer
  end

  defp stringify_keys(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
