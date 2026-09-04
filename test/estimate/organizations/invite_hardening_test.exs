defmodule Estimate.Organizations.InviteHardeningTest do
  use Estimate.DataCase, async: true

  import Estimate.AccountsFixtures
  alias Estimate.Accounts.Invite
  alias Estimate.Organizations

  test "invite codes use the 32-char alphabet, are 8 long, and 1000 draws do not repeat" do
    codes = for _ <- 1..1000, do: Invite.generate_code()

    assert Enum.all?(
             codes,
             &(String.length(&1) == 8 and
                 String.match?(&1, ~r/^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]+$/))
           )

    assert length(Enum.uniq(codes)) == 1000
  end

  test "an invite cannot be accepted twice: second claim fails with :expired and creates no membership" do
    %{user: owner, organization: org} = user_with_organization_fixture()
    invite = invite_fixture(org, owner, %{email: "a@example.com"})
    a = user_fixture(%{email: "a@example.com"})
    assert {:ok, _} = Organizations.accept_invite(invite, a)

    b = user_fixture(%{email: "a@example.com2"})

    # same invite struct (stale, accepted_at still nil in memory) — claim must hit the DB predicate
    invite_stale = %{invite | email: nil}
    assert {:error, :expired} = Organizations.accept_invite(invite_stale, b)
    refute Organizations.get_user_membership(b.id, org.id)
  end

  test "invites cannot carry the owner role" do
    %{user: owner, organization: org} = user_with_organization_fixture()

    assert {:error, cs} =
             Organizations.create_invite(
               org.id,
               %{email: "x@example.com", role: "owner"},
               owner.id
             )

    assert %{role: [_]} = errors_on(cs)
    assert {:error, cs} = Organizations.create_invite_code(org.id, "owner", owner.id)
    assert %{role: [_]} = errors_on(cs)
  end

  test "update_membership_role refuses owner" do
    %{organization: org} = user_with_organization_fixture()
    member = user_fixture()
    m = membership_fixture(member, org, "member")
    assert {:error, :invalid_role} = Organizations.update_membership_role(m, "owner")
    assert Organizations.get_user_membership(member.id, org.id).role == "member"
  end
end
