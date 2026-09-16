defmodule Estimate.Repo.Migrations.HardenAppRole do
  use Ecto.Migration

  # estimate_app is only ever assumed via SET ROLE (see Estimate.Repo.after_connect/1)
  # and never creates schema objects. Revoking CREATE needs only schema ownership
  # (the DB owner), so it can run as the regular migrating role.
  #
  # `ALTER ROLE estimate_app NOLOGIN` is deliberately NOT done here: on PG16+ it
  # requires CREATEROLE + ADMIN OPTION on the target role, which the migrating
  # role typically lacks. It is a one-off DBA hardening step (see README).
  def up do
    execute "REVOKE CREATE ON SCHEMA public FROM estimate_app"
  end

  def down do
    execute "GRANT CREATE ON SCHEMA public TO estimate_app"
  end
end
