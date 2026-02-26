defmodule EstimateWeb.UserSessionController do
  use EstimateWeb, :controller

  alias Estimate.Accounts
  alias Estimate.Accounts.{User, Totp}
  alias EstimateWeb.UserAuth

  def redirect_to_login(conn, _params) do
    redirect(conn, to: ~p"/users/log_in")
  end

  def create(conn, %{"user" => user_params} = params) do
    %{"email" => email, "password" => password} = user_params
    return_to = UserAuth.safe_return_to(params["return_to"])

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
      login_path =
        if return_to, do: ~p"/users/log_in?#{%{return_to: return_to}}", else: ~p"/users/log_in"

      conn
      |> put_flash(:error, "Invalid email or password")
      |> redirect(to: login_path)
    end
  end

  def verify_totp(conn, %{"code" => code}) do
    user = UserAuth.get_pending_2fa_user(conn)

    if user do
      code = String.trim(code)

      with {:ok, secret} <- Totp.get_decrypted_secret(user),
           true <- totp_or_backup_valid?(user, secret, code) do
        remember_params = UserAuth.pending_2fa_remember_me_params(conn)

        conn
        |> UserAuth.clear_pending_2fa()
        |> put_flash(:info, "Welcome back!")
        |> UserAuth.log_in_user(user, remember_params)
      else
        _ ->
          conn
          |> put_flash(:error, "Invalid verification code")
          |> redirect(to: ~p"/users/two-factor")
      end
    else
      conn
      |> put_flash(:error, "Session expired. Please log in again.")
      |> redirect(to: ~p"/users/log_in")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end

  defp totp_or_backup_valid?(user, secret, code) do
    if Totp.valid_code?(secret, code) do
      true
    else
      case Totp.consume_backup_code(user, code) do
        {:ok, _} -> true
        _ -> false
      end
    end
  end
end
