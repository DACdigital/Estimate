defmodule Estimate.Repo do
  use Ecto.Repo,
    otp_app: :estimate,
    adapter: Ecto.Adapters.Postgres

  import Ecto.Query

  # ---------------------------------------------------------------------------
  # Init — skip after_connect during migrations so DDL runs as superuser
  # ---------------------------------------------------------------------------

  @impl true
  def init(_type, config) do
    if skip_after_connect?() do
      {:ok, Keyword.delete(config, :after_connect)}
    else
      {:ok, config}
    end
  end

  # Skip SET ROLE during migrations (need DDL as superuser) and tests
  # (run as postgres by default; tests opt into RLS via DataCase.setup_rls/1).
  defp skip_after_connect? do
    Application.get_env(:estimate, :env) == :test or
      System.get_env("SKIP_RLS_ROLE") == "true" or
      System.argv()
      |> Enum.any?(
        &(&1 in ~w(ecto.migrate ecto.rollback ecto.reset ecto.setup ecto.create ecto.drop))
      )
  end

  # ---------------------------------------------------------------------------
  # prepare_query — app-level org scoping (defense-in-depth alongside RLS)
  # ---------------------------------------------------------------------------

  @impl true
  def prepare_query(_operation, query, opts) do
    case Keyword.get(opts, :org_id) do
      nil -> {query, opts}
      org_id -> {from(r in query, where: r.organization_id == ^org_id), opts}
    end
  end

  # ---------------------------------------------------------------------------
  # Connection lifecycle
  # ---------------------------------------------------------------------------

  @doc """
  Postgrex after_connect callback. Called once per new DB connection.
  Sets the non-superuser `estimate_app` role (subject to RLS policies)
  and clears any stale org context.

  Skipped during migrations (via init/2) so DDL runs as superuser.
  """
  def after_connect(conn) do
    Postgrex.query!(conn, "SET ROLE estimate_app", [])
    Postgrex.query!(conn, "SELECT set_config('app.current_org_id', '', false)", [])
    Postgrex.query!(conn, "SELECT set_config('app.current_user_id', '', false)", [])
  end

  # ---------------------------------------------------------------------------
  # Org-scoped RLS API
  # ---------------------------------------------------------------------------

  @doc """
  Stores org_id in the process dictionary. Called once per LiveView mount.
  Context functions use `ensure_org_context/1` to automatically wrap
  DB operations with the correct RLS context.
  """
  def put_org_id(org_id) when is_binary(org_id) do
    Process.put(:rls_org_id, org_id)
  end

  @doc """
  Stores user_id in the process dictionary. Called once per LiveView mount.
  Used by with_org_context to set RLS user context for collaborator policies.
  """
  def put_user_id(user_id) when is_binary(user_id) do
    Process.put(:rls_user_id, user_id)
  end

  @doc """
  Checks out a connection, ensures `estimate_app` role, and sets the
  RLS org context variable. All DB calls within `fun` use the same
  connection with RLS enforced for `org_id`.
  """
  def with_org_context(org_id, fun) when is_binary(org_id) and is_function(fun, 0) do
    user_id = Process.get(:rls_user_id)

    checkout(fn ->
      query!("SET ROLE estimate_app", [])
      query!("SELECT set_config('app.current_org_id', $1, false)", [org_id])

      if user_id do
        query!("SELECT set_config('app.current_user_id', $1, false)", [user_id])
      end

      fun.()
    end)
  end

  @doc """
  Wraps `fun` with RLS org context if org_id is in the process dictionary
  (set by `put_org_id/1` during LiveView mount). If no org_id is stored
  (e.g. during migrations or tests without setup_rls), runs without context.

  This is the primary API for context modules. It's transparent to callers
  and backward-compatible with tests that don't opt into RLS.
  """
  def ensure_org_context(fun) when is_function(fun, 0) do
    case Process.get(:rls_org_id) do
      nil -> fun.()
      org_id -> with_org_context(org_id, fun)
    end
  end

  @doc """
  Checks out a connection and resets to the login role (postgres/superuser),
  bypassing RLS. For system-level operations like search reindexing.
  """
  def without_rls(fun) when is_function(fun, 0) do
    checkout(fn ->
      query!("RESET ROLE", [])
      fun.()
    end)
  end

  @doc "Sets RLS org context on current connection. For test helper."
  def set_org_context(org_id) when is_binary(org_id) do
    query("SELECT set_config('app.current_org_id', $1, false)", [org_id])
  end

  @doc "Sets RLS user context on current connection. For test helper."
  def set_user_context(user_id) when is_binary(user_id) do
    query("SELECT set_config('app.current_user_id', $1, false)", [user_id])
  end

  @doc "Clears the RLS org context."
  def clear_org_context do
    query("SELECT set_config('app.current_org_id', '', false)")
  end

  @doc "SET ROLE estimate_app on current connection. For test helper."
  def assume_app_role do
    query!("SET ROLE estimate_app", [])
  end
end
