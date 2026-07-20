defmodule Estimate.Repo.Migrations.AddMcpWriteEnabledToOrganizations do
  use Ecto.Migration

  def change do
    alter table(:organizations) do
      add :mcp_write_enabled, :boolean, null: false, default: false
    end
  end
end
