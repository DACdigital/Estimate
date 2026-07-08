defmodule EstimateWeb.UserLive.AccountSecurityTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Estimate.AccountsFixtures

  alias Estimate.Accounts.User

  describe "TOTP setup" do
    setup :register_and_log_in_user

    test "wrong verification code stays on verify step and does not enable TOTP",
         %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/account/two-factor/setup")

      # Mount starts on the :qr step; advance to :verify first (real button
      # text is "Next", phx-click="next_to_verify" — there is no
      # #totp-verify-form id in the template, so scope by phx-submit instead).
      lv |> element("button", "Next") |> render_click()

      html =
        lv
        |> form(~s(form[phx-submit="verify_code"]), %{"code" => "000000"})
        |> render_submit()

      assert html =~ "Invalid code"
      refute User.totp_enabled?(Estimate.Accounts.get_user!(user.id))
    end
  end

  describe "account settings — disable 2FA" do
    test "valid code disables 2FA", %{conn: conn} do
      %{user: user, secret: secret} = user_with_totp_fixture()
      conn = log_in_user(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/account")

      # Real button text is "Disable 2FA" (event show_disable_form); the
      # confirm form has no #disable-2fa-form id, so scope by phx-submit.
      lv |> element("button", "Disable 2FA") |> render_click()

      html =
        lv
        |> form(~s(form[phx-submit="disable_totp"]), %{"code" => valid_totp_code(secret)})
        |> render_submit()

      assert html =~ "Two-factor authentication disabled"
      refute User.totp_enabled?(Estimate.Accounts.get_user!(user.id))
    end

    test "wrong code keeps 2FA enabled with error", %{conn: conn} do
      %{user: user} = user_with_totp_fixture()
      conn = log_in_user(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/account")

      lv |> element("button", "Disable 2FA") |> render_click()

      html =
        lv
        |> form(~s(form[phx-submit="disable_totp"]), %{"code" => "000000"})
        |> render_submit()

      assert html =~ "Invalid code"
      assert User.totp_enabled?(Estimate.Accounts.get_user!(user.id))
    end
  end

  describe "account settings — change password (non-oauth)" do
    setup :register_and_log_in_user

    test "wrong current password shows field error, no navigation", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/account")

      html =
        lv
        |> form(~s(form[phx-submit="save_password"]), %{
          "password" => %{
            "current_password" => "wrong",
            "password" => "new_valid_password!",
            "password_confirmation" => "new_valid_password!"
          }
        })
        |> render_submit()

      assert html =~ "is not valid"
    end

    test "correct current password updates and navigates to log in", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/account")

      {:ok, _login_lv, login_html} =
        lv
        |> form(~s(form[phx-submit="save_password"]), %{
          "password" => %{
            "current_password" => valid_user_password(),
            "password" => "another_valid_pw!",
            "password_confirmation" => "another_valid_pw!"
          }
        })
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log_in")

      assert login_html =~ "Password updated"
    end
  end
end
