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

    assert {:ok, %{access_token: access_token}} =
             OAuth.exchange_code(code, %{
               client_id: client.id,
               redirect_uri: @redirect,
               code_verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk",
               resource: EstimateWeb.MCPServer.mcp_url()
             })

    assert {:ok, %{organization_id: org_id}} = OAuth.verify_access_token(access_token)
    assert org_id == org.id
  end

  test "approve binds the code to the chosen org, not just the first mcp-enabled one", %{
    conn: conn,
    client: client,
    user: user,
    org: first_org
  } do
    second_org = organization_fixture()
    membership_fixture(user, second_org, "member")
    {:ok, second_org} = Organizations.update_mcp_settings(second_org, %{mcp_enabled: true})

    # user is now a member of two mcp-enabled orgs: first_org (from setup,
    # created first) and second_org (created here, second). Approving with
    # second_org.id must bind the token to second_org — a regression that
    # bound `hd(mcp_orgs)` instead of the chosen org would still pass the
    # single-org test above but fails this one.
    params =
      authorize_params(client)
      |> Map.put("organization_id", second_org.id)
      |> Map.put("decision", "approve")

    conn = post(conn, ~p"/oauth/authorize", params)

    assert %{"code" => code, "state" => "xyz"} =
             URI.decode_query(URI.parse(redirected_to(conn)).query)

    assert {:ok, %{access_token: access_token}} =
             OAuth.exchange_code(code, %{
               client_id: client.id,
               redirect_uri: @redirect,
               code_verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk",
               resource: EstimateWeb.MCPServer.mcp_url()
             })

    assert {:ok, %{organization_id: org_id}} = OAuth.verify_access_token(access_token)
    assert org_id == second_org.id
    refute org_id == first_org.id
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
    # mcp_enabled: true so the ONLY reason this can be rejected is that the
    # session user isn't a member — isolates cross-org membership enforcement
    # from a buggy validate_org that merely checks "is some mcp-enabled org".
    {:ok, other_org} = Organizations.update_mcp_settings(other_org, %{mcp_enabled: true})

    params =
      authorize_params(client)
      |> Map.put("organization_id", other_org.id)
      |> Map.put("decision", "approve")

    conn = post(conn, ~p"/oauth/authorize", params)

    query = URI.decode_query(URI.parse(redirected_to(conn)).query)
    assert query["error"] == "invalid_request"
    refute Map.has_key?(query, "code")
  end

  test "approve with a member org that has MCP disabled is rejected", %{
    conn: conn,
    client: client,
    user: user
  } do
    other_org = organization_fixture()
    membership_fixture(user, other_org)

    params =
      authorize_params(client)
      |> Map.put("organization_id", other_org.id)
      |> Map.put("decision", "approve")

    conn = post(conn, ~p"/oauth/authorize", params)

    query = URI.decode_query(URI.parse(redirected_to(conn)).query)
    assert query["error"] == "invalid_request"
    refute Map.has_key?(query, "code")
  end

  test "approve without an organization_id is rejected", %{conn: conn, client: client} do
    params =
      authorize_params(client)
      |> Map.put("decision", "approve")

    conn = post(conn, ~p"/oauth/authorize", params)

    query = URI.decode_query(URI.parse(redirected_to(conn)).query)
    assert query["error"] == "invalid_request"
    refute Map.has_key?(query, "code")
  end

  test "approve with a missing decision is treated as deny (fail-safe)", %{
    conn: conn,
    client: client,
    org: org
  } do
    params =
      authorize_params(client)
      |> Map.put("organization_id", org.id)

    conn = post(conn, ~p"/oauth/authorize", params)

    query = URI.decode_query(URI.parse(redirected_to(conn)).query)
    assert query["error"] == "access_denied"
    refute Map.has_key?(query, "code")
  end

  test "approve with a garbage decision is treated as deny (fail-safe)", %{
    conn: conn,
    client: client,
    org: org
  } do
    params =
      authorize_params(client)
      |> Map.put("organization_id", org.id)
      |> Map.put("decision", "garbage")

    conn = post(conn, ~p"/oauth/authorize", params)

    query = URI.decode_query(URI.parse(redirected_to(conn)).query)
    assert query["error"] == "access_denied"
    refute Map.has_key?(query, "code")
  end

  test "a bracket-array state param is dropped instead of crashing the redirect", %{
    conn: conn,
    client: client
  } do
    base =
      authorize_params(client, %{"resource" => "https://other.example/mcp"})
      |> Map.delete("state")
      |> URI.encode_query()

    conn = get(conn, "/oauth/authorize?" <> base <> "&state[]=a")

    query = URI.decode_query(URI.parse(redirected_to(conn)).query)
    assert query["error"] == "invalid_request"
    refute Map.has_key?(query, "state")
  end
end
