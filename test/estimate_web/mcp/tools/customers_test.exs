defmodule EstimateWeb.MCP.Tools.CustomersTest do
  use Estimate.DataCase, async: false

  import Estimate.AccountsFixtures
  import Estimate.CRMFixtures
  import Estimate.MCPFixtures

  alias Anubis.Server.Response
  alias EstimateWeb.MCP.Tools.{GetCustomer, ListCustomers}

  setup do
    %{user: user, organization: org} = user_with_organization_fixture()
    %{user: user, org: org, frame: mcp_frame(user, org)}
  end

  defp json_content(%Response{content: [%{"type" => "text", "text" => text}]}) do
    Jason.decode!(text)
  end

  describe "list_customers" do
    test "returns org customers with search filter and limit", %{org: org, frame: frame} do
      customer_fixture(org, %{"name" => "Acme Corp"})
      customer_fixture(org, %{"name" => "Beta LLC"})

      assert {:reply, response, _} = ListCustomers.execute(%{search: "acme", limit: 50}, frame)
      refute response.isError

      assert %{"customers" => [%{"name" => "Acme Corp"}]} = json_content(response)
    end

    test "cross-org: other org's customers are invisible", %{frame: frame} do
      %{organization: other_org} = user_with_organization_fixture()
      customer_fixture(other_org, %{"name" => "Foreign Inc"})

      assert {:reply, response, _} = ListCustomers.execute(%{limit: 50}, frame)
      assert %{"customers" => []} = json_content(response)
    end
  end

  describe "get_customer" do
    test "returns own customer", %{org: org, frame: frame} do
      customer = customer_fixture(org, %{"name" => "Acme Corp"})

      assert {:reply, response, _} = GetCustomer.execute(%{id: customer.id}, frame)
      refute response.isError
      assert %{"name" => "Acme Corp", "id" => id} = json_content(response)
      assert id == customer.id
    end

    test "foreign org customer → not found (no existence oracle)", %{frame: frame} do
      %{organization: other_org} = user_with_organization_fixture()
      foreign = customer_fixture(other_org)

      assert {:reply, %Response{isError: true}, _} = GetCustomer.execute(%{id: foreign.id}, frame)
    end

    test "malformed id → not found, not a crash", %{frame: frame} do
      assert {:reply, %Response{isError: true}, _} =
               GetCustomer.execute(%{id: "not-a-uuid"}, frame)
    end
  end
end
