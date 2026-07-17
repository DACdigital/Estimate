defmodule Estimate.MCPTest do
  use Estimate.DataCase, async: false

  import Estimate.AccountsFixtures

  alias Estimate.MCP
  alias Estimate.MCP.APIKey
  alias Estimate.Organizations

  setup do
    %{user: user, organization: org} = user_with_organization_fixture()
    {:ok, org} = Organizations.update_mcp_settings(org, %{mcp_enabled: true})
    %{user: user, org: org}
  end

  describe "generate_api_key/2" do
    test "returns plaintext once, stores only hash + prefix", %{user: user, org: org} do
      assert {:ok, {plaintext, %APIKey{} = key}} = MCP.generate_api_key(user.id, org.id)

      assert String.starts_with?(plaintext, "est_")
      assert key.key_prefix == String.slice(plaintext, 0, 12)
      assert key.key_hash == :crypto.hash(:sha256, plaintext)
      refute Map.has_key?(Map.from_struct(key), :plaintext)
      # plaintext never persisted anywhere
      assert Repo.reload!(key).key_hash == :crypto.hash(:sha256, plaintext)
    end

    test "regenerate replaces the old key and invalidates it", %{user: user, org: org} do
      {:ok, {old_plaintext, old_key}} = MCP.generate_api_key(user.id, org.id)
      {:ok, {new_plaintext, new_key}} = MCP.generate_api_key(user.id, org.id)

      assert old_key.id != new_key.id
      assert Repo.get(APIKey, old_key.id) == nil
      assert {:error, :invalid_key} = MCP.verify_api_key(old_plaintext)
      assert {:ok, _} = MCP.verify_api_key(new_plaintext)
    end

    test "never mints a key whose random part collides with the OAuth access-token prefix" do
      # est_ + a suffix starting with "at_" spells "est_at_...", which
      # verify_bearer/1 would route to the OAuth path instead of
      # verify_api_key/1 -- the key would silently never authenticate.
      assert MCP.oauth_prefix_collision?("at_" <> "anything-here")
      refute MCP.oauth_prefix_collision?("xyz123-not-a-collision")
    end
  end

  describe "get_api_key/2 and revoke_api_key/2" do
    test "get returns the key, revoke deletes it", %{user: user, org: org} do
      {:ok, {plaintext, key}} = MCP.generate_api_key(user.id, org.id)

      assert %APIKey{id: id} = MCP.get_api_key(user.id, org.id)
      assert id == key.id

      assert 1 = MCP.revoke_api_key(user.id, org.id)
      assert MCP.get_api_key(user.id, org.id) == nil
      assert {:error, :invalid_key} = MCP.verify_api_key(plaintext)
    end
  end

  describe "verify_api_key/1" do
    test "valid key returns user, org and membership role", %{user: user, org: org} do
      {:ok, {plaintext, _}} = MCP.generate_api_key(user.id, org.id)

      assert {:ok, %{user_id: user_id, organization_id: org_id, role: "owner"}} =
               MCP.verify_api_key(plaintext)

      assert user_id == user.id
      assert org_id == org.id
    end

    test "garbage and wrong-prefix tokens are invalid" do
      assert {:error, :invalid_key} = MCP.verify_api_key("est_" <> "notarealkey123")
      assert {:error, :invalid_key} = MCP.verify_api_key("sk-or-something")
      assert {:error, :invalid_key} = MCP.verify_api_key("")
    end

    test "org toggle off kills the key", %{user: user, org: org} do
      {:ok, {plaintext, _}} = MCP.generate_api_key(user.id, org.id)
      {:ok, _} = Organizations.update_mcp_settings(org, %{mcp_enabled: false})

      assert {:error, :mcp_disabled} = MCP.verify_api_key(plaintext)
    end

    test "membership removal kills the key", %{user: user, org: org} do
      {:ok, {plaintext, _}} = MCP.generate_api_key(user.id, org.id)

      Repo.get_by!(Estimate.Accounts.Membership, user_id: user.id, organization_id: org.id)
      |> Repo.delete!()

      assert {:error, :not_a_member} = MCP.verify_api_key(plaintext)
    end

    test "touches last_used_at at most once per 5 minutes", %{user: user, org: org} do
      {:ok, {plaintext, key}} = MCP.generate_api_key(user.id, org.id)
      assert key.last_used_at == nil

      {:ok, _} = MCP.verify_api_key(plaintext)
      first = Repo.reload!(key).last_used_at
      assert first != nil

      {:ok, _} = MCP.verify_api_key(plaintext)
      assert Repo.reload!(key).last_used_at == first
    end
  end

  describe "RLS policy on mcp_api_keys" do
    test "another user in the same org cannot read my key", %{user: user, org: org} do
      other = user_fixture()
      membership_fixture(other, org, "member")
      {:ok, _} = MCP.generate_api_key(user.id, org.id)

      # Switch to app role with the OTHER user's context — policy must hide the row.
      setup_rls(org.id, other.id)
      assert MCP.get_api_key(user.id, org.id) == nil
    end
  end
end
