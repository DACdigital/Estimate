defmodule EstimateWeb.UserSessionControllerTest do
  use EstimateWeb.ConnCase, async: true

  import Estimate.AccountsFixtures

  @password valid_user_password()

  describe "POST /users/log_in" do
    test "valid credentials without TOTP logs in and redirects", %{conn: conn} do
      user = user_fixture()

      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => @password}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/organizations"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Welcome back!"
    end

    test "valid credentials WITH TOTP routes to two-factor without logging in", %{conn: conn} do
      %{user: user} = user_with_totp_fixture()

      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => @password}
        })

      refute get_session(conn, :user_token)
      assert get_session(conn, :pending_2fa_user_id) == user.id
      assert redirected_to(conn) == ~p"/users/two-factor"
    end

    test "invalid credentials re-redirect with error flash", %{conn: conn} do
      user = user_fixture()

      conn =
        post(conn, ~p"/users/log_in", %{"user" => %{"email" => user.email, "password" => "wrong"}})

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

  describe "POST /users/log_in throttling" do
    test "11th attempt for the same email within a minute is refused", %{conn: conn} do
      user = user_fixture()
      params = %{"user" => %{"email" => user.email, "password" => "wrong"}}
      for _ <- 1..10, do: post(build_conn(), ~p"/users/log_in", params)

      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => @password}
        })

      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Too many attempts"
      assert redirected_to(conn) == ~p"/users/log_in"
    end
  end

  describe "POST /users/two-factor/verify" do
    setup %{conn: conn} do
      %{user: user, secret: secret} = user_with_totp_fixture()
      # put the connection into pending-2FA state via the real login step
      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => @password}
        })

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

    test "five wrong codes lock the pending session even when the cookie is replayed", %{
      conn: conn,
      secret: secret
    } do
      # replay the SAME pre-attempt cookie every time: a client-side counter would never trip
      for _ <- 1..5 do
        c = post(conn, ~p"/users/two-factor/verify", %{"code" => "000000"})
        refute get_session(c, :user_token)
      end

      locked = post(conn, ~p"/users/two-factor/verify", %{"code" => valid_totp_code(secret)})
      refute get_session(locked, :user_token)
      refute get_session(locked, :pending_2fa_user_id)
      assert Phoenix.Flash.get(locked.assigns.flash, :error) =~ "Too many failed attempts"
      assert redirected_to(locked) == ~p"/users/log_in"
    end

    test "a valid TOTP code cannot be replayed", %{conn: conn, user: user, secret: secret} do
      code = valid_totp_code(secret)
      first = post(conn, ~p"/users/two-factor/verify", %{"code" => code})
      assert get_session(first, :user_token)

      again =
        post(build_conn(), ~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => @password}
        })
        |> post(~p"/users/two-factor/verify", %{"code" => code})

      refute get_session(again, :user_token)
      assert Phoenix.Flash.get(again.assigns.flash, :error) =~ "Invalid verification code"
    end
  end

  describe "POST /users/two-factor/verify without pending session" do
    test "redirects to log in with session-expired error", %{conn: conn} do
      conn = post(conn, ~p"/users/two-factor/verify", %{"code" => "123456"})

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Session expired"
      assert redirected_to(conn) == ~p"/users/log_in"
    end
  end

  describe "POST /users/two-factor/verify with a backup code" do
    test "a backup code logs in once and cannot be reused", %{conn: conn} do
      %{user: user, backup_codes: [code | _]} = user_with_totp_fixture()

      # 1st pending session + verify with backup code -> success
      conn1 =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => @password}
        })

      conn1 = post(conn1, ~p"/users/two-factor/verify", %{"code" => code})
      assert get_session(conn1, :user_token)

      # fresh pending session + SAME backup code -> rejected
      conn2 =
        post(build_conn(), ~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => @password}
        })

      conn2 = post(conn2, ~p"/users/two-factor/verify", %{"code" => code})
      refute get_session(conn2, :user_token)
      assert Phoenix.Flash.get(conn2.assigns.flash, :error) =~ "Invalid verification code"
    end
  end
end
