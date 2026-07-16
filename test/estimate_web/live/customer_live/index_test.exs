defmodule EstimateWeb.CustomerLive.IndexTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Estimate.AccountsFixtures
  import Estimate.CRMFixtures
  import Estimate.PortfolioFixtures

  defp customers_path(org), do: ~p"/org/#{org.id}/customers"

  defp setup_org(_) do
    %{user: owner, organization: org} = user_with_organization_fixture()
    %{org: org, owner: owner}
  end

  describe "row content" do
    setup :setup_org

    test "no description → meta line with key, country, domain", %{
      conn: conn,
      org: org,
      owner: owner
    } do
      customer_fixture(org, %{
        "key" => "AVIO",
        "name" => "Avio Areo",
        "country" => "IT",
        "website_url" => "https://www.avioareo.it"
      })

      {:ok, lv, html} = live(log_in_user(conn, owner), customers_path(org))

      assert has_element?(lv, "span.font-mono", "AVIO")
      assert has_element?(lv, "span.font-mono", "IT")
      assert html =~ "avioareo.it"
      refute html =~ "www.avioareo.it"
    end

    test "meta line omits missing country/website", %{conn: conn, org: org, owner: owner} do
      customer = customer_fixture(org, %{"key" => "BRG", "name" => "Brigade"})

      {:ok, lv, _html} = live(log_in_user(conn, owner), customers_path(org))

      assert has_element?(lv, "span.font-mono", "BRG")
      # only the key + count pill for this row; no stray separators
      refute render(lv) =~ "BRG ·"
      assert customer.country == nil
    end

    test "description wins over meta line", %{conn: conn, org: org, owner: owner} do
      customer =
        customer_fixture(org, %{"name" => "Olus", "description" => "UK legal-tech consultancy"})

      {:ok, lv, html} = live(log_in_user(conn, owner), customers_path(org))

      assert has_element?(lv, "p", "UK legal-tech consultancy")
      refute html =~ customer.key
    end

    test "old standalone key column is gone", %{conn: conn, org: org, owner: owner} do
      customer_fixture(org)
      {:ok, lv, _html} = live(log_in_user(conn, owner), customers_path(org))
      refute has_element?(lv, "span.w-12")
    end
  end

  describe "project-count pill" do
    setup :setup_org

    test "0, 1, N projects render pluralized pill", %{conn: conn, org: org, owner: owner} do
      zero = customer_fixture(org, %{"name" => "Alpha"})
      one = customer_fixture(org, %{"name" => "Beta"})
      many = customer_fixture(org, %{"name" => "Gamma"})
      project_fixture(one, owner)
      project_fixture(many, owner)
      project_fixture(many, owner)

      {:ok, lv, _html} = live(log_in_user(conn, owner), customers_path(org))

      assert has_element?(lv, "span.rounded-full", "0 projects")
      assert has_element?(lv, "span.rounded-full", "1 project")
      assert has_element?(lv, "span.rounded-full", "2 projects")
      assert zero.id && one.id && many.id
    end

    test "zero pill is extra muted", %{conn: conn, org: org, owner: owner} do
      customer_fixture(org)
      {:ok, lv, _html} = live(log_in_user(conn, owner), customers_path(org))
      assert has_element?(lv, ~s{span[class*="text-base-content/40"]}, "0 projects")
    end
  end

  describe "permissions" do
    setup :setup_org

    test "member sees rows but no pencil", %{conn: conn, org: org} do
      customer = customer_fixture(org)
      member = user_fixture()
      membership_fixture(member, org, "member")

      {:ok, lv, html} = live(log_in_user(conn, member), customers_path(org))

      assert html =~ customer.name
      refute has_element?(lv, ~s{a[href="/org/#{org.id}/customers/#{customer.id}/edit"]})
    end
  end
end
