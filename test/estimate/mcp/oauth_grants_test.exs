defmodule Estimate.MCP.OAuthGrantsTest do
  use Estimate.DataCase, async: false

  import Estimate.AccountsFixtures
  alias Estimate.MCP.OAuth
  alias Estimate.Organizations

  @verifier "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
  @challenge "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
  @resource "http://localhost:4000/mcp"
  @redirect "https://claude.ai/api/mcp/auth_callback"

  defp grant(user, org, client, scope \\ "mcp:read") do
    {:ok, code} =
      OAuth.create_code(%{
        client_id: client.id,
        user_id: user.id,
        organization_id: org.id,
        redirect_uri: @redirect,
        code_challenge: @challenge,
        resource: @resource,
        scope: scope
      })

    {:ok, tokens} =
      OAuth.exchange_code(code, %{
        client_id: client.id,
        redirect_uri: @redirect,
        code_verifier: @verifier,
        resource: @resource
      })

    tokens
  end

  setup do
    %{user: user, organization: org} = user_with_organization_fixture()
    {:ok, org} = Organizations.update_mcp_settings(org, %{mcp_enabled: true})

    {:ok, client} =
      OAuth.register_client(%{"client_name" => "Claude", "redirect_uris" => [@redirect]})

    %{user: user, org: org, client: client}
  end

  test "list_grants shows one entry per family with client, org, scope", ctx do
    t1 = grant(ctx.user, ctx.org, ctx.client, "mcp:read mcp:write")
    # rotate once: still one family
    {:ok, _} = OAuth.refresh_tokens(t1.refresh_token, ctx.client.id)

    assert [g] = OAuth.list_grants(ctx.user.id)
    assert g.client_name == "Claude"
    assert g.organization_name == ctx.org.name
    assert g.scope == "mcp:read mcp:write"
    assert %DateTime{} = g.granted_at
  end

  test "list_grants excludes families past the 90-day absolute cap even with a live refresh window",
       ctx do
    grant(ctx.user, ctx.org, ctx.client)
    assert [_] = OAuth.list_grants(ctx.user.id)

    old = DateTime.utc_now() |> DateTime.add(-91, :day) |> DateTime.truncate(:second)
    Repo.update_all(Estimate.MCP.OAuth.Code, set: [inserted_at: old])

    assert OAuth.list_grants(ctx.user.id) == []
  end

  test "revoke_grant kills the family; other users cannot revoke it", ctx do
    t = grant(ctx.user, ctx.org, ctx.client)
    [g] = OAuth.list_grants(ctx.user.id)

    %{user: other} = user_with_organization_fixture()
    assert OAuth.revoke_grant(other.id, g.family_id) == {:error, :not_found}
    assert {:ok, %{}} = OAuth.verify_access_token(t.access_token)

    assert {:ok, 1} = OAuth.revoke_grant(ctx.user.id, g.family_id)
    assert {:error, :invalid_key} = OAuth.verify_access_token(t.access_token)
    assert {:error, :invalid_grant} = OAuth.refresh_tokens(t.refresh_token, ctx.client.id)
    assert OAuth.list_grants(ctx.user.id) == []
  end

  test "revoke_grant after a rotation only counts the live child, and kills it", ctx do
    t = grant(ctx.user, ctx.org, ctx.client)
    [g] = OAuth.list_grants(ctx.user.id)

    # rotate: parent token is now revoked_at != nil, child is the only live
    # row in the family. revoke_grant/2 must route through revoke_family/1
    # (advisory-locked update_all) rather than a plain update_all racing the
    # rotation's own transaction — asserting {:ok, 1} here (not 0 or 2) is
    # the signal that the live child was actually seen and revoked.
    {:ok, rotated} = OAuth.refresh_tokens(t.refresh_token, ctx.client.id)

    assert {:ok, 1} = OAuth.revoke_grant(ctx.user.id, g.family_id)
    assert {:error, :invalid_grant} = OAuth.refresh_tokens(rotated.refresh_token, ctx.client.id)
    assert {:error, :invalid_key} = OAuth.verify_access_token(rotated.access_token)
  end

  test "revoke_grant accepts an upper-cased family id and revokes via the DB-canonical id", ctx do
    t = grant(ctx.user, ctx.org, ctx.client)
    [g] = OAuth.list_grants(ctx.user.id)

    # Same UUID, different casing: revoke_grant/2 must look up the
    # DB-canonical (lowercase) family_id and revoke through *that* value, not
    # the raw param -- revoke_family/1's advisory lock is keyed by
    # hashtext(family_id) via a plain SQL param (no UUID cast/normalization),
    # so passing the caller's casing straight through would take a different
    # lock than a concurrent rotate/1 (which always loads the canonical
    # lowercase form from the DB), defeating the serialization between them.
    assert {:ok, 1} = OAuth.revoke_grant(ctx.user.id, String.upcase(g.family_id))
    assert {:error, :invalid_key} = OAuth.verify_access_token(t.access_token)
  end

  test "revoke_all_for_user revokes every family of that user only", ctx do
    t1 = grant(ctx.user, ctx.org, ctx.client)
    %{user: other, organization: org2} = user_with_organization_fixture()
    {:ok, org2} = Organizations.update_mcp_settings(org2, %{mcp_enabled: true})
    t2 = grant(other, org2, ctx.client)

    assert :ok = OAuth.revoke_all_for_user(ctx.user.id)
    assert {:error, :invalid_key} = OAuth.verify_access_token(t1.access_token)
    assert {:ok, %{}} = OAuth.verify_access_token(t2.access_token)
  end
end
