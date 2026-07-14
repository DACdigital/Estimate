defmodule EstimateWeb.SettingsLive.MembersReassignmentTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Estimate.AccountsFixtures
  import Estimate.PortfolioFixtures
  import Estimate.CRMFixtures

  alias Estimate.{Organizations, Portfolio}

  defp assigns(lv), do: :sys.get_state(lv.pid).socket.assigns
  defp path(org), do: ~p"/org/#{org.id}/settings/members"

  # Owner + org; a `leaver` who solely owns 2 projects across 2 customers;
  # two eligible members (`alice`, `bob`) to reassign to.
  defp reassignment_setup(%{conn: conn}) do
    %{user: owner, organization: org} = user_with_organization_fixture()

    leaver = user_fixture(%{name: "Zoe Leaver"})
    leaver_m = membership_fixture(leaver, org, "member")
    alice = user_fixture(%{name: "Alice"})
    _ = membership_fixture(alice, org, "member")
    bob = user_fixture(%{name: "Bob"})
    _ = membership_fixture(bob, org, "member")

    cust_a = customer_fixture(org)
    cust_b = customer_fixture(org)
    proj_a = project_fixture(cust_a, leaver)
    proj_b = project_fixture(cust_b, leaver)

    conn = log_in_user(conn, owner)
    {:ok, lv, _html} = live(conn, path(org))

    %{
      lv: lv,
      org: org,
      owner: owner,
      leaver: leaver,
      leaver_m: leaver_m,
      alice: alice,
      bob: bob,
      cust_a: cust_a,
      cust_b: cust_b,
      proj_a: proj_a,
      proj_b: proj_b
    }
  end

  describe "reassignment modal & state machine" do
    setup :reassignment_setup

    test "sole-owner removal opens the reassignment modal and prefills to first eligible",
         %{lv: lv, leaver_m: leaver_m, proj_a: proj_a, proj_b: proj_b, alice: alice} do
      render_click(lv, "confirm_remove_member", %{"id" => leaver_m.id})

      a = assigns(lv)
      assert length(a.sole_owned_projects) == 2
      assert a.reassign_tab == :all
      # eligible sorted by name: "Alice" first ⇒ both projects prefilled to alice
      assert a.reassignments == %{proj_a.id => alice.id, proj_b.id => alice.id}
      # reassignment modal (not the simple confirm modal) is shown
      assert has_element?(lv, "#reassign-modal")
      refute has_element?(lv, "#remove-member-modal")
    end

    test "switch_reassign_tab accepts valid tabs and ignores invalid",
         %{lv: lv, leaver_m: leaver_m} do
      render_click(lv, "confirm_remove_member", %{"id" => leaver_m.id})

      for tab <- ~w(all per_customer per_project) do
        render_click(lv, "switch_reassign_tab", %{"tab" => tab})
        assert assigns(lv).reassign_tab == String.to_existing_atom(tab)
      end

      render_click(lv, "switch_reassign_tab", %{"tab" => "bogus"})
      # unchanged from the last valid value (:per_project)
      assert assigns(lv).reassign_tab == :per_project
    end

    test "reassign_all replaces the whole map; empty and non-eligible ids clear it",
         %{lv: lv, leaver: leaver, leaver_m: leaver_m, proj_a: proj_a, proj_b: proj_b, bob: bob} do
      render_click(lv, "confirm_remove_member", %{"id" => leaver_m.id})

      render_click(lv, "reassign_all", %{"user_id" => bob.id})
      assert assigns(lv).reassignments == %{proj_a.id => bob.id, proj_b.id => bob.id}

      render_click(lv, "reassign_all", %{"user_id" => ""})
      assert assigns(lv).reassignments == %{}

      # re-seed, then prove a non-eligible id (the leaver's own user_id — excluded
      # from eligible_members since they're the one being removed) also clears
      # rather than being accepted
      render_click(lv, "reassign_all", %{"user_id" => bob.id})
      assert assigns(lv).reassignments == %{proj_a.id => bob.id, proj_b.id => bob.id}

      render_click(lv, "reassign_all", %{"user_id" => leaver.id})
      assert assigns(lv).reassignments == %{}
    end

    test "reassign_customer merges only that customer's projects",
         %{
           lv: lv,
           leaver_m: leaver_m,
           cust_a: cust_a,
           proj_a: proj_a,
           proj_b: proj_b,
           alice: alice,
           bob: bob
         } do
      render_click(lv, "confirm_remove_member", %{"id" => leaver_m.id})
      # start from a known state: everything to bob
      render_click(lv, "reassign_all", %{"user_id" => bob.id})
      assert assigns(lv).reassignments == %{proj_a.id => bob.id, proj_b.id => bob.id}

      # move only customer A's project to alice; customer B's stays on bob —
      # proves this merges into the map rather than replacing it wholesale
      render_click(lv, "reassign_customer", %{"customer_id" => cust_a.id, "user_id" => alice.id})
      r = assigns(lv).reassignments
      assert r[proj_a.id] == alice.id
      assert r[proj_b.id] == bob.id

      # invalid member for that customer drops only that customer's projects
      render_click(lv, "reassign_customer", %{"customer_id" => cust_a.id, "user_id" => ""})
      r2 = assigns(lv).reassignments
      refute Map.has_key?(r2, proj_a.id)
      assert r2[proj_b.id] == bob.id
    end

    test "reassign_project sets/deletes a single project; unknown project is a no-op",
         %{lv: lv, leaver_m: leaver_m, proj_a: proj_a, alice: alice} do
      render_click(lv, "confirm_remove_member", %{"id" => leaver_m.id})

      render_click(lv, "reassign_project", %{"project_id" => proj_a.id, "user_id" => alice.id})
      assert assigns(lv).reassignments[proj_a.id] == alice.id

      render_click(lv, "reassign_project", %{"project_id" => proj_a.id, "user_id" => ""})
      refute Map.has_key?(assigns(lv).reassignments, proj_a.id)

      before = assigns(lv).reassignments

      render_click(lv, "reassign_project", %{
        "project_id" => Ecto.UUID.generate(),
        "user_id" => alice.id
      })

      assert assigns(lv).reassignments == before
    end

    test "remove_member with complete reassignments removes the member",
         %{
           lv: lv,
           org: org,
           leaver: leaver,
           leaver_m: leaver_m,
           alice: alice,
           proj_a: proj_a,
           proj_b: proj_b
         } do
      render_click(lv, "confirm_remove_member", %{"id" => leaver_m.id})
      render_click(lv, "reassign_all", %{"user_id" => alice.id})

      html = render_click(lv, "remove_member", %{})
      assert html =~ "Member removed"
      refute leaver.id in Enum.map(Organizations.list_organization_members(org.id), & &1.user_id)
      assert assigns(lv).removing_member == nil

      # Ownership actually transferred: alice is the sole remaining collaborator
      # on each of the leaver's previously sole-owned projects.
      assert Enum.map(Portfolio.list_collaborators(proj_a.id), & &1.user_id) == [alice.id]
      assert Enum.map(Portfolio.list_collaborators(proj_b.id), & &1.user_id) == [alice.id]
    end

    test "CHARACTERIZATION: remove_member with EMPTY reassignments (button bypass)",
         %{lv: lv, org: org, leaver: leaver, leaver_m: leaver_m, proj_a: proj_a, proj_b: proj_b} do
      render_click(lv, "confirm_remove_member", %{"id" => leaver_m.id})
      # Force an incomplete map (the disabled UI button normally prevents this,
      # but a direct event push bypasses it). Pin whatever the code does today.
      render_click(lv, "reassign_all", %{"user_id" => ""})
      assert assigns(lv).reassignments == %{}

      html = render_click(lv, "remove_member", %{})

      # PINNED BASELINE (observed): Organizations.delete_membership/2 treats an
      # empty reassignments map as trivially valid (validate_reassignments/3
      # short-circuits to :ok when map_size == 0, without checking whether the
      # removed user has any sole-owned projects). The membership is deleted and
      # the "Member removed" success flash is shown, exactly like the complete
      # path above — there is no error branch for this case.
      assert html =~ "Member removed"

      # The leaver is gone from the org...
      refute leaver.id in Enum.map(Organizations.list_organization_members(org.id), & &1.user_id)
      assert assigns(lv).removing_member == nil

      # ...but because reassignments was empty, delete_membership's
      # Ecto.Multi.delete_all wipes ALL of the leaver's ProjectCollaborator rows
      # (their only collaborator record on each sole-owned project) without
      # upserting a replacement owner. Both previously sole-owned projects are
      # left with ZERO collaborators — LATENT BUG: silent ownership orphaning.
      assert Portfolio.list_collaborators(proj_a.id) == []
      assert Portfolio.list_collaborators(proj_b.id) == []
    end
  end
end
