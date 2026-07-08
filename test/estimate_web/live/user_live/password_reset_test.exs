defmodule EstimateWeb.UserLive.PasswordResetTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Estimate.AccountsFixtures

  # Redirects issued from a connected LiveView process (i.e. via handle_event,
  # as opposed to a redirect raised during disconnected mount) sign the flash
  # into an opaque token before handing it back to the test (see
  # Phoenix.LiveView.Channel's `copy_flash/3` -> `Utils.sign_flash/2`).
  # Decode it here so we can assert on the actual message content.
  defp decode_flash(flash) when is_binary(flash),
    do: Phoenix.LiveView.Utils.verify_flash(EstimateWeb.Endpoint, flash)

  describe "forgot password (enumeration safety)" do
    test "existing email: generic info flash + redirect to /", %{conn: conn} do
      user = user_fixture()
      {:ok, lv, _html} = live(conn, ~p"/users/reset_password")

      {:error, {:redirect, %{to: to, flash: flash}}} =
        lv |> form("#reset_password_form", user: %{email: user.email}) |> render_submit()

      flash = decode_flash(flash)
      assert to == "/"
      assert flash["info"] =~ "If your email is in our system"
    end

    test "non-existing email: IDENTICAL info flash + redirect to /", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/reset_password")

      {:error, {:redirect, %{to: to, flash: flash}}} =
        lv
        |> form("#reset_password_form", user: %{email: "nobody@example.com"})
        |> render_submit()

      flash = decode_flash(flash)
      assert to == "/"
      assert flash["info"] =~ "If your email is in our system"
    end
  end

  describe "reset password token" do
    test "invalid token redirects to / with error", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/", flash: flash}}} =
               live(conn, ~p"/users/reset_password/does-not-exist")

      assert flash["error"] =~ "invalid or it has expired"
    end

    test "valid token renders the reset form", %{conn: conn} do
      user = user_fixture()
      {:ok, token} = Estimate.Accounts.deliver_user_reset_password_instructions(user, & &1)

      {:ok, _lv, html} = live(conn, ~p"/users/reset_password/#{token}")
      assert html =~ "assword"
    end

    test "successful reset: info flash + redirect to log in", %{conn: conn} do
      user = user_fixture()
      {:ok, token} = Estimate.Accounts.deliver_user_reset_password_instructions(user, & &1)
      {:ok, lv, _html} = live(conn, ~p"/users/reset_password/#{token}")

      {:error, {:redirect, %{to: to, flash: flash}}} =
        lv
        |> form("#reset_password_form",
          user: %{password: "new_valid_password!", password_confirmation: "new_valid_password!"}
        )
        |> render_submit()

      flash = decode_flash(flash)
      assert to == "/users/log_in"
      assert flash["info"] =~ "Password reset successfully"
    end
  end
end
