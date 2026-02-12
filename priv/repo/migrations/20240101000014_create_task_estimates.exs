defmodule Estimate.Repo.Migrations.CreateTaskEstimates do
  use Ecto.Migration

  def change do
    create table(:task_estimates, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :min_hours, :decimal, null: false, default: 0
      add :max_hours, :decimal, null: false, default: 0
      add :task_id, references(:tasks, type: :binary_id, on_delete: :delete_all), null: false

      add :estimation_role_id,
          references(:estimation_roles, type: :binary_id, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:task_estimates, [:task_id])
    create index(:task_estimates, [:estimation_role_id])
    create unique_index(:task_estimates, [:task_id, :estimation_role_id])
  end
end
