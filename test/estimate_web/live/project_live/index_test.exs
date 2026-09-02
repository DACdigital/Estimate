defmodule EstimateWeb.ProjectLive.IndexTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Estimate.AccountsFixtures
  import Estimate.CRMFixtures
  import Estimate.PortfolioFixtures

  alias Estimate.{Portfolio, Repo}

  defp projects_path(org), do: ~p"/org/#{org.id}/projects"

  defp setup_org(_) do
    %{user: owner, organization: org} = user_with_organization_fixture()
    %{org: org, owner: owner}
  end

  describe "row content" do
    setup :setup_org

    test "meta line shows composite key + customer name", %{conn: conn, org: org, owner: owner} do
      customer = customer_fixture(org, %{"key" => "CHA", "name" => "Charite Berlin"})
      project_fixture(customer, owner, %{"key" => "WEB", "name" => "Website Relaunch"})

      {:ok, lv, _html} = live(log_in_user(conn, owner), projects_path(org))

      assert has_element?(lv, "span.font-mono", "CHA-WEB")
      assert has_element?(lv, "p", "Charite Berlin")
    end

    test "old standalone key column is gone", %{conn: conn, org: org, owner: owner} do
      customer = customer_fixture(org, %{"key" => "KCOL"})
      project_fixture(customer, owner, %{"key" => "GONE"})
      {:ok, lv, _html} = live(log_in_user(conn, owner), projects_path(org))
      refute has_element?(lv, "span.w-20")
    end

    test "status pill still renders", %{conn: conn, org: org, owner: owner} do
      project_fixture(nil, owner)
      {:ok, lv, _html} = live(log_in_user(conn, owner), projects_path(org))
      assert has_element?(lv, "span.rounded-full", "active")
    end
  end

  describe "edit gating" do
    setup do
      %{user: owner, organization: org} = user_with_organization_fixture()
      project = project_fixture(nil, owner)
      viewer = user_fixture()
      _ = membership_fixture(viewer, org, "member")
      {:ok, _} = Portfolio.add_collaborator(project.id, viewer.id, "viewer")
      editor = user_fixture()
      _ = membership_fixture(editor, org, "member")
      {:ok, _} = Portfolio.add_collaborator(project.id, editor.id, "editor")
      %{org: org, project: project, viewer: viewer, editor: editor}
    end

    test "viewer collaborator cannot save project edits", %{conn: conn} = ctx do
      conn = log_in_user(conn, ctx.viewer)
      edit_path = ~p"/org/#{ctx.org.id}/projects/#{ctx.project.id}/edit"
      index_path = ~p"/org/#{ctx.org.id}/projects"

      # the edit action itself must bounce a viewer back to the index. Since the
      # push_patch happens during the connected mount's handle_params, live/2
      # surfaces it as a live_redirect rather than an {:ok, lv, _} + assert_patch.
      assert {:error, {:live_redirect, %{to: ^index_path, flash: %{"error" => "Not authorized"}}}} =
               live(conn, edit_path)

      # forged save event even after the bounce: mount the index directly as the
      # viewer (project assign is nil there) and submit the same event name.
      {:ok, lv, _html} = live(conn, index_path)
      render_submit(lv, "save", %{"project" => %{"name" => "VIEWER-RENAMED"}})
      assert render(lv) =~ "Not authorized"
      assert Repo.get!(Estimate.Portfolio.Project, ctx.project.id).name == ctx.project.name
    end

    test "editor collaborator can save project edits", %{conn: conn} = ctx do
      {:ok, lv, _} =
        live(
          log_in_user(conn, ctx.editor),
          ~p"/org/#{ctx.org.id}/projects/#{ctx.project.id}/edit"
        )

      render_submit(lv, "save", %{"project" => %{"name" => "EDITOR-RENAMED"}})
      assert Repo.get!(Estimate.Portfolio.Project, ctx.project.id).name == "EDITOR-RENAMED"
    end
  end
end
