defmodule Estimate.Accounts.TotpTest do
  use Estimate.DataCase, async: true

  import Estimate.AccountsFixtures
  alias Estimate.Accounts.Totp

  test "verify_code accepts a fresh code once and refuses the same code again (DB-backed)" do
    %{user: user, secret: secret} = user_with_totp_fixture()
    code = valid_totp_code(secret)

    assert {:ok, user} = Totp.verify_code(user, secret, code)
    assert %DateTime{} = user.totp_last_used_at

    # reload from DB: the guard must not depend on process state
    fresh = Estimate.Accounts.get_user!(user.id)
    assert :error = Totp.verify_code(fresh, secret, code)
  end

  test "verify_code refuses garbage" do
    %{user: user, secret: secret} = user_with_totp_fixture()
    assert :error = Totp.verify_code(user, secret, "000000")
    refute Estimate.Accounts.get_user!(user.id).totp_last_used_at
  end

  test "verify_code_or_backup falls back to a single-use backup code" do
    %{user: user, secret: secret, backup_codes: [code | _]} = user_with_totp_fixture()
    assert {:ok, user} = Totp.verify_code_or_backup(user, secret, code)
    assert :error = Totp.verify_code_or_backup(user, secret, code)
  end

  test "users.totp_last_used_at exists and is nullable" do
    %{rows: [[nullable]]} =
      Repo.query!(
        "SELECT is_nullable FROM information_schema.columns WHERE table_name = 'users' AND column_name = 'totp_last_used_at'"
      )

    assert nullable == "YES"
  end
end
