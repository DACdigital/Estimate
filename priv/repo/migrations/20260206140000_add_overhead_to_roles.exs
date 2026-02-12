defmodule Estimate.Repo.Migrations.AddOverheadToRoles do
  use Ecto.Migration

  def change do
    # Add overhead fields to role_templates
    alter table(:role_templates) do
      add :pm_overhead, :decimal, precision: 5, scale: 2, default: 0
      add :qa_overhead, :decimal, precision: 5, scale: 2, default: 0
      add :risk_buffer, :decimal, precision: 5, scale: 2, default: 0
    end

    # Add overhead fields to project_roles
    alter table(:project_roles) do
      add :pm_overhead, :decimal, precision: 5, scale: 2, default: 0
      add :qa_overhead, :decimal, precision: 5, scale: 2, default: 0
      add :risk_buffer, :decimal, precision: 5, scale: 2, default: 0
    end

    # Add overhead fields to estimation_roles (so estimations keep their snapshot)
    alter table(:estimation_roles) do
      add :pm_overhead, :decimal, precision: 5, scale: 2, default: 0
      add :qa_overhead, :decimal, precision: 5, scale: 2, default: 0
      add :risk_buffer, :decimal, precision: 5, scale: 2, default: 0
    end
  end
end
