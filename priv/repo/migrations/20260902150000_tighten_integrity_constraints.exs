defmodule Estimate.Repo.Migrations.TightenIntegrityConstraints do
  use Ecto.Migration

  @overhead_tables ~w(estimation_roles project_roles role_templates)a

  def up do
    # 1. backfill NULLs with the column defaults
    execute "UPDATE estimations SET is_current = false WHERE is_current IS NULL"
    execute "UPDATE tasks SET priority = 'must' WHERE priority IS NULL"

    for t <- @overhead_tables, c <- ~w(pm_overhead qa_overhead risk_buffer) do
      execute "UPDATE #{t} SET #{c} = 0 WHERE #{c} IS NULL"
    end

    for t <- ~w(role_templates project_roles estimation_template_epics estimation_template_tasks) do
      execute "UPDATE #{t} SET position = 0 WHERE position IS NULL"
    end

    execute "UPDATE estimation_template_tasks SET priority = 'must' WHERE priority IS NULL"

    # 2. NOT NULL (defaults already exist on every column)
    alter table(:estimations), do: modify(:is_current, :boolean, null: false, default: false)
    alter table(:tasks), do: modify(:priority, :string, null: false, default: "must")

    for t <- @overhead_tables do
      alter table(t) do
        modify :pm_overhead, :decimal, precision: 5, scale: 2, null: false, default: 0
        modify :qa_overhead, :decimal, precision: 5, scale: 2, null: false, default: 0
        modify :risk_buffer, :decimal, precision: 5, scale: 2, null: false, default: 0
      end
    end

    for t <- ~w(role_templates project_roles estimation_template_epics estimation_template_tasks)a do
      alter table(t), do: modify(:position, :integer, null: false, default: 0)
    end

    alter table(:estimation_template_tasks),
      do: modify(:priority, :string, null: false, default: "must")

    # 3. composite uniqueness so the composite FKs below are valid targets
    create unique_index(:customers, [:id, :organization_id])
    create unique_index(:projects, [:id, :organization_id])

    # 4. cross-org linkage becomes impossible at the DB
    execute """
    ALTER TABLE projects ADD CONSTRAINT projects_customer_org_fkey
      FOREIGN KEY (customer_id, organization_id) REFERENCES customers (id, organization_id) ON DELETE CASCADE
    """

    execute """
    ALTER TABLE estimations ADD CONSTRAINT estimations_project_org_fkey
      FOREIGN KEY (project_id, organization_id) REFERENCES projects (id, organization_id) ON DELETE CASCADE
    """
  end

  def down do
    execute "ALTER TABLE estimations DROP CONSTRAINT estimations_project_org_fkey"
    execute "ALTER TABLE projects DROP CONSTRAINT projects_customer_org_fkey"
    drop unique_index(:projects, [:id, :organization_id])
    drop unique_index(:customers, [:id, :organization_id])

    alter table(:estimation_template_tasks),
      do: modify(:priority, :string, null: true, default: "must")

    for t <- ~w(role_templates project_roles estimation_template_epics estimation_template_tasks)a do
      alter table(t), do: modify(:position, :integer, null: true, default: 0)
    end

    for t <- @overhead_tables do
      alter table(t) do
        modify :pm_overhead, :decimal, precision: 5, scale: 2, null: true, default: 0
        modify :qa_overhead, :decimal, precision: 5, scale: 2, null: true, default: 0
        modify :risk_buffer, :decimal, precision: 5, scale: 2, null: true, default: 0
      end
    end

    alter table(:tasks), do: modify(:priority, :string, null: true, default: "must")
    alter table(:estimations), do: modify(:is_current, :boolean, null: true, default: false)
  end
end
