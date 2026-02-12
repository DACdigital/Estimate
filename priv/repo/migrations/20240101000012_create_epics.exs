defmodule Estimate.Repo.Migrations.CreateEpics do
  use Ecto.Migration

  def change do
    create table(:epics, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :position, :integer, null: false, default: 0

      add :estimation_id, references(:estimations, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps()
    end

    create index(:epics, [:estimation_id])
  end
end
