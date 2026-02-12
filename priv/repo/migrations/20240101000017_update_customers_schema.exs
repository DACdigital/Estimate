defmodule Estimate.Repo.Migrations.UpdateCustomersSchema do
  use Ecto.Migration

  def change do
    alter table(:customers) do
      remove :email, :string
      remove :phone, :string

      add :key, :string, null: false
      add :country, :string
      add :website_url, :string
      add :default_currency_id, references(:currencies, type: :binary_id, on_delete: :nilify_all)
    end

    rename table(:customers), :notes, to: :description

    create unique_index(:customers, [:organization_id, :key])
    create index(:customers, [:default_currency_id])
  end
end
