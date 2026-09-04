defmodule Estimate.EncryptionTest do
  use Estimate.DataCase, async: false

  import ExUnit.CaptureLog
  import Estimate.AccountsFixtures
  alias Estimate.{Encryption, Organizations, Repo}
  alias Estimate.Accounts.Totp

  @v2 Base.encode64(:crypto.strong_rand_bytes(32))

  setup do
    prev = Application.get_env(:estimate, Estimate.Encryption, [])

    on_exit(fn ->
      Application.put_env(:estimate, Estimate.Encryption, prev)
      Encryption.load_keys()
    end)

    :ok
  end

  defp set_key(nil), do: Application.put_env(:estimate, Estimate.Encryption, key: nil)
  defp set_key(k), do: Application.put_env(:estimate, Estimate.Encryption, key: k)

  test "without ENCRYPTION_KEY the ring has only v1" do
    set_key(nil)
    Encryption.load_keys()
    assert Encryption.current_version() == 1
    {:ok, n, ct, 1} = Encryption.encrypt("s3cret")
    assert {:ok, "s3cret"} = Encryption.decrypt(n, ct, 1)

    capture_log(fn ->
      assert {:error, :unknown_key_version} = Encryption.decrypt(n, ct, 2)
    end)
  end

  test "with ENCRYPTION_KEY new data is v2 and v1 data still decrypts" do
    set_key(nil)
    Encryption.load_keys()
    {:ok, n1, ct1, 1} = Encryption.encrypt("old")
    set_key(@v2)
    Encryption.load_keys()
    assert Encryption.current_version() == 2
    {:ok, n2, ct2, 2} = Encryption.encrypt("new")
    assert {:ok, "old"} = Encryption.decrypt(n1, ct1, 1)
    assert {:ok, "new"} = Encryption.decrypt(n2, ct2, 2)

    capture_log(fn ->
      assert {:error, :decrypt_failed} = Encryption.decrypt(n2, ct2, 1)
    end)
  end

  test "ENCRYPTION_KEY with surrounding whitespace (e.g. a trailing newline from a mounted secret file) still loads" do
    set_key("  #{@v2}\n")
    Encryption.load_keys()
    assert Encryption.current_version() == 2
    {:ok, n, ct, 2} = Encryption.encrypt("padded-key-secret")
    assert {:ok, "padded-key-secret"} = Encryption.decrypt(n, ct, 2)
  end

  test "TOTP secret is lazily re-encrypted to the current key on read" do
    set_key(nil)
    Encryption.load_keys()
    %{user: user, secret: secret} = user_with_totp_fixture()
    assert user.totp_key_version == 1
    set_key(@v2)
    Encryption.load_keys()
    assert {:ok, ^secret} = Totp.get_decrypted_secret(user)
    reloaded = Estimate.Accounts.get_user!(user.id)
    assert reloaded.totp_key_version == 2
    assert {:ok, ^secret} = Totp.get_decrypted_secret(reloaded)
  end

  test "org API key is lazily re-encrypted on read" do
    set_key(nil)
    Encryption.load_keys()
    %{organization: org} = user_with_organization_fixture()

    {:ok, org} =
      Organizations.update_ai_settings(org, %{"openrouter_api_key" => "sk-or-abc123456789"})

    assert org.openrouter_key_version == 1
    set_key(@v2)
    Encryption.load_keys()
    assert Organizations.get_decrypted_api_key(org) == "sk-or-abc123456789"
    assert Repo.reload!(org).openrouter_key_version == 2
  end

  test "decrypt failures are logged with the key version and reason, never plaintext or ciphertext" do
    set_key(nil)
    Encryption.load_keys()
    {:ok, n, ct, 1} = Encryption.encrypt("s3cret-value")

    log =
      capture_log(fn ->
        assert {:error, :unknown_key_version} = Encryption.decrypt(n, ct, 2)
      end)

    assert log =~ "encryption: decrypt failed"
    assert log =~ "unknown_key_version"
    assert log =~ "v2"
    refute log =~ "s3cret-value"
    refute log =~ Base.encode64(ct)

    log2 =
      capture_log(fn ->
        assert {:error, :decrypt_failed} = Encryption.decrypt(n, <<0::128>>, 1)
      end)

    assert log2 =~ "encryption: decrypt failed"
    assert log2 =~ "decrypt_failed"
    assert log2 =~ "v1"
  end

  test "key version columns exist with default 1" do
    for {t, c} <- [
          {"users", "totp_key_version"},
          {"organizations", "openrouter_key_version"},
          {"organizations", "smtp_key_version"}
        ] do
      %{rows: [[default, nullable]]} =
        Repo.query!(
          "SELECT column_default, is_nullable FROM information_schema.columns WHERE table_name = $1 AND column_name = $2",
          [t, c]
        )

      assert default == "1" and nullable == "NO"
    end
  end
end
