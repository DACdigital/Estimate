-- Create the estimate_app role for RLS enforcement
-- This role is also created by migrations, but we need it before migrations run
-- (after_connect callback tries to SET ROLE before migrations execute)
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'estimate_app') THEN
    CREATE ROLE estimate_app WITH LOGIN PASSWORD 'estimate_app_dev' NOSUPERUSER NOCREATEDB NOCREATEROLE;
  END IF;
END
$$;

-- Grant basic permissions (migrations will add table-specific permissions)
GRANT CONNECT ON DATABASE estimate TO estimate_app;
GRANT USAGE ON SCHEMA public TO estimate_app;
