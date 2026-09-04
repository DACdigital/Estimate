defmodule Estimate.Organizations.OwnershipTest do
  use Estimate.DataCase, async: true

  import Estimate.{AccountsFixtures, PortfolioFixtures}
  alias Estimate.Organizations

  setup do
    %{user: owner, organization: org} = user_with_organization_fixture()
    member = user_fixture()
    _ = membership_fixture(member, org, "member")
    %{owner: owner, org: org, member: member}
  end

  test "owner transfers ownership: target becomes owner, actor becomes admin", ctx do
    assert {:ok, %{new_owner: n, previous_owner: p}} =
             Organizations.transfer_ownership(ctx.org.id, ctx.owner.id, ctx.member.id)

    assert n.role == "owner" and n.user_id == ctx.member.id
    assert p.role == "admin" and p.user_id == ctx.owner.id
    assert Organizations.get_user_membership(ctx.member.id, ctx.org.id).role == "owner"
    assert Organizations.get_user_membership(ctx.owner.id, ctx.org.id).role == "admin"
  end

  test "non-owner cannot transfer; target must be a member; not to self", ctx do
    admin = user_fixture()
    _ = membership_fixture(admin, ctx.org, "admin")

    assert {:error, :not_owner} =
             Organizations.transfer_ownership(ctx.org.id, admin.id, ctx.member.id)

    stranger = user_fixture()

    assert {:error, :not_a_member} =
             Organizations.transfer_ownership(ctx.org.id, ctx.owner.id, stranger.id)

    assert {:error, :same_user} =
             Organizations.transfer_ownership(ctx.org.id, ctx.owner.id, ctx.owner.id)

    assert Organizations.get_user_membership(ctx.owner.id, ctx.org.id).role == "owner"
  end

  test "sole owner cannot leave; after transfer they can", ctx do
    assert {:error, :sole_owner} = Organizations.leave_organization(ctx.owner.id, ctx.org.id)
    {:ok, _} = Organizations.transfer_ownership(ctx.org.id, ctx.owner.id, ctx.member.id)
    assert {:ok, _} = Organizations.leave_organization(ctx.owner.id, ctx.org.id)
    refute Organizations.get_user_membership(ctx.owner.id, ctx.org.id)
  end

  test "sole project owner cannot leave", ctx do
    project = project_fixture(nil, ctx.member)
    _ = project

    assert {:error, :sole_project_owner} =
             Organizations.leave_organization(ctx.member.id, ctx.org.id)

    assert Organizations.get_user_membership(ctx.member.id, ctx.org.id)
  end

  test "member with no sole-owned projects can leave", ctx do
    assert {:ok, _} = Organizations.leave_organization(ctx.member.id, ctx.org.id)
    refute Organizations.get_user_membership(ctx.member.id, ctx.org.id)
  end

  test "non-member cannot leave", ctx do
    stranger = user_fixture()
    assert {:error, :not_a_member} = Organizations.leave_organization(stranger.id, ctx.org.id)
  end

  test "transfer refuses when the target membership vanishes before the write", ctx do
    target_membership = Organizations.get_user_membership(ctx.member.id, ctx.org.id)
    Estimate.Repo.delete!(target_membership)

    assert {:error, :not_a_member} =
             Organizations.transfer_ownership(ctx.org.id, ctx.owner.id, ctx.member.id)

    assert Organizations.get_user_membership(ctx.owner.id, ctx.org.id).role == "owner"
  end

  test "verify_transfer_counts/1 rejects any 0-row update (race guard)" do
    assert {:ok, :ok} =
             Organizations.verify_transfer_counts(%{
               new_owner: {1, nil},
               previous_owner: {1, nil}
             })

    assert {:error, :stale} =
             Organizations.verify_transfer_counts(%{
               new_owner: {0, nil},
               previous_owner: {1, nil}
             })

    assert {:error, :stale} =
             Organizations.verify_transfer_counts(%{
               new_owner: {1, nil},
               previous_owner: {0, nil}
             })

    assert {:error, :stale} =
             Organizations.verify_transfer_counts(%{
               new_owner: {0, nil},
               previous_owner: {0, nil}
             })
  end
end
