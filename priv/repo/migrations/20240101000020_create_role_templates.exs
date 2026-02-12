defmodule Estimate.Repo.Migrations.CreateRoleTemplates do
  use Ecto.Migration

  def change do
    create table(:role_templates, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :abbreviation, :string, null: false
      add :position, :integer, default: 0

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime)
    end

    create index(:role_templates, [:organization_id])
    create unique_index(:role_templates, [:organization_id, :abbreviation])

    create table(:role_template_rates, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :hourly_rate, :decimal, null: false, default: 0

      add :role_template_id,
          references(:role_templates, type: :binary_id, on_delete: :delete_all), null: false

      add :currency_id, references(:currencies, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime)
    end

    create index(:role_template_rates, [:role_template_id])
    create index(:role_template_rates, [:currency_id])
    create unique_index(:role_template_rates, [:role_template_id, :currency_id])
  end
end
