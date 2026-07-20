defmodule EstimateWeb.MCP.Tools.WriteRolesTest do
  use Estimate.DataCase, async: false

  import Estimate.{AccountsFixtures, PortfolioFixtures, EstimationEngineFixtures, MCPFixtures}
  import Estimate.MCPTestHelpers
  alias Anubis.Server.Response
  alias EstimateWeb.MCP.Tools.{AddEstimationRole, UpdateEstimationRole}

  setup do
    %{user: owner, organization: org} = user_with_organization_fixture()
    enable_mcp_write(org)
    project = project_fixture(nil, owner)
    est = estimation_fixture(project)
    %{owner: owner, org: org, project: project, est: est}
  end

  defp frame(user, org, role \\ "owner"), do: mcp_frame(user, org, role)

  test "adds a role with rate + overheads", %{owner: owner, org: org, est: est} do
    assert {:reply, resp, _} =
             AddEstimationRole.execute(
               %{
                 estimation_id: est.id,
                 name: "DevOps",
                 abbreviation: "DO",
                 hourly_rate: 100.0,
                 pm_overhead: 10.0
               },
               frame(owner, org)
             )

    refute resp.isError
    body = json_content(resp)
    assert body["abbreviation"] == "DO"
    assert body["hourly_rate"] == "100"
    assert body["url"] =~ "/estimations/#{est.id}/estimator"
  end

  test "adds a role without hourly_rate defaults to 0 (no NOT NULL crash)", %{
    owner: owner,
    org: org,
    est: est
  } do
    assert {:reply, resp, _} =
             AddEstimationRole.execute(
               %{estimation_id: est.id, name: "NoRate", abbreviation: "NR"},
               frame(owner, org)
             )

    refute resp.isError
    assert json_content(resp)["hourly_rate"] == "0"
  end

  test "add rejects abbreviation over 5 chars with readable error", %{
    owner: owner,
    org: org,
    est: est
  } do
    assert {:reply, %Response{isError: true} = resp, _} =
             AddEstimationRole.execute(
               %{estimation_id: est.id, name: "X", abbreviation: "TOOLONG"},
               frame(owner, org)
             )

    assert json_error(resp) =~ "abbreviation:"
  end

  test "non-collaborator member denied", %{org: org, est: est} do
    member = user_fixture()
    _ = membership_fixture(member, org, "member")

    # `estimation_access` RLS (org admins or project collaborators only) hides
    # the row entirely from a bare member — denies at `project_id_for` (not
    # found), never reaching `require_can_edit_project`. Same shape as
    # CreateEstimation's non-collaborator case in write_estimations_test.exs.
    assert {:reply, %Response{isError: true} = resp, _} =
             AddEstimationRole.execute(
               %{estimation_id: est.id, name: "X", abbreviation: "X"},
               frame(member, org, "member")
             )

    assert json_error(resp) =~ "not found"
  end

  test "updates a role's rate", %{owner: owner, org: org, est: est} do
    {:reply, add, _} =
      AddEstimationRole.execute(
        %{estimation_id: est.id, name: "BE", abbreviation: "BE", hourly_rate: 90.0},
        frame(owner, org)
      )

    role_id = json_content(add)["id"]

    assert {:reply, resp, _} =
             UpdateEstimationRole.execute(%{id: role_id, hourly_rate: 120.0}, frame(owner, org))

    refute resp.isError
    assert json_content(resp)["hourly_rate"] == "120"
  end

  # A real MCP client JSON-encodes a whole-number rate without a decimal
  # point (`{"hourly_rate": 90}`), which Jason decodes as an Elixir integer,
  # not a float. Peri's bare `:float` type rejects every such integer at
  # schema-validation time, before `execute/2` ever runs — see `add_task.ex`'s
  # `{:either, {:float, :integer}}` fix (`efforts`) and the task-15b report
  # for the full empirical trace.
  test "add schema validation accepts whole-number (integer) hourly_rate + overhead", %{
    est: est
  } do
    params = %{
      "estimation_id" => est.id,
      "name" => "X",
      "abbreviation" => "X",
      "hourly_rate" => 90,
      "pm_overhead" => 10
    }

    assert {:ok, validated} = AddEstimationRole.mcp_schema(params)
    assert validated.hourly_rate == 90
    assert validated.pm_overhead == 10
  end

  test "update schema validation accepts whole-number (integer) hourly_rate + overhead" do
    params = %{
      "id" => Ecto.UUID.generate(),
      "hourly_rate" => 120,
      "qa_overhead" => 5
    }

    assert {:ok, validated} = UpdateEstimationRole.mcp_schema(params)
    assert validated.hourly_rate == 120
    assert validated.qa_overhead == 5
  end
end
