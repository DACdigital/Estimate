defmodule EstimateWeb.MCP.Tools.ProjectsTest do
  use Estimate.DataCase, async: false

  import Estimate.AccountsFixtures
  import Estimate.CRMFixtures
  import Estimate.PortfolioFixtures
  import Estimate.MCPFixtures
  import Estimate.MCPTestHelpers

  alias Anubis.Server.Response
  alias EstimateWeb.MCP.Tools.{GetProject, ListProjects}

  setup do
    %{user: owner, organization: org} = user_with_organization_fixture()
    customer = customer_fixture(org)
    project = project_fixture(customer, owner, %{"name" => "Apollo"})
    %{owner: owner, org: org, customer: customer, project: project}
  end

  describe "list_projects" do
    test "owner sees all org projects", %{owner: owner, org: org} do
      frame = mcp_frame(owner, org, "owner")

      assert {:reply, response, _} = ListProjects.execute(%{limit: 50}, frame)
      assert %{"projects" => [%{"name" => "Apollo"}]} = json_content(response)
    end

    test "member without collaborator access sees nothing", %{org: org} do
      member = user_fixture()
      membership_fixture(member, org, "member")
      frame = mcp_frame(member, org, "member")

      assert {:reply, response, _} = ListProjects.execute(%{limit: 50}, frame)
      assert %{"projects" => []} = json_content(response)
    end
  end

  describe "get_project" do
    test "owner gets project with roles and estimation summaries", %{
      owner: owner,
      org: org,
      project: project
    } do
      frame = mcp_frame(owner, org, "owner")

      assert {:reply, response, _} = GetProject.execute(%{id: project.id}, frame)
      refute response.isError

      body = json_content(response)
      assert body["name"] == "Apollo"
      assert is_list(body["roles"])
      assert is_list(body["estimations"])
    end

    test "member without access → not found", %{org: org, project: project} do
      member = user_fixture()
      membership_fixture(member, org, "member")
      frame = mcp_frame(member, org, "member")

      assert {:reply, %Response{isError: true}, _} = GetProject.execute(%{id: project.id}, frame)
    end

    test "foreign org project → not found", %{project: project} do
      %{user: outsider, organization: other_org} = user_with_organization_fixture()
      frame = mcp_frame(outsider, other_org, "owner")

      assert {:reply, %Response{isError: true}, _} = GetProject.execute(%{id: project.id}, frame)
    end
  end
end
