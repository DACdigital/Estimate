defmodule EstimateWeb.ProjectLive.ShowTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Estimate.AccountsFixtures
  import Estimate.PortfolioFixtures

  alias Estimate.Portfolio

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

    # Every gated event below is checked with can_edit_project/can_delete_project/
    # can_manage_collaborators all false (viewer) and flashes "Not authorized" as its
    # unauthorized branch. remove_collaborator is intentionally excluded here — its gate
    # is structured differently (see the two dedicated tests below).
    test "gated events flash Not authorized for a viewer", %{lv: lv} do
      pushes = [
        {"save", %{"project" => %{"name" => "X"}}},
        {"delete_project", %{}},
        {"create_estimation", %{"estimation" => %{"name" => "E"}}},
        {"set_current_estimation", %{"id" => Ecto.UUID.generate()}},
        {"delete_estimation", %{"id" => Ecto.UUID.generate()}},
        {"restore_estimation", %{"id" => Ecto.UUID.generate()}},
        {"permanent_delete_estimation", %{"id" => Ecto.UUID.generate()}},
        {"add_collaborator", %{}},
        {"change_collaborator_role", %{"id" => Ecto.UUID.generate(), "role" => "editor"}}
      ]

      for {event, payload} <- pushes do
        # lv:clear-flash isolates each iteration: put_flash merges by key and is NOT
        # auto-cleared, so a prior :error would bleed through and mask an ungated event.
        render_click(lv, "lv:clear-flash", %{"key" => "error"})

        assert render_click(lv, event, payload) =~ "Not authorized",
               "expected #{event} to be authorization-gated for a viewer"
      end
    end

    test "remove_collaborator with no pending confirmation is a silent no-op for a viewer",
         %{lv: lv} do
      # remove_collaborator's `cond` checks `is_nil(socket.assigns.removing_collaborator)`
      # FIRST, before the can_manage_collaborators gate — unlike the other 9 events. Since
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

  describe "authorization gating — remove_collaborator (two-step confirm/execute)" do
    setup :setup_project

    test "viewer confirming a real target is still Not authorized on execute",
         %{conn: conn, org: org, project: project} do
      %{user: viewer} = add_collab(project, org, "viewer")

      # confirm_remove_collaborator looks the id up in socket.assigns.collaborators,
      # which is only populated on the :collaborators tab (empty on :overview).
      {:ok, lv, _} =
        live(log_in_user(conn, viewer), ~p"/org/#{org.id}/projects/#{project.id}/collaborators")

      owner_collab = Enum.find(assigns(lv).collaborators, &(&1.role == "owner"))
      assert owner_collab

      render_click(lv, "confirm_remove_collaborator", %{"id" => owner_collab.id})
      assert assigns(lv).removing_collaborator.id == owner_collab.id

      render_click(lv, "lv:clear-flash", %{"key" => "error"})

      assert render_click(lv, "remove_collaborator", %{}) =~ "Not authorized"
    end
  end
end
