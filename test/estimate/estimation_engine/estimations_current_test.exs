defmodule Estimate.EstimationEngine.EstimationsCurrentTest do
  use Estimate.DataCase, async: true
  import Estimate.{AccountsFixtures, PortfolioFixtures, EstimationEngineFixtures}
  alias Estimate.EstimationEngine.Estimation
  alias Estimate.Repo

  test "a second current estimation on one project is a changeset error" do
    %{user: owner} = user_with_organization_fixture()
    project = project_fixture(nil, owner)
    first = estimation_fixture(project)
    assert Repo.reload!(first).is_current
    second = estimation_fixture(project)
    refute Repo.reload!(second).is_current

    assert {:error, cs} = second |> Estimation.changeset(%{is_current: true}) |> Repo.update()
    assert %{is_current: ["another estimation is already current"]} = errors_on(cs)
  end
end
