defmodule EstimateWeb.MCP.Tools.WriteTasksTest do
  use Estimate.DataCase, async: false

  import Ecto.Query
  import Estimate.{AccountsFixtures, PortfolioFixtures, EstimationEngineFixtures, MCPFixtures}
  import Estimate.MCPTestHelpers
  alias Anubis.Server.Response
  alias Estimate.EstimationEngine
  alias EstimateWeb.MCP.Tools.{AddTask, UpdateTask}

  setup do
    %{user: owner, organization: org} = user_with_organization_fixture()
    enable_mcp_write(org)
    est = estimation_fixture(project_fixture(nil, owner))
    epic = epic_fixture(est)

    {:ok, _be} =
      EstimationEngine.create_role(%{
        "estimation_id" => est.id,
        "name" => "BE",
        "abbreviation" => "BE"
      })

    %{owner: owner, org: org, est: est, epic: epic}
  end

  defp frame(user, org, role \\ "owner"), do: mcp_frame(user, org, role)

  test "adds a task with inline efforts", %{owner: owner, org: org, epic: epic, est: est} do
    assert {:reply, resp, _} =
             AddTask.execute(
               %{epic_id: epic.id, name: "Login", priority: "must", efforts: %{"BE" => 8.0}},
               frame(owner, org)
             )

    refute resp.isError
    body = json_content(resp)
    assert body["name"] == "Login"
    assert [%{"hours" => "8"}] = body["estimates"]
    assert body["url"] =~ "/estimations/#{est.id}/estimator"
  end

  test "adds a skeleton task with no efforts (priority defaults to must)", %{
    owner: owner,
    org: org,
    epic: epic
  } do
    assert {:reply, resp, _} =
             AddTask.execute(%{epic_id: epic.id, name: "Later"}, frame(owner, org))

    refute resp.isError
    body = json_content(resp)
    assert body["priority"] == "must"
    assert body["estimates"] == []
  end

  test "unknown effort abbreviation → error listing valid ones, no task created", %{
    owner: owner,
    org: org,
    epic: epic
  } do
    assert {:reply, %Response{isError: true} = resp, _} =
             AddTask.execute(
               %{epic_id: epic.id, name: "Bad", efforts: %{"ZZ" => 3.0}},
               frame(owner, org)
             )

    err = json_error(resp)
    assert err =~ "ZZ"
    assert err =~ "BE"

    assert Repo.aggregate(
             from(t in Estimate.EstimationEngine.Task, where: t.name == "Bad"),
             :count
           ) == 0
  end

  test "non-collaborator denied", %{org: org, epic: epic} do
    member = user_fixture()
    _ = membership_fixture(member, org, "member")

    # `estimation_access` RLS (org admins or project collaborators only) hides
    # the row entirely from a bare member — denies at `project_id_for` (not
    # found), never reaching `require_can_edit_project`. Same shape as
    # AddEpic's non-collaborator case in write_epics_test.exs.
    assert {:reply, %Response{isError: true} = resp, _} =
             AddTask.execute(%{epic_id: epic.id, name: "X"}, frame(member, org, "member"))

    assert json_error(resp) =~ "not found"
  end

  test "updates a task priority", %{owner: owner, org: org, epic: epic} do
    {:reply, add, _} = AddTask.execute(%{epic_id: epic.id, name: "T"}, frame(owner, org))
    task_id = json_content(add)["id"]

    assert {:reply, resp, _} =
             UpdateTask.execute(%{id: task_id, priority: "could"}, frame(owner, org))

    refute resp.isError
    assert json_content(resp)["priority"] == "could"
  end
end
