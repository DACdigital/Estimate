defmodule Estimate.Repo.Migrations.HardenAppRole do
  use Ecto.Migration

  # estimate_app is only ever assumed via SET ROLE (see Estimate.Repo.after_connect/1);
  # it never needs LOGIN and never creates schema objects.
  def up do
    execute "ALTER ROLE estimate_app NOLOGIN"
    execute "REVOKE CREATE ON SCHEMA public FROM estimate_app"
  end

  def down do
    execute "GRANT CREATE ON SCHEMA public TO estimate_app"
    execute "ALTER ROLE estimate_app LOGIN"
  end
end
