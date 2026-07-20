defmodule Estimate.EstimationEngine.CreateTaskWithEstimatesTest do
  use Estimate.DataCase, async: false

  import Ecto.Query
  import Estimate.{AccountsFixtures, PortfolioFixtures, EstimationEngineFixtures}
  alias Estimate.EstimationEngine

  setup do
    %{user: user} = user_with_organization_fixture()
    est = estimation_fixture(project_fixture(nil, user))
    epic = epic_fixture(est)

    {:ok, be} =
      EstimationEngine.create_role(%{
        "estimation_id" => est.id,
        "name" => "BE",
        "abbreviation" => "BE"
      })

    %{epic: epic, be: be}
  end

  test "creates task and its estimates atomically", %{epic: epic, be: be} do
    assert {:ok, task} =
             EstimationEngine.create_task_with_estimates(epic.id, %{"name" => "Login"}, %{
               be.id => 8
             })

    assert task.name == "Login"
    assert [%{estimation_role_id: rid, hours: hours}] = task.estimates
    assert rid == be.id
    assert Decimal.equal?(hours, Decimal.new(8))
  end

  test "empty efforts creates just the task", %{epic: epic} do
    assert {:ok, task} =
             EstimationEngine.create_task_with_estimates(epic.id, %{"name" => "Skeleton"}, %{})

    assert task.estimates == []
  end

  test "a bad estimate rolls the whole thing back", %{epic: epic} do
    assert {:error, _cs} =
             EstimationEngine.create_task_with_estimates(epic.id, %{"name" => "X"}, %{
               Ecto.UUID.generate() => 8
             })

    assert Estimate.Repo.aggregate(
             from(t in Estimate.EstimationEngine.Task, where: t.name == "X"),
             :count
           ) == 0
  end
end
