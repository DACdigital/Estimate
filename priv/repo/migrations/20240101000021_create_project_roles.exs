defmodule Estimate.Repo.Migrations.CreateProjectRoles do
  use Ecto.Migration

  def change do
    create table(:project_roles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :abbreviation, :string, null: false
      add :hourly_rate, :decimal, null: false, default: 0
      add :position, :integer, default: 0

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime)
    end

    create index(:project_roles, [:project_id])
    create unique_index(:project_roles, [:project_id, :abbreviation])
  end
end
