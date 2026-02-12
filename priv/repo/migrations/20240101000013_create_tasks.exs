defmodule Estimate.Repo.Migrations.CreateTasks do
  use Ecto.Migration

  def change do
    create table(:tasks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :position, :integer, null: false, default: 0
      add :epic_id, references(:epics, type: :binary_id, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:tasks, [:epic_id])
  end
end
