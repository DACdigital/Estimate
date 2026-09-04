defmodule Estimate.EncryptionRotationTest do
  use Estimate.DataCase, async: false

  import Estimate.AccountsFixtures
  alias Estimate.{Encryption, Organizations, Repo}
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

    assert %{users: 1, organizations: 1} = Rotation.run()
    assert Estimate.Accounts.get_user!(user.id).totp_key_version == 2
    assert Repo.reload!(org).smtp_key_version == 2

    assert {:ok, ^secret} =
             Estimate.Accounts.Totp.get_decrypted_secret(Estimate.Accounts.get_user!(user.id))

    assert Organizations.get_decrypted_smtp_password(Repo.reload!(org)) == "pw-secret"

    assert %{users: 0, organizations: 0} = Rotation.run()
  end
end
