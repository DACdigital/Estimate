defmodule EstimateWeb.ProjectLive.ShowTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Estimate.AccountsFixtures
  import Estimate.PortfolioFixtures
  import Estimate.EstimationEngineFixtures
  import Estimate.TemplatesFixtures

  alias Estimate.Portfolio
  alias Estimate.Organizations.Currencies
  alias Estimate.EstimationEngine
  alias Estimate.EstimationEngine.JsonImport

  defp assigns(lv), do: :sys.get_state(lv.pid).socket.assigns

  # NOTE: named project_path/2, not path/2 — `path/2` collides with the
  # `Phoenix.VerifiedRoutes.path/2` macro pulled in transitively by
  # `use EstimateWeb.ConnCase` (via `use EstimateWeb, :verified_routes`), which
  # raises "expected compile-time ~p path string" at compile time for any same-arity
  # local definition. Sibling suite members_reassignment_test.exs sidesteps this with
  # an arity-1 `path/1`; ours needs (org, project), so it needs a different name.
  defp project_path(org, project), do: ~p"/org/#{org.id}/projects/#{project.id}"

  defp setup_project(_) do
    %{user: owner, organization: org} = user_with_organization_fixture()
    project = project_fixture(nil, owner)
    %{org: org, owner: owner, project: project}
  end

  # add an org-member + project collaborator of the given role
  defp add_collab(project, org, role) do
    user = user_fixture()
    _ = membership_fixture(user, org, "member")
    {:ok, collab} = Portfolio.add_collaborator(project.id, user.id, role)
    %{user: user, collaborator: collab}
  end

  describe "mount perimeter" do
    setup :setup_project

    test "project owner mounts overview", %{conn: conn, org: org, owner: owner, project: project} do
      {:ok, lv, html} = live(log_in_user(conn, owner), project_path(org, project))
      assert assigns(lv).tab == :overview
      assert assigns(lv).project.id == project.id

      assert assigns(lv).can_edit_project
      assert assigns(lv).can_delete_project
      assert assigns(lv).can_manage_collaborators
      assert html =~ project.name
    end

    test "org admin (non-collaborator) mounts with full perms", %{
      conn: conn,
      org: org,
      project: project
    } do
      admin = user_fixture()
      _ = membership_fixture(admin, org, "admin")
      {:ok, lv, _} = live(log_in_user(conn, admin), project_path(org, project))

      assert assigns(lv).can_edit_project
      assert assigns(lv).can_delete_project
      assert assigns(lv).can_manage_collaborators
    end

    test "editor collaborator: can edit, cannot delete/manage", %{
      conn: conn,
      org: org,
      project: project
    } do
      %{user: editor} = add_collab(project, org, "editor")
      {:ok, lv, _} = live(log_in_user(conn, editor), project_path(org, project))

      assert assigns(lv).can_edit_project
      refute assigns(lv).can_delete_project
      refute assigns(lv).can_manage_collaborators
    end

    test "viewer collaborator: no edit/delete/manage", %{conn: conn, org: org, project: project} do
      %{user: viewer} = add_collab(project, org, "viewer")
      {:ok, lv, _} = live(log_in_user(conn, viewer), project_path(org, project))

      refute assigns(lv).can_edit_project
      refute assigns(lv).can_delete_project
      refute assigns(lv).can_manage_collaborators
    end

    test "org member who is not a collaborator is redirected to projects",
         %{conn: conn, org: org, project: project} do
      m = user_fixture()
      _ = membership_fixture(m, org, "member")

      assert {:error, {:redirect, %{to: to}}} =
               live(log_in_user(conn, m), project_path(org, project))

      assert to =~ "/org/#{org.id}/projects"
    end

    test "non-member is redirected to /organizations", %{conn: conn, org: org, project: project} do
      stranger = user_fixture()

      assert {:error, {:redirect, %{to: "/organizations"}}} =
               live(log_in_user(conn, stranger), project_path(org, project))
    end

    test "anonymous is redirected to log in", %{conn: conn, org: org, project: project} do
      assert {:error, {:redirect, %{to: to}}} = live(conn, project_path(org, project))
      assert to =~ "/users/log_in"
    end
  end

  describe "tabs (handle_params)" do
    setup :setup_project

    test "collaborators/estimations tabs load their data", %{
      conn: conn,
      org: org,
      owner: owner,
      project: project
    } do
      {:ok, lv, _} = live(log_in_user(conn, owner), project_path(org, project))
      assert assigns(lv).tab == :overview

      {:ok, lv2, _} =
        live(log_in_user(conn, owner), ~p"/org/#{org.id}/projects/#{project.id}/collaborators")

      assert assigns(lv2).tab == :collaborators
      # owner is a collaborator (auto-added on project creation)
      assert is_list(assigns(lv2).collaborators)
      assert assigns(lv2).collaborators != []

      {:ok, lv3, _} =
        live(log_in_user(conn, owner), ~p"/org/#{org.id}/projects/#{project.id}/estimations")

      assert assigns(lv3).tab == :estimations
      assert is_list(assigns(lv3).deleted_estimations)

      {:ok, lv4, _} =
        live(log_in_user(conn, owner), ~p"/org/#{org.id}/projects/#{project.id}/estimations/new")

      assert assigns(lv4).show_new_estimation_modal == true
    end
  end

  describe "authorization gating (viewer pushing gated events)" do
    setup :setup_project

    setup %{conn: conn, org: org, project: project} do
      %{user: viewer} = add_collab(project, org, "viewer")
      {:ok, lv, _} = live(log_in_user(conn, viewer), project_path(org, project))
      %{lv: lv, project: project, org: org}
    end

    # These 7 events are each genuinely DISCRIMINATING for a viewer in this loop: with the
    # permission gate removed, the ungated path diverges from "Not authorized" — save →
    # "Project updated"; create_estimation → "Estimation created"/roles-error/redirect;
    # set_current_estimation & delete_estimation → get_estimation!/2 raises on the bogus id;
    # restore_estimation & permanent_delete_estimation → "Estimation not found" (empty list);
    # add_collaborator → silent no-op (no selected_member). So each assertion fails if the
    # gate is dropped — a real regression guard, not a tautology.
    #
    # THREE events are deliberately pulled OUT of this uniform loop, because a naive push
    # would flash "Not authorized" for the WRONG reason (green even without the permission
    # check). Each gets a dedicated, discriminating test instead:
    #   * delete_project — gate is `can_delete_project && input == project.name`; a `%{}`
    #     push leaves the confirmation input "" ≠ name, so the `&&` fails on the name half
    #     regardless of permission. Dedicated test below satisfies the name half first.
    #   * change_collaborator_role — inner branch does Enum.find(collaborators, id); on the
    #     :show tab collaborators == [] so ANY id misses → inner "Not authorized" masks the
    #     outer gate. Dedicated test (collaborators-tab describe) uses a real target id.
    #   * remove_collaborator — its `cond` checks is_nil(removing_collaborator) FIRST; a bare
    #     push is a silent no-op, never reaching the gate. No-op test below + real-gate test
    #     in the collaborators-tab describe.
    test "gated events flash Not authorized for a viewer", %{lv: lv} do
      pushes = [
        {"save", %{"project" => %{"name" => "X"}}},
        {"create_estimation", %{"estimation" => %{"name" => "E"}}},
        {"set_current_estimation", %{"id" => Ecto.UUID.generate()}},
        {"delete_estimation", %{"id" => Ecto.UUID.generate()}},
        {"restore_estimation", %{"id" => Ecto.UUID.generate()}},
        {"permanent_delete_estimation", %{"id" => Ecto.UUID.generate()}},
        {"add_collaborator", %{}}
      ]

      for {event, payload} <- pushes do
        # lv:clear-flash isolates each iteration: put_flash merges by key and is NOT
        # auto-cleared, so a prior :error would bleed through and mask an ungated event.
        render_click(lv, "lv:clear-flash", %{"key" => "error"})

        assert render_click(lv, event, payload) =~ "Not authorized",
               "expected #{event} to be authorization-gated for a viewer"
      end
    end

    test "delete_project is gated for a viewer even with a matching confirmation name",
         %{lv: lv, project: project} do
      # Satisfy the NAME half of `can_delete_project && input == project.name` first, so
      # can_delete_project (false for a viewer) is the SOLE remaining denial reason. If the
      # permission check were dropped, the delete would proceed (Portfolio.delete_project →
      # push_navigate / "Project deleted") and this assertion would fail — discriminating.
      render_click(lv, "lv:clear-flash", %{"key" => "error"})
      render_click(lv, "validate_delete_confirmation", %{"value" => project.name})

      assert render_click(lv, "delete_project", %{}) =~ "Not authorized"
    end

    test "remove_collaborator with no pending confirmation is a silent no-op for a viewer",
         %{lv: lv} do
      # remove_collaborator's `cond` checks `is_nil(socket.assigns.removing_collaborator)`
      # FIRST, before the can_manage_collaborators gate — unlike the 7 looped events. Since
      # removing_collaborator defaults to nil and this describe block never runs
      # confirm_remove_collaborator, pushing it directly never reaches the authorization
      # check at all: it just re-assigns removing_collaborator to nil, with no flash.
      assert assigns(lv).removing_collaborator == nil

      render_click(lv, "lv:clear-flash", %{"key" => "error"})
      html = render_click(lv, "remove_collaborator", %{})

      refute html =~ "Not authorized"
      assert assigns(lv).removing_collaborator == nil
    end
  end

  describe "authorization gating (viewer with a real target on the collaborators tab)" do
    setup :setup_project

    setup %{conn: conn, org: org, project: project} do
      # Mount on the :collaborators live_action so socket.assigns.collaborators is populated
      # (it's [] on :overview). This lets the gating tests use a REAL target id, so a denial
      # is attributable to the permission check — not to Enum.find/2 missing on an empty list.
      %{user: viewer} = add_collab(project, org, "viewer")

      {:ok, lv, _} =
        live(log_in_user(conn, viewer), ~p"/org/#{org.id}/projects/#{project.id}/collaborators")

      owner_collab = Enum.find(assigns(lv).collaborators, &(&1.role == "owner"))
      assert owner_collab
      %{lv: lv, owner_collab: owner_collab}
    end

    test "change_collaborator_role is gated for a viewer with a real target",
         %{lv: lv, owner_collab: owner_collab} do
      # With a real collaborator id the inner Enum.find succeeds, so "Not authorized" comes
      # from the permission layer (can_manage_collaborators false), not from a lookup miss.
      # Contrast the loop, where a bogus id on the empty :show list would flash the same
      # string via the inner nil-branch — passing for the wrong reason.
      render_click(lv, "lv:clear-flash", %{"key" => "error"})

      assert render_click(lv, "change_collaborator_role", %{
               "id" => owner_collab.id,
               "role" => "editor"
             }) =~ "Not authorized"
    end

    test "remove_collaborator is gated for a viewer confirming a real target",
         %{lv: lv, owner_collab: owner_collab} do
      # Two-step: confirm_remove_collaborator sets removing_collaborator (found via the real
      # id in the populated list), so the follow-up remove_collaborator gets PAST the is_nil
      # short-circuit and reaches the real can_remove_collaborator?/4 gate, which denies a
      # viewer removing the owner.
      render_click(lv, "confirm_remove_collaborator", %{"id" => owner_collab.id})
      assert assigns(lv).removing_collaborator.id == owner_collab.id

      render_click(lv, "lv:clear-flash", %{"key" => "error"})

      assert render_click(lv, "remove_collaborator", %{}) =~ "Not authorized"
    end
  end

  describe "authorization denial resets the pending confirm-state (behavior-identical guard)" do
    # The delete-family handlers set a "confirming" assign via a confirm_* event, then commit
    # via a GATED delete event. The OLD compound outer gate reset that assign on its
    # unauthorized else-branch; consolidating into require_can_* must preserve that reset
    # (Show.Authz.gate/4's deny_assigns). These 3 pin it: a viewer sets the confirm-state (or,
    # for delete_project, attempts to bypass it by sending the commit event directly), then the
    # gated commit must BOTH flash "Not authorized" AND clear the assign. Without the
    # deny_assigns the assign would stick at its confirmed value -- so each is discriminating.
    #
    # NOTE: confirm_delete_project is itself gated by require_can_delete/3 (Task 3, security
    # audit) -- a viewer can no longer flip deleting_project to true via the confirm event at
    # all (see "danger zone / delete project" describe block). So the delete_project case below
    # exercises the defense-in-depth path instead: a viewer sending the commit event directly,
    # skipping confirm, still gets denied and deleting_project stays false.
    setup :setup_project

    setup %{conn: conn, org: org, project: project} do
      %{user: viewer} = add_collab(project, org, "viewer")
      {:ok, lv, _} = live(log_in_user(conn, viewer), project_path(org, project))
      %{lv: lv}
    end

    test "delete_project denial (sent directly, bypassing confirm) leaves deleting_project false",
         %{
           lv: lv
         } do
      html = render_click(lv, "delete_project", %{})

      assert html =~ "Not authorized"
      assert assigns(lv).deleting_project == false
    end

    test "delete_estimation denial resets deleting_estimation to nil", %{lv: lv} do
      id = Ecto.UUID.generate()
      render_click(lv, "confirm_delete_estimation", %{"id" => id})
      assert assigns(lv).deleting_estimation == id

      html = render_click(lv, "delete_estimation", %{"id" => Ecto.UUID.generate()})

      assert html =~ "Not authorized"
      assert assigns(lv).deleting_estimation == nil
    end

    test "permanent_delete_estimation denial resets permanently_deleting to nil", %{lv: lv} do
      id = Ecto.UUID.generate()
      render_click(lv, "confirm_permanent_delete", %{"id" => id})
      assert assigns(lv).permanently_deleting == id

      html = render_click(lv, "permanent_delete_estimation", %{"id" => Ecto.UUID.generate()})

      assert html =~ "Not authorized"
      assert assigns(lv).permanently_deleting == nil
    end
  end

  describe "project details" do
    setup :setup_project

    test "validate sets form action to :validate, no flash", %{
      conn: conn,
      org: org,
      owner: owner,
      project: project
    } do
      {:ok, lv, _} = live(log_in_user(conn, owner), project_path(org, project))

      html = render_change(lv, "validate", %{"project" => %{"name" => "Draft Name"}})

      assert assigns(lv).form.source.action == :validate
      refute html =~ "Project updated"
    end

    test "save updates the project (owner)", %{
      conn: conn,
      org: org,
      owner: owner,
      project: project
    } do
      {:ok, lv, _} = live(log_in_user(conn, owner), project_path(org, project))

      html =
        lv
        |> form(~s(form[phx-submit="save"]), %{"project" => %{"name" => "Renamed Project"}})
        |> render_submit()

      assert html =~ "Project updated"
      assert Portfolio.get_project_with_roles!(project.id, org.id).name == "Renamed Project"
      # form is rebuilt from the reloaded project via a fresh, action-less changeset
      assert assigns(lv).form.source.action == nil
    end

    test "save with invalid repository_url shows a changeset error, no update", %{
      conn: conn,
      org: org,
      owner: owner,
      project: project
    } do
      {:ok, lv, _} = live(log_in_user(conn, owner), project_path(org, project))

      html = render_click(lv, "save", %{"project" => %{"repository_url" => "ftp://nope"}})

      refute html =~ "Project updated"
      # assert the field that was actually (attempted to be) set — a bad repository_url
      # (fails `^https?://`) must be rejected by update_project/2, leaving the DB value at
      # the fixture's original (nil). (The template renders bare <input>s with no inline
      # error component, so the changeset message itself is not surfaced in the HTML — the
      # DB rejection is the observable proof.)
      assert Portfolio.get_project_with_roles!(project.id, org.id).repository_url ==
               project.repository_url
    end
  end

  describe "danger zone / delete project" do
    setup :setup_project

    test "confirm, type matching name, then delete redirects", %{
      conn: conn,
      org: org,
      owner: owner,
      project: project
    } do
      {:ok, lv, _} = live(log_in_user(conn, owner), project_path(org, project))

      render_click(lv, "confirm_delete_project", %{})
      assert assigns(lv).deleting_project == true
      # freshly-created project: no estimations/tasks, just the auto-added owner collaborator
      assert assigns(lv).delete_impact == %{
               estimation_count: 0,
               task_count: 0,
               collaborator_count: 1
             }

      assert assigns(lv).delete_confirmation_input == ""

      render_click(lv, "validate_delete_confirmation", %{"value" => project.name})
      assert assigns(lv).delete_confirmation_input == project.name

      render_click(lv, "delete_project", %{})
      assert_redirect(lv, ~p"/org/#{org.id}/projects")

      # Portfolio.delete_project/1 is a hard delete (cascades via on_delete: :delete_all) —
      # prove it via a DB read, not just the flash/redirect.
      assert_raise Ecto.NoResultsError, fn ->
        Portfolio.get_project_with_roles!(project.id, org.id)
      end
    end

    test "delete refused when typed name doesn't match", %{
      conn: conn,
      org: org,
      owner: owner,
      project: project
    } do
      {:ok, lv, _} = live(log_in_user(conn, owner), project_path(org, project))

      render_click(lv, "confirm_delete_project", %{})
      render_click(lv, "validate_delete_confirmation", %{"value" => "wrong"})

      html = render_click(lv, "delete_project", %{})

      # gate is `can_delete_project && input == project.name` — owner passes the permission
      # half but fails the name half, so it denies with the same "Not authorized" flash.
      assert html =~ "Not authorized"
      assert assigns(lv).deleting_project == false
      assert Portfolio.get_project_with_roles!(project.id, org.id).name == project.name
    end

    test "cancel resets delete state", %{conn: conn, org: org, owner: owner, project: project} do
      {:ok, lv, _} = live(log_in_user(conn, owner), project_path(org, project))

      render_click(lv, "confirm_delete_project", %{})
      render_click(lv, "validate_delete_confirmation", %{"value" => "partial"})
      assert assigns(lv).delete_confirmation_input == "partial"

      render_click(lv, "cancel_delete_project", %{})
      assert assigns(lv).deleting_project == false
      assert assigns(lv).delete_confirmation_input == ""
    end

    test "viewer cannot open the delete-project confirmation", %{
      conn: conn,
      org: org,
      project: project
    } do
      %{user: viewer} = add_collab(project, org, "viewer")
      {:ok, lv, _} = live(log_in_user(conn, viewer), project_path(org, project))

      render_click(lv, "confirm_delete_project", %{})
      refute assigns(lv).deleting_project
      assert render(lv) =~ "Not authorized"
    end
  end

  describe "dashboard tab" do
    setup :setup_project

    test "set_dashboard_tab switches between the whitelisted tabs and ignores invalid", %{
      conn: conn,
      org: org,
      owner: owner,
      project: project
    } do
      {:ok, lv, _} = live(log_in_user(conn, owner), project_path(org, project))
      assert assigns(lv).dashboard_tab == :by_role

      render_click(lv, "set_dashboard_tab", %{"tab" => "by_epic"})
      assert assigns(lv).dashboard_tab == :by_epic

      render_click(lv, "set_dashboard_tab", %{"tab" => "by_priority"})
      assert assigns(lv).dashboard_tab == :by_priority

      # unmapped key (no matching case clause) → no-op, leaves the (diverged) value unchanged
      render_click(lv, "set_dashboard_tab", %{"tab" => "bogus"})
      assert assigns(lv).dashboard_tab == :by_priority

      render_click(lv, "set_dashboard_tab", %{"tab" => "by_role"})
      assert assigns(lv).dashboard_tab == :by_role
    end

    test "set_dashboard_tab handles by_epic with no current estimation (no atom crash)", %{
      conn: conn,
      org: org,
      owner: owner,
      project: project
    } do
      # bug (a) fix: set_dashboard_tab used to guard on a tab whitelist and convert via
      # String.to_existing_atom/1, which raises ArgumentError if :by_epic/:by_priority
      # hasn't been interned yet elsewhere (e.g. by EstimationDashboard rendering first) --
      # an order-dependent atom crash. The fixed handler matches against a module-attribute
      # map (@dashboard_tabs) whose values are compile-time atom literals in THIS module, so
      # they're always interned once Dashboard itself loads. No estimation is seeded here
      # (unlike the test above), so this proves the crash is gone independent of whether
      # EstimationDashboard has ever rendered.
      {:ok, lv, _} = live(log_in_user(conn, owner), project_path(org, project))

      render_click(lv, "set_dashboard_tab", %{"tab" => "by_epic"})

      assert assigns(lv).dashboard_tab == :by_epic
      assert Process.alive?(lv.pid)
    end
  end

  describe "new estimation modal state machine" do
    # Pins the STATE MACHINE only (open/close, source selection, modal-role list editing)
    # -- NOT the actual creation (create_estimation/dispatch_create, that's a separate
    # characterization slice). None of these events check can_edit_project or any other
    # permission -- only create_estimation gates on can_edit_project -- so a single owner
    # is sufficient here; there is nothing authz-related to discriminate.
    setup :setup_project

    # Pin the project to the org's main currency (seeded org has USD/EUR/GBP/PLN, USD
    # main) so `modal_currency_id == project.currency_id` is a concrete, non-nil id, and
    # so the seeded role templates' hourly rates (seeded ONLY for the org's main
    # currency -- see Accounts.seed_default_role_templates/1) are non-zero right after
    # open. That non-zero baseline is what makes the currency-switch test below
    # (switching to a currency with no template rate at all) discriminating: it proves
    # maybe_update_modal_role_rates/3 actually recomputes rates rather than leaving them.
    setup %{org: org, project: project} do
      currencies = Currencies.list_currencies(org.id)
      main_currency = Enum.find(currencies, & &1.is_main)
      other_currency = Enum.find(currencies, &(&1.id != main_currency.id))

      {:ok, project} = Portfolio.update_project(project, %{"currency_id" => main_currency.id})

      %{project: project, other_currency: other_currency}
    end

    test "open_estimation_modal RE-sets source/currency/roles after they've diverged (not just mount defaults)",
         %{conn: conn, org: org, owner: owner, project: project, other_currency: other_currency} do
      {:ok, lv, _} = live(log_in_user(conn, owner), project_path(org, project))
      templates = assigns(lv).role_templates

      # mount's init_modal_assigns/4 (show.ex:658-664) ALREADY sets estimation_source
      # "fresh", modal_currency_id project.currency_id, and modal_roles from the same
      # build_modal_roles_from_templates call -- so asserting those straight after a first
      # open proves nothing about the handler (they'd hold even if open_estimation_modal
      # dropped those assign lines). The handler's real job is RE-setting them on re-open
      # once they've diverged; that's what this pins.
      render_click(lv, "open_estimation_modal", %{})
      assert assigns(lv).show_new_estimation_modal == true

      # diverge every field open_estimation_modal is supposed to reset:
      render_click(lv, "set_estimation_source", %{"source" => "template"})
      render_change(lv, "validate_estimation", %{"currency_id" => other_currency.id})
      render_click(lv, "add_modal_role", %{})

      diverged = assigns(lv)
      assert diverged.estimation_source == "template"
      assert diverged.modal_currency_id == other_currency.id
      assert length(diverged.modal_roles) == length(templates) + 1

      # RE-open: every diverged field snaps back to the fresh baseline.
      render_click(lv, "open_estimation_modal", %{})
      a = assigns(lv)

      assert a.show_new_estimation_modal == true
      assert a.estimation_source == "fresh"
      assert a.modal_currency_id == project.currency_id

      # modal_roles rebuilt 1:1 from role_templates (the added blank role is gone) -- exact
      # name/abbreviation/template_id sequence, fresh unique integer temp_ids.
      assert length(a.modal_roles) == length(templates)
      assert Enum.map(a.modal_roles, & &1.name) == Enum.map(templates, & &1.name)
      assert Enum.map(a.modal_roles, & &1.abbreviation) == Enum.map(templates, & &1.abbreviation)
      assert Enum.map(a.modal_roles, & &1.template_id) == Enum.map(templates, & &1.id)
      assert Enum.all?(a.modal_roles, &is_integer(&1.temp_id))

      temp_ids = Enum.map(a.modal_roles, & &1.temp_id)
      assert Enum.uniq(temp_ids) == temp_ids
    end

    test "open_estimation_modal: source_estimation_id defaults to the project's existing estimation",
         %{conn: conn, org: org, owner: owner, project: project} do
      # estimations is loaded once at mount, so the fixture must exist BEFORE `live/2`.
      estimation = estimation_fixture(project)

      {:ok, lv, _} = live(log_in_user(conn, owner), project_path(org, project))
      render_click(lv, "open_estimation_modal", %{})

      assert assigns(lv).source_estimation_id == estimation.id
    end

    test "close_estimation_modal only flips the visibility flag", %{
      conn: conn,
      org: org,
      owner: owner,
      project: project
    } do
      {:ok, lv, _} = live(log_in_user(conn, owner), project_path(org, project))
      render_click(lv, "open_estimation_modal", %{})
      assert assigns(lv).show_new_estimation_modal == true

      # Move off the post-open default ("fresh") first: if close_estimation_modal is a
      # single assign in the source (as read), the non-default value must survive the
      # close untouched. Asserting against "fresh" here would be tautological -- it's
      # already "fresh" post-open, so it couldn't distinguish "left alone" from "reset".
      render_click(lv, "set_estimation_source", %{"source" => "template"})
      assert assigns(lv).estimation_source == "template"

      render_click(lv, "close_estimation_modal", %{})

      a = assigns(lv)
      refute a.show_new_estimation_modal
      assert a.estimation_source == "template"
    end

    test "set_estimation_source(copy) prefills name/source/currency from the estimation; switching away resets them",
         %{conn: conn, org: org, owner: owner, project: project, other_currency: other_currency} do
      estimation =
        estimation_fixture(project, %{"name" => "Alpha", "currency_id" => other_currency.id})

      {:ok, lv, _} = live(log_in_user(conn, owner), project_path(org, project))
      render_click(lv, "open_estimation_modal", %{})

      # Diverge source_estimation_id to nil FIRST: open_estimation_modal already sets it to
      # hd(estimations).id (== estimation.id) when an estimation exists (show.ex:824-825,838),
      # so asserting estimation.id straight after open would hold even if the copy branch
      # never touched it. Switching to "template" nulls it, making the copy transition real.
      render_click(lv, "set_estimation_source", %{"source" => "template"})
      assert assigns(lv).source_estimation_id == nil

      render_click(lv, "set_estimation_source", %{"source" => "copy"})
      a = assigns(lv)
      assert a.estimation_source == "copy"
      # nil -> estimation.id is now a transition genuinely driven by the copy branch.
      assert a.source_estimation_id == estimation.id
      assert a.estimation_form.params["name"] == "Copy of Alpha"
      # currency gets LOCKED to the source estimation's currency (other_currency),
      # overriding project.currency_id (main) that was in effect through open/template.
      assert a.modal_currency_id == other_currency.id
      assert a.modal_currency.id == other_currency.id

      render_click(lv, "set_estimation_source", %{"source" => "template"})
      a = assigns(lv)
      assert a.estimation_source == "template"
      assert a.source_estimation_id == nil
      assert a.estimation_form.params["name"] == ""

      render_click(lv, "set_estimation_source", %{"source" => "fresh"})
      assert assigns(lv).estimation_source == "fresh"
    end

    test "set_estimation_source(copy) with no estimations to copy behaves like any other source",
         %{conn: conn, org: org, owner: owner, project: project} do
      {:ok, lv, _} = live(log_in_user(conn, owner), project_path(org, project))
      render_click(lv, "open_estimation_modal", %{})

      # Diverge the form name off "" first (a valid JSON parse prefills it), so the
      # name == "" assertion below proves the copy-else branch RESET the form -- not that it
      # was merely never populated. With no estimations the `&& Enum.any?(estimations)` guard
      # is false, so copy must fall through to the else branch like any non-copy source.
      json =
        Jason.encode!(%{
          "estimation" => "Prefilled",
          "epics" => [%{"name" => "E", "tasks" => [%{"name" => "T"}]}]
        })

      render_change(lv, "validate_estimation", %{"json_input" => json})
      assert assigns(lv).estimation_form.params["name"] == "Prefilled"

      render_click(lv, "set_estimation_source", %{"source" => "copy"})

      a = assigns(lv)
      assert a.estimation_source == "copy"
      assert a.source_estimation_id == nil
      assert a.estimation_form.params["name"] == ""
    end

    test "set_estimation_source unconditionally clears any parsed/errored JSON state", %{
      conn: conn,
      org: org,
      owner: owner,
      project: project
    } do
      {:ok, lv, _} = live(log_in_user(conn, owner), project_path(org, project))
      render_click(lv, "open_estimation_modal", %{})

      render_change(lv, "validate_estimation", %{"json_input" => "{not valid json"})
      assert assigns(lv).json_error != nil

      # clear_json() runs unconditionally in set_estimation_source, regardless of which
      # source is being switched to (even re-selecting "json" wipes the parse state).
      render_click(lv, "set_estimation_source", %{"source" => "json"})

      a = assigns(lv)
      assert a.estimation_source == "json"
      assert a.json_error == nil
      assert a.json_parsed == nil
    end

    test "validate_estimation (general): edits a single modal role by temp_id, leaves the rest untouched",
         %{conn: conn, org: org, owner: owner, project: project} do
      {:ok, lv, _} = live(log_in_user(conn, owner), project_path(org, project))
      render_click(lv, "open_estimation_modal", %{})

      [role | rest] = assigns(lv).modal_roles

      render_change(lv, "validate_estimation", %{
        "roles" => %{
          to_string(role.temp_id) => %{
            "name" => "Renamed",
            "abbreviation" => "RN",
            "hourly_rate" => "42.5"
          }
        }
      })

      [updated | rest_after] = assigns(lv).modal_roles
      assert updated.name == "Renamed"
      assert updated.abbreviation == "RN"
      assert Decimal.equal?(updated.hourly_rate, Decimal.new("42.5"))
      assert rest_after == rest
    end

    test "validate_estimation (general): a currency change recomputes template-linked role rates",
         %{conn: conn, org: org, owner: owner, project: project, other_currency: other_currency} do
      {:ok, lv, _} = live(log_in_user(conn, owner), project_path(org, project))
      render_click(lv, "open_estimation_modal", %{})

      # baseline: every seeded template has a rate for the org's main currency (== project's)
      assert Enum.all?(
               assigns(lv).modal_roles,
               &(Decimal.compare(&1.hourly_rate, Decimal.new(0)) != :eq)
             )

      render_change(lv, "validate_estimation", %{"currency_id" => other_currency.id})

      a = assigns(lv)
      assert a.modal_currency_id == other_currency.id
      assert a.modal_currency.id == other_currency.id
      # no template has a rate for `other_currency` -> maybe_update_modal_role_rates/3
      # falls back to 0 for every role
      assert Enum.all?(a.modal_roles, &Decimal.equal?(&1.hourly_rate, Decimal.new(0)))
    end

    test "validate_estimation (json branch): valid JSON parses, prefills form, clears error", %{
      conn: conn,
      org: org,
      owner: owner,
      project: project
    } do
      {:ok, lv, _} = live(log_in_user(conn, owner), project_path(org, project))
      render_click(lv, "open_estimation_modal", %{})

      json =
        Jason.encode!(%{
          "estimation" => "Imported Plan",
          "description" => "from json",
          "epics" => [%{"name" => "Epic 1", "tasks" => [%{"name" => "Task 1"}]}]
        })

      render_change(lv, "validate_estimation", %{"json_input" => json})

      a = assigns(lv)
      assert a.json_error == nil
      assert a.json_parsed.estimation == "Imported Plan"
      assert a.estimation_form.params["name"] == "Imported Plan"
      assert a.estimation_form.params["description"] == "from json"
    end

    test "validate_estimation (json branch): invalid JSON sets json_error, leaves json_parsed nil",
         %{conn: conn, org: org, owner: owner, project: project} do
      {:ok, lv, _} = live(log_in_user(conn, owner), project_path(org, project))
      render_click(lv, "open_estimation_modal", %{})

      render_change(lv, "validate_estimation", %{"json_input" => "{not valid json"})

      a = assigns(lv)
      assert a.json_parsed == nil
      assert is_binary(a.json_error)
    end

    test "add_modal_role appends one blank role with a fresh temp_id", %{
      conn: conn,
      org: org,
      owner: owner,
      project: project
    } do
      {:ok, lv, _} = live(log_in_user(conn, owner), project_path(org, project))
      render_click(lv, "open_estimation_modal", %{})

      before_roles = assigns(lv).modal_roles
      render_click(lv, "add_modal_role", %{})
      after_roles = assigns(lv).modal_roles

      assert length(after_roles) == length(before_roles) + 1
      assert Enum.take(after_roles, length(before_roles)) == before_roles

      new_role = List.last(after_roles)
      assert new_role.name == ""
      assert new_role.abbreviation == ""
      assert Decimal.equal?(new_role.hourly_rate, Decimal.new(0))
      assert new_role.template_id == nil
      refute new_role.temp_id in Enum.map(before_roles, & &1.temp_id)
    end

    test "remove_modal_role drops exactly the role matching the given temp_id", %{
      conn: conn,
      org: org,
      owner: owner,
      project: project
    } do
      {:ok, lv, _} = live(log_in_user(conn, owner), project_path(org, project))
      render_click(lv, "open_estimation_modal", %{})

      before_roles = assigns(lv).modal_roles
      target = hd(before_roles)

      render_click(lv, "remove_modal_role", %{"temp-id" => to_string(target.temp_id)})

      after_roles = assigns(lv).modal_roles
      assert length(after_roles) == length(before_roles) - 1
      refute target.temp_id in Enum.map(after_roles, & &1.temp_id)
      assert after_roles == Enum.reject(before_roles, &(&1.temp_id == target.temp_id))
    end

    test "reorder_modal_roles reorders modal_roles to match the given temp-id sequence", %{
      conn: conn,
      org: org,
      owner: owner,
      project: project
    } do
      {:ok, lv, _} = live(log_in_user(conn, owner), project_path(org, project))
      render_click(lv, "open_estimation_modal", %{})

      before_roles = assigns(lv).modal_roles
      reversed_ids = before_roles |> Enum.map(& &1.temp_id) |> Enum.reverse()

      render_click(lv, "reorder_modal_roles", %{"ids" => Enum.map(reversed_ids, &to_string/1)})

      after_roles = assigns(lv).modal_roles
      assert Enum.map(after_roles, & &1.temp_id) == reversed_ids
      assert after_roles == Enum.reverse(before_roles)
    end

    test "reset_modal_roles discards edits and added roles, rebuilding fresh from templates", %{
      conn: conn,
      org: org,
      owner: owner,
      project: project
    } do
      {:ok, lv, _} = live(log_in_user(conn, owner), project_path(org, project))
      render_click(lv, "open_estimation_modal", %{})
      templates = assigns(lv).role_templates

      [first_role | _] = assigns(lv).modal_roles

      render_change(lv, "validate_estimation", %{
        "roles" => %{to_string(first_role.temp_id) => %{"name" => "Mutated"}}
      })

      render_click(lv, "add_modal_role", %{})
      assert length(assigns(lv).modal_roles) == length(templates) + 1
      assert hd(assigns(lv).modal_roles).name == "Mutated"

      render_click(lv, "reset_modal_roles", %{})

      a = assigns(lv)
      assert length(a.modal_roles) == length(templates)
      assert Enum.map(a.modal_roles, & &1.name) == Enum.map(templates, & &1.name)
      assert Enum.map(a.modal_roles, & &1.template_id) == Enum.map(templates, & &1.id)
    end
  end

  describe "create_estimation (fresh/copy/template/json sources)" do
    # The OUTER `can_edit_project` gate ("Not authorized" for a non-editor) is already pinned by
    # the "gated events" loop in "authorization gating (viewer pushing gated events)" above -- not
    # repeated here. This block pins dispatch_create/6's 4 branches plus the roles-invalid guard,
    # using an owner (can_edit_project true throughout) so every denial below comes from the
    # branch under test, not the outer permission gate.
    setup :setup_project

    test "fresh: mount's seeded role-template roles are already valid, so a plain submit creates the estimation and redirects to the estimator",
         %{conn: conn, org: org, owner: owner, project: project} do
      # user_with_organization_fixture/0 (via setup_project) seeds default role templates
      # (Accounts.seed_default_role_templates/1), and mount's init_modal_assigns/4 builds
      # modal_roles from them (show.ex:662) -- so roles_valid?/1 already passes without ever
      # opening the modal or touching modal_roles.
      before_ids =
        project.id
        |> EstimationEngine.list_estimations(project.organization_id)
        |> Enum.map(& &1.id)

      {:ok, lv, _} = live(log_in_user(conn, owner), project_path(org, project))

      render_click(lv, "create_estimation", %{
        "estimation" => %{"name" => "Fresh One"},
        "source" => "fresh"
      })

      {path, flash} = assert_redirect(lv)
      assert flash["info"] == "Estimation created"

      # Prove REAL creation, not just the flash: the project's estimation list actually grew,
      # and the redirect target names that concrete new estimation's id.
      after_list = EstimationEngine.list_estimations(project.id, project.organization_id)
      assert length(after_list) == length(before_ids) + 1
      new_estimation = Enum.find(after_list, &(&1.id not in before_ids))
      assert new_estimation

      assert path ==
               ~p"/org/#{org.id}/projects/#{project.id}/estimations/#{new_estimation.id}/estimator"
    end

    test "roles invalid: a blank modal role blocks creation, no estimation created", %{
      conn: conn,
      org: org,
      owner: owner,
      project: project
    } do
      before_count =
        project.id |> EstimationEngine.list_estimations(project.organization_id) |> length()

      {:ok, lv, _} = live(log_in_user(conn, owner), project_path(org, project))
      # mount's modal_roles start valid (from seeded templates, see the "fresh" test above) --
      # add_modal_role appends a genuinely blank %{name: "", abbreviation: ""} role, so
      # roles_valid?/1 fails for a REAL reason, not a vacuous empty-list pass.
      render_click(lv, "add_modal_role", %{})
      assert Enum.any?(assigns(lv).modal_roles, &(&1.name == ""))

      html =
        render_click(lv, "create_estimation", %{
          "estimation" => %{"name" => "Should Not Save"},
          "source" => "fresh"
        })

      assert html =~ "All roles must have a name and abbreviation"

      assert project.id |> EstimationEngine.list_estimations(project.organization_id) |> length() ==
               before_count
    end

    test "copy: copies an existing estimation in the SAME project, flashes Estimation copied, and redirects",
         %{conn: conn, org: org, owner: owner, project: project} do
      source_est = estimation_fixture(project)

      before_ids =
        project.id
        |> EstimationEngine.list_estimations(project.organization_id)
        |> Enum.map(& &1.id)

      {:ok, lv, _} = live(log_in_user(conn, owner), project_path(org, project))

      render_click(lv, "create_estimation", %{
        "estimation" => %{"name" => "Copy of Thing"},
        "source" => "copy",
        "source_estimation_id" => source_est.id
      })

      {path, flash} = assert_redirect(lv)
      assert flash["info"] == "Estimation copied"

      after_list = EstimationEngine.list_estimations(project.id, project.organization_id)
      assert length(after_list) == length(before_ids) + 1
      new_estimation = Enum.find(after_list, &(&1.id not in before_ids))
      assert new_estimation

      assert path ==
               ~p"/org/#{org.id}/projects/#{project.id}/estimations/#{new_estimation.id}/estimator"
    end

    test "copy: bypasses the modal roles-valid check entirely (a blank modal role does not block it)",
         %{conn: conn, org: org, owner: owner, project: project} do
      # create_estimation's guard is `source != "copy" && !roles_valid?(...)` (show.ex:952) --
      # for "copy" the whole condition short-circuits to false regardless of modal_roles, since
      # copy takes its roles from the SOURCE estimation, not the modal list.
      source_est = estimation_fixture(project)

      before_ids =
        project.id
        |> EstimationEngine.list_estimations(project.organization_id)
        |> Enum.map(& &1.id)

      {:ok, lv, _} = live(log_in_user(conn, owner), project_path(org, project))
      render_click(lv, "add_modal_role", %{})
      assert Enum.any?(assigns(lv).modal_roles, &(&1.name == ""))

      render_click(lv, "create_estimation", %{
        "estimation" => %{"name" => "Copy Despite Blank Role"},
        "source" => "copy",
        "source_estimation_id" => source_est.id
      })

      {_path, flash} = assert_redirect(lv)
      assert flash["info"] == "Estimation copied"

      after_list = EstimationEngine.list_estimations(project.id, project.organization_id)
      assert length(after_list) == length(before_ids) + 1
    end

    test "copy: a same-org estimation from a DIFFERENT project is rejected and nothing is created",
         %{conn: conn, org: org, owner: owner, project: project} do
      # dispatch_create("copy", ...) guards `source_estimation.project_id == project.id`,
      # returning {:error, :unauthorized} otherwise (show.ex:1403-1404) -- but create_estimation's
      # `case result do` (show.ex:960-979) does NOT special-case that reason: EVERY {:error, _}
      # (bad params, :no_json, :unauthorized, a changeset error...) falls into the SAME generic
      # "Could not create estimation" flash (show.ex:977-978). There is no dedicated "Not
      # authorized" text for this guard -- pinning the real string, not the one a cursory read of
      # dispatch_create alone would suggest.
      #
      # A cross-ORGANIZATION source_estimation_id is deliberately NOT used here: dispatch_create
      # looks the source up via EstimationEngine.get_estimation!(source_estimation_id, org_id)
      # scoped to the CURRENT session's org_id (show.ex:1401), so a foreign-org id never resolves
      # and raises Ecto.NoResultsError instead of returning {:error, :unauthorized} -- an uncaught
      # crash, not a flash. That's a separate, pre-existing latent gap (see task report), and
      # asserting a crash here would be a lookup-miss, not the project_id guard. A SAME-org
      # sibling project is what actually reaches that guard.
      other_project = project_fixture(nil, owner)
      sibling_est = estimation_fixture(other_project)

      before_count =
        project.id |> EstimationEngine.list_estimations(project.organization_id) |> length()

      {:ok, lv, _} = live(log_in_user(conn, owner), project_path(org, project))

      html =
        render_click(lv, "create_estimation", %{
          "estimation" => %{"name" => "Copy Attempt"},
          "source" => "copy",
          "source_estimation_id" => sibling_est.id
        })

      assert html =~ "Could not create estimation"
      refute html =~ "Estimation copied"

      assert project.id |> EstimationEngine.list_estimations(project.organization_id) |> length() ==
               before_count
    end

    test "template: creates from an estimation template, flashes Estimation created, and redirects",
         %{conn: conn, org: org, owner: owner, project: project} do
      template = template_fixture(org)

      before_ids =
        project.id
        |> EstimationEngine.list_estimations(project.organization_id)
        |> Enum.map(& &1.id)

      {:ok, lv, _} = live(log_in_user(conn, owner), project_path(org, project))

      render_click(lv, "create_estimation", %{
        "estimation" => %{"name" => "From Template"},
        "source" => "template",
        "estimation_template_id" => template.id
      })

      {path, flash} = assert_redirect(lv)
      assert flash["info"] == "Estimation created"

      after_list = EstimationEngine.list_estimations(project.id, project.organization_id)
      assert length(after_list) == length(before_ids) + 1
      new_estimation = Enum.find(after_list, &(&1.id not in before_ids))
      assert new_estimation

      assert path ==
               ~p"/org/#{org.id}/projects/#{project.id}/estimations/#{new_estimation.id}/estimator"
    end

    test "json: creates from parsed JSON once validate_estimation has set json_parsed", %{
      conn: conn,
      org: org,
      owner: owner,
      project: project
    } do
      before_ids =
        project.id
        |> EstimationEngine.list_estimations(project.organization_id)
        |> Enum.map(& &1.id)

      {:ok, lv, _} = live(log_in_user(conn, owner), project_path(org, project))

      json =
        Jason.encode!(%{
          "estimation" => "From JSON",
          "epics" => [%{"name" => "E1", "tasks" => [%{"name" => "T1"}]}]
        })

      render_change(lv, "validate_estimation", %{"json_input" => json})
      assert assigns(lv).json_parsed

      render_click(lv, "create_estimation", %{
        "estimation" => %{"name" => "From JSON"},
        "source" => "json"
      })

      {path, flash} = assert_redirect(lv)
      assert flash["info"] == "Estimation created"

      after_list = EstimationEngine.list_estimations(project.id, project.organization_id)
      assert length(after_list) == length(before_ids) + 1
      new_estimation = Enum.find(after_list, &(&1.id not in before_ids))
      assert new_estimation

      assert path ==
               ~p"/org/#{org.id}/projects/#{project.id}/estimations/#{new_estimation.id}/estimator"
    end

    test "json: source without a parsed json (the :no_json guard) creates nothing", %{
      conn: conn,
      org: org,
      owner: owner,
      project: project
    } do
      # json_parsed defaults to nil at mount (init_json_assigns) and nothing here sets it, so
      # dispatch_create("json", ...) hits its `nil -> {:error, :no_json}` clause (show.ex:1427) --
      # which, like the copy project_id guard above, surfaces only as the generic
      # "Could not create estimation" flash.
      before_count =
        project.id |> EstimationEngine.list_estimations(project.organization_id) |> length()

      {:ok, lv, _} = live(log_in_user(conn, owner), project_path(org, project))

      html =
        render_click(lv, "create_estimation", %{
          "estimation" => %{"name" => "No Json"},
          "source" => "json"
        })

      assert html =~ "Could not create estimation"

      assert project.id |> EstimationEngine.list_estimations(project.organization_id) |> length() ==
               before_count
    end
  end

  describe "json import events (upload/download/agent prompt)" do
    setup :setup_project

    test "json_file_uploaded parses the content and prefills the estimation form", %{
      conn: conn,
      org: org,
      owner: owner,
      project: project
    } do
      {:ok, lv, _} = live(log_in_user(conn, owner), project_path(org, project))

      json =
        Jason.encode!(%{
          "estimation" => "Uploaded",
          "description" => "via upload",
          "epics" => [%{"name" => "E1", "tasks" => [%{"name" => "T1"}]}]
        })

      render_click(lv, "json_file_uploaded", %{"content" => json})

      a = assigns(lv)
      assert a.json_error == nil
      assert a.json_parsed.estimation == "Uploaded"
      assert a.estimation_form.params["name"] == "Uploaded"
      assert a.estimation_form.params["description"] == "via upload"
    end

    test "download_json_schema pushes the example schema as a download_file event", %{
      conn: conn,
      org: org,
      owner: owner,
      project: project
    } do
      {:ok, lv, _} = live(log_in_user(conn, owner), project_path(org, project))

      render_click(lv, "download_json_schema", %{})

      assert_push_event(lv, "download_file", payload)
      assert payload.filename == "estimation-schema.json"
      assert payload.content_type == "application/json"
      assert payload.content == JsonImport.example_schema()
    end

    test "copy_agent_prompt pushes the real agent prompt to the clipboard and flashes confirmation",
         %{conn: conn, org: org, owner: owner, project: project} do
      {:ok, lv, _} = live(log_in_user(conn, owner), project_path(org, project))

      html = render_click(lv, "copy_agent_prompt", %{})

      assert_push_event(lv, "copy_to_clipboard", payload)
      assert payload.text == JsonImport.agent_prompt()
      assert html =~ "Agent prompt copied"
    end
  end

  describe "estimation list (set current / delete)" do
    # set_current_estimation's {:error, _} branch ("Could not set current estimation",
    # show.ex:1016-1017) is NOT pinned below. EstimationEngine.set_current_estimation/1
    # (estimations.ex:143-162) can only fail if Estimation.changeset/2 rejects :name or
    # :project_id -- but the handler always re-fetches the target via get_estimation!/2
    # first (show.ex:1001), so it's always an already-valid, persisted row with both fields
    # non-nil; the changeset call here only casts :is_current. The multi's unset-others-then
    # -set-target ordering also can never collide with the partial unique index on
    # (project_id) where is_current (migration 20260319080827_fix_unique_current_...).
    # There is no way to reach that branch through the LiveView without corrupting a
    # persisted row outside the public API -- it is dead code under normal operation.
    setup :setup_project

    setup %{conn: conn, org: org, owner: owner, project: project} do
      # estimation_fixture/1's FIRST estimation for a project auto-becomes is_current
      # (Estimations.prepare_estimation_attrs/1, estimations.ex:241-245) -- the second does
      # not, giving a genuine non-current target to delete/switch to.
      est1 = estimation_fixture(project)
      est2 = estimation_fixture(project)
      assert est1.is_current
      refute est2.is_current

      {:ok, lv, _} = live(log_in_user(conn, owner), project_path(org, project))
      %{lv: lv, est1: est1, est2: est2}
    end

    test "set_current_estimation switches current_estimation and flips is_current in the DB, with no flash",
         %{lv: lv, org: org, est1: est1, est2: est2} do
      # baseline BEFORE acting: mount's own current-estimation lookup (show.ex:623-627)
      # already reports est1 -- confirming that here first proves the transition below is
      # driven by the handler, not just an echo of what mount already assigned.
      assert assigns(lv).current_estimation.id == est1.id

      render_click(lv, "set_current_estimation", %{"id" => est2.id})

      # show.ex:1006-1014's {:ok, _} branch only assigns :estimations/:current_estimation --
      # no put_flash call at all (confirmed by reading the source). Pin that absence via the
      # flash assign directly, not a guessed `refute html =~ "..."`.
      assert assigns(lv).flash == %{}

      assert assigns(lv).current_estimation.id == est2.id

      # DB proof, not assign-only: the multi unsets every OTHER current row for the project
      # before setting the target -- confirm both sides actually flipped.
      assert EstimationEngine.get_estimation!(est2.id, org.id).is_current
      refute EstimationEngine.get_estimation!(est1.id, org.id).is_current

      assert Enum.find(assigns(lv).estimations, &(&1.id == est2.id)).is_current
    end

    test "set_current_estimation: a same-org DIFFERENT-project id is Not authorized, current_estimation unchanged",
         %{lv: lv, org: org, owner: owner, est1: est1} do
      # same-org sibling project (NOT a cross-ORG id -- that would raise inside
      # get_estimation!/2 before ever reaching the project_id guard, per the task's
      # ambiguity resolution -- a crash isn't what this guard test is pinning).
      other_project = project_fixture(nil, owner)
      foreign_est = estimation_fixture(other_project)

      html = render_click(lv, "set_current_estimation", %{"id" => foreign_est.id})

      assert html =~ "Not authorized"
      # unchanged -- meaningful because the test above already proves this same handler DOES
      # mutate current_estimation when the guard doesn't block it.
      assert assigns(lv).current_estimation.id == est1.id
      assert EstimationEngine.get_estimation!(est1.id, org.id).is_current
    end

    test "confirm_delete_estimation sets deleting_estimation; cancel_delete_estimation clears it",
         %{lv: lv, est2: est2} do
      assert assigns(lv).deleting_estimation == nil

      render_click(lv, "confirm_delete_estimation", %{"id" => est2.id})
      assert assigns(lv).deleting_estimation == est2.id

      render_click(lv, "cancel_delete_estimation", %{})
      assert assigns(lv).deleting_estimation == nil
    end

    test "delete_estimation: blocked when targeting the CURRENT estimation, deleting_estimation still resets",
         %{lv: lv, org: org, project: project, est1: est1} do
      # diverge deleting_estimation off nil FIRST so the reset this branch performs
      # (show.ex:1046-1049) is a real transition, not an unchanged default.
      render_click(lv, "confirm_delete_estimation", %{"id" => est1.id})
      assert assigns(lv).deleting_estimation == est1.id

      html = render_click(lv, "delete_estimation", %{"id" => est1.id})

      assert html =~ "Cannot delete current estimation"
      assert assigns(lv).deleting_estimation == nil

      live_ids =
        project.id
        |> EstimationEngine.list_estimations(project.organization_id)
        |> Enum.map(& &1.id)

      trashed_ids = project.id |> EstimationEngine.list_deleted_estimations() |> Enum.map(& &1.id)
      assert est1.id in live_ids
      refute est1.id in trashed_ids
      assert EstimationEngine.get_estimation!(est1.id, org.id).is_current
    end

    test "delete_estimation: a same-org DIFFERENT-project id is Not authorized, nothing touched",
         %{lv: lv, owner: owner, est1: est1} do
      other_project = project_fixture(nil, owner)
      foreign_est = estimation_fixture(other_project)

      render_click(lv, "confirm_delete_estimation", %{"id" => est1.id})
      assert assigns(lv).deleting_estimation == est1.id

      html = render_click(lv, "delete_estimation", %{"id" => foreign_est.id})

      assert html =~ "Not authorized"
      assert assigns(lv).deleting_estimation == nil

      foreign_live_ids =
        other_project.id
        |> EstimationEngine.list_estimations(other_project.organization_id)
        |> Enum.map(& &1.id)

      assert foreign_est.id in foreign_live_ids
    end

    test "delete_estimation: ok moves a non-current estimation to trash", %{
      lv: lv,
      project: project,
      est2: est2
    } do
      render_click(lv, "confirm_delete_estimation", %{"id" => est2.id})
      assert assigns(lv).deleting_estimation == est2.id

      html = render_click(lv, "delete_estimation", %{"id" => est2.id})

      assert html =~ "Estimation moved to trash"
      assert assigns(lv).deleting_estimation == nil

      live_ids =
        project.id
        |> EstimationEngine.list_estimations(project.organization_id)
        |> Enum.map(& &1.id)

      trashed_ids = project.id |> EstimationEngine.list_deleted_estimations() |> Enum.map(& &1.id)
      refute est2.id in live_ids
      assert est2.id in trashed_ids

      refute est2.id in Enum.map(assigns(lv).estimations, & &1.id)
      assert est2.id in Enum.map(assigns(lv).deleted_estimations, & &1.id)
    end
  end

  describe "trash (toggle / restore / permanent delete)" do
    setup :setup_project

    setup %{conn: conn, org: org, owner: owner, project: project} do
      est_current = estimation_fixture(project)
      est_trashed = estimation_fixture(project)
      assert est_current.is_current
      refute est_trashed.is_current

      {:ok, _} = EstimationEngine.soft_delete_estimation(est_trashed)

      # mount the :estimations live_action so apply_action/3 (show.ex:719-726) actually
      # populates deleted_estimations -- it defaults to [] at mount (show.ex:646) and stays
      # that way on every other tab.
      {:ok, lv, _} =
        live(log_in_user(conn, owner), ~p"/org/#{org.id}/projects/#{project.id}/estimations")

      assert Enum.map(assigns(lv).deleted_estimations, & &1.id) == [est_trashed.id]

      %{lv: lv, est_current: est_current, est_trashed: est_trashed}
    end

    test "toggle_trash flips show_trash", %{lv: lv} do
      assert assigns(lv).show_trash == false

      render_click(lv, "toggle_trash", %{})
      assert assigns(lv).show_trash == true

      render_click(lv, "toggle_trash", %{})
      assert assigns(lv).show_trash == false
    end

    test "confirm_permanent_delete sets permanently_deleting; cancel_permanent_delete clears it",
         %{lv: lv, est_trashed: est_trashed} do
      assert assigns(lv).permanently_deleting == nil

      render_click(lv, "confirm_permanent_delete", %{"id" => est_trashed.id})
      assert assigns(lv).permanently_deleting == est_trashed.id

      render_click(lv, "cancel_permanent_delete", %{})
      assert assigns(lv).permanently_deleting == nil
    end

    test "restore_estimation: ok restores from trash back into the live list", %{
      lv: lv,
      org: org,
      project: project,
      est_current: est_current,
      est_trashed: est_trashed
    } do
      # diverged baseline: a soft-deleted row is invisible to get_estimation!/2's
      # is_nil(deleted_at) filter (estimations.ex:52-74) -- confirm it raises BEFORE
      # restoring, so the successful call after restore is a genuine transition.
      assert_raise Ecto.NoResultsError, fn ->
        EstimationEngine.get_estimation!(est_trashed.id, org.id)
      end

      html = render_click(lv, "restore_estimation", %{"id" => est_trashed.id})

      assert html =~ "Estimation restored"

      live_ids =
        project.id
        |> EstimationEngine.list_estimations(project.organization_id)
        |> Enum.map(& &1.id)

      trashed_ids = project.id |> EstimationEngine.list_deleted_estimations() |> Enum.map(& &1.id)
      assert est_trashed.id in live_ids
      refute est_trashed.id in trashed_ids

      # now visible again -- deleted_at was really cleared, not just filtered differently.
      assert EstimationEngine.get_estimation!(est_trashed.id, org.id)

      refute est_trashed.id in Enum.map(assigns(lv).deleted_estimations, & &1.id)
      assert est_trashed.id in Enum.map(assigns(lv).estimations, & &1.id)

      # est_current was already the sole non-deleted is_current row, so
      # maybe_auto_set_current/1 (estimations.ex:254-269) leaves it alone -- current_estimation
      # stays est_current, not nulled out or reassigned to the just-restored row.
      assert assigns(lv).current_estimation.id == est_current.id
    end

    test "restore_estimation: an id not in deleted_estimations flashes Estimation not found",
         %{lv: lv, est_trashed: est_trashed} do
      html = render_click(lv, "restore_estimation", %{"id" => Ecto.UUID.generate()})

      assert html =~ "Estimation not found"
      assert Enum.map(assigns(lv).deleted_estimations, & &1.id) == [est_trashed.id]
    end

    test "permanent_delete_estimation: ok hard-deletes and removes it from the trash list", %{
      lv: lv,
      org: org,
      est_trashed: est_trashed
    } do
      assert est_trashed.id in Enum.map(assigns(lv).deleted_estimations, & &1.id)

      # diverge permanently_deleting off nil FIRST so its reset below is a real transition,
      # not an unchanged default (mirrors the not-found test right below).
      render_click(lv, "confirm_permanent_delete", %{"id" => est_trashed.id})
      assert assigns(lv).permanently_deleting == est_trashed.id

      html = render_click(lv, "permanent_delete_estimation", %{"id" => est_trashed.id})

      assert html =~ "Estimation permanently deleted"
      assert assigns(lv).permanently_deleting == nil

      refute est_trashed.id in Enum.map(assigns(lv).deleted_estimations, & &1.id)

      # hard delete, not a soft one: the row itself is gone, not just filtered out.
      assert_raise Ecto.NoResultsError, fn ->
        EstimationEngine.get_estimation!(est_trashed.id, org.id)
      end
    end

    test "permanent_delete_estimation: an id not in deleted_estimations flashes Estimation not found",
         %{lv: lv, project: project, est_trashed: est_trashed} do
      render_click(lv, "confirm_permanent_delete", %{"id" => est_trashed.id})
      assert assigns(lv).permanently_deleting == est_trashed.id

      html = render_click(lv, "permanent_delete_estimation", %{"id" => Ecto.UUID.generate()})

      assert html =~ "Estimation not found"
      assert assigns(lv).permanently_deleting == nil

      # untouched -- still soft-deleted (in trash), not hard-deleted, not restored.
      trashed_ids =
        project.id |> EstimationEngine.list_deleted_estimations() |> Enum.map(& &1.id)

      assert est_trashed.id in trashed_ids
    end
  end

  describe "collaborators tab: member-picker dropdown/select state machine" do
    setup :setup_project

    setup %{conn: conn, org: org, owner: owner, project: project} do
      # an org member NOT yet a collaborator -- shows up in available_members
      available_user = user_fixture()
      _ = membership_fixture(available_user, org, "member")

      {:ok, lv, _} =
        live(log_in_user(conn, owner), ~p"/org/#{org.id}/projects/#{project.id}/collaborators")

      assert Enum.any?(assigns(lv).available_members, &(&1.user.id == available_user.id))

      %{lv: lv, available_user: available_user}
    end

    test "open_member_dropdown sets show_member_dropdown true; close_member_dropdown clears it",
         %{lv: lv} do
      assert assigns(lv).show_member_dropdown == false

      render_click(lv, "open_member_dropdown", %{})
      assert assigns(lv).show_member_dropdown == true

      render_click(lv, "close_member_dropdown", %{})
      assert assigns(lv).show_member_dropdown == false
    end

    test "collaborator_form_change sets member_search/selected_role and opens the dropdown once search is non-empty",
         %{lv: lv} do
      assert assigns(lv).member_search == ""
      assert assigns(lv).selected_role == "viewer"
      assert assigns(lv).show_member_dropdown == false

      render_click(lv, "collaborator_form_change", %{
        "member_search" => "ali",
        "collaborator_role" => "editor"
      })

      assert assigns(lv).member_search == "ali"
      assert assigns(lv).selected_role == "editor"
      assert assigns(lv).show_member_dropdown == true
    end

    test "collaborator_form_change does not auto-close an already-open dropdown when search is cleared back to empty",
         %{lv: lv} do
      render_click(lv, "collaborator_form_change", %{
        "member_search" => "ali",
        "collaborator_role" => "viewer"
      })

      assert assigns(lv).show_member_dropdown == true

      # show.ex:1178 -- `show_member_dropdown: member_search != "" || <previous value>`.
      # Clearing the text back to "" does NOT flip it back to false on its own; only
      # close_member_dropdown/select_member explicitly set it false.
      render_click(lv, "collaborator_form_change", %{
        "member_search" => "",
        "collaborator_role" => "viewer"
      })

      assert assigns(lv).member_search == ""
      assert assigns(lv).show_member_dropdown == true
    end

    test "select_member sets selected_member, prefills member_search, and closes the dropdown; an unknown id is a no-op",
         %{lv: lv, available_user: available_user} do
      # diverge first: open the dropdown with partial text so the reset below is a real
      # transition, not a re-assertion of the mount default.
      render_click(lv, "collaborator_form_change", %{
        "member_search" => "partial",
        "collaborator_role" => "viewer"
      })

      assert assigns(lv).show_member_dropdown == true
      assert assigns(lv).selected_member == nil

      render_click(lv, "select_member", %{"user-id" => available_user.id})

      assert assigns(lv).selected_member.id == available_user.id
      assert assigns(lv).member_search == available_user.name
      assert assigns(lv).show_member_dropdown == false

      # unknown id: the real selection made above is left untouched -- proves the
      # `else -> {:noreply, socket}` no-op branch (show.ex:1199-1201), not a reset to nil.
      render_click(lv, "select_member", %{"user-id" => Ecto.UUID.generate()})

      assert assigns(lv).selected_member.id == available_user.id
      assert assigns(lv).member_search == available_user.name
    end

    test "clear_selected_member resets selected_member to nil and member_search to empty",
         %{lv: lv, available_user: available_user} do
      render_click(lv, "select_member", %{"user-id" => available_user.id})
      assert assigns(lv).selected_member.id == available_user.id
      assert assigns(lv).member_search != ""

      render_click(lv, "clear_selected_member", %{})

      assert assigns(lv).selected_member == nil
      assert assigns(lv).member_search == ""
    end
  end

  describe "collaborators tab: add_collaborator (owner)" do
    setup :setup_project

    setup %{conn: conn, org: org, owner: owner, project: project} do
      available_user = user_fixture()
      _ = membership_fixture(available_user, org, "member")

      {:ok, lv, _} =
        live(log_in_user(conn, owner), ~p"/org/#{org.id}/projects/#{project.id}/collaborators")

      %{lv: lv, available_user: available_user}
    end

    test "ok: adds the collaborator with the selected role, resets the form, and flashes Collaborator added",
         %{lv: lv, project: project, available_user: available_user} do
      before_ids = project.id |> Portfolio.list_collaborators() |> Enum.map(& &1.user_id)
      refute available_user.id in before_ids

      # diverge selected_role/selected_member off their mount defaults FIRST, so the
      # post-add form reset (reload_collaborators/2, show.ex:1352-1359) is a real
      # transition, and the persisted role proves selected_role was actually read
      # rather than a hardcoded default.
      render_click(lv, "collaborator_form_change", %{
        "member_search" => "",
        "collaborator_role" => "editor"
      })

      render_click(lv, "select_member", %{"user-id" => available_user.id})
      assert assigns(lv).selected_member.id == available_user.id
      assert assigns(lv).selected_role == "editor"

      html = render_click(lv, "add_collaborator", %{})

      assert html =~ "Collaborator added"

      collaborators = Portfolio.list_collaborators(project.id)
      added = Enum.find(collaborators, &(&1.user_id == available_user.id))
      assert added
      assert added.role == "editor"

      assert Enum.any?(assigns(lv).collaborators, &(&1.user_id == available_user.id))
      refute Enum.any?(assigns(lv).available_members, &(&1.user.id == available_user.id))

      assert assigns(lv).selected_member == nil
      assert assigns(lv).selected_role == "viewer"
      assert assigns(lv).member_search == ""
      assert assigns(lv).show_member_dropdown == false
    end

    test "no selected member is a silent no-op for an authorized user (no flash, no DB change)",
         %{lv: lv, project: project} do
      assert assigns(lv).selected_member == nil
      before_count = project.id |> Portfolio.list_collaborators() |> length()

      html = render_click(lv, "add_collaborator", %{})

      refute html =~ "Not authorized"
      refute html =~ "Collaborator added"
      assert project.id |> Portfolio.list_collaborators() |> length() == before_count
      assert length(assigns(lv).collaborators) == before_count
    end
  end

  describe "collaborators tab: change_collaborator_role (owner)" do
    setup :setup_project

    setup %{conn: conn, org: org, owner: owner, project: project} do
      %{collaborator: editor_collab} = add_collab(project, org, "editor")

      {:ok, lv, _} =
        live(log_in_user(conn, owner), ~p"/org/#{org.id}/projects/#{project.id}/collaborators")

      owner_collab = Enum.find(assigns(lv).collaborators, &(&1.user_id == owner.id))
      assert owner_collab

      %{lv: lv, editor_collab: editor_collab, owner_collab: owner_collab}
    end

    test "ok: updates another collaborator's role in the DB and flashes Role updated",
         %{lv: lv, project: project, editor_collab: editor_collab} do
      assert editor_collab.role == "editor"

      html =
        render_click(lv, "change_collaborator_role", %{
          "id" => editor_collab.id,
          "role" => "viewer"
        })

      assert html =~ "Role updated"

      updated = Enum.find(Portfolio.list_collaborators(project.id), &(&1.id == editor_collab.id))
      assert updated.role == "viewer"
      assert Enum.find(assigns(lv).collaborators, &(&1.id == editor_collab.id)).role == "viewer"
    end

    test "changing YOUR OWN role flashes Not authorized and leaves the role unchanged",
         %{lv: lv, project: project, owner_collab: owner_collab} do
      assert owner_collab.role == "owner"

      html =
        render_click(lv, "change_collaborator_role", %{
          "id" => owner_collab.id,
          "role" => "editor"
        })

      assert html =~ "Not authorized"

      unchanged = Enum.find(Portfolio.list_collaborators(project.id), &(&1.id == owner_collab.id))
      assert unchanged.role == "owner"
    end
  end

  describe "collaborators tab: remove_collaborator (confirm/cancel, last-owner, self-guard)" do
    setup :setup_project

    setup %{conn: conn, org: org, owner: owner, project: project} do
      %{collaborator: editor_collab} = add_collab(project, org, "editor")
      %{collaborator: second_owner_collab} = add_collab(project, org, "owner")

      {:ok, lv, _} =
        live(log_in_user(conn, owner), ~p"/org/#{org.id}/projects/#{project.id}/collaborators")

      owner_collab = Enum.find(assigns(lv).collaborators, &(&1.user_id == owner.id))
      assert owner_collab

      %{
        lv: lv,
        editor_collab: editor_collab,
        second_owner_collab: second_owner_collab,
        owner_collab: owner_collab
      }
    end

    test "confirm_remove_collaborator sets removing_collaborator; cancel_remove_collaborator clears it",
         %{lv: lv, editor_collab: editor_collab} do
      assert assigns(lv).removing_collaborator == nil

      render_click(lv, "confirm_remove_collaborator", %{"id" => editor_collab.id})
      assert assigns(lv).removing_collaborator.id == editor_collab.id

      render_click(lv, "cancel_remove_collaborator", %{})
      assert assigns(lv).removing_collaborator == nil
    end

    test "ok: removes a non-owner collaborator from the DB and flashes Collaborator removed",
         %{lv: lv, project: project, editor_collab: editor_collab} do
      before_ids = project.id |> Portfolio.list_collaborators() |> Enum.map(& &1.id)
      assert editor_collab.id in before_ids

      render_click(lv, "confirm_remove_collaborator", %{"id" => editor_collab.id})
      assert assigns(lv).removing_collaborator.id == editor_collab.id

      html = render_click(lv, "remove_collaborator", %{})

      assert html =~ "Collaborator removed"
      assert assigns(lv).removing_collaborator == nil

      after_ids = project.id |> Portfolio.list_collaborators() |> Enum.map(& &1.id)
      refute editor_collab.id in after_ids
      refute Enum.any?(assigns(lv).collaborators, &(&1.id == editor_collab.id))
    end

    test "ok: removes a non-last owner (a second owner collaborator) from the DB",
         %{lv: lv, project: project, second_owner_collab: second_owner_collab} do
      assert project.id |> Portfolio.list_collaborators() |> Enum.count(&(&1.role == "owner")) ==
               2

      render_click(lv, "confirm_remove_collaborator", %{"id" => second_owner_collab.id})

      html = render_click(lv, "remove_collaborator", %{})

      assert html =~ "Collaborator removed"
      assert assigns(lv).removing_collaborator == nil

      remaining = Portfolio.list_collaborators(project.id)
      refute Enum.any?(remaining, &(&1.id == second_owner_collab.id))
      assert Enum.count(remaining, &(&1.role == "owner")) == 1
    end

    test "removing yourself flashes Not authorized and the collaborator stays",
         %{lv: lv, project: project, owner_collab: owner_collab} do
      # can_remove_collaborator?/4 (portfolio.ex:331-337) checks `collab.user_id ==
      # current_user.id -> false` FIRST, unconditionally -- this self-guard applies even
      # to the project owner, who otherwise passes can_manage_collaborators.
      render_click(lv, "confirm_remove_collaborator", %{"id" => owner_collab.id})
      assert assigns(lv).removing_collaborator.id == owner_collab.id

      html = render_click(lv, "remove_collaborator", %{})

      assert html =~ "Not authorized"
      assert assigns(lv).removing_collaborator == nil

      still_present =
        Enum.find(Portfolio.list_collaborators(project.id), &(&1.id == owner_collab.id))

      assert still_present
    end

    test "removing the LAST owner (yourself, once the second owner is gone) is blocked by the self-guard, not the last-owner message",
         %{
           lv: lv,
           project: project,
           second_owner_collab: second_owner_collab,
           owner_collab: owner_collab
         } do
      # First remove the second owner (ok - proven in the test above), leaving the
      # acting owner as the sole remaining "owner" collaborator.
      render_click(lv, "confirm_remove_collaborator", %{"id" => second_owner_collab.id})
      assert render_click(lv, "remove_collaborator", %{}) =~ "Collaborator removed"

      assert project.id |> Portfolio.list_collaborators() |> Enum.count(&(&1.role == "owner")) ==
               1

      # Now the ONLY "owner" left to attempt removing IS the acting user's own row.
      # can_remove_collaborator?/4 short-circuits to `false` on the self-check BEFORE
      # remove_collaborator/1's `collab.role == "owner" && count <= 1` cond clause
      # (collaborators.ex:135-140) ever runs -- so this observably flashes "Not
      # authorized", not "Cannot remove the last project owner". That self-check is
      # unconditional and unchanged by the Task-7 admin/owner asymmetry fix, so this
      # specific owner-removes-self path still resolves the same way.
      #
      # NOTE: prior to Task 7 this was also true for every OTHER actor, making the
      # last-owner message structurally unreachable (dead code): reaching that cond
      # required can_remove_collaborator?/4 to already allow removing an owner-role
      # target, which required the ACTING user to be a distinct "owner" collaborator --
      # i.e. >= 2 owner rows, contradicting `count <= 1`. Task 7 changed
      # can_remove_collaborator?/4 so any can_manage=true actor (not just owner
      # collaborators) may remove a non-self owner target, which makes the message live
      # for an org ADMIN removing the sole owner (see "collaborators tab:
      # remove_collaborator admin/owner asymmetry fix" below). It remains unreachable
      # for THIS test's owner-actor specifically, because the sole remaining owner is
      # always the acting user themselves once a project has only one owner left.
      render_click(lv, "confirm_remove_collaborator", %{"id" => owner_collab.id})
      assert assigns(lv).removing_collaborator.id == owner_collab.id

      html = render_click(lv, "remove_collaborator", %{})

      assert html =~ "Not authorized"
      refute html =~ "Cannot remove the last project owner"
      assert assigns(lv).removing_collaborator == nil

      still_present =
        Enum.find(Portfolio.list_collaborators(project.id), &(&1.id == owner_collab.id))

      assert still_present
    end
  end

  describe "collaborators tab: remove_collaborator admin/owner asymmetry fix" do
    # can_remove_collaborator?/4 (portfolio.ex:331-337) used to require the ACTING user's
    # own collaborator row to have role "owner" before it would let them remove an
    # owner-role target. An org admin acting on a project they don't collaborate on has no
    # collaborator row at all (current_collaborator is nil), so this always evaluated to
    # false for admins -- an admin could manage every OTHER aspect of collaborators but
    # could never remove an owner. Fixed: any actor with can_manage=true (admin or owner
    # collaborator) may remove a non-self owner target; the last-owner guard in
    # remove_collaborator/1 (collaborators.ex:135-140) is unchanged and now genuinely
    # activates for the admin path (previously unreachable for admins, since they were
    # denied before that cond ever ran).
    setup :setup_project

    test "an org admin (non-collaborator) can remove a non-last owner", %{
      conn: conn,
      org: org,
      project: project
    } do
      # a 2nd owner so removal doesn't hit the last-owner guard
      %{user: owner2} = add_collab(project, org, "owner")
      admin = user_fixture()
      _ = membership_fixture(admin, org, "admin")

      {:ok, lv, _} =
        live(log_in_user(conn, admin), ~p"/org/#{org.id}/projects/#{project.id}/collaborators")

      collab = Enum.find(assigns(lv).collaborators, &(&1.user_id == owner2.id))
      render_click(lv, "confirm_remove_collaborator", %{"id" => collab.id})

      html = render_click(lv, "remove_collaborator", %{})

      assert html =~ "Collaborator removed"
      refute owner2.id in Enum.map(Portfolio.list_collaborators(project.id), & &1.user_id)
    end

    test "an org admin removing the SOLE owner is blocked (last-owner guard now active)", %{
      conn: conn,
      org: org,
      owner: owner,
      project: project
    } do
      admin = user_fixture()
      _ = membership_fixture(admin, org, "admin")

      {:ok, lv, _} =
        live(log_in_user(conn, admin), ~p"/org/#{org.id}/projects/#{project.id}/collaborators")

      owner_collab = Enum.find(assigns(lv).collaborators, &(&1.role == "owner"))
      render_click(lv, "confirm_remove_collaborator", %{"id" => owner_collab.id})

      html = render_click(lv, "remove_collaborator", %{})

      assert html =~ "Cannot remove the last project owner"
      assert owner.id in Enum.map(Portfolio.list_collaborators(project.id), & &1.user_id)
    end
  end

  describe "cross-org estimation ids are handled gracefully (bug b)" do
    setup :setup_project

    # fetch_authorized_estimation/2 (show/authz.ex) rescues Ecto.NoResultsError from
    # get_estimation!/2 when the id belongs to a DIFFERENT organization entirely (as
    # opposed to the same-org/different-project case pinned elsewhere) -- before this
    # fix that raised, crashing the LiveView process. Both tests below prove the fix by
    # asserting the flash AND that the process survived (Process.alive?), not just that
    # some string appeared.

    test "copy from a foreign-org estimation flashes an error, no crash", %{
      conn: conn,
      org: org,
      owner: owner,
      project: project
    } do
      %{user: other} = user_with_organization_fixture()
      other_project = project_fixture(nil, other)
      foreign = estimation_fixture(other_project)

      {:ok, lv, _} = live(log_in_user(conn, owner), project_path(org, project))

      html =
        render_click(lv, "create_estimation", %{
          "estimation" => %{"name" => "X"},
          "source" => "copy",
          "source_estimation_id" => foreign.id
        })

      assert html =~ "Could not create estimation"
      assert Process.alive?(lv.pid)
    end

    test "set_current with a foreign-org id flashes Not authorized, no crash", %{
      conn: conn,
      org: org,
      owner: owner,
      project: project
    } do
      %{user: other} = user_with_organization_fixture()
      other_project = project_fixture(nil, other)
      foreign = estimation_fixture(other_project)

      {:ok, lv, _} = live(log_in_user(conn, owner), project_path(org, project))

      assert render_click(lv, "set_current_estimation", %{"id" => foreign.id}) =~
               "Not authorized"

      assert Process.alive?(lv.pid)
    end
  end
end
