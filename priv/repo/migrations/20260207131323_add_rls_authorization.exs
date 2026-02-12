defmodule Estimate.Repo.Migrations.AddRlsAuthorization do
  use Ecto.Migration

  def up do
    # ==========================================================
    # Phase 1: Add organization_id to projects (denormalization)
    # ==========================================================
    alter table(:projects) do
      add :organization_id, references(:organizations, type: :uuid, on_delete: :restrict)
    end

    # Backfill from customers
    execute """
    UPDATE projects p
    SET organization_id = c.organization_id
    FROM customers c
    WHERE c.id = p.customer_id
    """

    # Make NOT NULL after backfill
    alter table(:projects) do
      modify :organization_id, :uuid, null: false
    end

    create index(:projects, [:organization_id])

    # ==========================================================
    # Phase 2: Add organization_id to estimations
    # ==========================================================
    alter table(:estimations) do
      add :organization_id, references(:organizations, type: :uuid, on_delete: :restrict)
    end

    # Backfill from projects
    execute """
    UPDATE estimations e
    SET organization_id = p.organization_id
    FROM projects p
    WHERE p.id = e.project_id
    """

    alter table(:estimations) do
      modify :organization_id, :uuid, null: false
    end

    create index(:estimations, [:organization_id])

    # ==========================================================
    # Phase 3: Triggers to maintain denormalized org_id
    # ==========================================================

    # Trigger for projects: auto-set org_id from customer on INSERT
    execute """
    CREATE OR REPLACE FUNCTION set_project_org_id()
    RETURNS trigger AS $$
    BEGIN
      SELECT organization_id INTO NEW.organization_id
      FROM customers
      WHERE id = NEW.customer_id;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
    """

    execute """
    CREATE TRIGGER project_set_org_id
    BEFORE INSERT ON projects
    FOR EACH ROW
    EXECUTE FUNCTION set_project_org_id()
    """

    # Trigger for estimations: auto-set org_id from project on INSERT
    execute """
    CREATE OR REPLACE FUNCTION set_estimation_org_id()
    RETURNS trigger AS $$
    BEGIN
      SELECT organization_id INTO NEW.organization_id
      FROM projects
      WHERE id = NEW.project_id;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
    """

    execute """
    CREATE TRIGGER estimation_set_org_id
    BEFORE INSERT ON estimations
    FOR EACH ROW
    EXECUTE FUNCTION set_estimation_org_id()
    """

    # ==========================================================
    # Phase 4: Session variable function for RLS
    # ==========================================================
    execute """
    CREATE OR REPLACE FUNCTION current_org_id() RETURNS uuid AS $$
      SELECT NULLIF(current_setting('app.current_org_id', true), '')::uuid;
    $$ LANGUAGE sql STABLE
    """

    # ==========================================================
    # Phase 5: Enable RLS on all tables
    # ==========================================================

    # Direct org_id tables
    execute "ALTER TABLE customers ENABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE currencies ENABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE role_templates ENABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE role_template_rates ENABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE search_index ENABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE memberships ENABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE invites ENABLE ROW LEVEL SECURITY"

    # Denormalized org_id tables
    execute "ALTER TABLE projects ENABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE estimations ENABLE ROW LEVEL SECURITY"

    # Child tables (via parent lookup)
    execute "ALTER TABLE project_roles ENABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE project_collaborators ENABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE estimation_roles ENABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE epics ENABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE tasks ENABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE task_estimates ENABLE ROW LEVEL SECURITY"

    # ==========================================================
    # Phase 6: RLS Policies
    # ==========================================================

    # Direct org_id tables - simple policies
    execute """
    CREATE POLICY org_isolation ON customers FOR ALL
      USING (organization_id = current_org_id())
      WITH CHECK (organization_id = current_org_id())
    """

    execute """
    CREATE POLICY org_isolation ON currencies FOR ALL
      USING (organization_id = current_org_id())
      WITH CHECK (organization_id = current_org_id())
    """

    execute """
    CREATE POLICY org_isolation ON role_templates FOR ALL
      USING (organization_id = current_org_id())
      WITH CHECK (organization_id = current_org_id())
    """

    execute """
    CREATE POLICY org_isolation ON role_template_rates FOR ALL
      USING (EXISTS (
        SELECT 1 FROM role_templates rt
        WHERE rt.id = role_template_id AND rt.organization_id = current_org_id()
      ))
    """

    execute """
    CREATE POLICY org_isolation ON search_index FOR ALL
      USING (organization_id = current_org_id())
      WITH CHECK (organization_id = current_org_id())
    """

    execute """
    CREATE POLICY org_isolation ON memberships FOR ALL
      USING (organization_id = current_org_id())
      WITH CHECK (organization_id = current_org_id())
    """

    execute """
    CREATE POLICY org_isolation ON invites FOR ALL
      USING (organization_id = current_org_id())
      WITH CHECK (organization_id = current_org_id())
    """

    # Denormalized org_id tables
    execute """
    CREATE POLICY org_isolation ON projects FOR ALL
      USING (organization_id = current_org_id())
      WITH CHECK (organization_id = current_org_id())
    """

    execute """
    CREATE POLICY org_isolation ON estimations FOR ALL
      USING (organization_id = current_org_id())
      WITH CHECK (organization_id = current_org_id())
    """

    # Child tables via project
    execute """
    CREATE POLICY org_isolation ON project_roles FOR ALL
      USING (EXISTS (
        SELECT 1 FROM projects p
        WHERE p.id = project_id AND p.organization_id = current_org_id()
      ))
    """

    execute """
    CREATE POLICY org_isolation ON project_collaborators FOR ALL
      USING (EXISTS (
        SELECT 1 FROM projects p
        WHERE p.id = project_id AND p.organization_id = current_org_id()
      ))
    """

    # Child tables via estimation
    execute """
    CREATE POLICY org_isolation ON estimation_roles FOR ALL
      USING (EXISTS (
        SELECT 1 FROM estimations e
        WHERE e.id = estimation_id AND e.organization_id = current_org_id()
      ))
    """

    execute """
    CREATE POLICY org_isolation ON epics FOR ALL
      USING (EXISTS (
        SELECT 1 FROM estimations e
        WHERE e.id = estimation_id AND e.organization_id = current_org_id()
      ))
    """

    # Deeply nested via epic -> estimation
    execute """
    CREATE POLICY org_isolation ON tasks FOR ALL
      USING (EXISTS (
        SELECT 1 FROM epics ep
        JOIN estimations e ON e.id = ep.estimation_id
        WHERE ep.id = epic_id AND e.organization_id = current_org_id()
      ))
    """

    # Deepest: task_estimates via task -> epic -> estimation
    execute """
    CREATE POLICY org_isolation ON task_estimates FOR ALL
      USING (EXISTS (
        SELECT 1 FROM tasks t
        JOIN epics ep ON ep.id = t.epic_id
        JOIN estimations e ON e.id = ep.estimation_id
        WHERE t.id = task_id AND e.organization_id = current_org_id()
      ))
    """

    # ==========================================================
    # Phase 7: Performance Indexes
    # ==========================================================

    # Composite indexes for org-scoped queries
    create index(:customers, [:organization_id, :name])
    create index(:projects, [:organization_id, :status])
    create index(:projects, [:organization_id, :updated_at])
    create index(:estimations, [:organization_id, :deleted_at])

    # Covering indexes for RLS policy lookups
    execute "CREATE INDEX idx_project_roles_project_include ON project_roles(project_id) INCLUDE (id)"
    execute "CREATE INDEX idx_epics_estimation_include ON epics(estimation_id) INCLUDE (id)"
    execute "CREATE INDEX idx_tasks_epic_include ON tasks(epic_id) INCLUDE (id)"
    execute "CREATE INDEX idx_task_estimates_task_include ON task_estimates(task_id) INCLUDE (id)"
  end

  def down do
    # Drop covering indexes
    execute "DROP INDEX IF EXISTS idx_task_estimates_task_include"
    execute "DROP INDEX IF EXISTS idx_tasks_epic_include"
    execute "DROP INDEX IF EXISTS idx_epics_estimation_include"
    execute "DROP INDEX IF EXISTS idx_project_roles_project_include"

    # Drop composite indexes
    drop_if_exists index(:estimations, [:organization_id, :deleted_at])
    drop_if_exists index(:projects, [:organization_id, :updated_at])
    drop_if_exists index(:projects, [:organization_id, :status])
    drop_if_exists index(:customers, [:organization_id, :name])

    # Drop RLS policies
    execute "DROP POLICY IF EXISTS org_isolation ON task_estimates"
    execute "DROP POLICY IF EXISTS org_isolation ON tasks"
    execute "DROP POLICY IF EXISTS org_isolation ON epics"
    execute "DROP POLICY IF EXISTS org_isolation ON estimation_roles"
    execute "DROP POLICY IF EXISTS org_isolation ON project_collaborators"
    execute "DROP POLICY IF EXISTS org_isolation ON project_roles"
    execute "DROP POLICY IF EXISTS org_isolation ON estimations"
    execute "DROP POLICY IF EXISTS org_isolation ON projects"
    execute "DROP POLICY IF EXISTS org_isolation ON invites"
    execute "DROP POLICY IF EXISTS org_isolation ON memberships"
    execute "DROP POLICY IF EXISTS org_isolation ON search_index"
    execute "DROP POLICY IF EXISTS org_isolation ON role_template_rates"
    execute "DROP POLICY IF EXISTS org_isolation ON role_templates"
    execute "DROP POLICY IF EXISTS org_isolation ON currencies"
    execute "DROP POLICY IF EXISTS org_isolation ON customers"

    # Disable RLS
    execute "ALTER TABLE task_estimates DISABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE tasks DISABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE epics DISABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE estimation_roles DISABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE project_collaborators DISABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE project_roles DISABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE estimations DISABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE projects DISABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE invites DISABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE memberships DISABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE search_index DISABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE role_template_rates DISABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE role_templates DISABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE currencies DISABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE customers DISABLE ROW LEVEL SECURITY"

    # Drop session function
    execute "DROP FUNCTION IF EXISTS current_org_id()"

    # Drop triggers and functions
    execute "DROP TRIGGER IF EXISTS estimation_set_org_id ON estimations"
    execute "DROP FUNCTION IF EXISTS set_estimation_org_id()"
    execute "DROP TRIGGER IF EXISTS project_set_org_id ON projects"
    execute "DROP FUNCTION IF EXISTS set_project_org_id()"

    # Drop org_id columns
    drop index(:estimations, [:organization_id])

    alter table(:estimations) do
      remove :organization_id
    end

    drop index(:projects, [:organization_id])

    alter table(:projects) do
      remove :organization_id
    end
  end
end
