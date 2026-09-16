defmodule EstimateWeb.Plugs.ContentSecurityPolicyTest do
  use EstimateWeb.ConnCase, async: false
  alias EstimateWeb.Plugs.ContentSecurityPolicy, as: CSP

  test "browser routes get an enforced CSP with a per-request nonce", %{conn: conn} do
    c1 = get(conn, ~p"/users/log_in")
    [h1] = get_resp_header(c1, "content-security-policy")
    assert get_resp_header(c1, "content-security-policy-report-only") == []
    assert h1 =~ "default-src 'self'; script-src 'self' 'nonce-"
    assert h1 =~ "frame-ancestors 'none'"
    [nonce] = Regex.run(~r/'nonce-([A-Za-z0-9_-]+)'/, h1, capture: :all_but_first)
    assert html_response(c1, 200) =~ ~s(<script nonce="#{nonce}">)

    c2 = get(build_conn(), ~p"/users/log_in")
    [h2] = get_resp_header(c2, "content-security-policy")
    refute h1 == h2
  end

  test "policy string is exact", _ do
    assert CSP.policy("abc") ==
             "default-src 'self'; script-src 'self' 'nonce-abc'; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com data:; img-src 'self' data: blob:; connect-src 'self' ws: wss:; frame-ancestors 'none'; base-uri 'self'; form-action 'self'"
  end

  test "JSON endpoints carry no CSP", %{conn: conn} do
    conn = get(conn, ~p"/healthz")
    assert get_resp_header(conn, "content-security-policy") == []
  end

  test "report-only flag switches the header name", %{conn: conn} do
    prev = Application.get_env(:estimate, CSP, [])
    Application.put_env(:estimate, CSP, Keyword.put(prev, :report_only, true))
    on_exit(fn -> Application.put_env(:estimate, CSP, prev) end)

    conn = get(conn, ~p"/users/log_in")

    # Report-only mode must still ship an enforced baseline — it's a kill-switch for
    # the FULL policy, not a "no CSP at all" mode.
    assert [enforced] = get_resp_header(conn, "content-security-policy")
    assert enforced == "base-uri 'self'; frame-ancestors 'none'"

    assert [report_only] = get_resp_header(conn, "content-security-policy-report-only")
    assert report_only =~ "script-src 'self' 'nonce-"
  end

  test "/oauth/token and /mcp carry no CSP header", %{conn: conn} do
    conn1 =
      conn
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> post(~p"/oauth/token", URI.encode_query(%{"grant_type" => "nope"}))

    assert get_resp_header(conn1, "content-security-policy") == []
    assert get_resp_header(conn1, "content-security-policy-report-only") == []

    # /mcp is forwarded outside the :browser pipeline, so the plug never runs
    # regardless of the response — start the Anubis server for real so the
    # request doesn't blow up before we get a response to inspect.
    start_supervised!(
      {EstimateWeb.MCPServer,
       transport: {:streamable_http, start: true},
       authorization: EstimateWeb.MCPServer.runtime_authorization()}
    )

    conn2 =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post("/mcp", Jason.encode!(%{}))

    assert get_resp_header(conn2, "content-security-policy") == []
    assert get_resp_header(conn2, "content-security-policy-report-only") == []
  end
end
