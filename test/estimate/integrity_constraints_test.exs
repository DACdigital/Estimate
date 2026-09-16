defmodule Estimate.IntegrityConstraintsTest do
  use Estimate.DataCase, async: true

  import Estimate.{AccountsFixtures, CRMFixtures, PortfolioFixtures, EstimationEngineFixtures}
  alias Estimate.Repo

  @not_null [
    {"estimations", "is_current"},
    {"tasks", "priority"},
    {"estimation_roles", "pm_overhead"},
    {"estimation_roles", "qa_overhead"},
    {"estimation_roles", "risk_buffer"},
    {"project_roles", "pm_overhead"},
    {"project_roles", "qa_overhead"},
    {"project_roles", "risk_buffer"},
    {"project_roles", "position"},
    {"role_templates", "pm_overhead"},
    {"role_templates", "qa_overhead"},
    {"role_templates", "risk_buffer"},
    {"role_templates", "position"},
    {"estimation_template_epics", "position"},
    {"estimation_template_tasks", "position"},
    {"estimation_template_tasks", "priority"}
  ]

  test "previously nullable columns are NOT NULL" do
    for {t, c} <- @not_null do
      %{rows: [[nullable]]} =
        Repo.query!(
          "SELECT is_nullable FROM information_schema.columns WHERE table_name = $1 AND column_name = $2",
          [t, c]
        )

      assert nullable == "NO", "#{t}.#{c} should be NOT NULL"
    end
  end

  test "composite FKs exist" do
    for name <- ~w(projects_customer_org_fkey estimations_project_org_fkey) do
      assert Repo.exists?(from(c in "pg_constraint", where: c.conname == ^name, select: 1)), name
    end
  end

  test "a project cannot point at another org's customer even with RLS bypassed" do
    %{user: owner_a, organization: _} = user_with_organization_fixture()
    %{organization: org_b} = user_with_organization_fixture()
    customer_b = customer_fixture(org_b)
    project_a = project_fixture(nil, owner_a)

    assert_raise Postgrex.Error, ~r/projects_customer_org_fkey/, fn ->
      Repo.query!("UPDATE projects SET customer_id = $1 WHERE id = $2", [
        Ecto.UUID.dump!(customer_b.id),
        Ecto.UUID.dump!(project_a.id)
      ])
    end

    assert Repo.reload!(project_a).customer_id == project_a.customer_id
  end

  test "an estimation cannot point at another org's project even with RLS bypassed" do
    %{user: owner_a} = user_with_organization_fixture()
    project_a = project_fixture(nil, owner_a)
    estimation_a = estimation_fixture(project_a)

    %{user: owner_b} = user_with_organization_fixture()
    project_b = project_fixture(nil, owner_b)

    assert_raise Postgrex.Error, ~r/estimations_project_org_fkey/, fn ->
      Repo.query!("UPDATE estimations SET project_id = $1 WHERE id = $2", [
        Ecto.UUID.dump!(project_b.id),
        Ecto.UUID.dump!(estimation_a.id)
      ])
    end

    assert Repo.reload!(estimation_a).project_id == project_a.id
  end
end
