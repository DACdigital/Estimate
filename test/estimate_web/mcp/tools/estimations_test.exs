defmodule EstimateWeb.MCP.Tools.EstimationsTest do
  use Estimate.DataCase, async: false

  import Estimate.AccountsFixtures
  import Estimate.CRMFixtures
  import Estimate.PortfolioFixtures
  import Estimate.EstimationEngineFixtures
  import Estimate.MCPFixtures

  alias Anubis.Server.Response
  alias EstimateWeb.MCP.Tools.{GetEstimation, ListEstimations}

  setup do
    %{user: owner, organization: org} = user_with_organization_fixture()
    customer = customer_fixture(org)
    project = project_fixture(customer, owner)
    estimation = estimation_fixture(project, %{"name" => "MVP v1"})
    epic = epic_fixture(estimation, %{"name" => "Auth"})
    task_fixture(epic, %{"name" => "Login flow"})

    %{
      owner: owner,
      org: org,
      project: project,
      estimation: estimation,
      frame: mcp_frame(owner, org, "owner")
    }
  end

  defp json_content(%Response{content: [%{"type" => "text", "text" => text}]}) do
    Jason.decode!(text)
  end

  test "list_estimations returns project estimations", %{project: project, frame: frame} do
    assert {:reply, response, _} = ListEstimations.execute(%{project_id: project.id}, frame)
    assert %{"estimations" => [%{"name" => "MVP v1"}]} = json_content(response)
  end

  test "get_estimation returns full tree with totals", %{estimation: estimation, frame: frame} do
    assert {:reply, response, _} = GetEstimation.execute(%{id: estimation.id}, frame)
    refute response.isError

    body = json_content(response)
    assert body["name"] == "MVP v1"

    assert [%{"name" => "Auth", "tasks" => [%{"name" => "Login flow", "priority" => "must"}]}] =
             body["epics"]

    assert %{"total_hours" => _, "grand_total_with_overhead" => _} = body["totals"]
  end

  test "foreign org estimation → not found", %{estimation: estimation} do
    %{user: outsider, organization: other_org} = user_with_organization_fixture()
    frame = mcp_frame(outsider, other_org, "owner")

    assert {:reply, %Response{isError: true}, _} =
             GetEstimation.execute(%{id: estimation.id}, frame)
  end
end
