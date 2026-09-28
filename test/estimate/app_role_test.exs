defmodule Estimate.AppRoleTest do
  use Estimate.DataCase, async: true

  # NOLOGIN is intentionally not asserted: ALTER ROLE ... NOLOGIN needs
  # CREATEROLE + ADMIN OPTION on PG16+, which the migrator lacks in prod,
  # so it is an optional DBA hardening step (see HardenAppRole migration).
  test "estimate_app cannot create schema objects" do
    %{rows: [[can_create]]} =
      Estimate.Repo.query!("SELECT has_schema_privilege('estimate_app', 'public', 'CREATE')")

    refute can_create
  end
end
