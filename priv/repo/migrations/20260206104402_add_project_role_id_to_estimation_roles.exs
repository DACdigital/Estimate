defmodule Estimate.Repo.Migrations.AddProjectRoleIdToEstimationRoles do
  use Ecto.Migration

  def change do
    alter table(:estimation_roles) do
      add :project_role_id, references(:project_roles, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:estimation_roles, [:project_role_id])
  end
end
