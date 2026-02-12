defmodule Estimate.Repo.Migrations.CreateJoinRequests do
  use Ecto.Migration

  def change do
    create table(:join_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :status, :string, null: false, default: "pending"
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :organization_id, references(:organizations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :reviewed_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :reviewed_at, :utc_datetime

      timestamps()
    end

    create index(:join_requests, [:user_id])
    create index(:join_requests, [:organization_id])

    create unique_index(:join_requests, [:user_id, :organization_id],
             where: "status = 'pending'",
             name: :join_requests_pending_unique
           )
  end
end
