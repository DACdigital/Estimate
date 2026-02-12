defmodule Estimate.Repo.Migrations.CreateProjects do
  use Ecto.Migration

  def change do
    create table(:projects, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :status, :string, null: false, default: "active"
      add :customer_id, references(:customers, type: :binary_id, on_delete: :nilify_all)

      timestamps()
    end

    create index(:projects, [:customer_id])
  end
end
