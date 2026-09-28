-- Runs once, the first time the postgres data volume is initialized.
-- Creates the `estimate_app` role that the application SETs into for RLS,
-- and the `estimate` database that the application connects to.
--
-- The role must exist BEFORE the application first connects: the Ecto
-- `after_connect` callback issues `SET ROLE estimate_app`, which happens
-- earlier than the migration that would otherwise create the role.
--
-- The password below is not used for login by the application — the app
-- connects as `postgres` and switches role. It exists only so operators
-- can `psql -U estimate_app` if they want to inspect what an RLS-scoped
-- session sees.

\connect postgres

DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'estimate_app') THEN
    CREATE ROLE estimate_app WITH LOGIN PASSWORD 'estimate_app' NOSUPERUSER NOCREATEDB NOCREATEROLE;
  END IF;
END
$$;

SELECT 'CREATE DATABASE estimate OWNER postgres'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'estimate')\gexec

\connect estimate

GRANT CONNECT ON DATABASE estimate TO estimate_app;
GRANT USAGE ON SCHEMA public TO estimate_app;
