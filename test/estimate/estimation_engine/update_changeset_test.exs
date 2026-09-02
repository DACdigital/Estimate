defmodule Estimate.EstimationEngine.UpdateChangesetTest do
  use Estimate.DataCase, async: true

  import Estimate.{AccountsFixtures, PortfolioFixtures, EstimationEngineFixtures}
  alias Estimate.EstimationEngine
  alias Estimate.EstimationEngine.{Epic, Task, Estimation, EstimationRole, TaskEstimate}

  setup do
    %{user: owner, organization: org} = user_with_organization_fixture()
    project = project_fixture(nil, owner)
    # estimation_fixture/1 returns a bare Repo.get!; reload with roles preloaded
    est_a = EstimationEngine.get_estimation!(estimation_fixture(project).id, org.id)
    est_b = estimation_fixture(project)
    epic_a = epic_fixture(est_a)
    epic_b = epic_fixture(est_b)
    task_a = task_fixture(epic_a)
    %{est_a: est_a, est_b: est_b, epic_a: epic_a, epic_b: epic_b, task_a: task_a}
  end

  test "update_epic ignores estimation_id", %{epic_a: epic_a, est_b: est_b} do
    {:ok, epic} =
      EstimationEngine.update_epic(epic_a, %{"name" => "renamed", "estimation_id" => est_b.id})

    assert epic.name == "renamed"
    assert epic.estimation_id == epic_a.estimation_id
  end

  test "update_task ignores epic_id", %{task_a: task_a, epic_b: epic_b} do
    {:ok, task} =
      EstimationEngine.update_task(task_a, %{"name" => "renamed", "epic_id" => epic_b.id})

    assert task.epic_id == task_a.epic_id
  end

  test "update_estimation ignores project_id and is_current", %{est_a: est_a} do
    {:ok, est} =
      EstimationEngine.update_estimation(est_a, %{
        "is_current" => true,
        "project_id" => Ecto.UUID.generate()
      })

    assert est.project_id == est_a.project_id
    assert est.is_current == est_a.is_current
  end

  test "update_role ignores estimation_id", %{est_a: est_a, est_b: est_b} do
    [role | _] = est_a.roles

    {:ok, role2} =
      EstimationEngine.update_role(role, %{"hourly_rate" => "10", "estimation_id" => est_b.id})

    assert role2.estimation_id == est_a.id
  end

  test "upsert_task_estimate update path ignores forged task_id and estimation_role_id", %{
    est_a: est_a,
    epic_b: epic_b,
    task_a: task_a
  } do
    [role | _] = est_a.roles
    task_b = task_fixture(epic_b)

    {:ok, est} = EstimationEngine.upsert_task_estimate(task_a.id, role.id, %{hours: 2}, est_a.id)

    {:ok, updated} =
      EstimationEngine.upsert_task_estimate(
        task_a.id,
        role.id,
        %{"hours" => "5", "task_id" => task_b.id, "estimation_role_id" => Ecto.UUID.generate()},
        est_a.id
      )

    assert updated.id == est.id
    assert Decimal.equal?(updated.hours, Decimal.new(5))
    assert updated.task_id == task_a.id
    assert updated.estimation_role_id == role.id

    persisted = Repo.get!(TaskEstimate, updated.id)
    assert Decimal.equal?(persisted.hours, Decimal.new(5))
    assert persisted.task_id == task_a.id
    assert persisted.estimation_role_id == role.id
  end

  test "schema update_changesets never cast parent keys" do
    refute Map.has_key?(
             Epic.update_changeset(%Epic{}, %{"estimation_id" => Ecto.UUID.generate()}).changes,
             :estimation_id
           )

    refute Map.has_key?(
             Task.update_changeset(%Task{}, %{"epic_id" => Ecto.UUID.generate()}).changes,
             :epic_id
           )

    refute Map.has_key?(
             Estimation.update_changeset(%Estimation{}, %{
               "project_id" => Ecto.UUID.generate(),
               "is_current" => true
             }).changes,
             :project_id
           )

    refute Map.has_key?(
             EstimationRole.update_changeset(%EstimationRole{}, %{
               "project_role_id" => Ecto.UUID.generate()
             }).changes,
             :project_role_id
           )

    refute Map.has_key?(
             TaskEstimate.update_changeset(%TaskEstimate{}, %{"task_id" => Ecto.UUID.generate()}).changes,
             :task_id
           )
  end
end
