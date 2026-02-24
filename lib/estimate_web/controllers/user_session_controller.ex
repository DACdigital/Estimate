defmodule EstimateWeb.UserSessionController do
  use EstimateWeb, :controller

  alias Estimate.Accounts
  alias EstimateWeb.UserAuth

  def redirect_to_login(conn, _params) do
    redirect(conn, to: ~p"/users/log_in")
  end

  def create(conn, %{"user" => user_params} = params) do
    %{"email" => email, "password" => password} = user_params
    return_to = UserAuth.safe_return_to(params["return_to"])

    if user = Accounts.get_user_by_email_and_password(email, password) do
      conn
      |> then(fn c -> if return_to, do: put_session(c, :user_return_to, return_to), else: c end)
      |> put_flash(:info, "Welcome back!")
      |> UserAuth.log_in_user(user, user_params)
    else
      login_path =
        if return_to, do: ~p"/users/log_in?#{%{return_to: return_to}}", else: ~p"/users/log_in"

      conn
      |> put_flash(:error, "Invalid email or password")
      |> redirect(to: login_path)
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
