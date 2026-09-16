defmodule Estimate.EstimationEngine.EstimationsCurrentTest do
  use Estimate.DataCase, async: true
  import Estimate.{AccountsFixtures, PortfolioFixtures, EstimationEngineFixtures}
  alias Estimate.EstimationEngine
  alias Estimate.EstimationEngine.Estimation
  alias Estimate.Repo

  setup do
    %{user: owner} = user_with_organization_fixture()
    project = project_fixture(nil, owner)
    %{project: project}
  end

  test "a second current estimation on one project is a changeset error", %{project: project} do
    first = estimation_fixture(project)
    assert Repo.reload!(first).is_current
    second = estimation_fixture(project)
    refute Repo.reload!(second).is_current

    assert {:error, cs} = second |> Estimation.changeset(%{is_current: true}) |> Repo.update()
    assert %{is_current: ["another estimation is already current"]} = errors_on(cs)
  end

  test "set_current_changeset/1 hits the same unique constraint as a changeset error, not a raise",
       %{project: project} do
    _first = estimation_fixture(project)
    second = estimation_fixture(project)

    assert {:error, cs} = second |> Estimation.set_current_changeset() |> Repo.update()
    assert %{is_current: ["another estimation is already current"]} = errors_on(cs)
    refute Repo.reload!(second).is_current
  end

  test "restoring the only estimation of a project makes it current again", %{project: project} do
    only = estimation_fixture(project)
    assert Repo.reload!(only).is_current

    {:ok, deleted} = EstimationEngine.soft_delete_estimation(Repo.reload!(only))
    refute deleted.is_current

    assert {:ok, restored} = EstimationEngine.restore_estimation(deleted)
    assert Repo.reload!(restored).is_current
  end

  test "restoring when another estimation is current leaves both flags unchanged", %{
    project: project
  } do
    first = estimation_fixture(project)
    second = estimation_fixture(project)
    assert Repo.reload!(first).is_current
    refute Repo.reload!(second).is_current

    {:ok, deleted} = EstimationEngine.soft_delete_estimation(Repo.reload!(second))
    assert {:ok, _restored} = EstimationEngine.restore_estimation(deleted)

    assert Repo.reload!(first).is_current
    refute Repo.reload!(second).is_current
  end
end
