defmodule EstimateWeb.MCP.Tools.SetTaskEffortTest do
  use Estimate.DataCase, async: false

  import Estimate.{AccountsFixtures, PortfolioFixtures, EstimationEngineFixtures, MCPFixtures}
  import Estimate.MCPTestHelpers
  alias Anubis.Server.Response
  alias Estimate.EstimationEngine
  alias EstimateWeb.MCP.Tools.SetTaskEffort

  setup do
    %{user: owner, organization: org} = user_with_organization_fixture()
    enable_mcp_write(org)
    est = estimation_fixture(project_fixture(nil, owner))
    epic = epic_fixture(est)
    task = task_fixture(epic)

    {:ok, be} =
      EstimationEngine.create_role(%{
        "estimation_id" => est.id,
        "name" => "BE",
        "abbreviation" => "BE"
      })

    %{owner: owner, org: org, task: task, be: be}
  end

  defp frame(user, org, role \\ "owner"), do: mcp_frame(user, org, role)

  test "sets effort by abbreviation, then overwrites (upsert)", %{
    owner: owner,
    org: org,
    task: task
  } do
    assert {:reply, resp, _} =
             SetTaskEffort.execute(%{task_id: task.id, role: "BE", hours: 5.0}, frame(owner, org))

    refute resp.isError
    assert json_content(resp)["hours"] == "5"

    assert {:reply, resp2, _} =
             SetTaskEffort.execute(%{task_id: task.id, role: "BE", hours: 9.0}, frame(owner, org))

    assert json_content(resp2)["hours"] == "9"
  end

  test "sets effort by role id", %{owner: owner, org: org, task: task, be: be} do
    assert {:reply, resp, _} =
             SetTaskEffort.execute(
               %{task_id: task.id, role: be.id, hours: 3.0},
               frame(owner, org)
             )

    refute resp.isError
    assert json_content(resp)["role_id"] == be.id
  end

  test "unknown role → error", %{owner: owner, org: org, task: task} do
    assert {:reply, %Response{isError: true} = resp, _} =
             SetTaskEffort.execute(%{task_id: task.id, role: "ZZ", hours: 1.0}, frame(owner, org))

    assert json_error(resp) =~ "ZZ"
  end

  test "non-collaborator denied", %{org: org, task: task} do
    member = user_fixture()
    _ = membership_fixture(member, org, "member")

    # `estimation_access` RLS (org admins or project collaborators only) hides
    # the row entirely from a bare member — denies at `project_id_for` (not
    # found), never reaching `require_can_edit_project`. Same shape as
    # AddTask's non-collaborator case in write_tasks_test.exs.
    assert {:reply, %Response{isError: true} = resp, _} =
             SetTaskEffort.execute(
               %{task_id: task.id, role: "BE", hours: 1.0},
               frame(member, org, "member")
             )

    assert json_error(resp) =~ "not found"
  end

  # Beyond the brief's verbatim tests: a real MCP client JSON-encodes a
  # whole-number `hours` without a decimal point (`{"hours": 8}`), which
  # Jason decodes as an Elixir integer, not a float. Peri's bare `:float`
  # type rejects every whole-number value at the schema-validation layer,
  # before `execute/2` ever runs — see `add_task.ex`'s
  # `{:either, {:float, :integer}}` fix (`efforts`) and
  # `write_tasks_test.exs`'s equivalent schema-layer test for the full trace.
  # The `execute/2` tests above bypass Peri validation entirely (they call
  # `execute/2` directly with already-valid params), so only a `mcp_schema/1`
  # call exercises this layer.
  test "schema validation accepts whole-number (integer) hours", %{task: task} do
    params = %{"task_id" => task.id, "role" => "BE", "hours" => 8}

    assert {:ok, validated} = SetTaskEffort.mcp_schema(params)
    assert validated.hours == 8
  end
end
