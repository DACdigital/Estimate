defmodule Estimate.RepoReorderChildrenTest do
  use Estimate.DataCase, async: true

  import Estimate.{AccountsFixtures, PortfolioFixtures, EstimationEngineFixtures}

  alias Estimate.EstimationEngine.Epic
  alias Estimate.Repo

  setup do
    %{user: owner} = user_with_organization_fixture()
    project = project_fixture(nil, owner)
    est = estimation_fixture(project)
    e1 = epic_fixture(est, %{name: "E1", position: 0})
    e2 = epic_fixture(est, %{name: "E2", position: 1})
    e3 = epic_fixture(est, %{name: "E3", position: 2})
    %{est: est, ids: [e1.id, e2.id, e3.id]}
  end

  defp positions(est_id) do
    Repo.all(
      from(e in Epic, where: e.estimation_id == ^est_id, order_by: e.position, select: e.id)
    )
  end

  test "assigns positions in list order", %{est: est, ids: [a, b, c]} do
    assert :ok = Repo.reorder_children(Epic, :estimation_id, est.id, [c, a, b])
    assert positions(est.id) == [c, a, b]
  end

  test "a list whose length differs from the child count is rejected untouched", %{
    est: est,
    ids: [a, b, _c] = ids
  } do
    assert {:error, :stale_reorder} = Repo.reorder_children(Epic, :estimation_id, est.id, [b, a])
    assert positions(est.id) == ids
  end

  test "an id from another parent is ignored, not moved", %{est: est, ids: [a, b, c]} do
    %{user: other_owner} = user_with_organization_fixture()
    other = estimation_fixture(project_fixture(nil, other_owner))
    foreign = epic_fixture(other, %{name: "X", position: 0})

    assert :ok = Repo.reorder_children(Epic, :estimation_id, est.id, [foreign.id, c, b])

    # foreign id consumed a slot but touched nothing; a keeps its old position 0 and now ties with c
    assert Repo.get!(Epic, foreign.id).position == 0
    assert Repo.get!(Epic, a).position == 0
    assert Repo.get!(Epic, c).position == 1
    assert Repo.get!(Epic, b).position == 2
  end
end
