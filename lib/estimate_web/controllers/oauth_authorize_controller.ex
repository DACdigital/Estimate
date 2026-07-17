defmodule EstimateWeb.OAuthAuthorizeController do
  use EstimateWeb, :controller

  alias Estimate.MCP.OAuth
  alias Estimate.MCP.OAuth.{PKCE, Redirect}
  alias Estimate.Organizations
  alias EstimateWeb.MCPServer

  plug :put_layout, html: {EstimateWeb.Layouts, :auth}

  def show(conn, params) do
    with {:ok, client, redirect_uri} <- resolve_client(params),
         :ok <- validate_request(params) do
      case mcp_orgs(conn.assigns.current_user.id) do
        [] ->
          conn
          |> put_status(200)
          |> render(:error,
            title: "No organization available",
            message:
              "None of your organizations has the MCP server enabled. Ask an admin to enable it under Settings → MCP."
          )

        orgs ->
          render(conn, :consent,
            client: client,
            redirect_host: URI.parse(redirect_uri).host,
            loopback_warning: Redirect.loopback_only?(client.redirect_uris),
            orgs: orgs,
            params: params
          )
      end
    else
      {:error, :bad_client} ->
        conn
        |> put_status(400)
        |> render(:error,
          title: "Invalid authorization request",
          message: "The client or redirect URI of this authorization request is not recognized."
        )

      {:error, :invalid_request, redirect_uri} ->
        deny_redirect(conn, redirect_uri, "invalid_request", params["state"])
    end
  end

  def approve(conn, %{"decision" => "deny"} = params) do
    case resolve_client(params) do
      {:ok, _client, redirect_uri} ->
        deny_redirect(conn, redirect_uri, "access_denied", params["state"])

      {:error, :bad_client} ->
        bad_client(conn)
    end
  end

  def approve(conn, params) do
    user = conn.assigns.current_user

    with {:ok, client, redirect_uri} <- resolve_client(params),
         :ok <- validate_request(params),
         {:ok, org_id} <- validate_org(params["organization_id"], user.id) do
      {:ok, code} =
        OAuth.create_code(%{
          client_id: client.id,
          user_id: user.id,
          organization_id: org_id,
          redirect_uri: redirect_uri,
          code_challenge: params["code_challenge"],
          resource: params["resource"]
        })

      query =
        URI.encode_query(
          Enum.reject([code: code, state: params["state"]], fn {_, v} -> is_nil(v) end)
        )

      redirect(conn, external: redirect_uri <> "?" <> query)
    else
      {:error, :bad_client} ->
        bad_client(conn)

      {:error, :invalid_request, redirect_uri} ->
        deny_redirect(conn, redirect_uri, "invalid_request", params["state"])

      {:error, :bad_org} ->
        deny_redirect(conn, params["redirect_uri"], "invalid_request", params["state"])
    end
  end

  defp resolve_client(%{"client_id" => client_id, "redirect_uri" => redirect_uri})
       when is_binary(client_id) and is_binary(redirect_uri) do
    with %OAuth.Client{} = client <- OAuth.get_client(client_id),
         true <- Redirect.matches?(client.redirect_uris, redirect_uri) do
      {:ok, client, redirect_uri}
    else
      _ -> {:error, :bad_client}
    end
  end

  defp resolve_client(_), do: {:error, :bad_client}

  defp validate_request(params) do
    valid? =
      params["response_type"] == "code" and
        params["code_challenge_method"] == "S256" and
        PKCE.valid_challenge?(params["code_challenge"]) and
        params["resource"] == MCPServer.mcp_url()

    if valid?, do: :ok, else: {:error, :invalid_request, params["redirect_uri"]}
  end

  defp validate_org(org_id, user_id) when is_binary(org_id) do
    if Enum.any?(mcp_orgs(user_id), fn {org, _role} -> org.id == org_id end),
      do: {:ok, org_id},
      else: {:error, :bad_org}
  end

  defp validate_org(_, _), do: {:error, :bad_org}

  defp mcp_orgs(user_id) do
    user_id
    |> Organizations.list_user_organizations()
    |> Enum.filter(fn {org, _role} -> org.mcp_enabled end)
  end

  defp deny_redirect(conn, redirect_uri, error, state) do
    query =
      URI.encode_query(Enum.reject([error: error, state: state], fn {_, v} -> is_nil(v) end))

    redirect(conn, external: redirect_uri <> "?" <> query)
  end

  defp bad_client(conn) do
    conn
    |> put_status(400)
    |> render(:error,
      title: "Invalid authorization request",
      message: "The client or redirect URI of this authorization request is not recognized."
    )
  end
end
