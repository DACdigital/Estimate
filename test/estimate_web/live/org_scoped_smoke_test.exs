defmodule EstimateWeb.OrgScopedSmokeTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_org_owner

  describe "index/list routes render" do
    test "dashboard", %{conn: conn, org: org} do
      assert {:ok, _view, _html} = live(conn, ~p"/org/#{org.id}")
    end

    test "roles", %{conn: conn, org: org} do
      assert {:ok, _view, _html} = live(conn, ~p"/org/#{org.id}/roles")
    end

    test "templates index", %{conn: conn, org: org} do
      assert {:ok, _view, _html} = live(conn, ~p"/org/#{org.id}/templates")
    end

    test "settings index", %{conn: conn, org: org} do
      assert {:ok, _view, _html} = live(conn, ~p"/org/#{org.id}/settings")
    end

    test "settings members", %{conn: conn, org: org} do
      assert {:ok, _view, _html} = live(conn, ~p"/org/#{org.id}/settings/members")
    end

    test "settings currencies", %{conn: conn, org: org} do
      assert {:ok, _view, _html} = live(conn, ~p"/org/#{org.id}/settings/currencies")
    end

    test "settings ai", %{conn: conn, org: org} do
      assert {:ok, _view, _html} = live(conn, ~p"/org/#{org.id}/settings/ai")
    end

    test "settings email", %{conn: conn, org: org} do
      assert {:ok, _view, _html} = live(conn, ~p"/org/#{org.id}/settings/email")
    end

    test "settings trash", %{conn: conn, org: org} do
      assert {:ok, _view, _html} = live(conn, ~p"/org/#{org.id}/settings/trash")
    end

    test "customers index", %{conn: conn, org: org} do
      assert {:ok, _view, _html} = live(conn, ~p"/org/#{org.id}/customers")
    end

    test "projects index", %{conn: conn, org: org} do
      assert {:ok, _view, _html} = live(conn, ~p"/org/#{org.id}/projects")
    end
  end

  describe "detail routes render with seeded data" do
    test "customer show", %{conn: conn, org: org} do
      customer = Estimate.CRMFixtures.customer_fixture(org)
      assert {:ok, _view, _html} = live(conn, ~p"/org/#{org.id}/customers/#{customer.id}")
    end

    test "project show", %{conn: conn, org: org, user: user} do
      project = Estimate.PortfolioFixtures.project_fixture(nil, user)
      assert {:ok, _view, _html} = live(conn, ~p"/org/#{org.id}/projects/#{project.id}")
    end

    test "templates show", %{conn: conn, org: org} do
      template = Estimate.TemplatesFixtures.template_fixture(org)
      assert {:ok, _view, _html} = live(conn, ~p"/org/#{org.id}/templates/#{template.id}")
    end

    test "estimator", %{conn: conn, org: org, user: user} do
      project = Estimate.PortfolioFixtures.project_fixture(nil, user)
      estimation = Estimate.EstimationEngineFixtures.estimation_fixture(project)

      assert {:ok, _view, _html} =
               live(
                 conn,
                 ~p"/org/#{org.id}/projects/#{project.id}/estimations/#{estimation.id}/estimator"
               )
    end
  end

  describe "action-variant routes render" do
    test "customer new", %{conn: conn, org: org} do
      assert {:ok, _view, _html} = live(conn, ~p"/org/#{org.id}/customers/new")
    end

    test "customer edit", %{conn: conn, org: org} do
      customer = Estimate.CRMFixtures.customer_fixture(org)
      assert {:ok, _view, _html} = live(conn, ~p"/org/#{org.id}/customers/#{customer.id}/edit")
    end

    test "project new", %{conn: conn, org: org} do
      assert {:ok, _view, _html} = live(conn, ~p"/org/#{org.id}/projects/new")
    end

    test "project edit", %{conn: conn, org: org, user: user} do
      project = Estimate.PortfolioFixtures.project_fixture(nil, user)
      assert {:ok, _view, _html} = live(conn, ~p"/org/#{org.id}/projects/#{project.id}/edit")
    end

    test "project collaborators", %{conn: conn, org: org, user: user} do
      project = Estimate.PortfolioFixtures.project_fixture(nil, user)

      assert {:ok, _view, _html} =
               live(conn, ~p"/org/#{org.id}/projects/#{project.id}/collaborators")
    end

    test "project estimations", %{conn: conn, org: org, user: user} do
      project = Estimate.PortfolioFixtures.project_fixture(nil, user)

      assert {:ok, _view, _html} =
               live(conn, ~p"/org/#{org.id}/projects/#{project.id}/estimations")
    end

    test "project new estimation", %{conn: conn, org: org, user: user} do
      project = Estimate.PortfolioFixtures.project_fixture(nil, user)

      assert {:ok, _view, _html} =
               live(conn, ~p"/org/#{org.id}/projects/#{project.id}/estimations/new")
    end
  end
end
