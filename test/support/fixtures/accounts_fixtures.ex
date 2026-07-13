defmodule Estimate.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Estimate.Accounts` context.
  """

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "hello_world!"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email(),
      name: "Test User",
      password: valid_user_password()
    })
  end

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Estimate.Accounts.register_user()

    user
  end

  def organization_fixture(attrs \\ %{}) do
    {:ok, organization} =
      attrs
      |> Enum.into(%{name: "Test Organization #{System.unique_integer()}"})
      |> Estimate.Organizations.create_organization()

    organization
  end

  def user_with_organization_fixture(user_attrs \\ %{}, org_attrs \\ %{}) do
    {:ok, result} =
      Estimate.Accounts.register_user_with_organization(
        valid_user_attributes(user_attrs),
        Enum.into(org_attrs, %{name: "Test Org #{System.unique_integer()}"})
      )

    result
  end

  def membership_fixture(user, organization, role \\ "member") do
    {:ok, membership} =
      Estimate.Organizations.create_membership(%{
        user_id: user.id,
        organization_id: organization.id,
        role: role
      })

    membership
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email, "[TOKEN]")
    token
  end

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
end
