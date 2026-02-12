defmodule Estimate.Repo.Migrations.AddPriorityToTasks do
  use Ecto.Migration

  def change do
    alter table(:tasks) do
      add :priority, :string, default: "must"
    end
  end
end
