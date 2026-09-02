defmodule EstimateWeb.UserSessionController do
  use EstimateWeb, :controller

  alias Estimate.Accounts
  alias Estimate.Accounts.{User, Totp}
  alias Estimate.RateLimit
  alias EstimateWeb.{ClientIP, UserAuth}

  def redirect_to_login(conn, _params) do
    redirect(conn, to: ~p"/users/log_in")
  end

  def create(conn, %{"user" => user_params} = params) do
    %{"email" => email, "password" => password} = user_params
    return_to = UserAuth.safe_return_to(params["return_to"])

    with {:allow, _} <- RateLimit.check(:login_ip, ClientIP.get(conn)),
         {:allow, _} <- RateLimit.check(:login_email, email) do
      do_create(conn, email, password, user_params, return_to)
    else
      {:deny, retry_ms} ->
        conn
        |> put_flash(
          :error,
          "Too many attempts. Try again in #{RateLimit.retry_seconds(retry_ms)} seconds."
        )
        |> redirect(to: login_path(return_to))
    end
  end

  defp do_create(conn, email, password, user_params, return_to) do
    if user = Accounts.get_user_by_email_and_password(email, password) do
      conn = if return_to, do: put_session(conn, :user_return_to, return_to), else: conn

      if User.totp_enabled?(user) do
        conn
        |> UserAuth.put_pending_2fa(user, user_params)
        |> redirect(to: ~p"/users/two-factor")
      else
        conn
        |> put_flash(:info, "Welcome back!")
        |> UserAuth.log_in_user(user, user_params)
      end
    else
      conn
      |> put_flash(:error, "Invalid email or password")
      |> redirect(to: login_path(return_to))
    end
  end

  defp login_path(nil), do: ~p"/users/log_in"
  defp login_path(return_to), do: ~p"/users/log_in?#{%{return_to: return_to}}"

  def verify_totp(conn, %{"code" => code}) do
    case UserAuth.get_pending_2fa_user(conn) do
      nil ->
        conn
        |> put_flash(:error, "Session expired. Please log in again.")
        |> redirect(to: ~p"/users/log_in")

      user ->
        code = String.trim(code)

        with :ok <- attempt_allowed(user),
             {:ok, secret} <- Totp.get_decrypted_secret(user),
             true <- Totp.valid_code_or_backup?(user, secret, code),
             :ok <- replay_allowed(user, code) do
          remember_params = UserAuth.pending_2fa_remember_me_params(conn)
          RateLimit.reset(:totp_attempt, user.id)

          conn
          |> UserAuth.clear_pending_2fa()
          |> put_flash(:info, "Welcome back!")
          |> UserAuth.log_in_user(user, remember_params)
        else
          :locked ->
            lock_out(conn)

          _invalid_or_replayed ->
            conn
            |> put_flash(:error, "Invalid verification code")
            |> redirect(to: ~p"/users/two-factor")
        end
    end
  end

  # The attempt bucket is hit on every submission (valid or not): 5 failed submissions
  # per 15 minutes per pending user, counted server-side so cookie replay cannot reset
  # it; a successful login resets the counter (see RateLimit.reset/2 call above).
  defp attempt_allowed(user) do
    case RateLimit.check(:totp_attempt, user.id) do
      {:allow, _} -> :ok
      {:deny, _} -> :locked
    end
  end

  # A valid code is accepted once per 90 s window; a replay reads as an invalid code.
  defp replay_allowed(user, code) do
    case RateLimit.check(:totp_replay, {user.id, code}) do
      {:allow, _} -> :ok
      {:deny, _} -> :replayed
    end
  end

  defp lock_out(conn) do
    conn
    |> UserAuth.clear_pending_2fa()
    |> put_flash(:error, "Too many failed attempts. Please log in again.")
    |> redirect(to: ~p"/users/log_in")
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
