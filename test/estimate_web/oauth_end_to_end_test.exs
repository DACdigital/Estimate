defmodule EstimateWeb.OAuthEndToEndTest do
  use EstimateWeb.ConnCase, async: false

  import Estimate.MCPTestHelpers

  alias Estimate.Organizations

  @verifier "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
  @challenge "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
  @redirect "https://claude.ai/api/mcp/auth_callback"

  setup :register_and_log_in_org_owner

  setup %{org: org} do
    start_supervised!(
      {EstimateWeb.MCPServer,
       transport: {:streamable_http, start: true},
       authorization: EstimateWeb.MCPServer.runtime_authorization()}
    )

    {:ok, org} = Organizations.update_mcp_settings(org, %{mcp_enabled: true})
    customer = Estimate.CRMFixtures.customer_fixture(org, %{"name" => "Flow Corp"})
    %{org: org, customer: customer}
  end

  test "register → authorize → token → MCP call → refresh → kill switch", %{conn: conn, org: org} do
    # 1. DCR
    reg =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post(
        ~p"/oauth/register",
        Jason.encode!(%{client_name: "Claude", redirect_uris: [@redirect]})
      )
      |> json_response(201)

    client_id = reg["client_id"]

    # 2. authorize (browser session)
    params = %{
      "client_id" => client_id,
      "redirect_uri" => @redirect,
      "response_type" => "code",
      "code_challenge" => @challenge,
      "code_challenge_method" => "S256",
      "resource" => EstimateWeb.MCPServer.mcp_url(),
      "state" => "s1",
      "organization_id" => org.id,
      "decision" => "approve"
    }

    consent = post(conn, ~p"/oauth/authorize", params)
    %{"code" => code} = URI.decode_query(URI.parse(redirected_to(consent)).query)

    # 3. token
    tokens =
      build_conn()
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> post(
        ~p"/oauth/token",
        URI.encode_query(%{
          grant_type: "authorization_code",
          code: code,
          client_id: client_id,
          redirect_uri: @redirect,
          code_verifier: @verifier,
          resource: EstimateWeb.MCPServer.mcp_url()
        })
      )
      |> json_response(200)

    # 4. MCP call with the OAuth access token
    init = post_mcp(init_body(), [{"authorization", "Bearer " <> tokens["access_token"]}])
    assert init.status == 200
    [session_id] = Plug.Conn.get_resp_header(init, "mcp-session-id")

    post_mcp(
      %{"jsonrpc" => "2.0", "method" => "notifications/initialized"},
      [{"authorization", "Bearer " <> tokens["access_token"]}, {"mcp-session-id", session_id}]
    )

    call =
      post_mcp(
        %{
          "jsonrpc" => "2.0",
          "id" => 2,
          "method" => "tools/call",
          "params" => %{"name" => "list_customers", "arguments" => %{}}
        },
        [{"authorization", "Bearer " <> tokens["access_token"]}, {"mcp-session-id", session_id}]
      )

    assert call.status == 200
    assert call.resp_body =~ "Flow Corp"

    # 5. refresh rotates
    refreshed =
      build_conn()
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> post(
        ~p"/oauth/token",
        URI.encode_query(%{
          grant_type: "refresh_token",
          refresh_token: tokens["refresh_token"],
          client_id: client_id
        })
      )
      |> json_response(200)

    assert refreshed["access_token"] != tokens["access_token"]

    # 6. kill switch
    {:ok, _} =
      Organizations.update_mcp_settings(Estimate.Repo.reload!(org), %{mcp_enabled: false})

    dead = post_mcp(init_body(), [{"authorization", "Bearer " <> refreshed["access_token"]}])
    assert dead.status == 401
  end
end
