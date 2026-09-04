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
  @default_initial_delay :timer.seconds(30)
  @code_grace_seconds 3600
  @token_grace_seconds 7 * 24 * 3600

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    config = Application.get_env(:estimate, __MODULE__, [])
    enabled = Keyword.get(opts, :enabled, Keyword.get(config, :enabled, true))

    interval =
      Keyword.get(opts, :interval_ms, Keyword.get(config, :interval_ms, @default_interval))

    initial_delay =
      Keyword.get(
        opts,
        :initial_delay_ms,
        Keyword.get(config, :initial_delay_ms, @default_initial_delay)
      )

    run_fun = Keyword.get(opts, :run_fun, &__MODULE__.run/0)

    # Boot never blocks on the DB: the first run is scheduled `initial_delay`
    # (default 30s) after supervision start, not fired synchronously with an
    # immediate `send/2`, so a slow/unavailable Repo at boot can't hold up
    # startup or the rest of the supervision tree.
    if enabled, do: Process.send_after(self(), :run, initial_delay)
    {:ok, %{interval: interval, enabled: enabled, run_fun: run_fun}}
  end

  # Disabled: never run, never reschedule. Only reachable in tests that send
  # :run directly (init/1 above never schedules a first run when disabled).
  @impl true
  def handle_info(:run, %{enabled: false} = state), do: {:noreply, state}

  # The janitor must never take the node down: a DB error, a bug in run/0, or
  # any other raise here must not crash this GenServer (it's a permanent
  # child of Estimate.Supervisor) or the caller await it via handle_info.
  # rescue + always-reschedule (placed after the try, so both the success and
  # rescue paths reach it) keeps the periodic sweep alive across failures.
  @impl true
  def handle_info(:run, state) do
    try do
      counts = state.run_fun.()
      # Logs only aggregate counts (integers), never token/code values or hashes.
      Logger.info("oauth janitor: pruned #{counts.codes} codes, #{counts.tokens} tokens")
    rescue
      # Exception.message/1 is the exception's own description text (e.g. an
      # Ecto/Postgrex error message), never a raw token/code plaintext or
      # hash -- the janitor's queries never bind those into an exception.
      e -> Logger.warning("oauth janitor: run failed: #{Exception.message(e)}")
    end

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
