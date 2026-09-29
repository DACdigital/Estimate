defmodule Estimate.Repo.Migrations.GrantEstimateAppMembershipWithSet do
  use Ecto.Migration

  # ============================================================================
  # Ensure the migrating role can `SET ROLE estimate_app` at runtime.
  #
  # `EnforceRlsWithAppRole` (20260211080345) creates the estimate_app role but
  # does not explicitly grant it to the migrating user. Two scenarios diverge:
  #
  #   * Superuser migrator (docker-compose, chart's bundled Postgres) — SET
  #     ROLE always works, superusers bypass the membership check.
  #
  #   * Non-superuser CREATEROLE migrator (CloudNativePG app user, managed
  #     Postgres with a locked-down bootstrap user, etc.) — PG16+ auto-grants
  #     membership on CREATE ROLE, but WITHOUT the SET option by default. The
  #     first `SET ROLE estimate_app` in `Estimate.Repo.after_connect` then
  #     fails with `permission denied to set role "estimate_app"` and every
  #     org-context page returns 500.
  #
  # Fix: idempotently grant with SET TRUE + INHERIT TRUE to the current user.
  # No-op for superusers, unblocks non-superuser migrators.
  # ============================================================================

  def up do
    execute """
    DO $$
    BEGIN
      EXECUTE format(
        'GRANT estimate_app TO %I WITH SET TRUE, INHERIT TRUE',
        current_user
      );
    END
    $$
    """
  end

  def down do
    # No-op: revoking SET on a live deployment would immediately break every
    # RLS-enforced query. If you're rolling back the estimate_app role itself,
    # the earlier migration's DROP ROLE cascade will strip the membership.
    :ok
  end
end
