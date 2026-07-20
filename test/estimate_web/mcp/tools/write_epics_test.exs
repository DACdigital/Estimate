defmodule EstimateWeb.MCP.Tools.WriteEpicsTest do
  use Estimate.DataCase, async: false

  import Estimate.{AccountsFixtures, PortfolioFixtures, EstimationEngineFixtures, MCPFixtures}
  import Estimate.MCPTestHelpers
  alias Anubis.Server.Response
  alias EstimateWeb.MCP.Tools.{AddEpic, UpdateEpic}

  setup do
    %{user: owner, organization: org} = user_with_organization_fixture()
    enable_mcp_write(org)
    est = estimation_fixture(project_fixture(nil, owner))
    %{owner: owner, org: org, est: est}
  end

  defp frame(user, org, role \\ "owner"), do: mcp_frame(user, org, role)

  test "adds an epic", %{owner: owner, org: org, est: est} do
    assert {:reply, resp, _} =
             AddEpic.execute(
               %{estimation_id: est.id, name: "Backend", description: "APIs"},
               frame(owner, org)
             )

    refute resp.isError
    body = json_content(resp)
    assert body["name"] == "Backend"
    assert body["url"] =~ "/estimations/#{est.id}/estimator"
  end

  test "non-collaborator denied", %{org: org, est: est} do
    member = user_fixture()
    _ = membership_fixture(member, org, "member")

    # `estimation_access` RLS (org admins or project collaborators only) hides
    # the row entirely from a bare member — denies at `project_id_for` (not
    # found), never reaching `require_can_edit_project`. Same shape as
    # AddEstimationRole's non-collaborator case in write_roles_test.exs.
    assert {:reply, %Response{isError: true} = resp, _} =
             AddEpic.execute(%{estimation_id: est.id, name: "X"}, frame(member, org, "member"))

    assert json_error(resp) =~ "not found"
  end

  test "updates an epic name", %{owner: owner, org: org, est: est} do
    {:reply, add, _} = AddEpic.execute(%{estimation_id: est.id, name: "Old"}, frame(owner, org))
    epic_id = json_content(add)["id"]

    assert {:reply, resp, _} = UpdateEpic.execute(%{id: epic_id, name: "New"}, frame(owner, org))
    refute resp.isError
    assert json_content(resp)["name"] == "New"
  end
end
