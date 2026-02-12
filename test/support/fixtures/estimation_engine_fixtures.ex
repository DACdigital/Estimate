defmodule Estimate.EstimationEngineFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Estimate.EstimationEngine` context.
  """

  alias Estimate.PortfolioFixtures

  def estimation_fixture(project \\ nil, attrs \\ %{}) do
    project = project || PortfolioFixtures.project_fixture()

    {:ok, estimation} =
      Estimate.EstimationEngine.create_estimation(
        Map.merge(
          %{
            "name" => "Test Estimation #{System.unique_integer()}",
            "project_id" => project.id
          },
          stringify_keys(attrs)
        )
      )

    # Reload to get organization_id from trigger
    Estimate.Repo.get!(Estimate.EstimationEngine.Estimation, estimation.id)
  end

  def epic_fixture(estimation \\ nil, attrs \\ %{}) do
    estimation = estimation || estimation_fixture()

    {:ok, epic} =
      Estimate.EstimationEngine.create_epic(
        Map.merge(
          %{
            "name" => "Test Epic #{System.unique_integer()}",
            "estimation_id" => estimation.id
          },
          stringify_keys(attrs)
        )
      )

    epic
  end

  def task_fixture(epic \\ nil, attrs \\ %{}) do
    epic = epic || epic_fixture()

    {:ok, task} =
      Estimate.EstimationEngine.create_task(
        Map.merge(
          %{
            "name" => "Test Task #{System.unique_integer()}",
            "epic_id" => epic.id
          },
          stringify_keys(attrs)
        )
      )

    task
  end

  defp stringify_keys(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
