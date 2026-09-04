defmodule EstimateWeb.OAuthAuthorizeController do
  use EstimateWeb, :controller

  alias Estimate.MCP.OAuth
  alias Estimate.MCP.OAuth.{PKCE, Redirect, Scopes}
  alias Estimate.Organizations
  alias EstimateWeb.MCPServer

  plug :put_layout, html: {EstimateWeb.Layouts, :auth}

  def show(conn, params) do
    with {:ok, client, redirect_uri} <- resolve_client(params),
         :ok <- validate_request(params),
         {:ok, scopes} <- parse_scope(params) do
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
            scopes: scopes,
            params: sanitize_state(params)
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

      {:error, :invalid_scope, redirect_uri} ->
        deny_redirect(conn, redirect_uri, "invalid_scope", params["state"])
    end
  end

  # Fail-safe consent: only an exact "approve" decision may mint a code.
  # Everything else (deny, missing, garbage) falls through to the catch-all
  # clause below and is treated as a denial.
  def approve(conn, %{"decision" => "approve"} = params) do
    user = conn.assigns.current_user

    with {:ok, client, redirect_uri} <- resolve_client(params),
         :ok <- validate_request(params),
         {:ok, scopes} <- parse_scope(params),
         {:ok, org_id} <- validate_org(params["organization_id"], user.id) do
      {:ok, code} =
        OAuth.create_code(%{
          client_id: client.id,
          user_id: user.id,
          organization_id: org_id,
          redirect_uri: redirect_uri,
          code_challenge: params["code_challenge"],
          resource: params["resource"],
          scope: Scopes.join(scopes)
        })

      redirect(conn, external: append_params(redirect_uri, code: code, state: params["state"]))
    else
      {:error, :bad_client} ->
        bad_client(conn)

      {:error, :invalid_request, redirect_uri} ->
        deny_redirect(conn, redirect_uri, "invalid_request", params["state"])

      {:error, :invalid_scope, redirect_uri} ->
        deny_redirect(conn, redirect_uri, "invalid_scope", params["state"])

      {:error, :bad_org} ->
        # Invariant: resolve_client/1 above already validated params["redirect_uri"]
        # against the registered client's redirect_uris, so redirecting to the raw
        # param here is safe (not an open redirect). Keep resolve_client first if
        # this clause is ever reordered.
        deny_redirect(conn, params["redirect_uri"], "invalid_request", params["state"])
    end
  end

  def approve(conn, params) do
    case resolve_client(params) do
      {:ok, _client, redirect_uri} ->
        deny_redirect(conn, redirect_uri, "access_denied", params["state"])

      {:error, :bad_client} ->
        bad_client(conn)
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

  defp parse_scope(params) do
    case Scopes.parse(params["scope"]) do
      {:ok, scopes} -> {:ok, scopes}
      {:error, :invalid_scope} -> {:error, :invalid_scope, params["redirect_uri"]}
    end
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
    redirect(conn, external: append_params(redirect_uri, error: error, state: state))
  end

  # A `?state[k]=v` (or `state[]=v`) request parses "state" to a map (or
  # list), not a binary. The redirect paths already tolerate this silently --
  # append_params/2 below filters to `is_binary(value)`, so a non-binary
  # state is simply dropped from the redirect query string. The consent
  # template renders `@params` values straight into a hidden input's
  # `value={...}`, which has no Phoenix.HTML.Safe impl for maps/lists and
  # 500s -- so `show/2` needs the same drop-if-not-binary treatment applied
  # to `params` before it ever reaches the template.
  defp sanitize_state(%{"state" => state} = params) when not is_binary(state) do
    Map.delete(params, "state")
  end

  defp sanitize_state(params), do: params

  # Appends params as proper query-string key/value pairs (RFC 6749 §3.1.2),
  # never a fragment. Registered redirect URIs are rejected at registration
  # if they already carry a query or fragment (Redirect.valid_for_registration?/1),
  # so `uri.query` here is normally empty — the merge is still implemented
  # properly so this stays correct if that invariant ever changes. Non-binary
  # values (e.g. a `state[]=a` request parses "state" to a list) and nil
  # values are dropped rather than fed to URI.encode_query/1, which raises on
  # list values.
  defp append_params(redirect_uri, params) do
    uri = URI.parse(redirect_uri)

    new_params =
      params
      |> Enum.filter(fn {_key, value} -> is_binary(value) end)
      |> Map.new(fn {key, value} -> {to_string(key), value} end)

    merged_query =
      (uri.query || "")
      |> URI.decode_query()
      |> Map.merge(new_params)
      |> URI.encode_query()

    URI.to_string(%{uri | query: merged_query, fragment: nil})
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
