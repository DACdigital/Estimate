defmodule EstimateWeb.MCP.Tools.SearchTest do
  use Estimate.DataCase, async: false

  import Estimate.AccountsFixtures
  import Estimate.CRMFixtures
  import Estimate.MCPFixtures
  import Estimate.MCPTestHelpers

  alias EstimateWeb.MCP.Tools.Search

  test "finds indexed entities in own org only" do
    %{user: user, organization: org} = user_with_organization_fixture()
    customer = customer_fixture(org, %{"name" => "Zephyr Industries"})
    Estimate.Search.index_customer(customer)

    %{organization: other_org} = user_with_organization_fixture()
    foreign = customer_fixture(other_org, %{"name" => "Zephyr Foreign"})
    Estimate.Search.index_customer(foreign)

    frame = mcp_frame(user, org)
    assert {:reply, response, _} = Search.execute(%{query: "zephyr", limit: 8}, frame)
    refute response.isError

    assert %{"results" => [hit]} = json_content(response)
    assert hit["title"] =~ "Zephyr Industries"
    assert hit["type"] == "customer"
  end
end
