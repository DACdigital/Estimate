defmodule Estimate.MCP.KeyValidatorTest do
  use Estimate.DataCase, async: false

  import Estimate.AccountsFixtures
  import Estimate.MCPFixtures

  alias Estimate.MCP.KeyValidator

  @config %{resource: "urn:estimate:mcp"}

  setup do
    %{user: user, organization: org} = user_with_organization_fixture()
    {plaintext, _key, org} = mcp_api_key_fixture(user, org)
    %{user: user, org: org, key: plaintext}
  end

  test "valid key → string-keyed claims incl. aud from config", %{user: user, org: org, key: key} do
    assert {:ok, claims} = KeyValidator.validate_token(key, @config)

    assert claims["sub"] == user.id
    assert claims["org_id"] == org.id
    assert claims["role"] == "owner"
    assert claims["aud"] == "urn:estimate:mcp"
  end

  test "invalid key → error" do
    assert {:error, :invalid_key} = KeyValidator.validate_token("est_bogus", @config)
  end

  test "disabled org → error", %{org: org, key: key} do
    {:ok, _} = Estimate.Organizations.update_mcp_settings(org, %{mcp_enabled: false})
    assert {:error, :mcp_disabled} = KeyValidator.validate_token(key, @config)
  end

  test "claims include scope", %{key: key} do
    assert {:ok, %{"scope" => "mcp:read mcp:write"}} =
             KeyValidator.validate_token(key, %{resource: "urn:x"})
  end
end
