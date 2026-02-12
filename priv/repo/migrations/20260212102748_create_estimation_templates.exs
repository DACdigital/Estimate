defmodule Estimate.Repo.Migrations.CreateEstimationTemplates do
  use Ecto.Migration

  def up do
    # ==========================================================
    # Tables
    # ==========================================================
    create table(:estimation_templates, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime)
    end

    create index(:estimation_templates, [:organization_id])

    create table(:estimation_template_epics, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :position, :integer, default: 0

      add :estimation_template_id,
          references(:estimation_templates, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime)
    end

    create index(:estimation_template_epics, [:estimation_template_id])

    create table(:estimation_template_tasks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :position, :integer, default: 0
      add :priority, :string, default: "must"

      add :estimation_template_epic_id,
          references(:estimation_template_epics, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime)
    end

    create index(:estimation_template_tasks, [:estimation_template_epic_id])

    # ==========================================================
    # RLS — same org_isolation pattern as role_templates
    # ==========================================================
    execute "ALTER TABLE estimation_templates ENABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE estimation_template_epics ENABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE estimation_template_tasks ENABLE ROW LEVEL SECURITY"

    execute """
    CREATE POLICY org_isolation ON estimation_templates FOR ALL
      USING (organization_id = current_org_id())
      WITH CHECK (organization_id = current_org_id())
    """

    execute """
    CREATE POLICY org_isolation ON estimation_template_epics FOR ALL
      USING (EXISTS (
        SELECT 1 FROM estimation_templates et
        WHERE et.id = estimation_template_epics.estimation_template_id
          AND et.organization_id = current_org_id()
      ))
    """

    execute """
    CREATE POLICY org_isolation ON estimation_template_tasks FOR ALL
      USING (EXISTS (
        SELECT 1 FROM estimation_template_epics ete
        JOIN estimation_templates et ON et.id = ete.estimation_template_id
        WHERE ete.id = estimation_template_tasks.estimation_template_epic_id
          AND et.organization_id = current_org_id()
      ))
    """
  end

  def down do
    execute "DROP POLICY IF EXISTS org_isolation ON estimation_template_tasks"
    execute "DROP POLICY IF EXISTS org_isolation ON estimation_template_epics"
    execute "DROP POLICY IF EXISTS org_isolation ON estimation_templates"

    execute "ALTER TABLE estimation_template_tasks DISABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE estimation_template_epics DISABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE estimation_templates DISABLE ROW LEVEL SECURITY"

    drop table(:estimation_template_tasks)
    drop table(:estimation_template_epics)
    drop table(:estimation_templates)
  end
end
