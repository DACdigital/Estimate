defmodule Estimate.Repo.Migrations.CreateProjectCollaborators do
  use Ecto.Migration

  def change do
    create table(:project_collaborators, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :role, :string, null: false, default: "viewer"

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:project_collaborators, [:project_id])
    create index(:project_collaborators, [:user_id])
    create unique_index(:project_collaborators, [:project_id, :user_id])
  end
end
