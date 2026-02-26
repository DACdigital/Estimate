defmodule EstimateWeb.UserAuth do
  @moduledoc """
  Handles user authentication for both regular requests and LiveView.
  """
  use EstimateWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias Estimate.Accounts

  @max_age 60 * 60 * 24 * 60
  @remember_me_cookie "_estimate_web_user_remember_me"
  @remember_me_options [sign: true, max_age: @max_age, same_site: "Lax"]

  def log_in_user(conn, user, params \\ %{}) do
    token = Accounts.generate_user_session_token(user)
    user_return_to = get_session(conn, :user_return_to)

    conn
    |> renew_session()
    |> put_token_in_session(token)
    |> maybe_write_remember_me_cookie(token, params)
    |> redirect(to: user_return_to || signed_in_path(user))
  end

  defp maybe_write_remember_me_cookie(conn, token, %{"remember_me" => "true"}) do
    put_resp_cookie(conn, @remember_me_cookie, token, @remember_me_options)
  end

  defp maybe_write_remember_me_cookie(conn, _token, _params) do
    conn
  end

  defp renew_session(conn) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  def log_out_user(conn) do
    user_token = get_session(conn, :user_token)
    user_token && Accounts.delete_user_session_token(user_token)

    if live_socket_id = get_session(conn, :live_socket_id) do
      EstimateWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session()
    |> delete_resp_cookie(@remember_me_cookie)
    |> redirect(to: ~p"/")
  end

  def fetch_current_user(conn, _opts) do
    {user_token, conn} = ensure_user_token(conn)
    user = user_token && Accounts.get_user_by_session_token(user_token)
    assign(conn, :current_user, user)
  end

  defp ensure_user_token(conn) do
    if token = get_session(conn, :user_token) do
      {token, conn}
    else
      conn = fetch_cookies(conn, signed: [@remember_me_cookie])

      if token = conn.cookies[@remember_me_cookie] do
        {token, put_token_in_session(conn, token)}
      else
        {nil, conn}
      end
    end
  end

  defp put_token_in_session(conn, token) do
    conn
    |> put_session(:user_token, token)
    |> put_session(:live_socket_id, "users_sessions:#{Base.url_encode64(token)}")
  end

  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> maybe_store_return_to()
      |> redirect(to: ~p"/users/log_in")
      |> halt()
    end
  end

  def redirect_if_user_is_authenticated(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
      |> redirect(to: signed_in_path(conn.assigns.current_user))
      |> halt()
    else
      conn
    end
  end

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :user_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn

  @doc "Validates a return_to path is safe (local, no open redirect)."
  def safe_return_to("/" <> rest = path) do
    uri = URI.parse(path)

    if is_nil(uri.host) and is_nil(uri.scheme) and not String.starts_with?(rest, ["/", "\\"]) do
      path
    end
  end

  def safe_return_to(_), do: nil

  defp signed_in_path(%{last_org_id: org_id}) when not is_nil(org_id), do: ~p"/org/#{org_id}"
  defp signed_in_path(_), do: ~p"/organizations"

  ## Pending 2FA session

  def put_pending_2fa(conn, user, params \\ %{}) do
    conn
    |> put_session(:pending_2fa_user_id, user.id)
    |> put_session(:pending_2fa_remember_me, params["remember_me"])
  end

  def get_pending_2fa_user(conn) do
    if user_id = get_session(conn, :pending_2fa_user_id) do
      Accounts.get_user!(user_id)
    end
  end

  def clear_pending_2fa(conn) do
    conn
    |> delete_session(:pending_2fa_user_id)
    |> delete_session(:pending_2fa_remember_me)
  end

  def pending_2fa_remember_me_params(conn) do
    if get_session(conn, :pending_2fa_remember_me) == "true" do
      %{"remember_me" => "true"}
    else
      %{}
    end
  end

  def require_pending_2fa(conn, _opts) do
    if get_session(conn, :pending_2fa_user_id) do
      conn
    else
      conn
      |> redirect(to: ~p"/users/log_in")
      |> halt()
    end
  end

  ## LiveView hooks

  def on_mount(:mount_current_user, _params, session, socket) do
    {:cont, mount_current_user(socket, session)}
  end

  def on_mount(:ensure_authenticated, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if socket.assigns.current_user do
      {:cont, socket}
    else
      socket =
        socket
        |> Phoenix.LiveView.put_flash(:error, "You must log in to access this page.")
        |> Phoenix.LiveView.redirect(to: ~p"/users/log_in")

      {:halt, socket}
    end
  end

  def on_mount(:redirect_if_user_is_authenticated, _params, session, socket) do
    socket = mount_current_user(socket, session)

    if socket.assigns.current_user do
      {:halt, Phoenix.LiveView.redirect(socket, to: signed_in_path(socket.assigns.current_user))}
    else
      {:cont, socket}
    end
  end

  def on_mount(:require_pending_2fa, _params, session, socket) do
    if user_id = session["pending_2fa_user_id"] do
      user = Accounts.get_user!(user_id)
      {:cont, Phoenix.Component.assign(socket, :pending_2fa_user, user)}
    else
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/users/log_in")}
    end
  end

  defp mount_current_user(socket, session) do
    Phoenix.Component.assign_new(socket, :current_user, fn ->
      if user_token = session["user_token"] do
        Accounts.get_user_by_session_token(user_token)
      end
    end)
  end
end
