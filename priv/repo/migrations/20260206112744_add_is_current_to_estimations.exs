defmodule Estimate.Repo.Migrations.AddIsCurrentToEstimations do
  use Ecto.Migration

  def change do
    alter table(:estimations) do
      add :is_current, :boolean, default: false
    end
  end
end
