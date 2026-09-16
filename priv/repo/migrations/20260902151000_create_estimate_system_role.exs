defmodule Estimate.Repo.Migrations.CreateEstimateSystemRole do
  use Ecto.Migration

  # System-level escape hatch for Repo.without_rls/1: a NOLOGIN role that
  # bypasses RLS without being a superuser. Granted to whatever role runs
  # migrations (the DATABASE_URL role) so the app can SET ROLE into it.
  def up do
    execute """
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'estimate_system') THEN
        CREATE ROLE estimate_system NOLOGIN BYPASSRLS NOSUPERUSER NOCREATEDB NOCREATEROLE;
      END IF;
    END
    $$
    """

    # Unconditional: corrects a pre-existing role's attributes too (e.g. one
    # created by hand, or by an older version of this migration) so BYPASSRLS
    # and the NOSUPERUSER/NOCREATEDB/NOCREATEROLE guardrails always hold.
    execute "ALTER ROLE estimate_system NOLOGIN BYPASSRLS NOSUPERUSER NOCREATEDB NOCREATEROLE"

    execute "GRANT USAGE ON SCHEMA public TO estimate_system"

    execute "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO estimate_system"

    execute "GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO estimate_system"
    execute "GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO estimate_system"

    execute "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO estimate_system"

    execute "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO estimate_system"

    execute "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO estimate_system"

    execute "GRANT estimate_system TO current_user"
  end

  def down do
    execute "REVOKE estimate_system FROM current_user"

    execute "ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM estimate_system"

    execute "ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE USAGE, SELECT ON SEQUENCES FROM estimate_system"

    execute "ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE SELECT, INSERT, UPDATE, DELETE ON TABLES FROM estimate_system"

    execute "REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM estimate_system"
    execute "REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM estimate_system"
    execute "REVOKE ALL ON ALL TABLES IN SCHEMA public FROM estimate_system"
    execute "REVOKE USAGE ON SCHEMA public FROM estimate_system"

    # Mirrors `20260211080345_enforce_rls_with_app_role.exs`'s `down` for
    # `estimate_app`: guard the drop so it's a no-op if the role is already
    # gone (roles are cluster-scoped — dev and test share a container, so a
    # concurrent down elsewhere may have already dropped it).
    execute """
    DO $$
    BEGIN
      IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'estimate_system') THEN
        DROP ROLE estimate_system;
      END IF;
    END
    $$
    """
  end
end
