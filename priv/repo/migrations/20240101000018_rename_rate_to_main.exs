defmodule Estimate.Repo.Migrations.RenameRateToMain do
  use Ecto.Migration

  def change do
    rename table(:currencies), :rate_to_usd, to: :exchange_rate
  end
end
