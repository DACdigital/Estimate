defmodule Estimate.Repo.Migrations.FixUniqueCurrentEstimationIndex do
  use Ecto.Migration

  def change do
    drop_if_exists unique_index(:estimations, [:project_id],
                     name: :estimations_unique_current_per_project
                   )

    create unique_index(:estimations, [:project_id],
             where: "is_current = true AND deleted_at IS NULL",
             name: :estimations_unique_current_per_project
           )
  end
end
