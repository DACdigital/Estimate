defmodule EstimateWeb.OnboardingTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Estimate.AccountsFixtures

  describe "invite acceptance" do
    test "register-and-accept forces the invite email and joins", %{conn: conn} do
      %{user: inviter, organization: org} = user_with_organization_fixture()
      invite = invite_fixture(org, inviter, %{email: "invited@example.com", role: "member"})

      {:ok, lv, _html} = live(conn, ~p"/invites/#{invite.token}")

      # Real form has id="registration_form" (shared with the plain
      # registration form on a different page) and submits phx-submit=
      # "register_and_accept"; scope by phx-submit to be unambiguous.
      # The email input is `readonly` in the UI when the invite carries an
      # email, but only `disabled` (not `readonly`) blocks the test harness
      # from overriding a value — so typing a *different* email here proves
      # the handler really forces it back to the invite's email, rather than
      # merely leaving the pre-filled default untouched.
      {:ok, conn} =
        lv
        |> form(~s(form[phx-submit="register_and_accept"]),
          user: %{
            name: "New Person",
            email: "typed-value@example.com",
            password: "a_valid_password!"
          }
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log_in")

      # InviteLive.Accept redirects with a plain `redirect/2` (not
      # push_navigate), so follow_redirect lands on a plain conn/HTML
      # response here, not a live view — unlike the push_navigate case in
      # account_security_test.exs. Flash is carried via the signed
      # __phoenix_flash__ cookie and rendered into the /users/log_in page.
      assert html_response(conn, 200) =~ "joined"
      assert Estimate.Accounts.get_user_by_email("invited@example.com")
      refute Estimate.Accounts.get_user_by_email("typed-value@example.com")
    end

    test "signed-in user with mismatched email is rejected (flash, no redirect)", %{conn: conn} do
      %{user: inviter, organization: org} = user_with_organization_fixture()
      invite = invite_fixture(org, inviter, %{email: "someone-else@example.com", role: "member"})
      outsider = user_fixture()
      conn = log_in_user(conn, outsider)

      {:ok, lv, _html} = live(conn, ~p"/invites/#{invite.token}")

      # Real button text is "Accept Invitation" (phx-click="accept_invite").
      html = lv |> element("button", "Accept Invitation") |> render_click()

      assert html =~ "different email address"
    end

    test "invalid token renders the invalid-invitation state", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/invites/nonexistent-token")
      assert html =~ "Invalid" or html =~ "invalid"
    end
  end

  describe "registration invite-code path (non-atomic)" do
    test "bogus invite code still persists the user row", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      # The invite_code field only renders after the "I have an invite code"
      # toggle (a bare checkbox, phx-click="toggle_invite_code", no name
      # attr) is clicked — trigger it before building the form.
      lv |> element(~s(input[phx-click="toggle_invite_code"])) |> render_click()

      html =
        lv
        |> form(~s(form[phx-submit="save"]),
          user: %{name: "Reg User", email: "reg-user@example.com", password: "a_valid_password!"},
          invite_code: "BOGUS-CODE"
        )
        |> render_submit()

      assert html =~ "Invalid or expired invite code"
      assert Estimate.Accounts.get_user_by_email("reg-user@example.com")
    end
  end
end
