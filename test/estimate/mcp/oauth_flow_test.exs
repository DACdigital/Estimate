defmodule Estimate.MCP.OAuthFlowTest do
  use Estimate.DataCase, async: false

  import Estimate.AccountsFixtures

  alias Estimate.MCP.OAuth
  alias Estimate.MCP.OAuth.Token
  alias Estimate.Organizations

  @verifier "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
  @challenge "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
  @resource "http://localhost:4000/mcp"
  @redirect "https://claude.ai/api/mcp/auth_callback"

  setup do
    %{user: user, organization: org} = user_with_organization_fixture()
    {:ok, org} = Organizations.update_mcp_settings(org, %{mcp_enabled: true})

    {:ok, client} =
      OAuth.register_client(%{"client_name" => "Claude", "redirect_uris" => [@redirect]})

    %{user: user, org: org, client: client}
  end

  defp mint_code(ctx) do
    {:ok, code} =
      OAuth.create_code(%{
        client_id: ctx.client.id,
        user_id: ctx.user.id,
        organization_id: ctx.org.id,
        redirect_uri: @redirect,
        code_challenge: @challenge,
        resource: @resource
      })

    code
  end

  defp exchange(ctx, code, overrides \\ %{}) do
    OAuth.exchange_code(
      code,
      Map.merge(
        %{
          client_id: ctx.client.id,
          redirect_uri: @redirect,
          code_verifier: @verifier,
          resource: @resource
        },
        overrides
      )
    )
  end

  describe "code exchange" do
    test "happy path issues working tokens", ctx do
      code = mint_code(ctx)
      assert String.starts_with?(code, "est_ac_")

      assert {:ok, %{access_token: at, refresh_token: rt, expires_in: 3600}} = exchange(ctx, code)
      assert String.starts_with?(at, "est_at_")
      assert String.starts_with?(rt, "est_rt_")

      assert {:ok, %{user_id: uid, organization_id: oid, role: "owner"}} =
               OAuth.verify_access_token(at)

      assert uid == ctx.user.id
      assert oid == ctx.org.id
    end

    test "wrong verifier, redirect, client or resource => invalid_grant", ctx do
      for overrides <- [
            %{code_verifier: "wrong-verifier-wrong-verifier-wrong-verifierAA"},
            %{redirect_uri: "https://claude.ai/other"},
            %{client_id: Ecto.UUID.generate()},
            %{resource: "http://localhost:4000/other"}
          ] do
        code = mint_code(ctx)
        assert {:error, :invalid_grant} = exchange(ctx, code, overrides)
      end
    end

    test "code is single-use; replay revokes issued tokens", ctx do
      code = mint_code(ctx)
      assert {:ok, %{access_token: at}} = exchange(ctx, code)
      assert {:error, :invalid_grant} = exchange(ctx, code)
      assert {:error, :invalid_key} = OAuth.verify_access_token(at)
    end

    test "expired code rejected", ctx do
      code = mint_code(ctx)
      hash = :crypto.hash(:sha256, code)
      past = DateTime.utc_now() |> DateTime.add(-121) |> DateTime.truncate(:second)

      Repo.update_all(from(c in OAuth.Code, where: c.code_hash == ^hash),
        set: [expires_at: past]
      )

      assert {:error, :invalid_grant} = exchange(ctx, code)
    end
  end

  describe "refresh rotation" do
    test "rotates and old refresh reuse kills the family", ctx do
      {:ok, %{access_token: at1, refresh_token: rt1}} = exchange(ctx, mint_code(ctx))

      assert {:ok, %{access_token: at2, refresh_token: rt2}} =
               OAuth.refresh_tokens(rt1, ctx.client.id)

      assert at2 != at1 and rt2 != rt1
      assert {:ok, _} = OAuth.verify_access_token(at2)

      # reuse of the rotated refresh token => whole family dead
      assert {:error, :invalid_grant} = OAuth.refresh_tokens(rt1, ctx.client.id)
      assert {:error, :invalid_key} = OAuth.verify_access_token(at2)
      assert {:error, :invalid_grant} = OAuth.refresh_tokens(rt2, ctx.client.id)
    end

    test "wrong client on refresh => invalid_grant", ctx do
      {:ok, %{refresh_token: rt}} = exchange(ctx, mint_code(ctx))
      assert {:error, :invalid_grant} = OAuth.refresh_tokens(rt, Ecto.UUID.generate())
    end
  end

  describe "verify_access_token/1" do
    test "expired access token => :token_expired", ctx do
      {:ok, %{access_token: at}} = exchange(ctx, mint_code(ctx))
      hash = :crypto.hash(:sha256, at)
      past = DateTime.utc_now() |> DateTime.add(-10) |> DateTime.truncate(:second)

      Repo.update_all(from(t in Token, where: t.access_token_hash == ^hash),
        set: [access_expires_at: past]
      )

      assert {:error, :token_expired} = OAuth.verify_access_token(at)
    end

    test "org toggle off and membership removal kill tokens", ctx do
      {:ok, %{access_token: at}} = exchange(ctx, mint_code(ctx))

      {:ok, _} = Organizations.update_mcp_settings(Repo.reload!(ctx.org), %{mcp_enabled: false})
      assert {:error, :mcp_disabled} = OAuth.verify_access_token(at)

      {:ok, _} = Organizations.update_mcp_settings(Repo.reload!(ctx.org), %{mcp_enabled: true})

      Repo.get_by!(Estimate.Accounts.Membership,
        user_id: ctx.user.id,
        organization_id: ctx.org.id
      )
      |> Repo.delete!()

      assert {:error, :not_a_member} = OAuth.verify_access_token(at)
    end

    test "garbage input => :invalid_key" do
      assert {:error, :invalid_key} = OAuth.verify_access_token("est_at_bogus")
      assert {:error, :invalid_key} = OAuth.verify_access_token("nonsense")
    end
  end

  describe "revoke_for_membership/2" do
    test "removes codes and tokens for the pair", ctx do
      unused_code = mint_code(ctx)
      {:ok, %{access_token: at}} = exchange(ctx, mint_code(ctx))

      Repo.without_rls(fn -> OAuth.revoke_for_membership(ctx.user.id, ctx.org.id) end)

      assert {:error, :invalid_key} = OAuth.verify_access_token(at)
      assert {:error, :invalid_grant} = exchange(ctx, unused_code)
    end
  end
end
