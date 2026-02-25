defmodule Estimate.AccountsTest do
  use Estimate.DataCase

  alias Estimate.Accounts
  alias Estimate.Organizations
  alias Estimate.Portfolio
  alias Estimate.Portfolio.ProjectCollaborator
  import Estimate.AccountsFixtures
  import Estimate.CRMFixtures
  import Estimate.PortfolioFixtures

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

      orgs = Organizations.list_user_organizations(user.id)
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
        Organizations.create_invite(org.id, %{email: new_user.email, role: "member"}, inviter.id)

      assert invite.token != nil
      assert Accounts.Invite.valid?(invite)

      fetched = Organizations.get_valid_invite_by_token(invite.token)
      assert fetched.id == invite.id

      {:ok, %{membership: membership}} = Organizations.accept_invite(invite, new_user)
      assert membership.user_id == new_user.id
      assert membership.organization_id == org.id
    end
  end

  describe "join requests workflow" do
    test "create and approve join request" do
      %{user: admin, organization: org} = user_with_organization_fixture()
      requester = user_fixture()

      {:ok, request} = Organizations.create_join_request(requester.id, org.id)
      assert request.status == "pending"

      {:ok, %{membership: membership}} = Organizations.approve_join_request(request, admin.id)
      assert membership.user_id == requester.id
      assert membership.organization_id == org.id
    end

    test "reject join request" do
      %{user: admin, organization: org} = user_with_organization_fixture()
      requester = user_fixture()

      {:ok, request} = Organizations.create_join_request(requester.id, org.id)
      {:ok, rejected} = Organizations.reject_join_request(request, admin.id)
      assert rejected.status == "rejected"
    end
  end

  describe "delete_membership/2 with reassignment" do
    setup do
      %{user: owner, organization: org} = user_with_organization_fixture()
      member = user_fixture()
      member_membership = membership_fixture(member, org)
      customer = customer_fixture(org)
      project = project_fixture(customer, member)

      %{
        owner: owner,
        org: org,
        member: member,
        member_membership: member_membership,
        customer: customer,
        project: project
      }
    end

    test "deletes membership with empty reassignment map", ctx do
      # Add another owner so project isn't orphaned
      Portfolio.add_collaborator(ctx.project.id, ctx.owner.id, "owner")

      assert {:ok, _} = Organizations.delete_membership(ctx.member_membership, %{})
      assert Repo.get_by(Estimate.Accounts.Membership,
               user_id: ctx.member.id, organization_id: ctx.org.id) == nil
    end

    test "reassigns sole-owned project to another member", ctx do
      reassignments = %{ctx.project.id => ctx.owner.id}

      assert {:ok, _} = Organizations.delete_membership(ctx.member_membership, reassignments)

      # membership deleted
      refute Repo.get_by(Estimate.Accounts.Membership,
               user_id: ctx.member.id, organization_id: ctx.org.id)

      # old collaborator removed
      refute Repo.get_by(ProjectCollaborator,
               project_id: ctx.project.id, user_id: ctx.member.id)

      # new owner assigned
      new_collab = Repo.get_by(ProjectCollaborator,
                     project_id: ctx.project.id, user_id: ctx.owner.id)
      assert new_collab.role == "owner"
    end

    test "upgrades existing collaborator to owner on reassignment", ctx do
      # owner is already a viewer on the project
      Portfolio.add_collaborator(ctx.project.id, ctx.owner.id, "viewer")

      collab = Repo.get_by(ProjectCollaborator,
                 project_id: ctx.project.id, user_id: ctx.owner.id)
      assert collab.role == "viewer"

      reassignments = %{ctx.project.id => ctx.owner.id}
      assert {:ok, _} = Organizations.delete_membership(ctx.member_membership, reassignments)

      updated = Repo.get_by(ProjectCollaborator,
                  project_id: ctx.project.id, user_id: ctx.owner.id)
      assert updated.role == "owner"
    end

    test "reassigns multiple projects at once", ctx do
      customer2 = customer_fixture(ctx.org)
      project2 = project_fixture(customer2, ctx.member)

      reassignments = %{
        ctx.project.id => ctx.owner.id,
        project2.id => ctx.owner.id
      }

      assert {:ok, _} = Organizations.delete_membership(ctx.member_membership, reassignments)

      assert Repo.get_by(ProjectCollaborator,
               project_id: ctx.project.id, user_id: ctx.owner.id).role == "owner"
      assert Repo.get_by(ProjectCollaborator,
               project_id: project2.id, user_id: ctx.owner.id).role == "owner"
    end

    test "rejects reassignment to non-org member", ctx do
      outsider = user_fixture()
      reassignments = %{ctx.project.id => outsider.id}

      assert {:error, :invalid_member} =
               Organizations.delete_membership(ctx.member_membership, reassignments)

      # membership NOT deleted
      assert Repo.get_by(Estimate.Accounts.Membership,
               user_id: ctx.member.id, organization_id: ctx.org.id)
    end

    test "rejects reassignment to the removed user", ctx do
      reassignments = %{ctx.project.id => ctx.member.id}

      assert {:error, :self_reassignment} =
               Organizations.delete_membership(ctx.member_membership, reassignments)
    end

    test "rejects reassignment with invalid project id", ctx do
      fake_id = Ecto.UUID.generate()
      reassignments = %{fake_id => ctx.owner.id}

      assert {:error, :invalid_project} =
               Organizations.delete_membership(ctx.member_membership, reassignments)
    end

    test "rejects reassignment with project from another org", ctx do
      # project_fixture/0 creates its own user+org+customer
      other_project = project_fixture()

      reassignments = %{other_project.id => ctx.owner.id}

      assert {:error, :invalid_project} =
               Organizations.delete_membership(ctx.member_membership, reassignments)
    end
  end

  describe "list_sole_owned_projects/2" do
    setup do
      %{user: owner, organization: org} = user_with_organization_fixture()
      customer = customer_fixture(org)
      %{owner: owner, org: org, customer: customer}
    end

    test "returns projects where user is sole owner", ctx do
      project = project_fixture(ctx.customer, ctx.owner)

      results = Portfolio.list_sole_owned_projects(ctx.owner.id, ctx.org.id)
      assert [{returned, _count}] = results
      assert returned.id == project.id
    end

    test "excludes co-owned projects", ctx do
      project = project_fixture(ctx.customer, ctx.owner)
      other_member = user_fixture()
      membership_fixture(other_member, ctx.org)
      Portfolio.add_collaborator(project.id, other_member.id, "owner")

      results = Portfolio.list_sole_owned_projects(ctx.owner.id, ctx.org.id)
      assert results == []
    end

    test "returns estimation count per project", ctx do
      import Estimate.EstimationEngineFixtures

      project = project_fixture(ctx.customer, ctx.owner)
      estimation_fixture(project)
      estimation_fixture(project)

      assert [{_project, 2}] = Portfolio.list_sole_owned_projects(ctx.owner.id, ctx.org.id)
    end

    test "returns zero count when no estimations", ctx do
      _project = project_fixture(ctx.customer, ctx.owner)

      assert [{_project, 0}] = Portfolio.list_sole_owned_projects(ctx.owner.id, ctx.org.id)
    end

    test "preloads customer", ctx do
      _project = project_fixture(ctx.customer, ctx.owner)

      assert [{project, _}] = Portfolio.list_sole_owned_projects(ctx.owner.id, ctx.org.id)
      assert project.customer.id == ctx.customer.id
    end

    test "excludes projects from other orgs", ctx do
      _project = project_fixture(ctx.customer, ctx.owner)

      # project in a completely separate org
      _other_project = project_fixture()

      results = Portfolio.list_sole_owned_projects(ctx.owner.id, ctx.org.id)
      assert length(results) == 1
    end

    test "returns empty when user owns nothing", ctx do
      assert Portfolio.list_sole_owned_projects(ctx.owner.id, ctx.org.id) == []
    end
  end
end
