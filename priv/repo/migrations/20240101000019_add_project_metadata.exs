defmodule Estimate.Repo.Migrations.AddProjectMetadata do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :key, :string
      add :currency_id, references(:currencies, type: :binary_id, on_delete: :nilify_all)
      add :short_description, :text
      add :repository_url, :string
    end

    rename table(:projects), :description, to: :detailed_description

    create unique_index(:projects, [:customer_id, :key])
    create index(:projects, [:currency_id])
  end
end
