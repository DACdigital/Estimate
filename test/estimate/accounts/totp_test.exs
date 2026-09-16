defmodule Estimate.Accounts.TotpTest do
  # async: false — some tests below mutate the global Estimate.Encryption key
  # ring (Application env + Encryption.load_keys/0), which is process-global
  # state and must not race concurrently-running async tests.
  use Estimate.DataCase, async: false

  import Estimate.AccountsFixtures
  alias Estimate.Accounts.Totp
  alias Estimate.Encryption

  @v2 Base.encode64(:crypto.strong_rand_bytes(32))

  # Copied from test/estimate/encryption_rotation_test.exs: forces the ring
  # to v1-only at the start of each test and restores the prior config +
  # ring on exit, so a v2 key set mid-test never leaks into later tests.
  setup do
    prev = Application.get_env(:estimate, Estimate.Encryption, [])
    Application.put_env(:estimate, Estimate.Encryption, key: nil)
    Encryption.load_keys()

    on_exit(fn ->
      Application.put_env(:estimate, Estimate.Encryption, prev)
      Encryption.load_keys()
    end)

    :ok
  end

  test "verify_code accepts a fresh code once and refuses the same code again (DB-backed)" do
    %{user: user, secret: secret} = user_with_totp_fixture()
    user = backdate_totp_last_used_at(user)

    code = valid_totp_code(secret)

    assert {:ok, user} = Totp.verify_code(user, secret, code)
    assert %DateTime{} = user.totp_last_used_at

    # reload from DB: the guard must not depend on process state
    fresh = Estimate.Accounts.get_user!(user.id)
    assert :error = Totp.verify_code(fresh, secret, code)
  end

  test "enrollment code cannot be replayed at first login" do
    user = Estimate.AccountsFixtures.user_fixture()
    secret = Totp.generate_secret()
    code = valid_totp_code(secret)
    assert Totp.valid_code?(secret, code)

    {_plain, hashed} = Totp.generate_backup_codes()
    assert {:ok, user} = Totp.enable_totp(user, secret, hashed)
    assert %DateTime{} = user.totp_last_used_at

    # The same code used to enroll must not verify again at first login.
    assert :error = Totp.verify_code(user, secret, code)
  end

  test "disable_totp clears totp_last_used_at" do
    %{user: user} = user_with_totp_fixture()
    assert %DateTime{} = user.totp_last_used_at

    assert {:ok, user} = Totp.disable_totp(user)
    assert user.totp_last_used_at == nil
  end

  test "verify_code refuses garbage and does not advance totp_last_used_at" do
    %{user: user, secret: secret} = user_with_totp_fixture()
    stamped_at = user.totp_last_used_at
    assert :error = Totp.verify_code(user, secret, "000000")
    assert Estimate.Accounts.get_user!(user.id).totp_last_used_at == stamped_at
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

  test "a stale read at v1 does not clobber a secret already re-encrypted at v2 by someone else" do
    %{user: user} = user_with_totp_fixture()
    stale = user
    assert stale.totp_key_version == 1

    Application.put_env(:estimate, Estimate.Encryption, key: @v2)
    Encryption.load_keys()

    # Simulate the row having been re-encrypted at v2 in the meantime, with a
    # different secret than the one baked into `stale` (e.g. a concurrent
    # rotation or a fresh re-enrollment), so a clobber would be observable.
    fresh_secret = NimbleTOTP.secret()
    {:ok, fresh_nonce, fresh_ciphertext, 2} = Encryption.encrypt(fresh_secret)

    {1, _} =
      Repo.update_all(
        from(u in Estimate.Accounts.User, where: u.id == ^stale.id),
        set: [
          encrypted_totp_secret: fresh_ciphertext,
          totp_secret_nonce: fresh_nonce,
          totp_key_version: 2
        ]
      )

    # The read path on the stale (v1) struct still decrypts fine (v1 key
    # stays in the ring) and must not overwrite the v2 row it never saw.
    assert {:ok, _decrypted} = Totp.get_decrypted_secret(stale)

    reloaded = Estimate.Accounts.get_user!(stale.id)
    assert reloaded.totp_key_version == 2
    assert reloaded.encrypted_totp_secret == fresh_ciphertext
    assert reloaded.totp_secret_nonce == fresh_nonce
  end
end
