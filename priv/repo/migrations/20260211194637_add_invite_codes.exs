defmodule Estimate.Repo.Migrations.AddInviteCodes do
  use Ecto.Migration

  def change do
    alter table(:invites) do
      add :code, :string
      modify :email, :citext, null: true, from: {:citext, null: false}
    end

    create unique_index(:invites, [:code])
  end
end
