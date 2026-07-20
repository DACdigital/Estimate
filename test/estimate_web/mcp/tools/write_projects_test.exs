defmodule EstimateWeb.MCP.Tools.WriteProjectsTest do
  use Estimate.DataCase, async: false

  import Estimate.{AccountsFixtures, CRMFixtures, MCPFixtures, PortfolioFixtures}
  import Estimate.MCPTestHelpers
  alias Anubis.Server.Response
  alias Estimate.Portfolio
  alias EstimateWeb.MCP.Tools.{CreateProject, UpdateProject}

  setup do
    %{user: owner, organization: org} = user_with_organization_fixture()
    enable_mcp_write(org)
    customer = customer_fixture(org, %{"key" => "ACME", "name" => "Acme"})
    %{owner: owner, org: org, customer: customer}
  end

  defp frame(user, org, role \\ "owner"), do: mcp_frame(user, org, role)

  test "member can create a project (becomes owner)", %{org: org, customer: customer} do
    member = user_fixture()
    _ = membership_fixture(member, org, "member")

    assert {:reply, resp, _} =
             CreateProject.execute(
               %{customer_id: customer.id, name: "Website", key: "WEB"},
               frame(member, org, "member")
             )

    refute resp.isError
    body = json_content(resp)
    assert body["name"] == "Website"
    assert body["url"] =~ "/projects/#{body["id"]}"
  end

  test "bad customer id → not found", %{owner: owner, org: org} do
    assert {:reply, %Response{isError: true} = resp, _} =
             CreateProject.execute(
               %{customer_id: Ecto.UUID.generate(), name: "X"},
               frame(owner, org)
             )

    assert json_error(resp) =~ "not found"
  end

  test "writes disabled → rejected", %{customer: _customer} do
    %{user: owner2, organization: org2} = user_with_organization_fixture()
    c2 = customer_fixture(org2, %{"key" => "BETA", "name" => "Beta"})

    assert {:reply, %Response{isError: true} = resp, _} =
             CreateProject.execute(%{customer_id: c2.id, name: "X"}, frame(owner2, org2))

    assert json_error(resp) =~ "writes are disabled"
  end

  test "owner edits; viewer collaborator is denied", %{owner: owner, org: org, customer: customer} do
    project = project_fixture(customer, owner, %{"name" => "Site"})

    assert {:reply, resp, _} =
             UpdateProject.execute(%{id: project.id, name: "Site v2"}, frame(owner, org))

    refute resp.isError
    assert json_content(resp)["name"] == "Site v2"

    viewer = user_fixture()
    _ = membership_fixture(viewer, org, "member")
    {:ok, _} = Portfolio.add_collaborator(project.id, viewer.id, "viewer")

    assert {:reply, %Response{isError: true} = denied, _} =
             UpdateProject.execute(%{id: project.id, name: "Nope"}, frame(viewer, org, "member"))

    assert json_error(denied) =~ "not authorized"
  end
end
