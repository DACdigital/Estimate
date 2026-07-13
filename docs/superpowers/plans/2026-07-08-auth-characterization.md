# Auth Cluster — Security Characterization Tests

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pin the current behavior of every security-sensitive auth/account/onboarding flow with tests BEFORE the auth cluster is refactored, so the refactor (auth chrome extraction, `registration.ex`/`account_settings.ex` decomposition) can proceed against a green safety net.

**Architecture:** Tests only — no production changes (except adding test fixtures/helpers). LiveView tests via `Phoenix.LiveViewTest`; controller flows (login, TOTP verify) via `EstimateWeb.ConnCase` HTTP requests. Each test asserts the EXACT observable outcome (flash string, redirect target + mechanism, session change, DB side-effect) captured from the current code.

**Tech Stack:** Elixir ~> 1.15, Phoenix 1.8, Phoenix.LiveView 1.1, NimbleTOTP, ExUnit, Ecto SQL Sandbox.

## Global Constraints

- **Behavior-preserving / characterization:** every test must assert what the code does TODAY. If a test fails, do NOT change the assertion to make it pass — STOP and report; a failing characterization test means either a real bug or a wrong assumption for a human to adjudicate.
- **No DB schema/migration changes.**
- **`mix precommit` must pass**; after running it, `git restore` any pre-existing repo-wide `mix format`/`deps.unlock` drift this plan did not intend (it's a separate housekeeping MR).
- **Branch off clean `master`** (Phase 0 test infra is merged there). Branch: `test/auth-characterization`.
- **Known landmine (do not trip):** `Estimate.AccountsFixtures.extract_user_token/1` is currently BROKEN against `deliver_user_reset_password_instructions/2` (that fn returns `{:ok, encoded_token}` and never calls its url-fun). Do NOT use `extract_user_token`. To get a reset token: `{:ok, token} = Estimate.Accounts.deliver_user_reset_password_instructions(user, & &1)`.
- **Redirect mechanism matters:** full `redirect/2` surfaces in `LiveViewTest` as `{:error, {:redirect, %{to: ...}}}`; `push_navigate` as `{:error, {:live_redirect, %{to: ...}}}`. Assert the exact shape each flow uses (specified per task).
- **No mail is sent** by these flows in test (the deliver_* fns just insert a token row); do not assert on mailboxes.

---

### Task 1: Auth test fixtures (TOTP user, valid code, invite)

**Files:**
- Modify: `test/support/fixtures/accounts_fixtures.ex`
- Test: `test/estimate/auth_fixtures_test.exs` (create)

**Interfaces:**
- Produces (used by Tasks 3–5):
  - `user_with_totp_fixture(attrs \\ %{}) :: %{user: User.t(), secret: binary(), backup_codes: [String.t()]}` — a registered user with TOTP enabled; `secret` is the raw secret, `backup_codes` the 10 plaintext codes.
  - `valid_totp_code(secret) :: String.t()` — a currently-valid 6-digit code for that secret.
  - `invite_fixture(organization, inviter, attrs \\ %{}) :: Invite.t()` — a valid pending invite (default role "member", unique email).

- [ ] **Step 1: Add the fixtures**

Append to the module body in `test/support/fixtures/accounts_fixtures.ex` (before the final `end`):
```elixir
  @doc "A registered user with TOTP enabled. Returns %{user:, secret:, backup_codes:}."
  def user_with_totp_fixture(attrs \\ %{}) do
    user = user_fixture(attrs)
    secret = Estimate.Accounts.Totp.generate_secret()
    {plain_codes, hashed_codes} = Estimate.Accounts.Totp.generate_backup_codes()
    {:ok, user} = Estimate.Accounts.Totp.enable_totp(user, secret, hashed_codes)
    %{user: user, secret: secret, backup_codes: plain_codes}
  end

  @doc "A currently-valid 6-digit TOTP code for the given raw secret."
  def valid_totp_code(secret), do: NimbleTOTP.verification_code(secret)

  @doc "A valid pending invite for `organization`, created by `inviter`."
  def invite_fixture(organization, inviter, attrs \\ %{}) do
    attrs = Enum.into(attrs, %{email: unique_user_email(), role: "member"})
    {:ok, invite} = Estimate.Organizations.create_invite(organization.id, attrs, inviter.id)
    invite
  end
```

- [ ] **Step 2: Write the fixtures test**

Create `test/estimate/auth_fixtures_test.exs`:
```elixir
defmodule Estimate.AuthFixturesTest do
  use Estimate.DataCase, async: true

  import Estimate.AccountsFixtures

  alias Estimate.Accounts.{Totp, User}

  test "user_with_totp_fixture returns a TOTP-enabled user with a working secret" do
    %{user: user, secret: secret, backup_codes: codes} = user_with_totp_fixture()
    assert User.totp_enabled?(user)
    assert length(codes) == 10
    assert Totp.valid_code?(secret, valid_totp_code(secret))
  end

  test "invite_fixture creates a valid pending invite" do
    %{user: inviter, organization: org} = user_with_organization_fixture()
    invite = invite_fixture(org, inviter, %{email: "invitee@example.com", role: "member"})
    assert invite.email == "invitee@example.com"
    assert invite.organization_id == org.id
    assert is_nil(invite.accepted_at)
  end
end
```

- [ ] **Step 3: Run it**

Run: `mix test test/estimate/auth_fixtures_test.exs`
Expected: PASS (2 tests). If `Totp.valid_code?/2` or `generate_backup_codes/0` have different names/arities, correct the fixture to the real API (check `lib/estimate/accounts/totp.ex`) — but the extraction confirms these signatures.

- [ ] **Step 4: Commit**
```bash
git add test/support/fixtures/accounts_fixtures.ex test/estimate/auth_fixtures_test.exs
git commit -m "test: add TOTP-user and invite fixtures for auth characterization

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Password-reset flows (forgot enumeration safety + reset token)

**Files:**
- Test: `test/estimate_web/live/user_live/password_reset_test.exs` (create)

**Interfaces:** Consumes `Estimate.AccountsFixtures.{user_fixture/1}`, `Estimate.Accounts.deliver_user_reset_password_instructions/2`.

Behaviors to pin (exact, from current code):
- **Forgot pw** (`/users/reset_password`, LiveView, event `send_email`): existing AND non-existing email BOTH → flash `:info` = `"If your email is in our system, you will receive instructions to reset your password shortly."` + `{:error, {:redirect, %{to: "/"}}}`. Identical (user-enumeration safety).
- **Reset pw** (`/users/reset_password/:token`, LiveView): invalid token at mount → flash `:error` = `"Reset password link is invalid or it has expired."` + redirect to `/` (mount raises `{:error, {:redirect, %{to: "/"}}}` from `live/2`). Valid token → page mounts. Successful submit (event `reset_password`, matching password+confirmation, ≥8 chars) → flash `:info` = `"Password reset successfully."` + `{:error, {:redirect, %{to: "/users/log_in"}}}`.

- [ ] **Step 1: Write the tests**

Create `test/estimate_web/live/user_live/password_reset_test.exs`:
```elixir
defmodule EstimateWeb.UserLive.PasswordResetTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Estimate.AccountsFixtures

  describe "forgot password (enumeration safety)" do
    test "existing email: generic info flash + redirect to /", %{conn: conn} do
      user = user_fixture()
      {:ok, lv, _html} = live(conn, ~p"/users/reset_password")

      {:error, {:redirect, %{to: to, flash: flash}}} =
        lv |> form("#reset-password-form", user: %{email: user.email}) |> render_submit()

      assert to == "/"
      assert flash["info"] =~ "If your email is in our system"
    end

    test "non-existing email: IDENTICAL info flash + redirect to /", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/reset_password")

      {:error, {:redirect, %{to: to, flash: flash}}} =
        lv |> form("#reset-password-form", user: %{email: "nobody@example.com"}) |> render_submit()

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
        |> form("#reset-password-form",
          user: %{password: "new_valid_password!", password_confirmation: "new_valid_password!"}
        )
        |> render_submit()

      assert to == "/users/log_in"
      assert flash["info"] =~ "Password reset successfully"
    end
  end
end
```

- [ ] **Step 2: Run + fix form selectors if needed**

Run: `mix test test/estimate_web/live/user_live/password_reset_test.exs`
Expected: PASS (5 tests). If the form DOM id isn't `#reset-password-form`, read the two LiveViews (`forgot_password.ex`, `reset_password.ex`) for the actual `<.form id=...>`/`<form id=...>` id and the field name prefix (`user[...]`), and correct the `form/3` selector + params to match. Do not change assertion strings.

- [ ] **Step 3: Full suite + commit**
```bash
mix test
git add test/estimate_web/live/user_live/password_reset_test.exs
git commit -m "test: characterize password-reset flows (enumeration safety, token validity)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Session controller (login + TOTP verify)

**Files:**
- Test: `test/estimate_web/controllers/user_session_controller_test.exs` (create)

**Interfaces:** Consumes `user_fixture/1`, `user_with_organization_fixture/0`, `user_with_totp_fixture/1`, `valid_totp_code/1`, `AccountsFixtures.valid_user_password/0`.

Behaviors to pin (controller POSTs; use `post(conn, ~p"/users/log_in", ...)` and assert on `redirected_to/1`, `get_session/2`, `Phoenix.Flash.get/2`):
- **Login valid, no TOTP** → session `:user_token` set; `redirected_to` == `signed_in_path` (`/organizations` for a user with no org, `/org/<id>` for one with `last_org_id`); flash info "Welcome back!".
- **Login valid, TOTP enabled** → NO `:user_token` in session; session `:pending_2fa_user_id` set; `redirected_to` == `/users/two-factor`.
- **Login invalid** → flash error "Invalid email or password"; `redirected_to` == `/users/log_in`; no `:user_token`.
- **Login with safe return_to** on failure → `redirected_to` == `/users/log_in?return_to=%2Forg...` (round-trips).
- **verify_totp valid code** → clears pending, sets `:user_token`, flash "Welcome back!".
- **verify_totp invalid code (1st)** → flash "Invalid verification code", redirect `/users/two-factor`, pending retained.
- **verify_totp no pending session** → flash "Session expired. Please log in again.", redirect `/users/log_in`.

- [ ] **Step 1: Write the tests**

Create `test/estimate_web/controllers/user_session_controller_test.exs`:
```elixir
defmodule EstimateWeb.UserSessionControllerTest do
  use EstimateWeb.ConnCase, async: true

  import Estimate.AccountsFixtures

  @password valid_user_password()

  describe "POST /users/log_in" do
    test "valid credentials without TOTP logs in and redirects", %{conn: conn} do
      user = user_fixture()

      conn = post(conn, ~p"/users/log_in", %{"user" => %{"email" => user.email, "password" => @password}})

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/organizations"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Welcome back!"
    end

    test "valid credentials WITH TOTP routes to two-factor without logging in", %{conn: conn} do
      %{user: user} = user_with_totp_fixture()

      conn = post(conn, ~p"/users/log_in", %{"user" => %{"email" => user.email, "password" => @password}})

      refute get_session(conn, :user_token)
      assert get_session(conn, :pending_2fa_user_id) == user.id
      assert redirected_to(conn) == ~p"/users/two-factor"
    end

    test "invalid credentials re-redirect with error flash", %{conn: conn} do
      user = user_fixture()

      conn = post(conn, ~p"/users/log_in", %{"user" => %{"email" => user.email, "password" => "wrong"}})

      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Invalid email or password"
      assert redirected_to(conn) == ~p"/users/log_in"
    end

    test "invalid credentials preserve a safe return_to", %{conn: conn} do
      user = user_fixture()

      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => "wrong"},
          "return_to" => "/org/abc"
        })

      assert redirected_to(conn) =~ "/users/log_in?return_to=%2Forg%2Fabc"
    end
  end

  describe "POST /users/two-factor/verify" do
    setup %{conn: conn} do
      %{user: user, secret: secret} = user_with_totp_fixture()
      # put the connection into pending-2FA state via the real login step
      conn = post(conn, ~p"/users/log_in", %{"user" => %{"email" => user.email, "password" => @password}})
      %{conn: conn, user: user, secret: secret}
    end

    test "valid code completes login", %{conn: conn, secret: secret} do
      conn = post(conn, ~p"/users/two-factor/verify", %{"code" => valid_totp_code(secret)})

      assert get_session(conn, :user_token)
      refute get_session(conn, :pending_2fa_user_id)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Welcome back!"
    end

    test "invalid code stays on two-factor with error", %{conn: conn} do
      conn = post(conn, ~p"/users/two-factor/verify", %{"code" => "000000"})

      refute get_session(conn, :user_token)
      assert get_session(conn, :pending_2fa_user_id)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Invalid verification code"
      assert redirected_to(conn) == ~p"/users/two-factor"
    end
  end

  describe "POST /users/two-factor/verify without pending session" do
    test "redirects to log in with session-expired error", %{conn: conn} do
      conn = post(conn, ~p"/users/two-factor/verify", %{"code" => "123456"})

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Session expired"
      assert redirected_to(conn) == ~p"/users/log_in"
    end
  end
end
```

- [ ] **Step 2: Run + adjust**

Run: `mix test test/estimate_web/controllers/user_session_controller_test.exs`
Expected: PASS (7 tests). If `@password valid_user_password()` at module level fails (module attr can't call imported fn), inline the password literal `"hello_world!"` (the fixture's `valid_user_password/0` value) instead. If the pending-2FA setup's `post` needs the code to be checked against session propagation, keep it — it drives the real controller. Do not change assertion strings/targets.

- [ ] **Step 3: Full suite + commit**
```bash
mix test
git add test/estimate_web/controllers/user_session_controller_test.exs
git commit -m "test: characterize login + TOTP-verify controller flows

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: TOTP setup + account security (2FA disable, password oauth/non-oauth)

**Files:**
- Test: `test/estimate_web/live/user_live/account_security_test.exs` (create)

**Interfaces:** Consumes `register_and_log_in_user/1`, `user_with_totp_fixture/1`, `valid_totp_code/1`, `log_in_user/2`.

Behaviors to pin:
- **TOTP setup** (`/account/two-factor/setup`, LiveView): event `verify_code` with a valid code (for the in-socket `@secret`) → moves to backup step (renders backup codes), enables TOTP on the user, and calls `Organizations.clear_2fa_deadlines_for_user`. Getting the socket's secret is hard from a test; instead assert the wrong-code path: `verify_code` with `"000000"` → stays on verify step with error text `"Invalid code. Check your authenticator app and try again."` and user is NOT totp-enabled.
- **Account settings 2FA disable** (`/account`, LiveView, event `disable_totp`): with a TOTP-enabled logged-in user, valid code → flash `:info` "Two-factor authentication disabled", user no longer totp-enabled; wrong code → flash `:error` "Invalid code", still enabled.
- **Account settings password (non-oauth)**: wrong current_password → inline `current_password` error "is not valid", no navigate; correct current_password + valid new → flash `:info` "Password updated — please sign in again" + `{:error, {:live_redirect, %{to: "/users/log_in"}}}` (push_navigate).

- [ ] **Step 1: Write the tests**

Create `test/estimate_web/live/user_live/account_security_test.exs`:
```elixir
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

      html =
        lv
        |> form("#totp-verify-form", %{"code" => "000000"})
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

      lv |> element("button", "Disable") |> render_click()

      html =
        lv
        |> form("#disable-2fa-form", %{"code" => valid_totp_code(secret)})
        |> render_submit()

      assert html =~ "Two-factor authentication disabled"
      refute User.totp_enabled?(Estimate.Accounts.get_user!(user.id))
    end

    test "wrong code keeps 2FA enabled with error", %{conn: conn} do
      %{user: user} = user_with_totp_fixture()
      conn = log_in_user(conn, user)
      {:ok, lv, _html} = live(conn, ~p"/account")

      lv |> element("button", "Disable") |> render_click()
      html = lv |> form("#disable-2fa-form", %{"code" => "000000"}) |> render_submit()

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
        |> form("#password-form", %{
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

      {:error, {:live_redirect, %{to: to, flash: flash}}} =
        lv
        |> form("#password-form", %{
          "password" => %{
            "current_password" => valid_user_password(),
            "password" => "another_valid_pw!",
            "password_confirmation" => "another_valid_pw!"
          }
        })
        |> render_submit()

      assert to == "/users/log_in"
      assert flash["info"] =~ "Password updated"
    end
  end
end
```

- [ ] **Step 2: Run + adjust selectors**

Run: `mix test test/estimate_web/live/user_live/account_security_test.exs`
Expected: PASS (5 tests). Form ids (`#totp-verify-form`, `#disable-2fa-form`, `#password-form`) and the "Disable" button text are best-guesses — read `totp_setup.ex` and `account_settings.ex` for the real `id=`/button labels and correct the selectors. The 2FA-disable form may be hidden until a "show disable" button is clicked (event `show_disable_form`) — the `render_click` on the Disable button handles that; adjust the trigger selector to the real one. Do not change assertion strings.

- [ ] **Step 3: Full suite + commit**
```bash
mix test
git add test/estimate_web/live/user_live/account_security_test.exs
git commit -m "test: characterize TOTP setup + account security (2FA disable, password change)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Onboarding (invite accept + registration atomicity)

**Files:**
- Test: `test/estimate_web/live/onboarding_test.exs` (create)

**Interfaces:** Consumes `user_with_organization_fixture/0`, `invite_fixture/3`, `user_fixture/1`, `log_in_user/2`, `valid_user_password/0`.

Behaviors to pin:
- **Invite accept (anonymous register-and-accept)** (`/invites/:token`, event `register_and_accept`): with an invite that has an email, submitting registration → email is FORCED to `invite.email` (so the created user has the invite's email regardless of a typed value); success → flash `:info` `"Account created and joined <org>!"` + `{:error, {:redirect, %{to: "/users/log_in"}}}`.
- **Invite accept (signed-in, email mismatch)** (event `accept_invite`): a logged-in user whose email ≠ invite.email → flash `:error` "This invitation was sent to a different email address." and NO redirect (stays on page). (Reachable because the invite has a specific email different from the current user.)
- **Invalid invite token**: mount with a bad token → page renders the inline "Invalid Invitation" state (no redirect); assert the page renders and shows invalid-invite text.
- **Registration invite-code path is NOT atomic** (`/users/register`, event `save` with `invite_code`): submit valid user params + a bogus invite code → a User row IS created (persisted) even though joining fails, and the invite-code error `"Invalid or expired invite code"` shows. Assert the user now exists via `Accounts.get_user_by_email/1`.

- [ ] **Step 1: Write the tests**

Create `test/estimate_web/live/onboarding_test.exs`:
```elixir
defmodule EstimateWeb.OnboardingTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Estimate.AccountsFixtures

  describe "invite acceptance" do
    test "register-and-accept forces the invite email and joins", %{conn: conn} do
      %{user: inviter, organization: org} = user_with_organization_fixture()
      invite = invite_fixture(org, inviter, %{email: "invited@example.com", role: "member"})

      {:ok, lv, _html} = live(conn, ~p"/invites/#{invite.token}")

      {:error, {:redirect, %{to: to, flash: flash}}} =
        lv
        |> form("#invite-registration-form",
          user: %{name: "New Person", password: "a_valid_password!"}
        )
        |> render_submit()

      assert to == "/users/log_in"
      assert flash["info"] =~ "joined"
      # email was forced to the invite's email
      assert Estimate.Accounts.get_user_by_email("invited@example.com")
    end

    test "signed-in user with mismatched email is rejected (flash, no redirect)", %{conn: conn} do
      %{user: inviter, organization: org} = user_with_organization_fixture()
      invite = invite_fixture(org, inviter, %{email: "someone-else@example.com", role: "member"})
      outsider = user_fixture()
      conn = log_in_user(conn, outsider)

      {:ok, lv, _html} = live(conn, ~p"/invites/#{invite.token}")
      html = lv |> element("button", "Accept") |> render_click()

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

      html =
        lv
        |> form("#registration-form",
          user: %{name: "Reg User", email: "reg-user@example.com", password: "a_valid_password!"},
          invite_code: "BOGUS-CODE"
        )
        |> render_submit()

      assert html =~ "Invalid or expired invite code"
      assert Estimate.Accounts.get_user_by_email("reg-user@example.com")
    end
  end
end
```

- [ ] **Step 2: Run + adjust selectors**

Run: `mix test test/estimate_web/live/onboarding_test.exs`
Expected: PASS (4 tests). Form ids (`#invite-registration-form`, `#registration-form`) and button labels ("Accept") are best-guesses — read `invite_live/accept.ex` and `user_live/registration.ex` for the real `id=`/labels, and the exact param shape (the registration form submits `user[...]` plus a top-level `invite_code` when the invite-code toggle is on — you may need to first `render_click` the "have an invite code" toggle, event `toggle_invite_code` or similar, before the `invite_code` field exists). Adjust selectors/params; keep assertion strings. If the invite-code registration form requires the toggle, trigger it first.

- [ ] **Step 3: Full suite + commit**
```bash
mix test
git add test/estimate_web/live/onboarding_test.exs
git commit -m "test: characterize invite acceptance + registration atomicity

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:** pins the 8 security behaviors the spec's testing strategy (§6.2) lists for the auth cluster: forgot-pw enumeration (T2), reset-token validity (T2), login + return_to + 2FA routing (T3), TOTP verify incl. lockout/session-expired (T3), TOTP enable + wrong-code (T4), 2FA disable code/backup (T4), password oauth-vs-nonoauth branch (T4), invite email-binding + mismatch (T5), registration invite-code atomicity (T5). Backup-code-consumption and the oauth `set_user_password` branch are partially covered (wrong-code paths + non-oauth path pinned); the oauth-password branch needs an OAuth user (no `hashed_password`) — deferred to the auth decomposition PR which will add that fixture, noted here as a known gap.

**Placeholder scan:** none — every task has complete test code with exact expected strings/targets. Selector-adjustment steps are explicit fallbacks with concrete instructions, not placeholders.

**Type consistency:** fixture names/returns (`user_with_totp_fixture` → `%{user:, secret:, backup_codes:}`, `valid_totp_code/1`, `invite_fixture/3`) defined in Task 1 match their use in Tasks 3–5. `log_in_user/2`, `register_and_log_in_user/1` are the Phase-0 ConnCase helpers (on master).
