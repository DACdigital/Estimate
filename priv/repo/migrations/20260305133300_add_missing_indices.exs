defmodule Estimate.Repo.Migrations.AddMissingIndices do
  use Ecto.Migration

  def change do
    # estimations: composite replaces single-column project_id index
    create index(:estimations, [:project_id, :deleted_at])
    drop_if_exists index(:estimations, [:project_id])

    # currencies: unique partial — enforces one main per org + fast lookup
    create unique_index(:currencies, [:organization_id],
             name: :currencies_org_main_index,
             where: "is_main = true"
           )

    # users_tokens: composite replaces single-column user_id index
    create index(:users_tokens, [:user_id, :context])
    drop_if_exists index(:users_tokens, [:user_id])

    # users: FK index for last_org_id (partial, skip nulls)
    create index(:users, [:last_org_id], where: "last_org_id IS NOT NULL")
  end
end
