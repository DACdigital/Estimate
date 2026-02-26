defmodule Estimate.Repo.Migrations.AddLastOrgIdToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :last_org_id, references(:organizations, type: :uuid, on_delete: :nilify_all),
        null: true
    end
  end
end
