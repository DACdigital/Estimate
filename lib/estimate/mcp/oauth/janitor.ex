defmodule Estimate.MCP.OAuth.Janitor do
  @moduledoc """
  Hourly cleanup of OAuth rows that can no longer be used: authorization
  codes more than an hour past expiry that no token references, and tokens
  revoked or refresh-expired more than seven days ago. Runs at boot and then
  every `interval_ms`. Disabled in test (config `enabled: false`); `run/0`
  is callable directly.
  """
  use GenServer
  require Logger
  import Ecto.Query

  alias Estimate.MCP.OAuth.{Code, Token}
  alias Estimate.Repo

  @default_interval :timer.hours(1)
  @code_grace_seconds 3600
  @token_grace_seconds 7 * 24 * 3600

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    config = Application.get_env(:estimate, __MODULE__, [])
    enabled = Keyword.get(opts, :enabled, Keyword.get(config, :enabled, true))

    interval =
      Keyword.get(opts, :interval_ms, Keyword.get(config, :interval_ms, @default_interval))

    if enabled, do: send(self(), :run)
    {:ok, %{interval: interval, enabled: enabled}}
  end

  @impl true
  def handle_info(:run, state) do
    counts = run()
    # Logs only aggregate counts (integers), never token/code values or hashes.
    Logger.info("oauth janitor: pruned #{counts.codes} codes, #{counts.tokens} tokens")
    Process.send_after(self(), :run, state.interval)
    {:noreply, state}
  end

  @spec run() :: %{codes: non_neg_integer(), tokens: non_neg_integer()}
  def run do
    Repo.without_rls(fn ->
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      code_cutoff = DateTime.add(now, -@code_grace_seconds)
      token_cutoff = DateTime.add(now, -@token_grace_seconds)

      # Delete tokens before codes so `code_id` nilification (nilify_all on
      # code delete) never races the token delete below, and so the
      # `not exists` check on Token stays consistent within this run.
      {tokens, _} =
        Repo.delete_all(
          from(t in Token,
            where: t.revoked_at < ^token_cutoff or t.refresh_expires_at < ^token_cutoff
          )
        )

      # Never delete a code still referenced by any token: Task 6's 90-day
      # absolute refresh lifetime reads the originating code's inserted_at
      # through Token.code_id, so a live token family must keep its code row.
      referenced = from(t in Token, where: t.code_id == parent_as(:code).id)

      {codes, _} =
        Repo.delete_all(
          from(c in Code,
            as: :code,
            where: c.expires_at < ^code_cutoff and not exists(referenced)
          )
        )

      %{codes: codes, tokens: tokens}
    end)
  end
end
