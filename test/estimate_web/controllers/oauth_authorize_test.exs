defmodule EstimateWeb.OAuthAuthorizeTest do
  use EstimateWeb.ConnCase, async: false

  import Estimate.AccountsFixtures

  alias Estimate.MCP.OAuth
  alias Estimate.Organizations

  @challenge "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
  @redirect "https://claude.ai/api/mcp/auth_callback"

  setup :register_and_log_in_org_owner

  setup %{org: org} do
    {:ok, org} = Organizations.update_mcp_settings(org, %{mcp_enabled: true})

    {:ok, client} =
      OAuth.register_client(%{"client_name" => "Claude", "redirect_uris" => [@redirect]})

    %{org: org, client: client}
  end

  defp authorize_params(client, overrides \\ %{}) do
    Map.merge(
      %{
        "client_id" => client.id,
        "redirect_uri" => @redirect,
        "response_type" => "code",
        "code_challenge" => @challenge,
        "code_challenge_method" => "S256",
        "resource" => EstimateWeb.MCPServer.mcp_url(),
        "state" => "xyz"
      },
      overrides
    )
  end

  test "anonymous user is sent to login and returns", %{client: client} do
    conn = build_conn() |> get(~p"/oauth/authorize?#{authorize_params(client)}")
    assert redirected_to(conn) == ~p"/users/log_in"
    assert get_session(conn, :user_return_to) =~ "/oauth/authorize?"
  end

  test "consent page shows client, redirect host and org picker", %{
    conn: conn,
    client: client,
    org: org
  } do
    html = conn |> get(~p"/oauth/authorize?#{authorize_params(client)}") |> html_response(200)

    assert html =~ "Claude"
    assert html =~ "claude.ai"
    assert html =~ org.name
  end

  test "unknown client or unmatched redirect renders error page, never redirects", %{
    conn: conn,
    client: client
  } do
    conn1 =
      get(
        conn,
        ~p"/oauth/authorize?#{authorize_params(client, %{"client_id" => Ecto.UUID.generate()})}"
      )

    assert html_response(conn1, 400) =~ "authorization request"

    conn2 =
      get(
        conn,
        ~p"/oauth/authorize?#{authorize_params(client, %{"redirect_uri" => "https://evil.com/cb"})}"
      )

    assert html_response(conn2, 400)
  end

  test "missing/invalid PKCE or wrong resource redirects with error", %{
    conn: conn,
    client: client
  } do
    for overrides <- [
          %{"code_challenge" => ""},
          %{"code_challenge_method" => "plain"},
          %{"resource" => "https://other.example/mcp"}
        ] do
      conn2 = get(conn, ~p"/oauth/authorize?#{authorize_params(client, overrides)}")
      assert redirected_to(conn2) =~ @redirect
      assert redirected_to(conn2) =~ "error=invalid_request"
      assert redirected_to(conn2) =~ "state=xyz"
    end
  end

  test "approve mints a code bound to the chosen org", %{conn: conn, client: client, org: org} do
    params =
      authorize_params(client)
      |> Map.put("organization_id", org.id)
      |> Map.put("decision", "approve")

    conn = post(conn, ~p"/oauth/authorize", params)

    assert redirected_to(conn) =~ @redirect <> "?"

    assert %{"code" => code, "state" => "xyz"} =
             URI.decode_query(URI.parse(redirected_to(conn)).query)

    assert {:ok, %{access_token: _}} =
             OAuth.exchange_code(code, %{
               client_id: client.id,
               redirect_uri: @redirect,
               code_verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk",
               resource: EstimateWeb.MCPServer.mcp_url()
             })
  end

  test "deny redirects with access_denied", %{conn: conn, client: client, org: org} do
    params =
      authorize_params(client)
      |> Map.put("organization_id", org.id)
      |> Map.put("decision", "deny")

    conn = post(conn, ~p"/oauth/authorize", params)
    assert redirected_to(conn) =~ "error=access_denied"
  end

  test "orgs with MCP disabled are not offered", %{conn: conn, client: client, org: org} do
    {:ok, _} = Organizations.update_mcp_settings(org, %{mcp_enabled: false})
    html = conn |> get(~p"/oauth/authorize?#{authorize_params(client)}") |> html_response(200)
    refute html =~ org.name
    assert html =~ "No organization"
  end

  test "approve with a foreign org id is rejected", %{conn: conn, client: client} do
    %{organization: other_org} = user_with_organization_fixture()

    params =
      authorize_params(client)
      |> Map.put("organization_id", other_org.id)
      |> Map.put("decision", "approve")

    conn = post(conn, ~p"/oauth/authorize", params)
    assert redirected_to(conn) =~ "error=invalid_request"
  end
end
