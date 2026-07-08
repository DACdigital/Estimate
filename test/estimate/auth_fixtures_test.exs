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
