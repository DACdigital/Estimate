defmodule Estimate.EstimationEngineTest do
  use Estimate.DataCase

  alias Estimate.EstimationEngine
  import Estimate.EstimationEngineFixtures
  import Estimate.PortfolioFixtures

  describe "estimations" do
    test "create_estimation/1 creates estimation with default roles" do
      project = project_fixture()
      org_id = project.organization_id

      {:ok, estimation} =
        EstimationEngine.create_estimation(%{"name" => "Test", "project_id" => project.id})

      loaded = EstimationEngine.get_estimation!(estimation.id, org_id)
      assert loaded.name == "Test"
      assert length(loaded.roles) == 8
    end

    test "soft_delete_estimation/1 sets deleted_at" do
      estimation = estimation_fixture()
      {:ok, deleted} = EstimationEngine.soft_delete_estimation(estimation)
      assert deleted.deleted_at != nil
    end
  end

  describe "epics" do
    test "create_epic/1 creates an epic" do
      estimation = estimation_fixture()

      {:ok, epic} =
        EstimationEngine.create_epic(%{"name" => "Epic 1", "estimation_id" => estimation.id})

      assert epic.name == "Epic 1"
      assert epic.estimation_id == estimation.id
    end

    test "reorder_epics/2 updates positions" do
      estimation = estimation_fixture()
      org_id = estimation.organization_id

      {:ok, epic1} =
        EstimationEngine.create_epic(%{"name" => "E1", "estimation_id" => estimation.id})

      {:ok, epic2} =
        EstimationEngine.create_epic(%{"name" => "E2", "estimation_id" => estimation.id})

      EstimationEngine.reorder_epics(estimation.id, [epic2.id, epic1.id])

      loaded = EstimationEngine.get_estimation!(estimation.id, org_id)
      [first, second] = loaded.epics
      assert first.id == epic2.id
      assert second.id == epic1.id
    end
  end

  describe "tasks" do
    test "create_task/1 creates a task" do
      epic = epic_fixture()

      {:ok, task} = EstimationEngine.create_task(%{"name" => "Task 1", "epic_id" => epic.id})

      assert task.name == "Task 1"
      assert task.epic_id == epic.id
    end
  end

  describe "task estimates" do
    test "upsert_task_estimate/3 creates new estimate" do
      estimation = estimation_fixture()
      org_id = estimation.organization_id
      loaded = EstimationEngine.get_estimation!(estimation.id, org_id)
      role = hd(loaded.roles)
      epic = epic_fixture(estimation)
      task = task_fixture(epic)

      {:ok, estimate} =
        EstimationEngine.upsert_task_estimate(
          task.id,
          role.id,
          %{hours: Decimal.new(3)}
        )

      assert estimate.hours == Decimal.new(3)
    end

    test "upsert_task_estimate/3 updates existing estimate" do
      estimation = estimation_fixture()
      org_id = estimation.organization_id
      loaded = EstimationEngine.get_estimation!(estimation.id, org_id)
      role = hd(loaded.roles)
      epic = epic_fixture(estimation)
      task = task_fixture(epic)

      {:ok, _} =
        EstimationEngine.upsert_task_estimate(task.id, role.id, %{hours: 2})

      {:ok, updated} =
        EstimationEngine.upsert_task_estimate(task.id, role.id, %{hours: 5})

      assert updated.hours == Decimal.new(5)
    end
  end

  describe "copy_estimation/4" do
    test "deep copies estimation with roles, epics, tasks, and estimates" do
      estimation = estimation_fixture()
      org_id = estimation.organization_id
      loaded = EstimationEngine.get_estimation!(estimation.id, org_id)
      role = hd(loaded.roles)
      epic = epic_fixture(estimation)
      task = task_fixture(epic)

      {:ok, _} =
        EstimationEngine.upsert_task_estimate(task.id, role.id, %{hours: 3})

      original = EstimationEngine.get_estimation!(estimation.id, org_id)

      {:ok, copy} =
        EstimationEngine.copy_estimation(original, "Copy of Test", original.project_id, org_id)

      assert copy.name == "Copy of Test"
      assert copy.id != original.id
      assert length(copy.roles) == length(original.roles)
      assert length(copy.epics) == 1

      copied_epic = hd(copy.epics)
      assert copied_epic.name == epic.name
      assert copied_epic.id != epic.id
      assert length(copied_epic.tasks) == 1

      copied_task = hd(copied_epic.tasks)
      assert copied_task.name == task.name
      assert copied_task.id != task.id
      assert length(copied_task.estimates) == 1

      copied_estimate = hd(copied_task.estimates)
      assert copied_estimate.hours == Decimal.new(3)
    end
  end
end
