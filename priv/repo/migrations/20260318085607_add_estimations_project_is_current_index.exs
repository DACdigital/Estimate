defmodule Estimate.Repo.Migrations.AddEstimationsProjectIsCurrentIndex do
  use Ecto.Migration

  def change do
    create_if_not_exists index(:estimations, [:project_id, :is_current])
  end
end
