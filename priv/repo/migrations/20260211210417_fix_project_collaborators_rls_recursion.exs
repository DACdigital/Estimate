defmodule Estimate.Repo.Migrations.FixProjectCollaboratorsRlsRecursion do
  use Ecto.Migration

  def up do
    execute "DROP POLICY IF EXISTS org_isolation ON project_collaborators"
    execute "ALTER TABLE project_collaborators DISABLE ROW LEVEL SECURITY"
  end

  def down do
    execute "ALTER TABLE project_collaborators ENABLE ROW LEVEL SECURITY"

    execute """
    CREATE POLICY org_isolation ON project_collaborators
      USING (
        EXISTS (
          SELECT 1 FROM projects p
          WHERE p.id = project_collaborators.project_id
            AND p.organization_id = current_setting('app.current_organization_id')::uuid
        )
      )
    """
  end
end
