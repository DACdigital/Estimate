defmodule Estimate.Repo.Migrations.AddCheckConstraints do
  use Ecto.Migration

  def up do
    # S2: invite must have email OR code
    execute """
    ALTER TABLE invites
    ADD CONSTRAINT invites_email_or_code
    CHECK (email IS NOT NULL OR code IS NOT NULL)
    """

    # S5: role enum constraints
    execute """
    ALTER TABLE memberships
    ADD CONSTRAINT memberships_role_check
    CHECK (role IN ('owner', 'admin', 'member'))
    """

    execute """
    ALTER TABLE invites
    ADD CONSTRAINT invites_role_check
    CHECK (role IN ('owner', 'admin', 'member'))
    """

    execute """
    ALTER TABLE join_requests
    ADD CONSTRAINT join_requests_status_check
    CHECK (status IN ('pending', 'approved', 'rejected'))
    """
  end

  def down do
    execute "ALTER TABLE invites DROP CONSTRAINT invites_email_or_code"
    execute "ALTER TABLE memberships DROP CONSTRAINT memberships_role_check"
    execute "ALTER TABLE invites DROP CONSTRAINT invites_role_check"
    execute "ALTER TABLE join_requests DROP CONSTRAINT join_requests_status_check"
  end
end
