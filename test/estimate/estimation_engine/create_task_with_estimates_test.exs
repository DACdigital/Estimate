defmodule Estimate.EstimationEngine.CreateTaskWithEstimatesTest do
  use Estimate.DataCase, async: false

  import Ecto.Query
  import Estimate.{AccountsFixtures, PortfolioFixtures, EstimationEngineFixtures}
  alias Estimate.EstimationEngine

  setup do
    %{user: user, organization: org} = user_with_organization_fixture()
    est = estimation_fixture(project_fixture(nil, user))
    epic = epic_fixture(est)

    {:ok, be} =
      EstimationEngine.create_role(%{
        "estimation_id" => est.id,
        "name" => "BE",
        "abbreviation" => "BE"
      })

    %{epic: epic, be: be, est: est, org: org}
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

  # Mirrors `create_task/1`'s reindex-on-create parity (web path already does
  # this). Tasks have no `searchable_type` of their own — they fold into the
  # parent estimation's `content` (see `Search.build_estimation_content/2`) —
  # so a task only becomes findable once the estimation is reindexed with the
  # new task preloaded. Before the fix, this call is missing and the search
  # index still reflects the pre-task content.
  test "reindexes the estimation so the new task becomes searchable", %{
    epic: epic,
    est: est,
    org: org
  } do
    assert {:ok, _task} =
             EstimationEngine.create_task_with_estimates(
               epic.id,
               %{"name" => "Zyxelquat Onboarding"},
               %{}
             )

    assert Enum.any?(
             Estimate.Search.search(org.id, "Zyxelquat"),
             &(&1.type == "estimation" and &1.id == est.id)
           )
  end
end
