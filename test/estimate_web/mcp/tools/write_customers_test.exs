defmodule EstimateWeb.MCP.Tools.WriteCustomersTest do
  use Estimate.DataCase, async: false

  import Estimate.{AccountsFixtures, CRMFixtures, MCPFixtures}
  import Estimate.MCPTestHelpers
  alias Anubis.Server.Response
  alias EstimateWeb.MCP.Tools.CreateCustomer

  setup do
    %{user: owner, organization: org} = user_with_organization_fixture()
    enable_mcp_write(org)
    %{owner: owner, org: org}
  end

  defp frame(user, org, role \\ "owner"), do: mcp_frame(user, org, role)

  test "admin creates a customer; response carries id + url", %{owner: owner, org: org} do
    assert {:reply, resp, _} =
             CreateCustomer.execute(
               %{key: "acme", name: "Acme Corp", currency: "EUR"},
               frame(owner, org)
             )

    refute resp.isError
    body = json_content(resp)
    assert body["key"] == "ACME"
    assert body["name"] == "Acme Corp"
    assert body["currency"] == "EUR"
    assert body["url"] =~ "/org/#{org.id}/customers/#{body["id"]}"
  end

  test "member is not authorized", %{org: org} do
    member = user_fixture()
    _ = membership_fixture(member, org, "member")

    assert {:reply, %Response{isError: true} = resp, _} =
             CreateCustomer.execute(%{key: "ACME", name: "Acme"}, frame(member, org, "member"))

    assert json_error(resp) =~ "not authorized"
  end

  test "writes disabled → rejected", %{} do
    %{user: owner2, organization: org2} = user_with_organization_fixture()
    # org2 write NOT enabled
    assert {:reply, %Response{isError: true} = resp, _} =
             CreateCustomer.execute(%{key: "ACME", name: "Acme"}, frame(owner2, org2))

    assert json_error(resp) =~ "writes are disabled"
  end

  test "duplicate key → readable changeset error", %{owner: owner, org: org} do
    customer_fixture(org, %{"key" => "ACME", "name" => "Acme"})

    assert {:reply, %Response{isError: true} = resp, _} =
             CreateCustomer.execute(%{key: "ACME", name: "Acme Two"}, frame(owner, org))

    assert json_error(resp) =~ "key:"
  end

  test "admin updates a customer's name + currency", %{owner: owner, org: org} do
    customer = customer_fixture(org, %{"key" => "ACME", "name" => "Acme"})

    assert {:reply, resp, _} =
             EstimateWeb.MCP.Tools.UpdateCustomer.execute(
               %{id: customer.id, name: "Acme Renamed", currency: "GBP"},
               frame(owner, org)
             )

    refute resp.isError
    body = json_content(resp)
    assert body["name"] == "Acme Renamed"
    assert body["currency"] == "GBP"
    assert body["url"] =~ "/customers/#{customer.id}"
  end

  test "update foreign-org customer → not found", %{owner: owner, org: org} do
    %{organization: other} = user_with_organization_fixture()
    foreign = customer_fixture(other, %{"key" => "FGN", "name" => "Foreign"})

    assert {:reply, %Response{isError: true} = resp, _} =
             EstimateWeb.MCP.Tools.UpdateCustomer.execute(
               %{id: foreign.id, name: "x"},
               frame(owner, org)
             )

    assert json_error(resp) =~ "not found"
  end

  test "read-only oauth scope cannot write even with the toggle on", %{owner: owner, org: org} do
    assert {:reply, %Response{isError: true} = resp, _} =
             CreateCustomer.execute(
               %{key: "ACME", name: "Acme"},
               mcp_frame(owner, org, "owner", "mcp:read")
             )

    assert json_error(resp) =~ "authorized read-only"
    refute Estimate.Repo.get_by(Estimate.CRM.Customer, key: "ACME", organization_id: org.id)
  end
end
