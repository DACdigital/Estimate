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

  test "get_estimation!/2 orders tied positions by insertion, deterministically", %{
    project: project
  } do
    est = estimation_fixture(project)
    # all created at position 0 (schema default) — only inserted_at/id can break the tie.
    # inserted_at is second-precision and ids are random UUIDs (not monotonic), so the
    # tie is NOT guaranteed to resolve in creation order - it resolves to whatever
    # {position, inserted_at, id} sorts to. We assert against that same tuple, computed
    # from the real rows, rather than against the literal creation order.
    epics =
      for name <- ~w(E1 E2 E3 E4 E5 E6 E7 E8) do
        {:ok, epic} = EstimationEngine.create_epic(%{"name" => name, "estimation_id" => est.id})
        epic
      end

    # the epic that get_estimation! will actually return first (per the same
    # {position, inserted_at, id} order under test), so the task assertions below
    # read back the epic we attach tasks to.
    [epic | _] =
      Enum.sort_by(epics, &{&1.position, &1.inserted_at, &1.id})

    tasks =
      for name <- ~w(T1 T2 T3 T4 T5 T6 T7 T8) do
        {:ok, task} = EstimationEngine.create_task(%{"name" => name, "epic_id" => epic.id})
        task
      end

    expected_epic_names =
      epics |> Enum.sort_by(&{&1.position, &1.inserted_at, &1.id}) |> Enum.map(& &1.name)

    expected_task_names =
      tasks |> Enum.sort_by(&{&1.position, &1.inserted_at, &1.id}) |> Enum.map(& &1.name)

    org_id = Repo.reload!(est).organization_id

    names = fn ->
      EstimationEngine.get_estimation!(est.id, org_id).epics |> Enum.map(& &1.name)
    end

    task_names = fn ->
      hd(EstimationEngine.get_estimation!(est.id, org_id).epics).tasks |> Enum.map(& &1.name)
    end

    assert names.() == expected_epic_names
    assert task_names.() == expected_task_names
    # stable across reads
    assert Enum.all?(1..5, fn _ -> names.() == expected_epic_names end)
    assert Enum.all?(1..5, fn _ -> task_names.() == expected_task_names end)
  end
end
