defmodule Estimate.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use Estimate.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias Estimate.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Estimate.DataCase
    end
  end

  setup tags do
    Estimate.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Estimate.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end

  @doc """
  Sets up RLS enforcement for a test. Assumes the `estimate_app` role
  and sets the org context. Call after creating your org fixture.

      setup do
        org = create_org_fixture()
        setup_rls(org.id)
        %{org: org}
      end
  """
  def setup_rls(org_id) when is_binary(org_id) do
    Estimate.Repo.assume_app_role()
    Estimate.Repo.set_org_context(org_id)
  end

  @doc """
  Sets up RLS with both org and user context. Required for
  project-level collaborator policies.
  """
  def setup_rls(org_id, user_id) when is_binary(org_id) and is_binary(user_id) do
    Estimate.Repo.assume_app_role()
    Estimate.Repo.set_org_context(org_id)
    Estimate.Repo.set_user_context(user_id)
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
