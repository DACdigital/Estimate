defmodule Estimate.Repo.Migrations.AddRatesFetchedAtToOrganizations do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :rates_fetched_at, :utc_datetime
    end
  end
end
