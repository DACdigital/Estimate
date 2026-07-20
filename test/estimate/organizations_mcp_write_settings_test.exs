defmodule Estimate.OrganizationsMcpWriteSettingsTest do
  use Estimate.DataCase, async: false

  import Estimate.AccountsFixtures
  alias Estimate.Organizations

  setup do
    %{organization: org} = user_with_organization_fixture()
    %{org: org}
  end

  test "defaults to false", %{org: org} do
    refute org.mcp_write_enabled
    refute Organizations.mcp_write_enabled?(org.id)
  end

  test "update_mcp_write_settings flips it and mcp_write_enabled? reflects it", %{org: org} do
    assert {:ok, org} = Organizations.update_mcp_write_settings(org, %{mcp_write_enabled: true})
    assert org.mcp_write_enabled
    assert Organizations.mcp_write_enabled?(org.id)
  end

  test "mcp_write_enabled? is false for unknown org" do
    refute Organizations.mcp_write_enabled?(Ecto.UUID.generate())
  end
end
