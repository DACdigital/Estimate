defmodule Estimate.Repo.Migrations.CreateCurrencies do
  use Ecto.Migration

  def change do
    create table(:currencies, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :code, :string, null: false
      add :name, :string, null: false
      add :symbol, :string
      add :rate_to_usd, :decimal, null: false, default: 1.0
      add :is_main, :boolean, null: false, default: false

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps()
    end

    create index(:currencies, [:organization_id])
    create unique_index(:currencies, [:organization_id, :code])
  end
end
