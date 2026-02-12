defmodule Estimate.Repo.Migrations.FixProjectAccessPolicyColumnRef do
  use Ecto.Migration

  def up do
    execute "DROP POLICY IF EXISTS project_access ON projects"

    execute """
    CREATE POLICY project_access ON projects FOR ALL
      USING (
        organization_id = current_org_id()
        AND (
          is_org_admin()
          OR EXISTS (
            SELECT 1 FROM project_collaborators pc
            WHERE pc.project_id = projects.id AND pc.user_id = current_user_id()
          )
        )
      )
      WITH CHECK (organization_id = current_org_id())
    """
  end

  def down do
    execute "DROP POLICY IF EXISTS project_access ON projects"

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
  end
end
