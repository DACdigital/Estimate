defmodule Estimate.Repo.Migrations.UpdateEstimationsCurrency do
  use Ecto.Migration

  def change do
    alter table(:estimations) do
      remove :currency, :string, null: false, default: "USD"
      add :currency_id, references(:currencies, type: :binary_id, on_delete: :restrict)
    end

    create index(:estimations, [:currency_id])
  end
end
