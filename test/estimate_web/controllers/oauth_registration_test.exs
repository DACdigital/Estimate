defmodule EstimateWeb.OAuthRegistrationTest do
  use EstimateWeb.ConnCase, async: true

  test "registers a public client", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(
        ~p"/oauth/register",
        Jason.encode!(%{
          client_name: "Claude",
          redirect_uris: ["https://claude.ai/api/mcp/auth_callback"],
          token_endpoint_auth_method: "none"
        })
      )

    body = json_response(conn, 201)
    assert body["client_id"] =~ ~r/^[0-9a-f-]{36}$/
    assert body["client_name"] == "Claude"
    assert body["redirect_uris"] == ["https://claude.ai/api/mcp/auth_callback"]
    assert body["token_endpoint_auth_method"] == "none"
  end

  test "rejects invalid redirect uris with an RFC 7591 error", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/oauth/register", Jason.encode!(%{redirect_uris: ["http://evil.com/cb"]}))

    assert %{"error" => "invalid_redirect_uri"} = json_response(conn, 400)
  end

  test "rejects missing redirect uris", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/oauth/register", Jason.encode!(%{client_name: "X"}))

    assert %{"error" => "invalid_client_metadata"} = json_response(conn, 400)
  end
end
