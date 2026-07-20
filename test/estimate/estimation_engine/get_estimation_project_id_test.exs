defmodule Estimate.EstimationEngine.GetEstimationProjectIdTest do
  use Estimate.DataCase, async: false

  import Estimate.{AccountsFixtures, PortfolioFixtures, EstimationEngineFixtures}
  alias Estimate.EstimationEngine

  test "returns the owning project id" do
    %{user: user, organization: org} = user_with_organization_fixture()
    project = project_fixture(nil, user)
    estimation = estimation_fixture(project)

    assert EstimationEngine.get_estimation_project_id(estimation.id, org.id) == project.id
  end

  test "returns nil for a foreign-org estimation" do
    est = estimation_fixture()
    %{organization: other} = user_with_organization_fixture()
    assert EstimationEngine.get_estimation_project_id(est.id, other.id) == nil
  end
end
