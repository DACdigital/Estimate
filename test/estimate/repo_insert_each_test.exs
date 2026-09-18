defmodule Estimate.RepoInsertEachTest do
  use Estimate.DataCase, async: true

  import Estimate.{AccountsFixtures, PortfolioFixtures, EstimationEngineFixtures}

  alias Estimate.EstimationEngine.Epic
  alias Estimate.Repo

  setup do
    %{user: owner} = user_with_organization_fixture()
    project = project_fixture(nil, owner)
    est = estimation_fixture(project)
    %{est: est}
  end

  test "inserts every changeset in order and returns the structs in the same order", %{est: est} do
    names = ~w(A B C)

    assert {:ok, epics} =
             Repo.insert_each(Enum.with_index(names), fn {name, idx} ->
               Epic.changeset(%Epic{}, %{name: name, position: idx, estimation_id: est.id})
             end)

    assert Enum.map(epics, & &1.name) == names
    assert Enum.map(epics, & &1.position) == [0, 1, 2]
    assert Repo.aggregate(from(e in Epic, where: e.estimation_id == ^est.id), :count) == 3
  end

  test "halts on the first invalid changeset, returns it, and inserts nothing after it", %{
    est: est
  } do
    names = ["ok-1", "", "never"]

    assert {:error, %Ecto.Changeset{} = cs} =
             Repo.insert_each(names, fn name ->
               Epic.changeset(%Epic{}, %{name: name, estimation_id: est.id})
             end)

    assert %{name: [_ | _]} = errors_on(cs)
    inserted = Repo.all(from(e in Epic, where: e.estimation_id == ^est.id, select: e.name))
    assert inserted == ["ok-1"]
  end

  test "empty input is {:ok, []} and touches nothing" do
    assert Repo.insert_each([], fn _ -> flunk("must not be called") end) == {:ok, []}
  end
end
