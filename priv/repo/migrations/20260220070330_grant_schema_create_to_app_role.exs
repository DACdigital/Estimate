defmodule Estimate.Repo.Migrations.GrantSchemaCreateToAppRole do
  use Ecto.Migration

  def up do
    execute "GRANT CREATE ON SCHEMA public TO estimate_app"
  end

  def down do
    execute "REVOKE CREATE ON SCHEMA public FROM estimate_app"
  end
end
