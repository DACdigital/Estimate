defmodule Estimate.Repo.Migrations.CreateEstimationRoles do
  use Ecto.Migration

  def change do
    create table(:estimation_roles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :abbreviation, :string, null: false
      add :hourly_rate, :decimal, null: false, default: 0
      add :position, :integer, null: false, default: 0

      add :estimation_id, references(:estimations, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps()
    end

    create index(:estimation_roles, [:estimation_id])
  end
end
