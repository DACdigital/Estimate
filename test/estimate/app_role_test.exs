defmodule Estimate.AppRoleTest do
  use Estimate.DataCase, async: true

  test "estimate_app cannot log in and cannot create schema objects" do
    %{rows: [[can_login]]} =
      Estimate.Repo.query!("SELECT rolcanlogin FROM pg_roles WHERE rolname = 'estimate_app'")

    refute can_login

    %{rows: [[can_create]]} =
      Estimate.Repo.query!("SELECT has_schema_privilege('estimate_app', 'public', 'CREATE')")

    refute can_create
  end
end
