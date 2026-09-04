defmodule Estimate.EncryptionRotationTest do
  use Estimate.DataCase, async: false

  import ExUnit.CaptureLog
  import Estimate.AccountsFixtures
  alias Estimate.{Encryption, Organizations, Repo}
  alias Estimate.Accounts.User
  alias Estimate.Encryption.Rotation

  @v2 Base.encode64(:crypto.strong_rand_bytes(32))

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

  test "rotates every v1 row to the current key and is idempotent" do
    %{user: user, secret: secret} = user_with_totp_fixture()
    %{organization: org} = user_with_organization_fixture()

    {:ok, org} =
      Organizations.update_smtp_settings(org, %{
        "smtp_host" => "smtp.example.com",
        "smtp_from_email" => "a@b.co",
        "smtp_password" => "pw-secret"
      })

    Application.put_env(:estimate, Estimate.Encryption, key: @v2)
    Encryption.load_keys()

    assert %{users: 1, users_failed: 0, organizations: 1, organizations_failed: 0} =
             Rotation.run()

    assert Estimate.Accounts.get_user!(user.id).totp_key_version == 2
    assert Repo.reload!(org).smtp_key_version == 2

    assert {:ok, ^secret} =
             Estimate.Accounts.Totp.get_decrypted_secret(Estimate.Accounts.get_user!(user.id))

    assert Organizations.get_decrypted_smtp_password(Repo.reload!(org)) == "pw-secret"

    assert %{users: 0, users_failed: 0, organizations: 0, organizations_failed: 0} =
             Rotation.run()
  end

  test "a row with corrupt ciphertext is reported failed and does not stop the run" do
    %{user: good_user, secret: good_secret} = user_with_totp_fixture()
    %{user: bad_user} = user_with_totp_fixture()

    {1, _} =
      Repo.update_all(from(u in User, where: u.id == ^bad_user.id),
        set: [encrypted_totp_secret: :crypto.strong_rand_bytes(48)]
      )

    Application.put_env(:estimate, Estimate.Encryption, key: @v2)
    Encryption.load_keys()

    log =
      capture_log(fn ->
        assert %{users: 1, users_failed: 1, organizations: 0, organizations_failed: 0} =
                 Rotation.run()
      end)

    assert log =~ "rotate: could not re-encrypt users #{bad_user.id}"

    assert Estimate.Accounts.get_user!(good_user.id).totp_key_version == 2
    assert Estimate.Accounts.get_user!(bad_user.id).totp_key_version == 1

    assert {:ok, ^good_secret} =
             Estimate.Accounts.Totp.get_decrypted_secret(
               Estimate.Accounts.get_user!(good_user.id)
             )
  end
end
