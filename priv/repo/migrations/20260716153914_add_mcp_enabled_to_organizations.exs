defmodule Estimate.Repo.Migrations.AddMcpEnabledToOrganizations do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :mcp_enabled, :boolean, default: false, null: false
    end
  end
end
