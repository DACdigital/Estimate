defmodule EstimateWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use EstimateWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint EstimateWeb.Endpoint

      use EstimateWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import EstimateWeb.ConnCase
    end
  end

  setup tags do
    Estimate.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Logs the given `user` into the `conn` by writing a real session token.
  """
  def log_in_user(conn, user) do
    token = Estimate.Accounts.generate_user_session_token(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end

  @doc """
  ExUnit setup helper: registers a plain user and logs them in.
  """
  def register_and_log_in_user(%{conn: conn}) do
    user = Estimate.AccountsFixtures.user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  @doc """
  ExUnit setup helper: registers a user with a new organization (owner)
  and logs them in. Returns `:conn`, `:user`, and `:org`.
  """
  def register_and_log_in_org_owner(%{conn: conn}) do
    %{user: user, organization: org} =
      Estimate.AccountsFixtures.user_with_organization_fixture()

    %{conn: log_in_user(conn, user), user: user, org: org}
  end
end
