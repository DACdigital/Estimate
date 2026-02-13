defmodule Estimate.Repo.Migrations.EnforceRlsWithAppRole do
  use Ecto.Migration

  def up do
    # ==========================================================
    # 1. Create non-superuser app role for RLS enforcement
    #    Superusers ALWAYS bypass RLS. The app must connect as
    #    a regular role for policies to take effect.
    # ==========================================================
    execute """
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'estimate_app') THEN
        CREATE ROLE estimate_app WITH LOGIN PASSWORD 'estimate_app_dev' NOSUPERUSER NOCREATEDB NOCREATEROLE;
      END IF;
    END
    $$
    """

    # Grant connect
    execute "GRANT CONNECT ON DATABASE #{current_database()} TO estimate_app"

    # Grant schema usage
    execute "GRANT USAGE ON SCHEMA public TO estimate_app"

    # Grant DML on all existing tables
    execute "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO estimate_app"

    # Grant sequence usage
    execute "GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO estimate_app"

    # Grant execute on all functions
    execute "GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO estimate_app"

    # Default privileges for future objects created by postgres
    execute "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO estimate_app"

    execute "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO estimate_app"

    execute "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO estimate_app"

    # ==========================================================
    # 2. Remove RLS from memberships and invites.
    #    These tables need cross-org access for auth flows:
    #    - "list my organizations" queries memberships across orgs
    #    - invite acceptance queries invites by token, no org context
    # ==========================================================
    execute "DROP POLICY IF EXISTS org_isolation ON memberships"
    execute "ALTER TABLE memberships DISABLE ROW LEVEL SECURITY"

    execute "DROP POLICY IF EXISTS org_isolation ON invites"
    execute "ALTER TABLE invites DISABLE ROW LEVEL SECURITY"
  end

  def down do
    # Re-enable RLS on memberships and invites
    execute "ALTER TABLE memberships ENABLE ROW LEVEL SECURITY"

    execute """
    CREATE POLICY org_isolation ON memberships FOR ALL
      USING (organization_id = current_org_id())
      WITH CHECK (organization_id = current_org_id())
    """

    execute "ALTER TABLE invites ENABLE ROW LEVEL SECURITY"

    execute """
    CREATE POLICY org_isolation ON invites FOR ALL
      USING (organization_id = current_org_id())
      WITH CHECK (organization_id = current_org_id())
    """

    # Revoke default privileges
    execute "ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM estimate_app"

    execute "ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE USAGE, SELECT ON SEQUENCES FROM estimate_app"

    execute "ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE SELECT, INSERT, UPDATE, DELETE ON TABLES FROM estimate_app"

    # Revoke permissions
    execute "REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public FROM estimate_app"
    execute "REVOKE USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public FROM estimate_app"

    execute "REVOKE SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public FROM estimate_app"

    execute "REVOKE USAGE ON SCHEMA public FROM estimate_app"
    execute "REVOKE CONNECT ON DATABASE #{current_database()} FROM estimate_app"

    # Drop the role
    execute """
    DO $$
    BEGIN
      IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'estimate_app') THEN
        DROP ROLE estimate_app;
      END IF;
    END
    $$
    """
  end

  defp current_database do
    config = Application.get_env(:estimate, Estimate.Repo)

    config[:database] ||
      extract_database_from_url(config[:url]) ||
      raise "Database name not configured"
  end

  defp extract_database_from_url(nil), do: nil

  defp extract_database_from_url(url) do
    url |> URI.parse() |> Map.get(:path) |> String.trim_leading("/")
  end
end
