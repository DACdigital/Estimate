defmodule EstimateWeb.OAuthTokenTest do
  use EstimateWeb.ConnCase, async: false

  import Estimate.AccountsFixtures

  alias Estimate.MCP.OAuth
  alias Estimate.Organizations

  @verifier "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
  @challenge "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
  @redirect "https://claude.ai/api/mcp/auth_callback"

  setup do
    %{user: user, organization: org} = user_with_organization_fixture()
    {:ok, org} = Organizations.update_mcp_settings(org, %{mcp_enabled: true})
    {:ok, client} = OAuth.register_client(%{"redirect_uris" => [@redirect]})

    {:ok, code} =
      OAuth.create_code(%{
        client_id: client.id,
        user_id: user.id,
        organization_id: org.id,
        redirect_uri: @redirect,
        code_challenge: @challenge,
        resource: EstimateWeb.MCPServer.mcp_url()
      })

    %{client: client, code: code}
  end

  defp post_form(conn, params) do
    conn
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> post(~p"/oauth/token", URI.encode_query(params))
  end

  test "authorization_code grant over form-urlencoded", %{conn: conn, client: client, code: code} do
    conn =
      post_form(conn, %{
        grant_type: "authorization_code",
        code: code,
        client_id: client.id,
        redirect_uri: @redirect,
        code_verifier: @verifier,
        resource: EstimateWeb.MCPServer.mcp_url()
      })

    body = json_response(conn, 200)
    assert body["token_type"] == "Bearer"
    assert body["expires_in"] == 3600
    assert String.starts_with?(body["access_token"], "est_at_")
    assert String.starts_with?(body["refresh_token"], "est_rt_")
    assert get_resp_header(conn, "cache-control") == ["no-store"]
  end

  test "refresh_token grant rotates; reuse => invalid_grant", %{
    conn: conn,
    client: client,
    code: code
  } do
    first =
      post_form(conn, %{
        grant_type: "authorization_code",
        code: code,
        client_id: client.id,
        redirect_uri: @redirect,
        code_verifier: @verifier,
        resource: EstimateWeb.MCPServer.mcp_url()
      })
      |> json_response(200)

    second =
      post_form(build_conn(), %{
        grant_type: "refresh_token",
        refresh_token: first["refresh_token"],
        client_id: client.id
      })
      |> json_response(200)

    assert second["refresh_token"] != first["refresh_token"]

    reuse =
      post_form(build_conn(), %{
        grant_type: "refresh_token",
        refresh_token: first["refresh_token"],
        client_id: client.id
      })

    assert %{"error" => "invalid_grant"} = json_response(reuse, 400)
  end

  test "wrong verifier => invalid_grant", %{conn: conn, client: client, code: code} do
    conn =
      post_form(conn, %{
        grant_type: "authorization_code",
        code: code,
        client_id: client.id,
        redirect_uri: @redirect,
        code_verifier: "wrong-verifier-wrong-verifier-wrong-verifierAA",
        resource: EstimateWeb.MCPServer.mcp_url()
      })

    assert %{"error" => "invalid_grant"} = json_response(conn, 400)
  end

  test "unsupported grant type / missing params", %{conn: conn} do
    assert %{"error" => "unsupported_grant_type"} =
             post_form(conn, %{grant_type: "client_credentials"}) |> json_response(400)

    assert %{"error" => "invalid_request"} =
             post_form(build_conn(), %{grant_type: "authorization_code"}) |> json_response(400)
  end
end
