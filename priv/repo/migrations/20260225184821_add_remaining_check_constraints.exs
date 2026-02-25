defmodule Estimate.Repo.Migrations.AddRemainingCheckConstraints do
  use Ecto.Migration

  def up do
    execute """
    ALTER TABLE projects
    ADD CONSTRAINT projects_status_check
    CHECK (status IN ('active', 'completed', 'archived'))
    """

    execute """
    ALTER TABLE project_collaborators
    ADD CONSTRAINT project_collaborators_role_check
    CHECK (role IN ('owner', 'editor', 'viewer'))
    """
  end

  def down do
    execute "ALTER TABLE projects DROP CONSTRAINT projects_status_check"
    execute "ALTER TABLE project_collaborators DROP CONSTRAINT project_collaborators_role_check"
  end
end
