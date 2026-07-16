defmodule Estimate.Repo.Migrations.CreateMcpApiKeys do
  use Ecto.Migration

  def up do
    create table(:mcp_api_keys, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key_hash, :binary, null: false
      add :key_prefix, :string, null: false
      add :last_used_at, :utc_datetime

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:mcp_api_keys, [:key_hash])
    create unique_index(:mcp_api_keys, [:user_id, :organization_id])
    create index(:mcp_api_keys, [:organization_id])

    execute "ALTER TABLE mcp_api_keys ENABLE ROW LEVEL SECURITY"

    # Users manage only their own key within the current org context.
    # Bearer-key verification bypasses RLS via Repo.without_rls (pre-context by definition).
    execute """
    CREATE POLICY own_key_isolation ON mcp_api_keys FOR ALL
      USING (organization_id = current_org_id() AND user_id = current_user_id())
      WITH CHECK (organization_id = current_org_id() AND user_id = current_user_id())
    """
  end

  def down do
    execute "DROP POLICY IF EXISTS own_key_isolation ON mcp_api_keys"
    execute "ALTER TABLE mcp_api_keys DISABLE ROW LEVEL SECURITY"
    drop table(:mcp_api_keys)
  end
end
