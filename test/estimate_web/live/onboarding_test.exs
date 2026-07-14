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

  describe "registration invite-code path (atomic)" do
    test "bogus invite code persists NO user (rolled back / never inserted)", %{conn: conn} do
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
      refute Estimate.Accounts.get_user_by_email("reg-user@example.com")
    end

    test "valid invite code creates the user, joins the org, and completes auto-login (phx-trigger-action POST)",
         %{conn: conn} do
      %{user: inviter, organization: org} = user_with_organization_fixture()
      {:ok, invite} = Estimate.Organizations.create_invite_code(org.id, "member", inviter.id)

      {:ok, lv, _html} = live(conn, ~p"/users/register")

      lv |> element(~s(input[phx-click="toggle_invite_code"])) |> render_click()

      form =
        lv
        |> form(~s(form[phx-submit="save"]),
          user: %{
            name: "Invite User",
            email: "invite-user@example.com",
            password: "a_valid_password!"
          },
          invite_code: invite.code
        )

      html = render_submit(form)

      assert html =~ ~s(name="user[email]")
      assert html =~ "phx-trigger-action"

      # Follow the real phx-trigger-action auto-POST through the plug
      # pipeline, exactly like the browser would.
      conn = follow_trigger_action(form, conn)

      assert redirected_to(conn)
      assert get_session(conn, :user_token)

      user = Estimate.Accounts.get_user_by_email("invite-user@example.com")
      assert user
      assert Estimate.Organizations.get_user_membership(user.id, org.id)
    end

    test "save/invite-code success branch reassigns @form instead of leaving it nil", %{
      conn: conn
    } do
      # This is the regression test for the bug: the success branch used to
      # do `assign(socket, trigger_submit: true)` without reassigning `@form`.
      # Because `mount/3` declares `temporary_assigns: [form: nil]`, the
      # socket's `@form` is reset to `nil` after *every* render (see
      # Phoenix.LiveView.Utils.clear_changed/1), so by the time the "save"
      # event runs, `socket.assigns.form` is already nil going in.
      #
      # NOTE on why this can't be caught end-to-end (via the test above):
      # LiveView's change tracking only re-renders template parts whose
      # referenced assigns are marked "changed" this cycle. The buggy branch
      # never touches `:form`, so its `<.auth_input field={@form[...]}>`
      # slots are considered unchanged and are skipped entirely in the diff —
      # the client keeps whatever `name="user[...]"` HTML it was last sent
      # (from the connected mount), even though the server's own `@form` is
      # already nil. That's why the html/phx-trigger-action assertions above
      # pass identically whether or not this fix is applied — the visible
      # DOM never actually breaks in this exact flow. The only way to observe
      # the assign itself is to inspect the socket directly.
      %{user: inviter, organization: org} = user_with_organization_fixture()
      {:ok, invite} = Estimate.Organizations.create_invite_code(org.id, "member", inviter.id)

      {:ok, lv, _html} = live(conn, ~p"/users/register")
      lv |> element(~s(input[phx-click="toggle_invite_code"])) |> render_click()

      # Pull the real, live socket out of the running LiveView process (same
      # technique as account_security_test.exs) and drive the callback
      # directly so we can inspect the assign it returns, unmasked by the
      # diff/temporary_assigns machinery described above.
      socket = :sys.get_state(lv.pid).socket

      params = %{
        "user" => %{
          "name" => "Invite User 2",
          "email" => "invite-user-2@example.com",
          "password" => "a_valid_password!"
        },
        "invite_code" => invite.code
      }

      assert {:noreply, new_socket} =
               EstimateWeb.UserLive.Registration.handle_event("save", params, socket)

      assert new_socket.assigns.trigger_submit
      assert %Phoenix.HTML.Form{} = new_socket.assigns.form

      user = Estimate.Accounts.get_user_by_email("invite-user-2@example.com")
      assert user
      assert Estimate.Organizations.get_user_membership(user.id, org.id)
    end
  end

  describe "join-request registration" do
    test "register-and-request-join creates the user + a pending request", %{conn: conn} do
      %{organization: org} = user_with_organization_fixture()

      {:ok, lv, _html} = live(conn, ~p"/organizations/#{org.id}/join")

      # JoinRequestLive.New redirects with a plain `redirect/2` (not
      # push_navigate) on both success and failure, same as InviteLive.Accept
      # above — so follow_redirect is needed to decode the signed flash
      # cookie on the /users/log_in response, rather than pattern-matching
      # the raw {:error, {:redirect, %{flash: ...}}} tuple directly.
      {:ok, conn} =
        lv
        |> form(~s(form[phx-submit="register_and_request_join"]),
          user: %{name: "Joiner", email: "joiner@example.com", password: "a_valid_password!"}
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log_in")

      assert html_response(conn, 200) =~ "pending approval"
      assert Estimate.Accounts.get_user_by_email("joiner@example.com")
    end
  end
end
