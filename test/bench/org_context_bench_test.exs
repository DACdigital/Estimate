defmodule Estimate.Bench.OrgContextBenchTest do
  @moduledoc """
  Timing harness, not a correctness test. Run with:

      mix test --include bench test/bench/org_context_bench_test.exs

  Prints statement count and wall time for 1_000 flat and 1_000 nested
  `Repo.with_org_context/2` calls. Record the numbers in the commit message.
  """
  use Estimate.DataCase, async: false
  @moduletag :bench

  alias Estimate.Repo

  @n 1_000

  setup do
    test_pid = self()
    handler = "bench-org-ctx-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler,
      [:estimate, :repo, :query],
      fn _event, _measurements, _meta, _ -> send(test_pid, :query) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)
    %{org_id: Ecto.UUID.generate()}
  end

  defp drain(count \\ 0) do
    receive do
      :query -> drain(count + 1)
    after
      0 -> count
    end
  end

  test "flat and nested with_org_context cost", %{org_id: org_id} do
    Repo.put_user_id(Ecto.UUID.generate())
    drain()

    {flat_us, _} =
      :timer.tc(fn ->
        for _ <- 1..@n, do: Repo.with_org_context(org_id, fn -> :ok end)
      end)

    flat_queries = drain()

    {nested_us, _} =
      :timer.tc(fn ->
        for _ <- 1..@n do
          Repo.with_org_context(org_id, fn ->
            Repo.with_org_context(org_id, fn -> :ok end)
          end)
        end
      end)

    nested_queries = drain()

    IO.puts("""

    org_context bench (n=#{@n})
      flat:   #{flat_queries} statements, #{div(flat_us, 1000)} ms  (#{Float.round(flat_queries / @n, 1)} stmts/call)
      nested: #{nested_queries} statements, #{div(nested_us, 1000)} ms  (#{Float.round(nested_queries / @n, 1)} stmts/outer call)
    """)

    assert flat_queries > 0
  end
end
