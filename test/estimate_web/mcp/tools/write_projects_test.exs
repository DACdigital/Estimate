defmodule EstimateWeb.MCP.Tools.WriteProjectsTest do
  use Estimate.DataCase, async: false

  import Estimate.{AccountsFixtures, CRMFixtures, MCPFixtures}
  import Estimate.MCPTestHelpers
  alias Anubis.Server.Response
  alias EstimateWeb.MCP.Tools.CreateProject

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
end
