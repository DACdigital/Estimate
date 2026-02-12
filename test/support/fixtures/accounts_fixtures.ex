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
      |> Estimate.Accounts.create_organization()

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
      Estimate.Accounts.create_membership(%{
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
end
