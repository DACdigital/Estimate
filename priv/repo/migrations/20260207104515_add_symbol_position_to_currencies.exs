defmodule Estimate.Repo.Migrations.AddSymbolPositionToCurrencies do
  use Ecto.Migration

  def change do
    alter table(:currencies) do
      add :symbol_position, :string, default: "prefix"
    end

    # Set PLN to suffix by default
    execute "UPDATE currencies SET symbol_position = 'suffix' WHERE code = 'PLN'", ""
  end
end
