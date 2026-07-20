defmodule EstimateWeb.MCP.Tools.WriteEstimationsTest do
  use Estimate.DataCase, async: false

  import Estimate.{AccountsFixtures, PortfolioFixtures, EstimationEngineFixtures, MCPFixtures}
  import Estimate.MCPTestHelpers
  alias Anubis.Server.Response
  alias Estimate.Portfolio
  alias EstimateWeb.MCP.Tools.{CreateEstimation, UpdateEstimation}

  setup do
    %{user: owner, organization: org} = user_with_organization_fixture()
    enable_mcp_write(org)
    project = project_fixture(nil, owner)
    %{owner: owner, org: org, project: project}
  end

  defp frame(user, org, role \\ "owner"), do: mcp_frame(user, org, role)

  test "inline roles are created; response has tree totals + url", %{
    owner: owner,
    org: org,
    project: project
  } do
    params = %{
      project_id: project.id,
      name: "MVP",
      currency: "EUR",
      roles: [
        %{name: "Backend", abbreviation: "BE", hourly_rate: 90.0},
        %{name: "Frontend", abbreviation: "FE", hourly_rate: 80.0}
      ]
    }

    assert {:reply, resp, _} = CreateEstimation.execute(params, frame(owner, org))
    refute resp.isError
    body = json_content(resp)
    assert body["name"] == "MVP"
    assert Enum.map(body["roles"], & &1["abbreviation"]) |> Enum.sort() == ["BE", "FE"]
    assert body["url"] =~ "/projects/#{project.id}/estimations/#{body["id"]}/estimator"
  end

  test "omitting roles seeds the org role templates", %{owner: owner, org: org, project: project} do
    assert {:reply, resp, _} =
             CreateEstimation.execute(
               %{project_id: project.id, name: "Seeded"},
               frame(owner, org)
             )

    refute resp.isError
    # user_with_organization_fixture seeds 8 default role templates
    assert length(json_content(resp)["roles"]) == 8
  end

  test "org member who is not a collaborator can't see the project → not found", %{
    org: org,
    project: project
  } do
    member = user_fixture()
    _ = membership_fixture(member, org, "member")

    # Project-level RLS (`project_access` policy) only admits org admins or
    # project collaborators — a bare member has no row visibility at all, so
    # this denies at `ensure_project` (not found), never reaching the
    # collaborator-role check.
    assert {:reply, %Response{isError: true} = resp, _} =
             CreateEstimation.execute(
               %{project_id: project.id, name: "Nope"},
               frame(member, org, "member")
             )

    assert json_error(resp) =~ "not found"
  end

  test "project collaborator without edit rights is denied", %{org: org, project: project} do
    viewer = user_fixture()
    _ = membership_fixture(viewer, org, "member")
    {:ok, _} = Portfolio.add_collaborator(project.id, viewer.id, "viewer")

    assert {:reply, %Response{isError: true} = resp, _} =
             CreateEstimation.execute(
               %{project_id: project.id, name: "Nope"},
               frame(viewer, org, "member")
             )

    assert json_error(resp) =~ "not authorized"
  end

  test "unknown project → not found", %{owner: owner, org: org} do
    assert {:reply, %Response{isError: true} = resp, _} =
             CreateEstimation.execute(
               %{project_id: Ecto.UUID.generate(), name: "x"},
               frame(owner, org)
             )

    assert json_error(resp) =~ "not found"
  end

  test "owner updates estimation name + currency", %{owner: owner, org: org, project: project} do
    est = estimation_fixture(project)

    assert {:reply, resp, _} =
             UpdateEstimation.execute(
               %{id: est.id, name: "Renamed", currency: "GBP"},
               frame(owner, org)
             )

    refute resp.isError
    body = json_content(resp)
    assert body["name"] == "Renamed"
    assert body["currency"] == "GBP"
    assert body["url"] =~ "/estimations/#{est.id}/estimator"
  end

  # A real MCP client JSON-encodes a whole-number rate without a decimal
  # point (`{"hourly_rate": 90}`), which Jason decodes as an Elixir integer,
  # not a float. Peri's bare `:float` type rejects every such integer at
  # schema-validation time, before `execute/2` ever runs — see `add_task.ex`'s
  # `{:either, {:float, :integer}}` fix (`efforts`) and the task-15b report
  # for the full empirical trace. `roles` is an `embeds_many`, so this also
  # covers integer acceptance through a nested Peri schema.
  test "schema validation accepts whole-number (integer) role hourly_rate + overhead", %{
    project: project
  } do
    params = %{
      "project_id" => project.id,
      "name" => "MVP",
      "roles" => [
        %{"name" => "Backend", "abbreviation" => "BE", "hourly_rate" => 90, "pm_overhead" => 10}
      ]
    }

    assert {:ok, validated} = CreateEstimation.mcp_schema(params)
    assert [%{hourly_rate: 90, pm_overhead: 10}] = validated.roles
  end
end
