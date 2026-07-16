defmodule Estimate.OrganizationsMcpSettingsTest do
  use Estimate.DataCase, async: true

  import Estimate.AccountsFixtures

  alias Estimate.Organizations

  describe "update_mcp_settings/2" do
    test "enables MCP (default is disabled)" do
      %{organization: org} = user_with_organization_fixture()

      refute org.mcp_enabled

      assert {:ok, org} = Organizations.update_mcp_settings(org, %{mcp_enabled: true})
      assert org.mcp_enabled
      assert Repo.reload!(org).mcp_enabled
    end

    test "disables MCP after enabling (divergence first — default is already false)" do
      %{organization: org} = user_with_organization_fixture()
      {:ok, org} = Organizations.update_mcp_settings(org, %{mcp_enabled: true})

      assert {:ok, org} = Organizations.update_mcp_settings(org, %{mcp_enabled: false})
      refute Repo.reload!(org).mcp_enabled
    end
  end
end
