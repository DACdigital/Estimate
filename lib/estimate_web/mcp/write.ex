defmodule EstimateWeb.MCP.Write do
  @moduledoc """
  Shared orchestration for write tools: sets RLS scope, enforces the org
  write kill-switch and a per-tool authorization gate, runs the mutation,
  and renders a uniform Anubis response. `run_fun` returns the ready
  JSON-native success map (entity + `:url`) or an error.
  """

  alias Anubis.Server.Response
  alias EstimateWeb.MCP.{Authz, Scope, Serializers}
  alias Estimate.Organizations.Currencies

  def execute(frame, gate_fun, run_fun)
      when is_function(gate_fun, 1) and is_function(run_fun, 1) do
    result =
      Scope.with_scope(frame, fn claims ->
        with :ok <- Authz.require_write_scope(claims),
             :ok <- Authz.require_write_enabled(claims),
             :ok <- gate_fun.(claims) do
          safe_run(run_fun, claims)
        end
      end)

    {:reply, render(result), frame}
  end

  def resolve_currency(code, _org_id) when code in [nil, ""], do: {:ok, nil}

  def resolve_currency(code, org_id) when is_binary(code) do
    case Currencies.get_currency_by_code(org_id, code) do
      nil -> {:error, "unknown currency code: #{code}"}
      currency -> {:ok, currency.id}
    end
  end

  defp safe_run(run_fun, claims) do
    run_fun.(claims)
  rescue
    Ecto.NoResultsError -> {:error, :not_found}
    Ecto.Query.CastError -> {:error, :not_found}
  end

  defp render({:ok, map}) when is_map(map), do: Response.json(Response.tool(), map)

  defp render({:error, %Ecto.Changeset{} = cs}),
    do: Response.error(Response.tool(), Serializers.changeset_errors(cs))

  defp render({:error, :write_disabled}),
    do: Response.error(Response.tool(), "MCP writes are disabled for this organization")

  defp render({:error, :insufficient_scope}),
    do:
      Response.error(
        Response.tool(),
        "this connection was authorized read-only; reconnect it and grant write access"
      )

  defp render({:error, :unauthorized}), do: Response.error(Response.tool(), "not authorized")
  defp render({:error, :not_found}), do: Response.error(Response.tool(), "not found")
  defp render({:error, msg}) when is_binary(msg), do: Response.error(Response.tool(), msg)

  # Defensive catch-all: an unexpected error shape must render a clean tool
  # error, never raise FunctionClauseError into anubis.
  defp render({:error, _reason}), do: Response.error(Response.tool(), "operation failed")
end
