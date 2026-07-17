defmodule Estimate.MCP.VerifyBearerTest do
  use Estimate.DataCase, async: false

  import Estimate.AccountsFixtures
  import Estimate.MCPFixtures

  alias Estimate.MCP
  alias Estimate.MCP.OAuth

  setup do
    %{user: user, organization: org} = user_with_organization_fixture()
    {plaintext_key, _key, org} = mcp_api_key_fixture(user, org)
    %{user: user, org: org, api_key: plaintext_key}
  end

  test "dispatches est_ API keys to the key path", %{api_key: key, user: user} do
    assert {:ok, %{user_id: uid}} = MCP.verify_bearer(key)
    assert uid == user.id
  end

  test "dispatches est_at_ tokens to the OAuth path", %{user: user, org: org} do
    {:ok, client} =
      OAuth.register_client(%{"redirect_uris" => ["https://claude.ai/api/mcp/auth_callback"]})

    {:ok, code} =
      OAuth.create_code(%{
        client_id: client.id,
        user_id: user.id,
        organization_id: org.id,
        redirect_uri: "https://claude.ai/api/mcp/auth_callback",
        code_challenge: "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
        resource: "http://localhost:4000/mcp"
      })

    {:ok, %{access_token: at}} =
      OAuth.exchange_code(code, %{
        client_id: client.id,
        redirect_uri: "https://claude.ai/api/mcp/auth_callback",
        code_verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk",
        resource: "http://localhost:4000/mcp"
      })

    assert {:ok, %{user_id: uid, role: "owner"}} = MCP.verify_bearer(at)
    assert uid == user.id
  end

  test "garbage => invalid_key" do
    assert {:error, :invalid_key} = MCP.verify_bearer("garbage")
    assert {:error, :invalid_key} = MCP.verify_bearer("est_at_bogus")
    assert {:error, :invalid_key} = MCP.verify_bearer("est_bogus")
  end

  test "validator claims carry through for OAuth tokens", %{user: user, org: org} do
    # KeyValidator is exercised with a real OAuth token via the config map shape
    {:ok, client} =
      OAuth.register_client(%{"redirect_uris" => ["https://claude.ai/api/mcp/auth_callback"]})

    {:ok, code} =
      OAuth.create_code(%{
        client_id: client.id,
        user_id: user.id,
        organization_id: org.id,
        redirect_uri: "https://claude.ai/api/mcp/auth_callback",
        code_challenge: "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
        resource: "http://localhost:4000/mcp"
      })

    {:ok, %{access_token: at}} =
      OAuth.exchange_code(code, %{
        client_id: client.id,
        redirect_uri: "https://claude.ai/api/mcp/auth_callback",
        code_verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk",
        resource: "http://localhost:4000/mcp"
      })

    assert {:ok, claims} = Estimate.MCP.KeyValidator.validate_token(at, %{resource: "urn:r"})
    assert claims["sub"] == user.id
    assert claims["org_id"] == org.id
    assert claims["aud"] == "urn:r"
  end
end
