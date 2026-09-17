# Audit Batch 3C — Perf Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the three measured performance ceilings from the audit: the originating LiveView's own PubSub round-trip (`broadcast_from`), the 7-statement per-call cost of `Repo.with_org_context/2`, and the whole-grid re-render on every estimator change (LiveView streams with precomputed totals).

**Architecture:** `EstimationEngine.broadcast/2` excludes the caller; `with_org_context` collapses to 3 statements and becomes a no-op when nested in the same context. The estimator grid becomes one `:rows` stream of three row kinds (`epic-<id>`, `task-<id>`, `epic-<id>-subtotal`) built by a pure `Rows` module, with all footer/breakdown numbers precomputed once into a `Totals` struct. A `Grid` module owns every stream mutation; a `Sync` module maps each PubSub event to either a targeted `stream_insert` or a full reset. `@estimation` stays the in-memory source of truth. Bench tests (tagged `:bench`, excluded by default) record before/after numbers in commit messages.

**Tech Stack:** Elixir 1.18, Phoenix 1.8.3, Phoenix LiveView 1.1 streams (`stream/4`, `stream_insert/4`, `stream_configure/3`, `phx-update="stream"`), Ecto 3.13 / Postgres 17 RLS, `:telemetry` (`[:estimate, :repo, :query]`), ExUnit.

**Spec:** `docs/superpowers/specs/2026-09-16-audit-batch-3-followups-decomposition-perf-design.md` — section "3C — perf" (C1, C2, C3). Read it first. Carry-overs from 3B recorded in that batch's ledger and this plan's Task 2 / Task 7.

## Global Constraints

- Tests never use `Process.sleep` (AGENTS.md). Characterization tests **diverge state from its default before asserting**. `refute_receive`/`assert_receive` with explicit timeouts are fine.
- The 3B characterization suite (`test/estimate_web/live/estimator_live/*_test.exs`, 81 tests) is the gate: it may be **edited only where this plan says so** (realtime test re-pointed at the stream, `reorder_roles` test, exact-order assertions once ordering is deterministic). It must be green after every task.
- Handler modules keep the `(socket, params) -> {:noreply, socket}` contract and `Reads:`/`Writes:` moduledocs. `Index` stays mount/render/delegations.
- No schema migrations. No changes to `Estimate.EstimationEngine.Calculator` semantics (it may be *called* from new modules). No CSP/security surface changes. Contexts under `lib/estimate/` may change only where a task names the file.
- Update matrix (spec C3) is the contract: **any assign a row reads either triggers a re-insert of the rows it affects or a stream reset.** Rows read: `@editing`, `@can_edit`, `@show_descriptions`, `@show_all_in_rates` (via row totals), `@estimation.roles`, `@estimation.currency`.
- Bench numbers (before/after) go into the commit message of the task that changes the measured thing.
- `mix precommit` (format, `--warnings-as-errors`, full suite) green before every commit; bench tests are excluded from the default run. Commit trailer exactly `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` — never any other model name.
- Worktree via EnterWorktree then `git reset --hard main`; copy `deps/`, `_build/`, `.env`. If `git commit` fails with "1Password: failed to fill whole buffer", stop and report.

## File structure after 3C

| File | Responsibility |
|---|---|
| `lib/estimate/repo.ex` | `with_org_context/2`: 3 statements, nested same-context no-op via `:rls_ctx` process-dict marker |
| `lib/estimate/estimation_engine.ex` | `broadcast/2` → `Phoenix.PubSub.broadcast_from/4`; moduledoc payload contract |
| `lib/estimate/estimation_engine/estimations.ex` | `get_estimation!/2` preloads ordered by `position, inserted_at, id` |
| `lib/estimate_web/live/estimator_live/helpers.ex` | gains public `display_roles/2` (single home) |
| `lib/estimate_web/live/estimator_live/rows.ex` | `Rows` — pure builder of the three row kinds (+ `Rows.EpicHeader`, `Rows.Task`, `Rows.EpicSubtotal` structs) |
| `lib/estimate_web/live/estimator_live/totals.ex` | `Totals` — struct + `compute/3`, all footer/breakdown numbers |
| `lib/estimate_web/live/estimator_live/grid.ex` | `Grid` — owns the `:rows` stream and `@totals`/`@grid_empty?`: `init/1`, `reset/1`, `upsert_task/2`, `upsert_epic_header/2`, `refresh_editing/3` |
| `lib/estimate_web/live/estimator_live/sync.ex` | `Sync.handle/2` — PubSub event → targeted update or reset (the update matrix) |
| `lib/estimate_web/live/estimator_live/estimates.ex` | gains `update_task_in_memory/2`, `update_epic_in_memory/2`; handlers call `Grid` |
| `lib/estimate_web/live/estimator_live/authz.ex` | `reload_estimation/1` = reload **and** `Grid.reset/1` (single choke point) |
| `lib/estimate_web/live/estimator_live/components/estimation_table.ex` | renders `@rows` stream via `grid_row/1` + footer from `@totals` |
| `lib/estimate_web/live/estimator_live/components/cost_breakdown.ex` | renders from `@totals.breakdown` |
| `lib/estimate_web/live/estimator_live/index.ex` | `mount` calls `Grid.init/1`; `render` passes stream/totals; `handle_info` delegates to `Sync.handle/2` |
| `test/bench/org_context_bench_test.exs`, `test/bench/estimator_grid_bench_test.exs` | `@moduletag :bench` timing harnesses |
| `test/estimate_web/live/estimator_live/{rows,totals,grid,sync}_test.exs` | unit/LV tests for the new modules |

---

### Task 1: `Repo.with_org_context/2` — 3 statements + nested no-op (C2)

**Files:**
- Modify: `lib/estimate/repo.ex` (`with_org_context/2`, ~lines 82-113)
- Modify: `test/test_helper.exs`
- Create: `test/bench/org_context_bench_test.exs`
- Test: `test/estimate/repo_without_rls_test.exs` (existing state-restoration tests stay unchanged; add a `describe "with_org_context/2 statement count"`)

**Interfaces:**
- Consumes: `Repo.checkout/1`, `Repo.query!/2`, process-dict keys `:rls_org_id`, `:rls_user_id` (set by `put_org_id/1`, `put_user_id/1`).
- Produces: unchanged public API. New process-dict key `:rls_ctx :: {org_id, user_id | nil}` set only while inside the outermost `with_org_context` on a checked-out connection.

Background: today each call runs 7 statements (capture; `SET ROLE`; `set_config` org; optional `set_config` user; restore ×3) and nested calls repeat all of them. `set_config('role', $1, false)` is exactly `SET ROLE $1`, and role names are legal bind parameters there, so the whole setup is one `SELECT`. Because `checkout/1` pins the connection to the process for the duration of `fun`, a nested call in the same process with the same `{org_id, user_id}` can skip every statement.

- [ ] **Step 1: Make `:bench` tests opt-in**

`test/test_helper.exs`:

```elixir
ExUnit.start(exclude: [:bench])
```

- [ ] **Step 2: Write the bench harness and record BEFORE numbers**

`test/bench/org_context_bench_test.exs`:

```elixir
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
```

Run: `mix test --include bench test/bench/org_context_bench_test.exs`
Expected BEFORE: ~7 stmts/call flat, ~14 stmts/outer call nested. Copy the printed block into your report.

- [ ] **Step 3: Write the failing statement-count tests**

Append to `test/estimate/repo_without_rls_test.exs` inside the module:

```elixir
  describe "with_org_context/2 statement count" do
    setup do
      test_pid = self()
      handler = "ctx-count-#{System.unique_integer([:positive])}"

      :telemetry.attach(
        handler,
        [:estimate, :repo, :query],
        fn _e, _m, meta, _ -> send(test_pid, {:query, meta.query}) end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler) end)
      :ok
    end

    defp queries(acc \\ []) do
      receive do
        {:query, q} -> queries([q | acc])
      after
        0 -> Enum.reverse(acc)
      end
    end

    test "a flat call issues exactly 3 statements: capture, set, restore" do
      org_id = Ecto.UUID.generate()
      Repo.put_user_id(Ecto.UUID.generate())
      queries()

      Repo.with_org_context(org_id, fn -> :ok end)

      [capture, set, restore] = queries()
      assert capture =~ "current_setting('app.current_org_id'"
      assert set =~ "set_config('role'"
      assert set =~ "set_config('app.current_org_id'"
      assert set =~ "set_config('app.current_user_id'"
      assert restore =~ "set_config('role'"
    end

    test "a nested call with the same org and user issues no statements" do
      org_id = Ecto.UUID.generate()
      Repo.put_user_id(Ecto.UUID.generate())
      queries()

      Repo.with_org_context(org_id, fn ->
        queries()
        inner = Repo.with_org_context(org_id, fn -> current_user_role() end)
        assert inner == "estimate_app"
        assert queries() == []
      end)

      assert Process.get(:rls_ctx) == nil
    end

    test "a nested call with a different org runs the full path and restores the outer context" do
      org_a = Ecto.UUID.generate()
      org_b = Ecto.UUID.generate()
      Repo.put_user_id(Ecto.UUID.generate())

      Repo.with_org_context(org_a, fn ->
        queries()
        Repo.with_org_context(org_b, fn -> assert current_org_setting() == org_b end)
        assert length(queries()) == 3
        assert current_org_setting() == org_a
        assert current_user_role() == "estimate_app"
      end)
    end

    test "the marker is cleared even when fun raises" do
      org_id = Ecto.UUID.generate()

      assert_raise RuntimeError, "boom", fn ->
        Repo.with_org_context(org_id, fn -> raise "boom" end)
      end

      assert Process.get(:rls_ctx) == nil
    end
  end
```

(`current_user_role/0` and `current_org_setting/0` already exist at the top of this test file.)

- [ ] **Step 4: Run to verify they fail**

Run: `mix test test/estimate/repo_without_rls_test.exs`
Expected: the four new tests fail (statement count is 7, nested call issues statements, no `:rls_ctx` key logic).

- [ ] **Step 5: Implement**

Replace `with_org_context/2` in `lib/estimate/repo.ex`:

```elixir
  @doc """
  Checks out a connection, assumes the `estimate_app` role and pins the RLS
  org (and user) context for the duration of `fun`.

  Three statements per call: capture prior state, set role+org+user in one
  `SELECT set_config(...)`, restore. A call nested inside another
  `with_org_context` on the same process with the *same* `{org_id, user_id}`
  runs `fun` directly with zero statements — `checkout/1` pins the connection
  to this process, so the outer context is still in force. A nested call with
  a different context runs the full path and restores the outer one.

  State-neutral: pooled connections never check back in polluted.
  """
  def with_org_context(org_id, fun) when is_binary(org_id) and is_function(fun, 0) do
    user_id = Process.get(:rls_user_id)
    ctx = {org_id, user_id}

    case Process.get(:rls_ctx) do
      ^ctx -> fun.()
      prev_ctx -> enter_org_context(ctx, prev_ctx, fun)
    end
  end

  defp enter_org_context({org_id, user_id} = ctx, prev_ctx, fun) do
    checkout(fn ->
      %{rows: [[prev_role, prev_org, prev_user]]} =
        query!(
          "SELECT current_user::text, current_setting('app.current_org_id', true), current_setting('app.current_user_id', true)",
          []
        )

      # `set_config('role', ...)` is SET ROLE; role names are legal bind params here.
      # When no user_id is pinned for this process, keep whatever the connection had.
      query!(
        "SELECT set_config('role', $1, false), set_config('app.current_org_id', $2, false), set_config('app.current_user_id', $3, false)",
        ["estimate_app", org_id, user_id || prev_user || ""]
      )

      Process.put(:rls_ctx, ctx)

      try do
        fun.()
      after
        if prev_ctx, do: Process.put(:rls_ctx, prev_ctx), else: Process.delete(:rls_ctx)

        query!(
          "SELECT set_config('role', $1, false), set_config('app.current_org_id', $2, false), set_config('app.current_user_id', $3, false)",
          [prev_role, prev_org || "", prev_user || ""]
        )
      end
    end)
  end
```

- [ ] **Step 6: Run the tests**

Run: `mix test test/estimate/repo_without_rls_test.exs test/estimate`
Expected: all green — the pre-existing state-restoration tests (`with_org_context/2 state restoration`, `without_rls nested inside with_org_context …`, `with_org_context nested inside without_rls …`) are the safety net and must pass unchanged.

- [ ] **Step 7: Record AFTER numbers**

Run: `mix test --include bench test/bench/org_context_bench_test.exs`
Expected: 3.0 stmts/call flat, 3.0 stmts/outer call nested. Copy the block into the report and the commit message.

- [ ] **Step 8: Precommit and commit**

Run: `mix precommit` (bench excluded by default).

```bash
git add lib/estimate/repo.ex test/test_helper.exs test/bench/org_context_bench_test.exs test/estimate/repo_without_rls_test.exs
git commit -m "perf(repo): with_org_context in 3 statements; nested same-context calls are free

set_config('role', ...) is SET ROLE, so capture/set/restore collapse to one
SELECT each (7 -> 3). A process-dict marker {:rls_ctx, {org, user}} set on
the checked-out connection lets a nested call with the same context skip
every statement; a different context runs the full path and restores.

Bench (test/bench/org_context_bench_test.exs, n=1000):
  before: flat <X> stmts/call, <ms> ms; nested <Y> stmts/outer, <ms> ms
  after:  flat 3.0 stmts/call, <ms> ms; nested 3.0 stmts/outer, <ms> ms

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

(Replace the `<…>` with the measured numbers — the commit message must carry real values.)

---

### Task 2: Deterministic child ordering + grid bench baseline

**Files:**
- Modify: `lib/estimate/estimation_engine/estimations.ex` (`get_estimation!/2` preloads, ~lines 56-77)
- Modify: `test/support/estimator_live_helpers.ex`, `test/estimate_web/live/estimator_live/epics_test.exs`, `tasks_test.exs`, `realtime_test.exs` (drop the `# NOTE: characterizes current behaviour` set-assertions in favour of exact order)
- Create: `test/bench/estimator_grid_bench_test.exs`
- Test: `test/estimate/estimation_engine/estimations_current_test.exs` (add one ordering test)

**Interfaces:**
- Produces: `get_estimation!/2` returns `roles`, `epics`, `epics[].tasks` ordered by `position ASC, inserted_at ASC, id ASC`. Streams (Task 6) rely on this order being stable.

Background (3B carry-over): `Epic.changeset/2`/`Task.changeset/2` default `position` to 0 and creates never set it, so siblings tie and Postgres returns them in arbitrary order. A stream renders rows in list order; a flapping order would re-insert rows on every reset. Fix at the read side with tie-breakers (no write-path behaviour change).

- [ ] **Step 1: Write the failing ordering test**

Append to `test/estimate/estimation_engine/estimations_current_test.exs`:

```elixir
  test "get_estimation!/2 orders tied positions by insertion, deterministically", %{project: project} do
    est = estimation_fixture(project)
    # all created at position 0 (schema default) — only inserted_at/id can break the tie
    for name <- ~w(E1 E2 E3 E4 E5 E6 E7 E8),
        do: {:ok, _} = EstimationEngine.create_epic(%{"name" => name, "estimation_id" => est.id})

    [first | _] = EstimationEngine.get_estimation!(est.id, Repo.reload!(est).organization_id).epics
    epic = first

    for name <- ~w(T1 T2 T3 T4 T5 T6 T7 T8),
        do: {:ok, _} = EstimationEngine.create_task(%{"name" => name, "epic_id" => epic.id})

    org_id = Repo.reload!(est).organization_id
    names = fn -> EstimationEngine.get_estimation!(est.id, org_id).epics |> Enum.map(& &1.name) end
    task_names = fn -> hd(EstimationEngine.get_estimation!(est.id, org_id).epics).tasks |> Enum.map(& &1.name) end

    assert names.() == ~w(E1 E2 E3 E4 E5 E6 E7 E8)
    assert task_names.() == ~w(T1 T2 T3 T4 T5 T6 T7 T8)
    # stable across reads
    assert Enum.all?(1..5, fn _ -> names.() == ~w(E1 E2 E3 E4 E5 E6 E7 E8) end)
  end
```

- [ ] **Step 2: Run to verify it fails (or flakes)**

Run: `mix test test/estimate/estimation_engine/estimations_current_test.exs --seed 0` and again with `--seed 1`. Expected: at least one run fails on order (if both pass by luck, the implementation step still applies — ties are undefined without the fix).

- [ ] **Step 3: Implement the tie-breakers**

In `get_estimation!/2`, change the three `order_by` clauses:

```elixir
          roles: ^from(r in EstimationRole, order_by: [asc: r.position, asc: r.inserted_at, asc: r.id]),
          epics:
            ^from(ep in Estimate.EstimationEngine.Epic,
              order_by: [asc: ep.position, asc: ep.inserted_at, asc: ep.id],
              preload: [
                tasks:
                  ^from(t in Estimate.EstimationEngine.Task,
                    order_by: [asc: t.position, asc: t.inserted_at, asc: t.id],
                    preload: [:estimates]
                  )
              ]
            )
```

(`inserted_at` is second-precision, so `id` is the final tie-breaker; UUIDs are not monotonic, but the order is at least stable across reads.)

- [ ] **Step 4: Tighten the 3B set-assertions to exact order**

In `test/estimate_web/live/estimator_live/epics_test.exs` test `"save_epic creates a new epic..."`: replace the sorted-set assertion with `assert Enum.map(a.estimation.epics, & &1.name) == ["Alpha", "Beta"]`. In `"reorder_epics persists..."`: keep as is (already exact after reorder). In `tasks_test.exs` `"save_task creates a task..."`: `assert Enum.map(hd(a.estimation.epics).tasks, & &1.name) == ["T-one", "T-two", "T-three"]`. In `realtime_test.exs` first test: `assert Enum.map(assigns(ctx.lv).estimation.epics, & &1.name) == ["Alpha", "Gamma"]`. Remove the `# NOTE: characterizes current behaviour…` comments that explained the ties (keep the `position: 0/1` fixture args in the helper — they are harmless). Grep for any remaining `NOTE: characterizes current behaviour` and resolve each the same way.

- [ ] **Step 5: Grid bench harness + BEFORE numbers**

`test/bench/estimator_grid_bench_test.exs`:

```elixir
defmodule EstimateWeb.Bench.EstimatorGridBenchTest do
  @moduledoc """
  Timing harness for the estimator grid. Run with:

      mix test --include bench test/bench/estimator_grid_bench_test.exs

  Seeds 20 epics x 5 tasks (100 tasks) with the default roles, then times
  (a) 20 cell edits, (b) 5 full reloads via a PubSub :epic_created event,
  (c) one priority toggle. Record the printed block in the commit message.
  """
  use EstimateWeb.ConnCase, async: false
  @moduletag :bench

  import Phoenix.LiveViewTest
  import Estimate.{AccountsFixtures, PortfolioFixtures, EstimationEngineFixtures}

  alias Estimate.EstimationEngine

  setup %{conn: conn} do
    %{user: owner, organization: org} = user_with_organization_fixture()
    project = project_fixture(nil, owner)
    est = estimation_fixture(project)

    for e <- 1..20 do
      epic = epic_fixture(est, %{name: "Epic #{e}", position: e})
      for t <- 1..5, do: task_fixture(epic, %{name: "Task #{e}.#{t}", position: t})
    end

    est = EstimationEngine.get_estimation!(est.id, org.id)
    conn = log_in_user(conn, owner)

    {:ok, lv, _} =
      live(conn, ~p"/org/#{org.id}/projects/#{project.id}/estimations/#{est.id}/estimator")

    %{lv: lv, est: est, role: hd(est.roles)}
  end

  test "cell edit, reload and filter timings", %{lv: lv, est: est, role: role} do
    tasks = est.epics |> Enum.flat_map(& &1.tasks) |> Enum.take(20)

    {edit_us, _} =
      :timer.tc(fn ->
        for {task, i} <- Enum.with_index(tasks, 1) do
          render_click(lv, "edit_estimate", %{"key" => "#{task.id}-#{role.id}"})

          render_click(lv, "save_estimate", %{
            "task-id" => task.id,
            "role-id" => role.id,
            "value" => Integer.to_string(i)
          })
        end
      end)

    {reload_us, _} =
      :timer.tc(fn ->
        for _ <- 1..5 do
          send(lv.pid, {:epic_created, nil})
          render(lv)
        end
      end)

    {filter_us, _} =
      :timer.tc(fn ->
        render_click(lv, "toggle_priority", %{"priority" => "wont"})
        render_click(lv, "toggle_priority", %{"priority" => "wont"})
      end)

    IO.puts("""

    estimator grid bench (100 tasks x #{length(est.roles)} roles)
      20 cell edits:      #{div(edit_us, 1000)} ms  (#{div(edit_us, 20_000)} ms/edit)
      5 pubsub reloads:   #{div(reload_us, 1000)} ms  (#{div(reload_us, 5_000)} ms/reload)
      priority toggle x2: #{div(filter_us, 1000)} ms
    """)

    assert edit_us > 0
  end
end
```

Run: `mix test --include bench test/bench/estimator_grid_bench_test.exs`. Copy the printed block into the report as the BEFORE baseline (it will be quoted again in Task 8).

- [ ] **Step 6: Run the estimator suite + precommit**

Run: `mix test test/estimate_web/live/estimator_live test/estimate/estimation_engine` then `mix precommit`.

- [ ] **Step 7: Commit**

```bash
git add lib/estimate/estimation_engine/estimations.ex test/estimate/estimation_engine/estimations_current_test.exs test/estimate_web/live/estimator_live test/support/estimator_live_helpers.ex test/bench/estimator_grid_bench_test.exs
git commit -m "fix(estimations): deterministic ordering for tied positions; grid bench harness

get_estimation!/2 orders roles/epics/tasks by position, inserted_at, id so
rows created at the default position 0 keep a stable order (required by
the streams-based grid). 3B set-assertions tightened to exact order.

Grid bench baseline (test/bench/estimator_grid_bench_test.exs, 100 tasks):
  20 cell edits: <ms> ms; 5 pubsub reloads: <ms> ms; priority toggle x2: <ms> ms

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: `broadcast_from` (C1)

**Files:**
- Modify: `lib/estimate/estimation_engine.ex` (`broadcast/2`, moduledoc)
- Modify: `lib/estimate_web/live/estimator_live/settings.ex` (`reorder_roles/2` must reload)
- Modify: `lib/estimate_web/live/estimator_live/estimates.ex` (moduledoc: the 3C caveat sentence is now resolved)
- Modify: `test/estimate_web/live/estimator_live/settings_test.exs` (`reorder_roles` test)
- Create: `test/estimate_web/live/estimator_live/broadcast_from_test.exs`

**Interfaces:**
- Consumes: `Phoenix.PubSub.broadcast_from/4`.
- Produces: `EstimationEngine.broadcast(estimation_id, event)` no longer delivers to `self()`. **Contract (moduledoc):** context functions are called inline in the writer's process; the writer must apply its own change locally. Payloads: `{:epic_created | :epic_updated | :epic_deleted, %Epic{}}`, `{:task_created | :task_updated | :task_deleted, %Task{}}`, `{:estimate_updated, %TaskEstimate{}}`, `{:role_created | :role_updated | :role_deleted, %EstimationRole{}}`, `{:estimation_updated, %Estimation{}}`, `{:epics_reordered, [id]}`, `{:roles_reordered, [id]}`, `{:tasks_reordered, epic_id, [id]}`.

Audit of the estimator's mutating handlers (all in `lib/estimate_web/live/estimator_live/`): `Epics.save_epic/delete_epic/reorder_epics`, `Tasks.save_task/delete_task/reorder_tasks`, `Settings.save_settings/add_estimation_role/delete_estimation_role` all call `reload_estimation/1`; `Estimates.save_estimate/save_rate` patch in memory. **`Settings.reorder_roles/2` does neither** — it relied on receiving its own broadcast. It must reload.

- [ ] **Step 1: Write the failing tests**

`test/estimate_web/live/estimator_live/broadcast_from_test.exs`:

```elixir
defmodule EstimateWeb.EstimatorLive.BroadcastFromTest do
  use EstimateWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import EstimateWeb.EstimatorLiveHelpers

  alias Estimate.EstimationEngine

  setup :setup_estimator

  # Records every SELECT against "estimations" issued by a given LV process.
  defp watch_reloads(lv) do
    test_pid = self()
    handler = "reload-watch-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler,
      [:estimate, :repo, :query],
      fn _e, _m, %{source: source} = meta, _ ->
        if source == "estimations" and self() == lv.pid,
          do: send(test_pid, {:estimation_query, meta.query})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)
    :ok
  end

  defp reload_count(acc \\ 0) do
    receive do
      {:estimation_query, _} -> reload_count(acc + 1)
    after
      0 -> acc
    end
  end

  test "the originating LV does not reload on its own cell edit; a peer LV receives the event", ctx do
    {_user, {:ok, peer, _}} = mount_as("editor", ctx)
    watch_reloads(ctx.lv)
    render(ctx.lv)
    reload_count()

    render_click(ctx.lv, "save_estimate", %{
      "task-id" => ctx.task1.id,
      "role-id" => ctx.role.id,
      "value" => "7"
    })

    # flush the originator's mailbox: a self-delivered broadcast would be handled here
    render(ctx.lv)
    assert reload_count() == 0

    render(peer)
    hours =
      peer
      |> assigns()
      |> Map.fetch!(:estimation)
      |> Map.fetch!(:epics)
      |> hd()
      |> Map.fetch!(:tasks)
      |> Enum.find(&(&1.id == ctx.task1.id))
      |> Map.fetch!(:estimates)
      |> Enum.find(&(&1.estimation_role_id == ctx.role.id))
      |> Map.fetch!(:hours)

    assert Decimal.equal?(hours, Decimal.new(7))
  end

  test "a write from another process still reaches every LV", ctx do
    {_user, {:ok, peer, _}} = mount_as("editor", ctx)

    task =
      Task.async(fn ->
        Estimate.Repo.put_org_id(ctx.org.id)
        EstimationEngine.create_epic(%{"name" => "FromMCP", "estimation_id" => ctx.est.id})
      end)

    {:ok, _} = Task.await(task)
    assert render(ctx.lv) =~ "FromMCP"
    assert render(peer) =~ "FromMCP"
  end

  test "reorder_roles applies locally without waiting for a broadcast", ctx do
    [r1, r2 | rest] = ctx.est.roles
    ids = Enum.map([r2, r1 | rest], & &1.id)

    render_click(ctx.lv, "reorder_roles", %{"ids" => ids})
    assert Enum.map(assigns(ctx.lv).estimation.roles, & &1.id) == ids
  end
end
```

Also update `settings_test.exs` `"reorder_roles persists the order (no in-memory reload; the broadcast does it)"`: rename to `"reorder_roles persists the order and reloads"`, delete the `render(ctx.lv)` line and its comment, keep the two assertions.

Note on the async sandbox: the `Task.async` test runs in `async: false` with the shared sandbox (`setup_sandbox` uses `shared: not tags[:async]`), so the spawned process can use the connection.

- [ ] **Step 2: Run to verify they fail**

Run: `mix test test/estimate_web/live/estimator_live/broadcast_from_test.exs test/estimate_web/live/estimator_live/settings_test.exs`
Expected: first test fails (`reload_count() == 1`), third and the renamed settings test fail (`reorder_roles` does not reload). Second passes already.

- [ ] **Step 3: Implement**

`lib/estimate/estimation_engine.ex`:

```elixir
  ## PubSub
  #
  # Contract: context functions run inline in the writer's process, and
  # `broadcast/2` excludes that process (`broadcast_from`). The writer must
  # apply its own change locally (reload or in-memory patch); every other
  # subscriber receives the event. Payloads carry the full updated struct
  # ({:task_updated, %Task{}}, {:estimate_updated, %TaskEstimate{}}, …) or
  # the id list for reorders ({:epics_reordered, ids}, {:roles_reordered, ids},
  # {:tasks_reordered, epic_id, ids}).

  def broadcast(estimation_id, event) do
    Phoenix.PubSub.broadcast_from(@pubsub, self(), topic(estimation_id), event)
  end
```

`lib/estimate_web/live/estimator_live/settings.ex` `reorder_roles/2`:

```elixir
  def reorder_roles(socket, %{"ids" => ids}) do
    with_edit_auth(socket, fn socket ->
      EstimationEngine.reorder_roles(socket.assigns.estimation.id, ids)
      {:noreply, reload_estimation(socket)}
    end)
  end
```

`lib/estimate_web/live/estimator_live/estimates.ex` moduledoc: replace the sentence beginning "Note: today the write's own PubSub broadcast still reaches…" with "The write's own PubSub broadcast is excluded from this LiveView (`EstimationEngine.broadcast/2` uses `broadcast_from`), so the in-memory patch is the only update the originator performs."

- [ ] **Step 4: Run the estimator suite**

Run: `mix test test/estimate_web/live/estimator_live` → all green (the realtime test still sends events by hand, so it is unaffected).

- [ ] **Step 5: Precommit and commit**

```bash
git add lib/estimate/estimation_engine.ex lib/estimate_web/live/estimator_live/settings.ex lib/estimate_web/live/estimator_live/estimates.ex test/estimate_web/live/estimator_live/settings_test.exs test/estimate_web/live/estimator_live/broadcast_from_test.exs
git commit -m "perf(pubsub): EstimationEngine.broadcast excludes the originating process

broadcast_from(self()) — the writer already reloads or patches in memory,
so its own event only cost a redundant full reload. reorder_roles was the
one handler relying on the self-broadcast; it now reloads explicitly.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: `EstimatorLive.Rows` — pure row builder

**Files:**
- Create: `lib/estimate_web/live/estimator_live/rows.ex`
- Modify: `lib/estimate_web/live/estimator_live/helpers.ex` (add public `display_roles/2`)
- Modify: `lib/estimate_web/live/estimator_live/export.ex` (drop private `display_roles/2` + `Calculator` alias; import from Helpers)
- Modify: `lib/estimate_web/live/estimator_live/components/estimation_table.ex` (drop private `display_roles/2`; import from Helpers — the component's other content is rewritten in Task 6)
- Create: `test/estimate_web/live/estimator_live/rows_test.exs`

**Interfaces:**
- Consumes: `ViewState.filtered_epics/2`, `Calculator.task_total_hours/1`, `task_total_cost/2`, `epic_role_hours/2`, `epic_hours/1`, `epic_total_cost/2`, `roles_with_all_in_rates/1`.
- Produces:
  - `Helpers.display_roles(roles, show_all_in_rates :: boolean) :: [role]`
  - `%Rows.EpicHeader{id: "epic-<id>", epic: %Epic{}}`
  - `%Rows.Task{id: "task-<id>", task: %Task{}, epic_id, total_hours :: Decimal, total_cost :: Decimal}`
  - `%Rows.EpicSubtotal{id: "epic-<id>-subtotal", epic_id, role_hours :: %{role_id => Decimal}, epic_hours :: Decimal, epic_total_cost :: Decimal}`
  - `Rows.view(assigns) :: %{enabled_priorities: MapSet.t(), show_all_in_rates: boolean}`
  - `Rows.build(estimation, view) :: [row]` — display order, filtered by priorities, subtotal only for epics with more than one *visible* task.
  - `Rows.for_task(estimation, view, task_id) :: [row]` — the task row plus its epic's subtotal row when that subtotal is present in `build/2`; `[]` if the task is filtered out.
  - `Rows.for_epic_header(estimation, epic_id) :: [%Rows.EpicHeader{}] | []`

- [ ] **Step 1: Write the failing tests**

`test/estimate_web/live/estimator_live/rows_test.exs`:

```elixir
defmodule EstimateWeb.EstimatorLive.RowsTest do
  use Estimate.DataCase, async: true

  import Estimate.{AccountsFixtures, PortfolioFixtures, EstimationEngineFixtures}

  alias Estimate.EstimationEngine
  alias EstimateWeb.EstimatorLive.Rows

  @all MapSet.new(["must", "should", "could", "wont"])

  setup do
    %{user: owner, organization: org} = user_with_organization_fixture()
    project = project_fixture(nil, owner)
    est = estimation_fixture(project)
    e1 = epic_fixture(est, %{name: "E1", position: 0})
    e2 = epic_fixture(est, %{name: "E2", position: 1})
    t1 = task_fixture(e1, %{name: "T1", position: 0, priority: "must"})
    t2 = task_fixture(e1, %{name: "T2", position: 1, priority: "wont"})
    t3 = task_fixture(e2, %{name: "T3", position: 0, priority: "must"})
    est = EstimationEngine.get_estimation!(est.id, org.id)
    role = hd(est.roles)
    {:ok, _} = EstimationEngine.upsert_task_estimate(t1.id, role.id, %{hours: Decimal.new(4)}, est.id)
    est = EstimationEngine.get_estimation!(est.id, org.id)
    %{est: est, e1: e1, e2: e2, t1: t1, t2: t2, t3: t3, role: role}
  end

  defp view(priorities \\ @all, all_in \\ false),
    do: %{enabled_priorities: priorities, show_all_in_rates: all_in}

  test "build/2 emits header, tasks, and a subtotal only for epics with more than one visible task", ctx do
    ids = ctx.est |> Rows.build(view()) |> Enum.map(& &1.id)

    assert ids == [
             "epic-#{ctx.e1.id}",
             "task-#{ctx.t1.id}",
             "task-#{ctx.t2.id}",
             "epic-#{ctx.e1.id}-subtotal",
             "epic-#{ctx.e2.id}",
             "task-#{ctx.t3.id}"
           ]
  end

  test "build/2 respects the priority filter and drops emptied epics", ctx do
    ids = ctx.est |> Rows.build(view(MapSet.new(["wont"]))) |> Enum.map(& &1.id)
    assert ids == ["epic-#{ctx.e1.id}", "task-#{ctx.t2.id}"]
  end

  test "task rows carry precomputed totals; all-in rates change the cost", ctx do
    [_, %Rows.Task{} = t1_row | _] = Rows.build(ctx.est, view())
    assert t1_row.epic_id == ctx.e1.id
    assert Decimal.equal?(t1_row.total_hours, Decimal.new(4))
    assert Decimal.equal?(t1_row.total_cost, Decimal.mult(Decimal.new(4), ctx.role.hourly_rate))

    [_, %Rows.Task{} = all_in_row | _] = Rows.build(ctx.est, view(@all, true))
    expected = Decimal.mult(Decimal.new(4), Estimate.EstimationEngine.Calculator.all_in_rate(ctx.role))
    assert Decimal.equal?(all_in_row.total_cost, expected)
  end

  test "subtotal rows carry per-role hours and epic totals", ctx do
    subtotal = ctx.est |> Rows.build(view()) |> Enum.find(&match?(%Rows.EpicSubtotal{}, &1))
    assert subtotal.epic_id == ctx.e1.id
    assert Decimal.equal?(subtotal.role_hours[ctx.role.id], Decimal.new(4))
    assert Decimal.equal?(subtotal.epic_hours, Decimal.new(4))
  end

  test "for_task/3 returns the task row and its subtotal when present, nothing when filtered out", ctx do
    rows = Rows.for_task(ctx.est, view(), ctx.t1.id)
    assert Enum.map(rows, & &1.id) == ["task-#{ctx.t1.id}", "epic-#{ctx.e1.id}-subtotal"]

    assert Enum.map(Rows.for_task(ctx.est, view(), ctx.t3.id), & &1.id) == ["task-#{ctx.t3.id}"]
    assert Rows.for_task(ctx.est, view(MapSet.new(["must"])), ctx.t2.id) == []
  end

  test "for_epic_header/2 returns the header row or nothing for an unknown epic", ctx do
    assert [%Rows.EpicHeader{id: id, epic: %{name: "E2"}}] = Rows.for_epic_header(ctx.est, ctx.e2.id)
    assert id == "epic-#{ctx.e2.id}"
    assert Rows.for_epic_header(ctx.est, Ecto.UUID.generate()) == []
  end
end
```

- [ ] **Step 2: Run to verify it fails** — `mix test test/estimate_web/live/estimator_live/rows_test.exs` → module undefined.

- [ ] **Step 3: Move `display_roles/2` to Helpers**

In `lib/estimate_web/live/estimator_live/helpers.ex` add (near `parse_decimal`):

```elixir
  @doc "Roles as displayed: with all-in (overhead-inclusive) hourly rates when the toggle is on."
  def display_roles(roles, true), do: Calculator.roles_with_all_in_rates(roles)
  def display_roles(roles, false), do: roles
```

(`Calculator` is already aliased in `helpers.ex`.) Remove the private `display_roles/2` clauses and the `Calculator` alias from `export.ex` (change its Helpers import to `only: [build_json_export: 4, display_roles: 2]`) and remove the private clauses from `components/estimation_table.ex` (it already imports Helpers wholesale).

- [ ] **Step 4: Implement `Rows`**

```elixir
defmodule EstimateWeb.EstimatorLive.Rows do
  @moduledoc """
  Pure builder of the estimator grid's stream rows. Three kinds, stable DOM ids:

    * `%Rows.EpicHeader{id: "epic-<id>"}`
    * `%Rows.Task{id: "task-<id>"}` with precomputed `total_hours`/`total_cost`
    * `%Rows.EpicSubtotal{id: "epic-<id>-subtotal"}` — only when the epic has
      more than one *visible* task (mirrors the pre-streams template)

  Row totals are computed here, once per build/insert, never at render.
  """
  alias Estimate.EstimationEngine.Calculator
  alias EstimateWeb.EstimatorLive.ViewState
  import EstimateWeb.EstimatorLive.Helpers, only: [display_roles: 2]

  defmodule EpicHeader, do: defstruct([:id, :epic])
  defmodule Task, do: defstruct([:id, :task, :epic_id, :total_hours, :total_cost])
  defmodule EpicSubtotal, do: defstruct([:id, :epic_id, :role_hours, :epic_hours, :epic_total_cost])

  @type view :: %{enabled_priorities: MapSet.t(), show_all_in_rates: boolean()}
  @type row :: %EpicHeader{} | %Task{} | %EpicSubtotal{}

  @doc "The view-state slice rows depend on, taken from socket assigns."
  @spec view(map()) :: view()
  def view(assigns),
    do: %{enabled_priorities: assigns.enabled_priorities, show_all_in_rates: assigns.show_all_in_rates}

  @spec build(map(), view()) :: [row()]
  def build(estimation, view) do
    roles = display_roles(estimation.roles, view.show_all_in_rates)

    estimation
    |> ViewState.filtered_epics(view.enabled_priorities)
    |> Enum.flat_map(&epic_rows(&1, estimation.roles, roles))
  end

  @spec for_task(map(), view(), String.t()) :: [row()]
  def for_task(estimation, view, task_id) do
    roles = display_roles(estimation.roles, view.show_all_in_rates)

    estimation
    |> ViewState.filtered_epics(view.enabled_priorities)
    |> Enum.find_value([], fn epic ->
      case Enum.find(epic.tasks, &(&1.id == task_id)) do
        nil -> nil
        task -> [task_row(task, epic, roles) | subtotal_rows(epic, estimation.roles, roles)]
      end
    end)
  end

  @spec for_epic_header(map(), String.t()) :: [row()]
  def for_epic_header(estimation, epic_id) do
    case Enum.find(estimation.epics, &(&1.id == epic_id)) do
      nil -> []
      epic -> [header_row(epic)]
    end
  end

  defp epic_rows(epic, raw_roles, roles) do
    [header_row(epic)] ++
      Enum.map(epic.tasks, &task_row(&1, epic, roles)) ++
      subtotal_rows(epic, raw_roles, roles)
  end

  defp header_row(epic), do: %EpicHeader{id: "epic-#{epic.id}", epic: epic}

  defp task_row(task, epic, roles) do
    %Task{
      id: "task-#{task.id}",
      task: task,
      epic_id: epic.id,
      total_hours: Calculator.task_total_hours(task),
      total_cost: Calculator.task_total_cost(task, roles)
    }
  end

  defp subtotal_rows(%{tasks: tasks}, _raw_roles, _roles) when length(tasks) < 2, do: []

  defp subtotal_rows(epic, raw_roles, roles) do
    [
      %EpicSubtotal{
        id: "epic-#{epic.id}-subtotal",
        epic_id: epic.id,
        role_hours: Map.new(raw_roles, &{&1.id, Calculator.epic_role_hours(epic, &1.id)}),
        epic_hours: Calculator.epic_hours(epic),
        epic_total_cost: Calculator.epic_total_cost(epic, roles)
      }
    ]
  end
end
```

- [ ] **Step 5: Run the tests** — `mix test test/estimate_web/live/estimator_live/rows_test.exs test/estimate_web/live/estimator_live` → green (the estimator suite proves the `display_roles` move changed nothing).

- [ ] **Step 6: Precommit and commit**

```bash
git add lib/estimate_web/live/estimator_live/rows.ex lib/estimate_web/live/estimator_live/helpers.ex lib/estimate_web/live/estimator_live/export.ex lib/estimate_web/live/estimator_live/components/estimation_table.ex test/estimate_web/live/estimator_live/rows_test.exs
git commit -m "feat(estimator): Rows — pure stream-row builder with precomputed row totals; display_roles has one home

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: `EstimatorLive.Totals` — footer and breakdown numbers

**Files:**
- Create: `lib/estimate_web/live/estimator_live/totals.ex`
- Create: `test/estimate_web/live/estimator_live/totals_test.exs`

**Interfaces:**
- Consumes: `Calculator.{role_hours/2, calc_total_hours/1, calc_base_cost/2, grand_total_with_overhead/2, total_base_cost/2, total_pm_overhead/2, total_qa_overhead/2, total_risk_buffer/2, weighted_avg_overhead/3, role_base_cost/2, role_pm_overhead/2, role_qa_overhead/2, role_risk_buffer/2}`, `Helpers.display_roles/2`.
- Produces:

```elixir
%Totals{
  empty?: boolean,                 # no visible epics
  total_hours: Decimal,            # footer "Hours"
  base_cost: Decimal,              # footer "Cost" (display roles, i.e. all-in when toggled)
  role_hours: %{role_id => Decimal},
  breakdown: %{                    # raw roles, matches cost_breakdown.ex today
    grand_total: Decimal, base_cost: Decimal, total_hours: Decimal,
    pm: Decimal, qa: Decimal, risk: Decimal,
    avg_pm: Decimal, avg_qa: Decimal, avg_risk: Decimal,
    roles: [%{role: role, hours: Decimal, base: Decimal, pm: Decimal, qa: Decimal, risk: Decimal, total: Decimal}]  # only roles with hours > 0
  }
}
```
  - `Totals.compute(filtered_epics, roles, show_all_in_rates) :: %Totals{}`

- [ ] **Step 1: Write the failing tests** — the drift guard: every field equals the `Calculator` call the templates make today.

`test/estimate_web/live/estimator_live/totals_test.exs`:

```elixir
defmodule EstimateWeb.EstimatorLive.TotalsTest do
  use Estimate.DataCase, async: true

  import Estimate.{AccountsFixtures, PortfolioFixtures, EstimationEngineFixtures}

  alias Estimate.EstimationEngine
  alias Estimate.EstimationEngine.Calculator
  alias EstimateWeb.EstimatorLive.Totals
  import EstimateWeb.EstimatorLive.Helpers, only: [display_roles: 2]

  setup do
    %{user: owner, organization: org} = user_with_organization_fixture()
    project = project_fixture(nil, owner)
    est = estimation_fixture(project)
    e1 = epic_fixture(est, %{name: "E1", position: 0})
    t1 = task_fixture(e1, %{name: "T1", position: 0})
    t2 = task_fixture(e1, %{name: "T2", position: 1})
    est = EstimationEngine.get_estimation!(est.id, org.id)
    [r1, r2 | _] = est.roles
    {:ok, _} = EstimationEngine.update_role(r1, %{hourly_rate: Decimal.new(100), pm_overhead: Decimal.new(10), qa_overhead: Decimal.new(5), risk_buffer: Decimal.new(0)})
    {:ok, _} = EstimationEngine.update_role(r2, %{hourly_rate: Decimal.new(50), pm_overhead: Decimal.new(0), qa_overhead: Decimal.new(0), risk_buffer: Decimal.new(20)})
    {:ok, _} = EstimationEngine.upsert_task_estimate(t1.id, r1.id, %{hours: Decimal.new(4)}, est.id)
    {:ok, _} = EstimationEngine.upsert_task_estimate(t2.id, r2.id, %{hours: Decimal.new(2)}, est.id)
    est = EstimationEngine.get_estimation!(est.id, org.id)
    %{est: est, epics: est.epics, roles: est.roles, r1: r1, r2: r2}
  end

  defp eq(a, b), do: assert(Decimal.equal?(a, b), "expected #{a} == #{b}")

  test "footer numbers equal the Calculator calls the table makes", %{epics: epics, roles: roles} do
    for all_in <- [false, true] do
      t = Totals.compute(epics, roles, all_in)
      dr = display_roles(roles, all_in)
      refute t.empty?
      eq(t.total_hours, Calculator.calc_total_hours(epics))
      eq(t.base_cost, Calculator.calc_base_cost(epics, dr))
      for role <- roles, do: eq(t.role_hours[role.id], Calculator.role_hours(epics, role.id))
    end
  end

  test "breakdown numbers equal the Calculator calls cost_breakdown makes", %{epics: epics, roles: roles, r1: r1, r2: r2} do
    b = Totals.compute(epics, roles, false).breakdown
    eq(b.grand_total, Calculator.grand_total_with_overhead(epics, roles))
    eq(b.base_cost, Calculator.total_base_cost(epics, roles))
    eq(b.total_hours, Calculator.calc_total_hours(epics))
    eq(b.pm, Calculator.total_pm_overhead(epics, roles))
    eq(b.qa, Calculator.total_qa_overhead(epics, roles))
    eq(b.risk, Calculator.total_risk_buffer(epics, roles))
    eq(b.avg_pm, Calculator.weighted_avg_overhead(epics, roles, &Calculator.role_pm_overhead/2))
    eq(b.avg_qa, Calculator.weighted_avg_overhead(epics, roles, &Calculator.role_qa_overhead/2))
    eq(b.avg_risk, Calculator.weighted_avg_overhead(epics, roles, &Calculator.role_risk_buffer/2))

    assert Enum.map(b.roles, & &1.role.id) == [r1.id, r2.id]

    for row <- b.roles do
      role = row.role
      eq(row.hours, Calculator.role_hours(epics, role.id))
      eq(row.base, Calculator.role_base_cost(epics, role))
      eq(row.pm, Calculator.role_pm_overhead(epics, role))
      eq(row.qa, Calculator.role_qa_overhead(epics, role))
      eq(row.risk, Calculator.role_risk_buffer(epics, role))
      eq(row.total, row.base |> Decimal.add(row.pm) |> Decimal.add(row.qa) |> Decimal.add(row.risk))
    end
  end

  test "roles with zero hours are excluded from the breakdown rows; empty epics give empty? totals", %{epics: epics, roles: roles} do
    b = Totals.compute(epics, roles, false).breakdown
    assert length(b.roles) == 2

    t = Totals.compute([], roles, false)
    assert t.empty?
    eq(t.total_hours, Decimal.new(0))
    assert t.breakdown.roles == []
  end
end
```

- [ ] **Step 2: Run to verify it fails** — module undefined.

- [ ] **Step 3: Implement**

```elixir
defmodule EstimateWeb.EstimatorLive.Totals do
  @moduledoc """
  Every number the estimator footer and cost-breakdown panel show, computed
  once per change (never at render). `base_cost`/`role_hours`/`total_hours`
  feed the table footer and use display roles (all-in when toggled); the
  `breakdown` map feeds `cost_breakdown/1` and uses raw roles, exactly as the
  pre-streams templates did.
  """
  alias Estimate.EstimationEngine.Calculator
  import EstimateWeb.EstimatorLive.Helpers, only: [display_roles: 2]

  defstruct empty?: true,
            total_hours: Decimal.new(0),
            base_cost: Decimal.new(0),
            role_hours: %{},
            breakdown: %{}

  @spec compute([map()], [map()], boolean()) :: %__MODULE__{}
  def compute(epics, roles, show_all_in_rates) do
    dr = display_roles(roles, show_all_in_rates)

    %__MODULE__{
      empty?: epics == [],
      total_hours: Calculator.calc_total_hours(epics),
      base_cost: Calculator.calc_base_cost(epics, dr),
      role_hours: Map.new(roles, &{&1.id, Calculator.role_hours(epics, &1.id)}),
      breakdown: breakdown(epics, roles)
    }
  end

  defp breakdown(epics, roles) do
    %{
      grand_total: Calculator.grand_total_with_overhead(epics, roles),
      base_cost: Calculator.total_base_cost(epics, roles),
      total_hours: Calculator.calc_total_hours(epics),
      pm: Calculator.total_pm_overhead(epics, roles),
      qa: Calculator.total_qa_overhead(epics, roles),
      risk: Calculator.total_risk_buffer(epics, roles),
      avg_pm: Calculator.weighted_avg_overhead(epics, roles, &Calculator.role_pm_overhead/2),
      avg_qa: Calculator.weighted_avg_overhead(epics, roles, &Calculator.role_qa_overhead/2),
      avg_risk: Calculator.weighted_avg_overhead(epics, roles, &Calculator.role_risk_buffer/2),
      roles:
        for role <- roles,
            hours = Calculator.role_hours(epics, role.id),
            Decimal.compare(hours, 0) == :gt do
          base = Calculator.role_base_cost(epics, role)
          pm = Calculator.role_pm_overhead(epics, role)
          qa = Calculator.role_qa_overhead(epics, role)
          risk = Calculator.role_risk_buffer(epics, role)

          %{
            role: role,
            hours: hours,
            base: base,
            pm: pm,
            qa: qa,
            risk: risk,
            total: base |> Decimal.add(pm) |> Decimal.add(qa) |> Decimal.add(risk)
          }
        end
    }
  end
end
```

- [ ] **Step 4: Run the tests** — `mix test test/estimate_web/live/estimator_live/totals_test.exs` → green.

- [ ] **Step 5: Precommit and commit**

```bash
git add lib/estimate_web/live/estimator_live/totals.ex test/estimate_web/live/estimator_live/totals_test.exs
git commit -m "feat(estimator): Totals — footer and breakdown numbers computed once per change

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: Streams rendering (reset-only) — `Grid`, components, `Index`, handlers

This task switches the grid to the `:rows` stream with **every** change resetting the stream. Targeted updates come in Task 7. The full 3B characterization suite must stay green (DOM assertions are stream-agnostic); only the realtime test is re-pointed at the DOM.

**Files:**
- Create: `lib/estimate_web/live/estimator_live/grid.ex`
- Modify: `lib/estimate_web/live/estimator_live/authz.ex` (`reload_estimation/1` also resets the grid)
- Modify: `lib/estimate_web/live/estimator_live/index.ex` (`mount`: `Grid.init/1`; `render`: no render-time `epics`; pass `@streams.rows`, `@totals`, `@grid_empty?`)
- Modify: `lib/estimate_web/live/estimator_live/components/estimation_table.ex` (stream rendering + footer from totals)
- Modify: `lib/estimate_web/live/estimator_live/components/cost_breakdown.ex` (from `@totals.breakdown`)
- Modify: `lib/estimate_web/live/estimator_live/view_state.ex` (`toggle_all_in_rates`, `toggle_descriptions`, `toggle_priority`, `restore_priorities` → `Grid.reset/1`)
- Modify: `lib/estimate_web/live/estimator_live/estimates.ex` (`save_estimate`, `save_rate`, `edit_estimate`, `cancel_edit` → `Grid.reset/1` for now)
- Modify: `test/estimate_web/live/estimator_live/realtime_test.exs` (re-point at DOM)
- Create: `test/estimate_web/live/estimator_live/grid_test.exs`

**Interfaces:**
- Consumes: `Rows.{view/1, build/2}`, `Totals.compute/3`, `ViewState.filtered_epics/2`, `Phoenix.LiveView.{stream_configure/3, stream/4}`.
- Produces:
  - `Grid.init(socket) :: socket` — `stream_configure(:rows, dom_id: & &1.id)` then `reset/1`. Called once in `mount/3` after `:estimation`, `:enabled_priorities`, `:show_all_in_rates` are assigned.
  - `Grid.reset(socket) :: socket` — `stream(:rows, Rows.build(...), reset: true)`, assigns `:totals` (`%Totals{}`) and `:grid_empty?` (boolean).
  - New assigns: `:totals`, `:grid_empty?`; stream `:rows`.
  - Component attrs: `estimation_table` takes `rows` (the stream), `totals`, `grid_empty?`, `estimation`, `editing`, `editing_rate`, `can_edit`, `show_all_in_rates`, `show_descriptions`; `cost_breakdown` takes `totals`, `currency`, `show_breakdown`.

- [ ] **Step 1: Write the failing Grid + realtime tests**

`test/estimate_web/live/estimator_live/grid_test.exs`:

```elixir
defmodule EstimateWeb.EstimatorLive.GridTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import EstimateWeb.EstimatorLiveHelpers
  import Ecto.Query, only: [from: 2]

  alias Estimate.Repo
  alias Estimate.EstimationEngine.Task

  setup :setup_estimator

  test "mount renders the grid as a stream container with stable row ids", ctx do
    html = render(ctx.lv)
    assert html =~ ~s(id="epics-container")
    assert html =~ ~s(phx-update="stream")
    assert html =~ ~s(id="epic-#{ctx.epic.id}")
    assert html =~ ~s(id="task-#{ctx.task1.id}")
    assert html =~ ~s(id="task-#{ctx.task2.id}")
    assert html =~ ~s(id="epic-#{ctx.epic.id}-subtotal")
    assert %EstimateWeb.EstimatorLive.Totals{empty?: false} = assigns(ctx.lv).totals
    refute assigns(ctx.lv).grid_empty?
  end

  test "a DB change reaches the DOM only after a reset event (stream is not re-rendered by itself)", ctx do
    Repo.update_all(from(t in Task, where: t.id == ^ctx.task1.id), set: [name: "DB-RENAMED"])
    refute render(ctx.lv) =~ "DB-RENAMED"

    send(ctx.lv.pid, {:task_created, nil})
    assert render(ctx.lv) =~ "DB-RENAMED"
  end

  test "the footer and breakdown read from @totals", ctx do
    render_click(ctx.lv, "edit_estimate", %{"key" => "#{ctx.task1.id}-#{ctx.role.id}"})
    render_click(ctx.lv, "save_estimate", %{"task-id" => ctx.task1.id, "role-id" => ctx.role.id, "value" => "3"})

    totals = assigns(ctx.lv).totals
    assert Decimal.equal?(totals.total_hours, Decimal.new(3))
    assert Decimal.equal?(totals.role_hours[ctx.role.id], Decimal.new(3))
    assert render(ctx.lv) =~ EstimateWeb.EstimatorLive.Helpers.format_hours(Decimal.new(3))
  end

  test "deleting the last epic shows the empty state", ctx do
    render_click(ctx.lv, "confirm_delete_epic", %{"id" => ctx.epic.id})
    render_click(ctx.lv, "delete_epic", %{})
    assert assigns(ctx.lv).grid_empty?
    assert render(ctx.lv) =~ "No epics yet"
  end
end
```

Rewrite `realtime_test.exs`'s second test so the divergence is visible in the DOM (the stream is only re-rendered on a stream operation, so a DB-only change is the right divergence):

```elixir
  test "every broadcast event re-streams the grid from the database", ctx do
    events = [
      {:estimation_updated, nil},
      {:epic_created, nil},
      {:epic_updated, nil},
      {:epic_deleted, nil},
      {:epics_reordered, nil},
      {:task_created, nil},
      {:task_updated, nil},
      {:task_deleted, nil},
      {:estimate_updated, nil},
      {:role_created, nil},
      {:role_updated, nil},
      {:role_deleted, nil},
      {:roles_reordered, nil},
      {:tasks_reordered, ctx.epic.id, []}
    ]

    for {event, i} <- Enum.with_index(events, 1) do
      name = "DB-#{i}"
      # diverge in the DB only (no broadcast): the rendered grid must not know yet
      Repo.update_all(from(t in Task, where: t.id == ^ctx.task1.id), set: [name: name])
      refute render(ctx.lv) =~ name, inspect(event)

      send(ctx.lv.pid, event)
      assert render(ctx.lv) =~ name, inspect(event)
    end
  end
```

(add `alias Estimate.Repo` and `alias Estimate.EstimationEngine.Task` and `import Ecto.Query, only: [from: 2]` to the realtime test module; the first realtime test stays as is.) Task 7 replaces the payload-carrying events in this list with targeted assertions — for now `nil` payloads route to reset.

- [ ] **Step 2: Run to verify they fail** — `mix test test/estimate_web/live/estimator_live/grid_test.exs test/estimate_web/live/estimator_live/realtime_test.exs` → no stream container, no `:totals` assign.

- [ ] **Step 3: Implement `Grid`**

```elixir
defmodule EstimateWeb.EstimatorLive.Grid do
  @moduledoc """
  Owner of the estimator's `:rows` stream and its derived assigns
  (`:totals`, `:grid_empty?`). Every stream mutation goes through here so
  the update matrix (spec 3C) has one implementation.

  Reads: `:estimation`, `:enabled_priorities`, `:show_all_in_rates`.
  Writes: stream `:rows`, `:totals`, `:grid_empty?`.
  """
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [stream: 4, stream_configure: 3]

  alias EstimateWeb.EstimatorLive.{Rows, Totals, ViewState}

  @doc "Configure the stream (once, in mount) and render the initial rows."
  def init(socket) do
    socket
    |> stream_configure(:rows, dom_id: & &1.id)
    |> reset()
  end

  @doc "Rebuild every row and every total from `@estimation` and the view state."
  def reset(socket) do
    estimation = socket.assigns.estimation
    view = Rows.view(socket.assigns)
    rows = Rows.build(estimation, view)

    socket
    |> stream(:rows, rows, reset: true)
    |> assign_totals(estimation, view)
    |> assign(:grid_empty?, rows == [])
  end

  @doc false
  def assign_totals(socket, estimation, view) do
    epics = ViewState.filtered_epics(estimation, view.enabled_priorities)
    assign(socket, :totals, Totals.compute(epics, estimation.roles, view.show_all_in_rates))
  end
end
```

- [ ] **Step 4: `Authz.reload_estimation/1` resets the grid**

```elixir
  @doc "Re-read the estimation and rebuild the grid stream + totals. The single reload choke point."
  def reload_estimation(socket) do
    estimation =
      EstimationEngine.get_estimation!(socket.assigns.estimation.id, socket.assigns.org_id)

    socket
    |> assign(:estimation, estimation)
    |> EstimateWeb.EstimatorLive.Grid.reset()
  end
```

(Fully-qualified call avoids an alias; `Grid` does not depend on `Authz`, so no cycle.)

- [ ] **Step 5: `Index` mount + render**

In `mount/3`, after the existing assign pipeline ends with `|> assign(:ai_loading, nil)}`, change it so `Grid.init/1` runs last:

```elixir
       |> assign(:ai_loading, nil)
       |> Grid.init()}
```

Add `Grid` to the alias list. In `render/1`: delete the line `<% epics = ViewState.filtered_epics(@estimation, @enabled_priorities) %>` and replace the two component calls:

```heex
      <.estimation_table
        estimation={@estimation}
        rows={@streams.rows}
        totals={@totals}
        grid_empty?={@grid_empty?}
        editing={@editing}
        editing_rate={@editing_rate}
        can_edit={@can_edit}
        show_all_in_rates={@show_all_in_rates}
        show_descriptions={@show_descriptions}
      />

      <%!-- Cost Breakdown Panel (hidden when all-in rates enabled) --%>
      <.cost_breakdown
        :if={not @grid_empty? and not @show_all_in_rates}
        totals={@totals}
        currency={@estimation.currency}
        show_breakdown={@show_breakdown}
      />
```

- [ ] **Step 6: Rewrite `estimation_table.ex`**

Replace the module body. Head (`<thead>`), footer (`<tfoot>`) and empty state keep their markup; the `<tbody>` becomes a stream container rendering one `grid_row` per item; the footer reads `@totals`.

```elixir
defmodule EstimateWeb.EstimatorLive.Components.EstimationTable do
  use EstimateWeb, :html

  import EstimateWeb.EstimatorLive.Helpers
  import EstimateWeb.EstimatorLive.Components.EstimateCell

  alias EstimateWeb.EstimatorLive.Rows

  attr :estimation, :map, required: true
  attr :rows, :any, required: true, doc: "the :rows stream"
  attr :totals, :map, required: true
  attr :grid_empty?, :boolean, required: true
  attr :editing, :string, default: nil
  attr :editing_rate, :string, default: nil
  attr :can_edit, :boolean, required: true
  attr :show_all_in_rates, :boolean, required: true
  attr :show_descriptions, :boolean, required: true

  def estimation_table(assigns) do
    ~H"""
    <div class="bg-base-100 border border-base-300 rounded-xl">
      <div class="overflow-auto max-h-[calc(100vh-12rem)] rounded-xl">
        <table class="w-full">
          <thead class="sticky top-0 z-20">
            <tr class="bg-base-200 border-b border-base-content/10">
              <th class="px-6 py-2.5 text-left text-xs font-medium text-base-content/60 uppercase tracking-wider w-72 min-w-72 sticky left-0 z-30 bg-base-200">
                Task
              </th>
              <th
                :for={role <- @estimation.roles}
                class="px-3 py-2.5 text-center text-xs font-medium text-base-content/60 uppercase tracking-wider w-24 min-w-24"
              >
                <div class="relative group/role">
                  <div>{role.abbreviation}</div>
                  <span class="pointer-events-none absolute left-1/2 -translate-x-1/2 top-full mt-1 px-2 py-1 bg-neutral text-neutral-content text-[10px] font-normal normal-case rounded shadow-lg opacity-0 group-hover/role:opacity-100 transition-opacity whitespace-nowrap z-50">
                    {role.name}
                  </span>
                </div>
                <.rate_cell
                  role={role}
                  currency={@estimation.currency}
                  editing_rate={@editing_rate}
                  show_all_in_rates={@show_all_in_rates}
                  can_edit={@can_edit}
                />
              </th>
              <th class="px-4 py-2.5 text-center text-xs font-medium text-base-content/60 uppercase tracking-wider w-24">
                Hours
              </th>
              <th class="px-4 py-2.5 text-center text-xs font-medium text-base-content/60 uppercase tracking-wider w-28">
                Cost
              </th>
            </tr>
          </thead>
          <tbody
            id="epics-container"
            phx-update="stream"
            phx-hook={if @can_edit, do: "Sortable"}
            data-group="epics"
          >
            <.grid_row
              :for={{dom_id, row} <- @rows}
              id={dom_id}
              row={row}
              roles={@estimation.roles}
              currency={@estimation.currency}
              editing={@editing}
              can_edit={@can_edit}
              show_descriptions={@show_descriptions}
            />
          </tbody>
          <tfoot class="sticky bottom-0 z-20">
            <tr class="bg-neutral text-neutral-content">
              <td class="px-6 py-3 text-right font-semibold sticky left-0 z-10 bg-neutral">
                Total
              </td>
              <td :for={role <- @estimation.roles} class="px-3 py-3 text-center text-sm font-mono">
                {format_hours(Map.get(@totals.role_hours, role.id, Decimal.new(0)))}
              </td>
              <td class="px-4 py-3 text-center font-mono font-bold">
                {format_hours(@totals.total_hours)}
              </td>
              <td class="px-4 py-3 text-center font-mono font-bold">
                {format_cost(@totals.base_cost, @estimation.currency)}
              </td>
            </tr>
          </tfoot>
        </table>
      </div>

      <%!-- Empty State --%>
      <div :if={@grid_empty?} class="px-6 py-16 text-center border-t border-base-300">
        <.icon name="hero-rectangle-stack" class="w-12 h-12 text-base-content/30 mx-auto" />
        <p class="mt-3 text-base-content/60">No epics yet</p>
        <p class="text-sm text-base-content/40 mt-1">Add your first epic to start estimating</p>
        <button
          :if={@can_edit}
          phx-click="add_epic"
          class="mt-4 px-4 py-2 bg-neutral text-neutral-content text-sm rounded-lg hover:bg-neutral/90 transition-colors font-medium"
        >
          Add Epic
        </button>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :row, :any, required: true
  attr :roles, :list, required: true
  attr :currency, :map, required: true
  attr :editing, :string, default: nil
  attr :can_edit, :boolean, required: true
  attr :show_descriptions, :boolean, required: true

  # One <tr> per stream item. The three clauses dispatch on the row struct.
  def grid_row(%{row: %Rows.EpicHeader{}} = assigns) do
    ~H"""
    <tr id={@id} class="bg-base-200 border-t border-base-content/10" data-id={@row.epic.id}>
      <td class="px-6 py-3 sticky left-0 z-10 bg-base-200 w-72 min-w-72">
        <div class="flex items-center gap-3">
          <span
            :if={@can_edit}
            class="cursor-move text-base-content/40 hover:text-base-content/70 drag-handle"
          >
            <.icon name="hero-bars-3" class="w-4 h-4" />
          </span>
          <%= if @can_edit do %>
            <span
              class="font-semibold text-base-content cursor-pointer hover:text-base-content/70"
              phx-click="edit_epic"
              phx-value-id={@row.epic.id}
            >
              {@row.epic.name}
            </span>
          <% else %>
            <span class="font-semibold text-base-content">{@row.epic.name}</span>
          <% end %>
        </div>
      </td>
      <td colspan={length(@roles) + 2} class="px-6 py-3 bg-base-200 text-right">
        <div :if={@can_edit} class="flex items-center justify-end gap-3">
          <button
            phx-click="add_task"
            phx-value-epic-id={@row.epic.id}
            class="text-sm text-base-content/60 hover:text-base-content transition-colors"
          >
            + Add Task
          </button>
          <button
            phx-click="confirm_delete_epic"
            phx-value-id={@row.epic.id}
            class="text-sm text-base-content/40 hover:text-error transition-colors"
          >
            <.icon name="hero-trash" class="w-4 h-4" />
          </button>
        </div>
      </td>
    </tr>
    """
  end

  def grid_row(%{row: %Rows.Task{}} = assigns) do
    ~H"""
    <tr id={@id} class="group" data-id={@row.task.id} data-epic-id={@row.epic_id}>
      <td class="px-6 py-1.5 sticky left-0 z-10 bg-base-100">
        <div class="flex items-start gap-3">
          <span
            :if={@can_edit}
            class="cursor-move text-base-content/30 hover:text-base-content/60 drag-handle opacity-0 group-hover:opacity-100 transition-opacity mt-1"
          >
            <.icon name="hero-bars-3" class="w-3 h-3" />
          </span>
          <span class="relative group/priority flex items-center mt-0.5">
            <span class={"w-5 h-5 flex items-center justify-center text-[10px] rounded font-medium cursor-help #{priority_class(@row.task.priority)}"}>
              {String.first(priority_label(@row.task.priority))}
            </span>
            <span class="pointer-events-none absolute left-0 bottom-full mb-2 w-48 px-3 py-2 bg-neutral text-neutral-content text-xs rounded-lg shadow-lg opacity-0 group-hover/priority:opacity-100 transition-opacity z-50">
              <span class="font-semibold">{priority_label(@row.task.priority)}</span>
              <span class="block mt-1 text-neutral-content/60 leading-relaxed">
                {priority_description(@row.task.priority)}
              </span>
              <span class="absolute top-full left-3 border-4 border-transparent border-t-neutral">
              </span>
            </span>
          </span>
          <div class="min-w-0 flex-1">
            <div class="flex items-center gap-2">
              <%= if @can_edit do %>
                <span
                  class="text-sm text-base-content/80 cursor-pointer hover:text-base-content"
                  phx-click="edit_task"
                  phx-value-id={@row.task.id}
                >
                  {@row.task.name}
                </span>
                <button
                  phx-click="confirm_delete_task"
                  phx-value-id={@row.task.id}
                  class="flex items-center text-base-content/30 hover:text-error opacity-0 group-hover:opacity-100 transition-opacity"
                >
                  <.icon name="hero-trash" class="w-4 h-4" />
                </button>
              <% else %>
                <span class="text-sm text-base-content/80">{@row.task.name}</span>
              <% end %>
            </div>
            <p
              :if={@show_descriptions && @row.task.description && @row.task.description != ""}
              class="text-xs text-base-content/40 leading-snug mt-0.5"
            >
              {@row.task.description}
            </p>
          </div>
        </div>
      </td>
      <td :for={role <- @roles} class="px-2 py-1.5 text-center">
        <.estimate_cell
          task_id={@row.task.id}
          role_id={role.id}
          estimates={@row.task.estimates}
          editing={@editing}
          can_edit={@can_edit}
        />
      </td>
      <td class="px-4 py-1.5 text-center text-sm font-mono text-base-content/70">
        {format_hours(@row.total_hours)}
      </td>
      <td class="px-4 py-1.5 text-center text-sm font-mono text-base-content/70">
        {format_cost(@row.total_cost, @currency)}
      </td>
    </tr>
    """
  end

  def grid_row(%{row: %Rows.EpicSubtotal{}} = assigns) do
    ~H"""
    <tr id={@id} class="border-t border-base-content/10">
      <td class="px-6 py-1.5 text-right text-xs text-base-content/40 sticky left-0 z-10 bg-base-100">
        Subtotal
      </td>
      <td
        :for={role <- @roles}
        class="px-3 py-1.5 text-center text-xs font-mono text-base-content/40"
      >
        {format_hours(Map.get(@row.role_hours, role.id, Decimal.new(0)))}
      </td>
      <td class="px-4 py-1.5 text-center text-sm font-mono text-base-content/60">
        {format_hours(@row.epic_hours)}
      </td>
      <td class="px-4 py-1.5 text-center text-sm font-mono text-base-content/60">
        {format_cost(@row.epic_total_cost, @currency)}
      </td>
    </tr>
    """
  end
end
```

DOM contract preserved for the JS `Sortable` hook: epic header rows keep `data-id` and no `data-epic-id`; task rows keep `data-id` + `data-epic-id`; subtotal rows have neither.

- [ ] **Step 7: Rewrite `cost_breakdown.ex` to read `@totals.breakdown`**

Change the attrs to `attr :totals, :map, required: true`, `attr :currency, :map, required: true`, `attr :show_breakdown, :boolean, required: true`; remove the `Calculator` alias; then substitute each call using this table (`b` = `@totals.breakdown`):

| old expression | new expression |
|---|---|
| `Calculator.grand_total_with_overhead(@epics, @roles)` | `@totals.breakdown.grand_total` |
| `Calculator.total_base_cost(@epics, @roles)` | `@totals.breakdown.base_cost` |
| `Calculator.calc_total_hours(@epics)` | `@totals.breakdown.total_hours` |
| `Calculator.total_pm_overhead(@epics, @roles)` | `@totals.breakdown.pm` |
| `Calculator.weighted_avg_overhead(@epics, @roles, &Calculator.role_pm_overhead/2)` | `@totals.breakdown.avg_pm` |
| `Calculator.total_qa_overhead(@epics, @roles)` / `…role_qa_overhead/2)` | `@totals.breakdown.qa` / `@totals.breakdown.avg_qa` |
| `Calculator.total_risk_buffer(@epics, @roles)` / `…role_risk_buffer/2)` | `@totals.breakdown.risk` / `@totals.breakdown.avg_risk` |
| `<%= for role <- @roles, Decimal.compare(Calculator.role_hours(@epics, role.id), 0) == :gt do %>` … `<% end %>` | `<tr :for={r <- @totals.breakdown.roles} class="hover:bg-base-200">` with `role = r.role` replaced inline: `r.role.name`, `r.role.pm_overhead`, `r.role.qa_overhead`, `r.role.risk_buffer` |
| inside the role row: `Calculator.role_hours(@epics, role.id)` / `role_base_cost` / `role_pm_overhead` / `role_qa_overhead` / `role_risk_buffer` / the 4-term `Decimal.add` chain | `r.hours` / `r.base` / `r.pm` / `r.qa` / `r.risk` / `r.total` |

Everything else in the template (classes, labels, structure) is unchanged.

- [ ] **Step 8: Handlers reset the grid**

Rule for this task: **every branch that changes an assign a row reads (`:editing`, `:show_descriptions`, `:show_all_in_rates`, `:enabled_priorities`) pipes the socket through `Grid.reset/1`.** Add `alias EstimateWeb.EstimatorLive.Grid` to both modules and update their `Writes:` moduledoc lines with "stream `:rows`, `:totals`, `:grid_empty?` (via Grid)".

`view_state.ex`:

```elixir
  def toggle_all_in_rates(socket, _params),
    do: {:noreply, socket |> assign(:show_all_in_rates, !socket.assigns.show_all_in_rates) |> Grid.reset()}

  def toggle_descriptions(socket, _params),
    do: {:noreply, socket |> assign(:show_descriptions, !socket.assigns.show_descriptions) |> Grid.reset()}

  def toggle_priority(socket, %{"priority" => priority}) do
    current = socket.assigns.enabled_priorities

    updated =
      if MapSet.member?(current, priority) and MapSet.size(current) > 1,
        do: MapSet.delete(current, priority),
        else: MapSet.put(current, priority)

    {:noreply,
     socket
     |> assign(:enabled_priorities, updated)
     |> Grid.reset()
     |> push_event("save_priorities", %{priorities: MapSet.to_list(updated)})}
  end

  def restore_priorities(socket, %{"priorities" => priorities}) do
    valid = MapSet.intersection(MapSet.new(priorities), @all_priorities)

    if MapSet.size(valid) > 0,
      do: {:noreply, socket |> assign(:enabled_priorities, valid) |> Grid.reset()},
      else: {:noreply, socket}
  end
```

(`toggle_breakdown` and `close_modal` are unchanged — no row reads them.)

`estimates.ex` — every `assign(:editing, …)` / `assign(:editing_rate, …)` site gets `|> Grid.reset()` appended in this task (Task 7 narrows the `:editing` ones):

```elixir
  def cancel_edit(socket, _params),
    do: {:noreply, socket |> assign(:editing, nil) |> assign(:editing_rate, nil) |> Grid.reset()}

  def edit_estimate(socket, %{"key" => key}),
    do: {:noreply, socket |> assign(:editing, key) |> Grid.reset()}
```

In `save_rate`: the `{:ok, updated_role}` branch becomes `socket |> assign(:estimation, update_role_in_memory(estimation, updated_role)) |> assign(:editing_rate, nil) |> Grid.reset()`; the `{:error, _}` and the `else` branch stay as they are (`editing_rate` is read by the header, not by a row). In `save_estimate`: the `{:ok, updated_estimate}` branch becomes `socket |> assign(:estimation, update_estimate_in_memory(estimation, updated_estimate)) |> assign(:editing, nil) |> Grid.reset()`; the `{:error, _}` branch and the outer `else` branch become `{:noreply, socket |> assign(:editing, nil) |> Grid.reset()}`.

- [ ] **Step 9: Run everything**

Run: `mix test test/estimate_web/live/estimator_live` → all green (81 + new). Then `mix precommit`.
Manual check (implementer, in the browser if `mix phx.server` is available; otherwise note as not done): drag an epic and a task — `Sortable` still posts `reorder_epics`/`reorder_tasks`.

- [ ] **Step 10: Commit**

```bash
git add lib/estimate_web/live/estimator_live test/estimate_web/live/estimator_live
git commit -m "perf(estimator): grid rendered as a LiveView stream with precomputed rows and totals

One :rows stream (epic-<id>, task-<id>, epic-<id>-subtotal) built by Rows,
footer/breakdown from Totals; Grid owns every stream mutation and
reload_estimation/1 resets it. Every change is a reset in this commit;
targeted inserts follow.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: Targeted updates — `Sync` + in-memory patches (the update matrix)

**Files:**
- Create: `lib/estimate_web/live/estimator_live/sync.ex`
- Modify: `lib/estimate_web/live/estimator_live/grid.ex` (`upsert_task/2`, `upsert_epic_header/2`, `refresh_editing/3`)
- Modify: `lib/estimate_web/live/estimator_live/estimates.ex` (`update_task_in_memory/2`, `update_epic_in_memory/2`; handlers use targeted ops)
- Modify: `lib/estimate_web/live/estimator_live/index.ex` (`handle_info/2` → `Sync.handle/2`)
- Modify: `test/estimate_web/live/estimator_live/realtime_test.exs` (payload events assert targeted behaviour)
- Create: `test/estimate_web/live/estimator_live/sync_test.exs`

**Interfaces:**
- Consumes: `Rows.{for_task/3, for_epic_header/2, view/1}`, `Phoenix.LiveView.stream_insert/3`.
- Produces:
  - `Grid.upsert_task(socket, task_id) :: socket` — `stream_insert` each row from `Rows.for_task/3` (task + subtotal), recompute totals. No-op on the stream if the task is filtered out (totals still recomputed).
  - `Grid.upsert_epic_header(socket, epic_id) :: socket`.
  - `Grid.refresh_editing(socket, old_key | nil, new_key | nil) :: socket` — re-inserts the task rows for the task ids in the two keys (`"<task_id>-<role_id>"`), deduplicated.
  - `Estimates.update_task_in_memory(estimation, %Task{}) :: estimation` — merges `name`, `description`, `priority`, `position` (keeps existing `estimates`).
  - `Estimates.update_epic_in_memory(estimation, %Epic{}) :: estimation` — merges `name`, `description`, `position` (keeps existing `tasks`).
  - `Sync.handle(event, socket) :: {:noreply, socket}` — the matrix:

| event | action |
|---|---|
| `{:estimate_updated, %{task_id: _} = est}` | `update_estimate_in_memory` → `Grid.upsert_task(task_id)` |
| `{:task_updated, %{id: _} = task}` | `update_task_in_memory` → `Grid.upsert_task(task.id)` |
| `{:epic_updated, %{id: _} = epic}` | `update_epic_in_memory` → `Grid.upsert_epic_header(epic.id)` |
| `{:role_updated, %{id: _} = role}` | `update_role_in_memory` → `Grid.reset` |
| anything else (creates, deletes, reorders, `estimation_updated`, or a payload that is not a struct with the expected keys) | `reload_estimation` (reload + reset) |

- [ ] **Step 1: Write the failing tests**

`test/estimate_web/live/estimator_live/sync_test.exs`:

```elixir
defmodule EstimateWeb.EstimatorLive.SyncTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import EstimateWeb.EstimatorLiveHelpers

  alias Estimate.Repo
  alias Estimate.EstimationEngine.{Epic, Task}

  setup :setup_estimator

  # a telemetry probe: any SELECT on "estimations" by the LV process = a reload
  defp watch_reloads(lv) do
    test_pid = self()
    handler = "sync-reload-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler,
      [:estimate, :repo, :query],
      fn _e, _m, %{source: source}, _ -> if source == "estimations" and self() == lv.pid, do: send(test_pid, :reload) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)
  end

  defp reloads(n \\ 0), do: (receive do :reload -> reloads(n + 1) after 0 -> n end)

  test "task_updated patches the row from the payload without a reload", ctx do
    watch_reloads(ctx.lv)
    render(ctx.lv)
    reloads()

    send(ctx.lv.pid, {:task_updated, %{ctx.task1 | name: "Patched"}})
    html = render(ctx.lv)

    assert html =~ "Patched"
    assert reloads() == 0
    # DB untouched: the payload is the source
    assert Repo.get!(Task, ctx.task1.id).name == "T-one"
    # in-memory estimates on the task survive the patch
    task = assigns(ctx.lv).estimation.epics |> hd() |> Map.fetch!(:tasks) |> Enum.find(&(&1.id == ctx.task1.id))
    assert is_list(task.estimates)
  end

  test "epic_updated patches the header row without touching its tasks", ctx do
    watch_reloads(ctx.lv)
    render(ctx.lv)
    reloads()

    send(ctx.lv.pid, {:epic_updated, %{ctx.epic | name: "Alpha Prime"}})
    html = render(ctx.lv)

    assert html =~ "Alpha Prime"
    assert html =~ "T-one" and html =~ "T-two"
    assert reloads() == 0
    assert Repo.get!(Epic, ctx.epic.id).name == "Alpha"
  end

  test "estimate_updated patches the cell, the subtotal and the footer without a reload", ctx do
    watch_reloads(ctx.lv)
    render(ctx.lv)
    reloads()

    estimate = %Estimate.EstimationEngine.TaskEstimate{
      id: Ecto.UUID.generate(),
      task_id: ctx.task1.id,
      estimation_role_id: ctx.role.id,
      hours: Decimal.new(9)
    }

    send(ctx.lv.pid, {:estimate_updated, estimate})
    html = render(ctx.lv)

    nine = EstimateWeb.EstimatorLive.Helpers.format_hours(Decimal.new(9))
    assert html =~ nine
    assert Decimal.equal?(assigns(ctx.lv).totals.role_hours[ctx.role.id], Decimal.new(9))
    assert reloads() == 0
  end

  test "creates, deletes and reorders reload", ctx do
    watch_reloads(ctx.lv)
    render(ctx.lv)
    reloads()

    for event <- [{:task_created, nil}, {:epic_deleted, nil}, {:epics_reordered, []}, {:tasks_reordered, ctx.epic.id, []}, {:estimation_updated, nil}] do
      send(ctx.lv.pid, event)
      render(ctx.lv)
      assert reloads() == 1, inspect(event)
    end
  end

  test "a malformed payload falls back to a reload", ctx do
    watch_reloads(ctx.lv)
    render(ctx.lv)
    reloads()

    send(ctx.lv.pid, {:task_updated, nil})
    render(ctx.lv)
    assert reloads() == 1
  end

  test "editing a cell re-inserts only that task row", ctx do
    watch_reloads(ctx.lv)
    key = "#{ctx.task1.id}-#{ctx.role.id}"
    render_click(ctx.lv, "edit_estimate", %{"key" => key})
    assert render(ctx.lv) =~ ~s(id="hours-#{key}")

    render_click(ctx.lv, "cancel_edit", %{})
    refute render(ctx.lv) =~ ~s(id="hours-#{key}")
    assert reloads() == 0
  end

  test "save_estimate is a targeted update; save_rate resets", ctx do
    watch_reloads(ctx.lv)
    render(ctx.lv)
    reloads()

    render_click(ctx.lv, "edit_estimate", %{"key" => "#{ctx.task1.id}-#{ctx.role.id}"})
    render_click(ctx.lv, "save_estimate", %{"task-id" => ctx.task1.id, "role-id" => ctx.role.id, "value" => "5"})
    assert render(ctx.lv) =~ EstimateWeb.EstimatorLive.Helpers.format_hours(Decimal.new(5))
    assert reloads() == 0

    render_click(ctx.lv, "edit_rate", %{"role-id" => ctx.role.id})
    render_click(ctx.lv, "save_rate", %{"role-id" => ctx.role.id, "value" => "200"})
    assert reloads() == 0
    role = Enum.find(assigns(ctx.lv).estimation.roles, &(&1.id == ctx.role.id))
    assert Decimal.equal?(role.hourly_rate, Decimal.new(200))
  end
end
```

Update `realtime_test.exs`'s second test: remove `{:task_updated, nil}`, `{:epic_updated, nil}`, `{:estimate_updated, nil}`, `{:role_updated, nil}` from the reset list (their `nil` payloads now exercise the fallback, which `sync_test` covers) and keep the remaining ten reset events.

- [ ] **Step 2: Run to verify they fail** — `mix test test/estimate_web/live/estimator_live/sync_test.exs` → `Sync` undefined / reload counts are 1.

- [ ] **Step 3: In-memory patches in `Estimates`**

```elixir
  @doc false
  def update_task_in_memory(estimation, %{id: task_id} = updated) do
    epics =
      Enum.map(estimation.epics, fn epic ->
        %{
          epic
          | tasks:
              Enum.map(epic.tasks, fn task ->
                if task.id == task_id,
                  do: %{task | name: updated.name, description: updated.description, priority: updated.priority, position: updated.position},
                  else: task
              end)
        }
      end)

    %{estimation | epics: epics}
  end

  @doc false
  def update_epic_in_memory(estimation, %{id: epic_id} = updated) do
    epics =
      Enum.map(estimation.epics, fn epic ->
        if epic.id == epic_id,
          do: %{epic | name: updated.name, description: updated.description, position: updated.position},
          else: epic
      end)

    %{estimation | epics: epics}
  end
```

- [ ] **Step 4: Targeted ops in `Grid`**

Add to `grid.ex` (and `stream_insert: 3` to the import):

```elixir
  @doc "Re-insert the task's row (+ its epic subtotal) and recompute totals."
  def upsert_task(socket, task_id) do
    estimation = socket.assigns.estimation
    view = Rows.view(socket.assigns)

    estimation
    |> Rows.for_task(view, task_id)
    |> Enum.reduce(socket, &stream_insert(&2, :rows, &1))
    |> assign_totals(estimation, view)
  end

  @doc "Re-insert one epic header row."
  def upsert_epic_header(socket, epic_id) do
    socket.assigns.estimation
    |> Rows.for_epic_header(epic_id)
    |> Enum.reduce(socket, &stream_insert(&2, :rows, &1))
  end

  @doc "Re-insert the task rows behind the previous and the new editing key (\"<task_id>-<role_id>\")."
  def refresh_editing(socket, old_key, new_key) do
    # editing keys are "<task_id>-<role_id>"; both are 36-char UUIDs (dashes inside), so slice, don't split
    [old_key, new_key]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&String.slice(&1, 0, 36))
    |> Enum.uniq()
    |> Enum.reduce(socket, fn task_id, sock -> upsert_task_rows_only(sock, task_id) end)
  end

  defp upsert_task_rows_only(socket, task_id) do
    socket.assigns.estimation
    |> Rows.for_task(Rows.view(socket.assigns), task_id)
    |> Enum.reduce(socket, &stream_insert(&2, :rows, &1))
  end
```

- [ ] **Step 5: `Estimates` handlers use targeted ops**

- `edit_estimate`: `{:noreply, socket |> assign(:editing, key) |> Grid.refresh_editing(socket.assigns.editing, key)}`
- `cancel_edit`: `{:noreply, socket |> assign(:editing, nil) |> assign(:editing_rate, nil) |> Grid.refresh_editing(socket.assigns.editing, nil)}`
- `save_estimate` success: `socket |> assign(:estimation, update_estimate_in_memory(estimation, updated_estimate)) |> assign(:editing, nil) |> Grid.upsert_task(task_id)` (the row re-render also drops the input since `editing` is nil).
- `save_estimate` error/denied branches that only clear `editing`: `|> Grid.refresh_editing(socket.assigns.editing, nil)`.
- `save_rate` success: keep `Grid.reset()` (a rate changes every cost).

- [ ] **Step 6: `Sync` + `Index.handle_info`**

```elixir
defmodule EstimateWeb.EstimatorLive.Sync do
  @moduledoc """
  Maps PubSub events from `Estimate.EstimationEngine` onto the grid (spec 3C
  update matrix). Payload-carrying updates patch `@estimation` in memory and
  re-insert only the affected rows; everything else reloads and resets.

  Reads: `:estimation`. Writes: `:estimation`, stream `:rows`, `:totals`, `:grid_empty?`.
  """
  import EstimateWeb.EstimatorLive.Authz, only: [reload_estimation: 1]
  import Phoenix.Component, only: [assign: 3]
  alias EstimateWeb.EstimatorLive.{Estimates, Grid}

  def handle({:estimate_updated, %{task_id: task_id} = estimate}, socket) when is_binary(task_id) do
    estimation = Estimates.update_estimate_in_memory(socket.assigns.estimation, estimate)
    {:noreply, socket |> assign(:estimation, estimation) |> Grid.upsert_task(task_id)}
  end

  def handle({:task_updated, %{id: id, name: _} = task}, socket) when is_binary(id) do
    estimation = Estimates.update_task_in_memory(socket.assigns.estimation, task)
    {:noreply, socket |> assign(:estimation, estimation) |> Grid.upsert_task(id)}
  end

  def handle({:epic_updated, %{id: id, name: _} = epic}, socket) when is_binary(id) do
    estimation = Estimates.update_epic_in_memory(socket.assigns.estimation, epic)
    {:noreply, socket |> assign(:estimation, estimation) |> Grid.upsert_epic_header(id)}
  end

  def handle({:role_updated, %{id: id, hourly_rate: _} = role}, socket) when is_binary(id) do
    estimation = Estimates.update_role_in_memory(socket.assigns.estimation, role)
    {:noreply, socket |> assign(:estimation, estimation) |> Grid.reset()}
  end

  # creates, deletes, reorders, estimation_updated, and any malformed payload
  def handle(_event, socket), do: {:noreply, reload_estimation(socket)}
end
```

In `Index`, replace both `handle_info/2` clauses (and the `# All broadcast events trigger a full reload` comment) with:

```elixir
  @impl true
  def handle_info(event, socket), do: Sync.handle(event, socket)
```

(add `Sync` to the alias list). `Index` may now have an unused `import … Authz, only: [reload_estimation: 1]` — remove it if the compiler says so.

- [ ] **Step 7: Run everything** — `mix test test/estimate_web/live/estimator_live` then `mix precommit`.

- [ ] **Step 8: Commit**

```bash
git add lib/estimate_web/live/estimator_live test/estimate_web/live/estimator_live
git commit -m "perf(estimator): targeted stream updates — cell edits and payload events touch only their rows

Sync maps estimate/task/epic/role updates to in-memory patches +
stream_insert of the affected rows; creates/deletes/reorders reload and
reset. Editing a cell re-inserts just that task row.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: Bench AFTER numbers + documentation

**Files:**
- Modify: `README.md` (perf notes: streams, broadcast_from, org-context cost; how to run the bench)
- Modify: `docs/superpowers/specs/2026-09-16-audit-batch-3-followups-decomposition-perf-design.md` (C3: note the `Grid`/`Sync` modules and the `position, inserted_at, id` ordering fix)
- No code changes.

- [ ] **Step 1: Run both benches**

```bash
mix test --include bench test/bench/org_context_bench_test.exs
mix test --include bench test/bench/estimator_grid_bench_test.exs
```

Copy both printed blocks. Compare the grid block with the BEFORE block recorded in Task 2's commit message (`git log --grep "Grid bench baseline" -1 --format=%B`).

- [ ] **Step 2: README**

In the README section that describes the estimator / real-time collaboration (search for "Real-time collaboration"), add a short "Performance notes" list:

```markdown
- **Estimator grid is a LiveView stream.** Rows (`epic-<id>`, `task-<id>`, `epic-<id>-subtotal`) are built by `EstimatorLive.Rows` with their totals precomputed; footer/breakdown numbers live in one `EstimatorLive.Totals` struct. A cell edit re-inserts two rows; creates/deletes/reorders reset the stream. `EstimatorLive.Sync` is the event→update matrix.
- **Writers don't hear their own broadcasts.** `EstimationEngine.broadcast/2` uses `broadcast_from`; the originating LiveView applies its change locally.
- **RLS context is 3 statements per call**, and nested `Repo.with_org_context/2` calls in the same context are free.
- Bench harnesses (excluded from `mix test`): `mix test --include bench test/bench/<name>_bench_test.exs`.
```

- [ ] **Step 3: Spec note**

Under "### C3. Estimator grid on LiveView streams" add: "Implemented 2026-09-17: `Grid` owns the stream (`init/reset/upsert_task/upsert_epic_header/refresh_editing`), `Sync.handle/2` is the update matrix, `Authz.reload_estimation/1` = reload + reset. Deterministic child order (`position, inserted_at, id`) added to `get_estimation!/2` so stream order is stable."

- [ ] **Step 4: Precommit and commit**

```bash
git add README.md docs/superpowers/specs/2026-09-16-audit-batch-3-followups-decomposition-perf-design.md
git commit -m "docs(perf): estimator streams, broadcast_from and org-context notes; bench results

Grid bench (100 tasks x 5 roles), before -> after:
  20 cell edits:      <ms> -> <ms> ms
  5 pubsub reloads:   <ms> -> <ms> ms
  priority toggle x2: <ms> -> <ms> ms
org_context bench (n=1000): flat 7 -> 3 stmts/call; nested 14 -> 3 stmts/outer call

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

## Done criteria

- `EstimationEngine.broadcast/2` is `broadcast_from`; `Settings.reorder_roles/2` reloads; two-LV test proves originator does not reload.
- `Repo.with_org_context/2`: 3 statements flat, 0 nested-same-context; existing restoration tests untouched and green.
- Grid renders from the `:rows` stream; `Rows`, `Totals`, `Grid`, `Sync` modules with tests; update matrix enforced by `sync_test`; realtime test re-pointed at the DOM.
- 3B suite green throughout (with the named edits only); bench numbers in the Task 1, 2 and 8 commit messages.

## Unresolved questions

None.
