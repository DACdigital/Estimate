defmodule Estimate.MCP.KeyValidatorTest do
  use Estimate.DataCase, async: false

  import Estimate.AccountsFixtures
  import Estimate.MCPFixtures

  alias Estimate.MCP.KeyValidator

  @config %{resource: "urn:estimate:mcp"}

  setup do
    %{user: user, organization: org} = user_with_organization_fixture()
    {plaintext, _key} = mcp_api_key_fixture(user, org)
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
    # `mcp_api_key_fixture/2` enables MCP via `update_mcp_settings/2` on its own
    # (unreturned) copy of `org`, so the `org` bound in `setup` is stale
    # in-memory (`mcp_enabled: false`, its value at creation). Reload before
    # flipping it off so the changeset diffs against real current state —
    # otherwise `cast/3` sees `false -> false` (no-op) and never issues the
    # UPDATE, since the target value coincidentally matches the stale struct.
    org = Estimate.Repo.reload!(org)
    {:ok, _} = Estimate.Organizations.update_mcp_settings(org, %{mcp_enabled: false})
    assert {:error, :mcp_disabled} = KeyValidator.validate_token(key, @config)
  end
end
