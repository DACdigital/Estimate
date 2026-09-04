defmodule Estimate.Repo.Migrations.AddScopeToOauth do
  use Ecto.Migration

  # Existing grants were consented as read-only; the default backfills them as such.
  def change do
    alter table(:oauth_codes) do
      add :scope, :string, null: false, default: "mcp:read"
    end

    alter table(:oauth_tokens) do
      add :scope, :string, null: false, default: "mcp:read"
    end
  end
end
