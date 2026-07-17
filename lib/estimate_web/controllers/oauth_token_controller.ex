defmodule EstimateWeb.OAuthTokenController do
  use EstimateWeb, :controller

  alias Estimate.MCP.OAuth

  plug :no_store

  def create(conn, %{"grant_type" => "authorization_code"} = params) do
    required = ~w(code client_id redirect_uri code_verifier resource)

    with true <- Enum.all?(required, &is_binary(params[&1])),
         {:ok, tokens} <-
           OAuth.exchange_code(params["code"], %{
             client_id: params["client_id"],
             redirect_uri: params["redirect_uri"],
             code_verifier: params["code_verifier"],
             resource: params["resource"]
           }) do
      success(conn, tokens)
    else
      false -> error(conn, "invalid_request")
      {:error, :invalid_grant} -> error(conn, "invalid_grant")
    end
  end

  def create(conn, %{"grant_type" => "refresh_token"} = params) do
    with true <- is_binary(params["refresh_token"]) and is_binary(params["client_id"]),
         {:ok, tokens} <- OAuth.refresh_tokens(params["refresh_token"], params["client_id"]) do
      success(conn, tokens)
    else
      false -> error(conn, "invalid_request")
      {:error, :invalid_grant} -> error(conn, "invalid_grant")
    end
  end

  def create(conn, _params), do: error(conn, "unsupported_grant_type")

  defp success(conn, tokens) do
    json(conn, %{
      access_token: tokens.access_token,
      token_type: "Bearer",
      expires_in: tokens.expires_in,
      refresh_token: tokens.refresh_token,
      scope: "mcp:read"
    })
  end

  defp error(conn, code) do
    conn |> put_status(400) |> json(%{error: code})
  end

  defp no_store(conn, _opts), do: Plug.Conn.put_resp_header(conn, "cache-control", "no-store")
end
