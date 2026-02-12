defmodule Estimate.Repo.Migrations.AddProjectLevelRls do
  use Ecto.Migration

  def up do
    # ==========================================================
    # 1. current_user_id() session variable function
    # ==========================================================
    execute """
    CREATE OR REPLACE FUNCTION current_user_id() RETURNS uuid AS $$
      SELECT NULLIF(current_setting('app.current_user_id', true), '')::uuid;
    $$ LANGUAGE sql STABLE
    """

    # ==========================================================
    # 2. is_org_admin() helper — checks if current user is
    #    owner/admin of the current org. memberships has RLS
    #    disabled so this is safe to call from within policies.
    # ==========================================================
    execute """
    CREATE OR REPLACE FUNCTION is_org_admin() RETURNS boolean AS $$
      SELECT EXISTS (
        SELECT 1 FROM memberships
        WHERE user_id = current_user_id()
          AND organization_id = current_org_id()
          AND role IN ('owner', 'admin')
      );
    $$ LANGUAGE sql STABLE
    """

    # ==========================================================
    # 3. Replace projects policy: org match + (admin OR collaborator)
    # ==========================================================
    execute "DROP POLICY IF EXISTS org_isolation ON projects"

    execute """
    CREATE POLICY project_access ON projects FOR ALL
      USING (
        organization_id = current_org_id()
        AND (
          is_org_admin()
          OR EXISTS (
            SELECT 1 FROM project_collaborators pc
            WHERE pc.project_id = id AND pc.user_id = current_user_id()
          )
        )
      )
      WITH CHECK (organization_id = current_org_id())
    """

    # ==========================================================
    # 4. Replace estimations policy: same pattern via project_id
    # ==========================================================
    execute "DROP POLICY IF EXISTS org_isolation ON estimations"

    execute """
    CREATE POLICY estimation_access ON estimations FOR ALL
      USING (
        organization_id = current_org_id()
        AND (
          is_org_admin()
          OR EXISTS (
            SELECT 1 FROM project_collaborators pc
            WHERE pc.project_id = estimations.project_id AND pc.user_id = current_user_id()
          )
        )
      )
      WITH CHECK (organization_id = current_org_id())
    """

    # ==========================================================
    # 5. Performance index for collaborator lookups in policies
    # ==========================================================
    execute """
    CREATE INDEX IF NOT EXISTS idx_project_collaborators_user_project
      ON project_collaborators(user_id, project_id)
    """
  end

  def down do
    execute "DROP INDEX IF EXISTS idx_project_collaborators_user_project"

    # Restore original org_isolation policies
    execute "DROP POLICY IF EXISTS estimation_access ON estimations"

    execute """
    CREATE POLICY org_isolation ON estimations FOR ALL
      USING (organization_id = current_org_id())
      WITH CHECK (organization_id = current_org_id())
    """

    execute "DROP POLICY IF EXISTS project_access ON projects"

    execute """
    CREATE POLICY org_isolation ON projects FOR ALL
      USING (organization_id = current_org_id())
      WITH CHECK (organization_id = current_org_id())
    """

    execute "DROP FUNCTION IF EXISTS is_org_admin()"
    execute "DROP FUNCTION IF EXISTS current_user_id()"
  end
end
