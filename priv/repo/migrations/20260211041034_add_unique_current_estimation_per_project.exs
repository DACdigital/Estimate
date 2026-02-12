defmodule Estimate.Repo.Migrations.AddUniqueCurrentEstimationPerProject do
  use Ecto.Migration

  def change do
    create unique_index(:estimations, [:project_id],
             where: "is_current = true",
             name: :estimations_unique_current_per_project
           )
  end
end
