defmodule EstimateWeb.OAuthRegistrationController do
  use EstimateWeb, :controller

  alias Estimate.MCP.OAuth

  def create(conn, params) do
    case OAuth.register_client(params) do
      {:ok, client} ->
        conn
        |> put_status(201)
        |> json(%{
          client_id: client.id,
          client_name: client.name,
          redirect_uris: client.redirect_uris,
          token_endpoint_auth_method: "none",
          grant_types: ["authorization_code", "refresh_token"],
          response_types: ["code"]
        })

      {:error, changeset} ->
        error =
          if Keyword.has_key?(changeset.errors, :redirect_uris) and
               get_in(changeset.changes, [:redirect_uris]) not in [nil, []],
             do: "invalid_redirect_uri",
             else: "invalid_client_metadata"

        conn
        |> put_status(400)
        |> json(%{error: error, error_description: "client registration rejected"})
    end
  end
end
