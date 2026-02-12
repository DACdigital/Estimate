defmodule Estimate.AccountsTest do
  use Estimate.DataCase

  alias Estimate.Accounts
  import Estimate.AccountsFixtures

  describe "register_user_with_organization/2" do
    test "creates user, organization, and owner membership" do
      user_attrs = valid_user_attributes()
      org_attrs = %{name: "Test Org"}

      assert {:ok, %{user: user, organization: org, membership: membership}} =
               Accounts.register_user_with_organization(user_attrs, org_attrs)

      assert user.email == user_attrs.email
      assert user.name == user_attrs.name
      assert org.name == "Test Org"
      assert membership.role == "owner"
      assert membership.user_id == user.id
      assert membership.organization_id == org.id
    end

    test "returns error for invalid user" do
      assert {:error, :user, changeset} =
               Accounts.register_user_with_organization(%{email: "bad"}, %{name: "Org"})

      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
    end

    test "returns error for invalid organization" do
      user_attrs = valid_user_attributes()

      assert {:error, :organization, changeset} =
               Accounts.register_user_with_organization(user_attrs, %{name: ""})

      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "get_user_by_email_and_password/2" do
    test "returns user with valid credentials" do
      user = user_fixture()
      assert Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end

    test "returns nil with invalid password" do
      user = user_fixture()
      refute Accounts.get_user_by_email_and_password(user.email, "wrong")
    end

    test "returns nil with invalid email" do
      refute Accounts.get_user_by_email_and_password("wrong@example.com", "any")
    end
  end

  describe "list_user_organizations/1" do
    test "returns all organizations for a user" do
      %{user: user, organization: org} = user_with_organization_fixture()
      org2 = organization_fixture()
      membership_fixture(user, org2)

      orgs = Accounts.list_user_organizations(user.id)
      assert length(orgs) == 2
      org_ids = Enum.map(orgs, fn {o, _role} -> o.id end)
      assert org.id in org_ids
      assert org2.id in org_ids
    end
  end

  describe "invites workflow" do
    test "create and accept invite" do
      %{user: inviter, organization: org} = user_with_organization_fixture()
      new_user = user_fixture()

      {:ok, invite} =
        Accounts.create_invite(org.id, %{email: new_user.email, role: "member"}, inviter.id)

      assert invite.token != nil
      assert Accounts.Invite.valid?(invite)

      fetched = Accounts.get_valid_invite_by_token(invite.token)
      assert fetched.id == invite.id

      {:ok, %{membership: membership}} = Accounts.accept_invite(invite, new_user.id)
      assert membership.user_id == new_user.id
      assert membership.organization_id == org.id
    end
  end

  describe "join requests workflow" do
    test "create and approve join request" do
      %{user: admin, organization: org} = user_with_organization_fixture()
      requester = user_fixture()

      {:ok, request} = Accounts.create_join_request(requester.id, org.id)
      assert request.status == "pending"

      {:ok, %{membership: membership}} = Accounts.approve_join_request(request, admin.id)
      assert membership.user_id == requester.id
      assert membership.organization_id == org.id
    end

    test "reject join request" do
      %{user: admin, organization: org} = user_with_organization_fixture()
      requester = user_fixture()

      {:ok, request} = Accounts.create_join_request(requester.id, org.id)
      {:ok, rejected} = Accounts.reject_join_request(request, admin.id)
      assert rejected.status == "rejected"
    end
  end
end
