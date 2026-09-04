defmodule EstimateWeb.MCP.AuthzTest do
  use Estimate.DataCase, async: false

  import Estimate.{AccountsFixtures, PortfolioFixtures, EstimationEngineFixtures, MCPFixtures}
  alias EstimateWeb.MCP.{Authz, Scope}

  defp claims(user, org, role), do: Scope.claims(mcp_frame(user, org, role))

  setup do
    %{user: owner, organization: org} = user_with_organization_fixture()
    %{owner: owner, org: org}
  end

  describe "require_write_enabled" do
    test "off by default, on after enable", %{owner: owner, org: org} do
      assert Authz.require_write_enabled(claims(owner, org, "owner")) == {:error, :write_disabled}
      enable_mcp_write(org)
      assert Authz.require_write_enabled(claims(owner, org, "owner")) == :ok
    end
  end

  describe "require_org_admin" do
    test "owner/admin pass, member fails", %{owner: owner, org: org} do
      assert Authz.require_org_admin(claims(owner, org, "owner")) == :ok
      assert Authz.require_org_admin(claims(owner, org, "admin")) == :ok
      assert Authz.require_org_admin(claims(owner, org, "member")) == {:error, :unauthorized}
    end
  end

  describe "require_can_edit_project" do
    setup %{owner: owner} do
      project = project_fixture(nil, owner)
      %{project: project}
    end

    test "org admin always passes", %{owner: owner, org: org, project: project} do
      assert Authz.require_can_edit_project(project.id, claims(owner, org, "admin")) == :ok
    end

    test "member who is owner/editor collaborator passes; viewer/non-collaborator fails",
         %{org: org, project: project} do
      member = build_member(org)
      member = member.user

      # non-collaborator member
      assert Authz.require_can_edit_project(project.id, claims(member, org, "member")) ==
               {:error, :unauthorized}

      {:ok, _} = Estimate.Portfolio.add_collaborator(project.id, member.id, "viewer")

      assert Authz.require_can_edit_project(project.id, claims(member, org, "member")) ==
               {:error, :unauthorized}

      collab = Estimate.Portfolio.get_collaborator(project.id, member.id)
      {:ok, _} = Estimate.Portfolio.update_collaborator_role(collab, "editor")
      assert Authz.require_can_edit_project(project.id, claims(member, org, "member")) == :ok
    end
  end

  describe "project_id_for / ensure_project" do
    test "resolves estimation/epic/task/role to project; foreign → not_found",
         %{owner: owner, org: org} do
      project = project_fixture(nil, owner)
      est = estimation_fixture(project)
      epic = epic_fixture(est)
      task = task_fixture(epic)

      assert Authz.ensure_project(project.id, org.id) == {:ok, project.id}
      assert Authz.project_id_for(:estimation, est.id, org.id) == {:ok, project.id}
      assert Authz.project_id_for(:epic, epic.id, org.id) == {:ok, project.id}
      assert Authz.project_id_for(:task, task.id, org.id) == {:ok, project.id}

      %{organization: other} = user_with_organization_fixture()
      assert Authz.project_id_for(:estimation, est.id, other.id) == {:error, :not_found}
      assert Authz.ensure_project(project.id, other.id) == {:error, :not_found}
      assert Authz.project_id_for(:task, "not-a-uuid", org.id) == {:error, :not_found}
    end
  end

  describe "require_write_scope" do
    test "write scope passes, read-only fails", %{owner: owner, org: org} do
      full = Scope.claims(mcp_frame(owner, org, "owner"))
      assert Authz.require_write_scope(full) == :ok
      ro = Scope.claims(mcp_frame(owner, org, "owner", "mcp:read"))
      assert Authz.require_write_scope(ro) == {:error, :insufficient_scope}
    end
  end

  # Adds a second user as an org member (role "member") and returns %{user: user}.
  defp build_member(org) do
    user = user_fixture()
    _ = membership_fixture(user, org, "member")
    %{user: user}
  end
end
