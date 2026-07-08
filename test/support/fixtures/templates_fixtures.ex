defmodule Estimate.TemplatesFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Estimate.Templates` context.
  """

  alias Estimate.AccountsFixtures

  def template_fixture(organization \\ nil, attrs \\ %{}) do
    organization = organization || AccountsFixtures.organization_fixture()
    unique = System.unique_integer([:positive])

    {:ok, template} =
      Estimate.Templates.create_estimation_template(
        organization.id,
        Map.merge(%{"name" => "Test Template #{unique}"}, stringify_keys(attrs))
      )

    template
  end

  defp stringify_keys(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
