defmodule EstimateWeb.ProjectLive.ShowTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Estimate.AccountsFixtures
  import Estimate.PortfolioFixtures
  import Estimate.EstimationEngineFixtures

  alias Estimate.Portfolio
  alias Estimate.Organizations.Currencies

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
  end

  describe "dashboard tab" do
    setup :setup_project

    test "set_dashboard_tab accepts by_role and ignores an invalid value", %{
      conn: conn,
      org: org,
      owner: owner,
      project: project
    } do
      {:ok, lv, _} = live(log_in_user(conn, owner), project_path(org, project))

      render_click(lv, "set_dashboard_tab", %{"tab" => "by_role"})
      assert assigns(lv).dashboard_tab == :by_role

      # fallback clause (no matching guard) → no-op
      render_click(lv, "set_dashboard_tab", %{"tab" => "bogus"})
      assert assigns(lv).dashboard_tab == :by_role

      # NOTE: by_epic/by_priority are deliberately NOT pinned here. set_dashboard_tab does
      # String.to_existing_atom/1 (show.ex:815) on the client-controlled "tab" string, and
      # those two atoms exist only as literals inside EstimationDashboard
      # (estimation_dashboard.ex) — a component show.ex renders solely `:if={@current_estimation}`.
      # So whether they're interned is load-order-dependent across the async suite: pushing
      # either before that component has ever rendered crashes the LiveView (ArgumentError),
      # but once any test renders a current estimation the atoms register VM-wide and the same
      # push succeeds. That order-dependent crash is a LATENT BUG recorded for the
      # decomposition to fix (guard should map strings → atoms explicitly, not
      # to_existing_atom), not stable behavior to assert. :by_role is safe: show.ex's mount
      # sets `dashboard_tab: :by_role`, so that atom always exists once the LiveView loads.
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

    test "open_estimation_modal: fresh source, roles rebuilt from templates, currency locked to project, no source estimation when none exist",
         %{conn: conn, org: org, owner: owner, project: project} do
      {:ok, lv, _} = live(log_in_user(conn, owner), project_path(org, project))
      templates = assigns(lv).role_templates

      render_click(lv, "open_estimation_modal", %{})
      a = assigns(lv)

      assert a.show_new_estimation_modal == true
      assert a.estimation_source == "fresh"
      assert a.modal_currency_id == project.currency_id
      assert a.source_estimation_id == nil

      # modal_roles is a 1:1, order-preserving rebuild from role_templates -- not just
      # "some roles", the exact template name/abbreviation/template_id sequence.
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

      render_click(lv, "close_estimation_modal", %{})

      a = assigns(lv)
      refute a.show_new_estimation_modal
      # a single assign in the source -- source/roles from the open are left untouched
      assert a.estimation_source == "fresh"
    end

    test "set_estimation_source(copy) prefills name/source/currency from the estimation; switching away resets them",
         %{conn: conn, org: org, owner: owner, project: project, other_currency: other_currency} do
      estimation =
        estimation_fixture(project, %{"name" => "Alpha", "currency_id" => other_currency.id})

      {:ok, lv, _} = live(log_in_user(conn, owner), project_path(org, project))
      render_click(lv, "open_estimation_modal", %{})

      render_click(lv, "set_estimation_source", %{"source" => "copy"})
      a = assigns(lv)
      assert a.estimation_source == "copy"
      assert a.source_estimation_id == estimation.id
      assert a.estimation_form.params["name"] == "Copy of Alpha"
      # currency gets LOCKED to the source estimation's currency, overriding the
      # project's currency that open_estimation_modal had set.
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
end
