defmodule Estimate.Repo.Migrations.CreateEstimations do
  use Ecto.Migration

  def change do
    create table(:estimations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :currency, :string, null: false, default: "USD"
      add :deleted_at, :utc_datetime

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps()
    end

    create index(:estimations, [:project_id])
    create index(:estimations, [:deleted_at])
  end
end
