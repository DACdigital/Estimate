defmodule EstimateWeb.ProjectLive.IndexTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Estimate.AccountsFixtures
  import Estimate.CRMFixtures
  import Estimate.PortfolioFixtures

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

      {:ok, lv, html} = live(log_in_user(conn, owner), projects_path(org))

      assert has_element?(lv, "span.font-mono", "CHA-WEB")
      assert html =~ "Charite Berlin"
    end

    test "old standalone key column is gone", %{conn: conn, org: org, owner: owner} do
      project_fixture(nil, owner)
      {:ok, lv, _html} = live(log_in_user(conn, owner), projects_path(org))
      refute has_element?(lv, "span.w-20")
    end

    test "status pill still renders", %{conn: conn, org: org, owner: owner} do
      project_fixture(nil, owner)
      {:ok, lv, _html} = live(log_in_user(conn, owner), projects_path(org))
      assert has_element?(lv, "span.rounded-full", "active")
    end
  end
end
