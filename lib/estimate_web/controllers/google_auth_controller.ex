defmodule EstimateWeb.GoogleAuthController do
  use EstimateWeb, :controller

  alias Estimate.Accounts
  alias EstimateWeb.UserAuth

  @compile {:no_warn_undefined, Assent.Strategy.Google}
  @strategy Assent.Strategy.Google

  def request(conn, params) do
    config = google_config()

    case @strategy.authorize_url(config) do
      {:ok, %{url: url, session_params: session_params}} ->
        conn
        |> put_session(:google_session_params, session_params)
        |> maybe_store_return_to(params)
        |> redirect(external: url)

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Failed to start Google authentication")
        |> redirect(to: ~p"/users/log_in")
    end
  end

  def callback(conn, params) do
    session_params = get_session(conn, :google_session_params)
    config = google_config() |> Keyword.put(:session_params, session_params)
    conn = delete_session(conn, :google_session_params)

    case @strategy.callback(config, params) do
      {:ok, %{user: google_user}} ->
        email = google_user["email"]
        name = google_user["name"] || email

        case Accounts.find_or_create_oauth_user(%{email: email, name: name}) do
          {:ok, user} ->
            UserAuth.log_in_user(conn, user)

          {:error, _changeset} ->
            conn
            |> put_flash(:error, "Failed to create account")
            |> redirect(to: ~p"/users/log_in")
        end

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Google authentication failed")
        |> redirect(to: ~p"/users/log_in")
    end
  end

  defp maybe_store_return_to(conn, %{"return_to" => return_to}) do
    case UserAuth.safe_return_to(return_to) do
      nil -> conn
      safe -> put_session(conn, :user_return_to, safe)
    end
  end

  defp maybe_store_return_to(conn, _params), do: conn

  defp google_config do
    oauth_config = Application.fetch_env!(:estimate, :google_oauth)

    [
      client_id: oauth_config[:client_id],
      client_secret: oauth_config[:client_secret],
      redirect_uri: url(~p"/auth/google/callback"),
      http_adapter: Assent.HTTPAdapter.Req
    ]
  end
end
