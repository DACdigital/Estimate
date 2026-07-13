# Foundation Cleanups + Canonical Format Module — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the non-speculative, cross-cutting web-layer foundation: purge confirmed dead code, collapse two 1-function auth-helper modules into one (removing 11 redundant imports), and create the canonical `EstimateWeb.Format` module that clusters will migrate their scattered formatters onto.

**Architecture:** Behavior-preserving. Three independent changes: (1) delete dead functions, (2) merge `EstimateWeb.LiveHelpers` into `EstimateWeb.AuthHelpers` and wire `require_admin/2` app-wide via `estimate_web.ex`, (3) add `EstimateWeb.Format` with faithful copies of the existing formatter bodies + unit tests. No call-site migration of formatters (that is per-cluster work, because the formatters have semantic variants that need per-screen judgment). No new UI components (created born-with-adopters in cluster PRs).

**Tech Stack:** Elixir ~> 1.15, Phoenix 1.8, Phoenix.LiveView 1.1, Decimal, Number, ExUnit.

## Global Constraints

- **Behavior-preserving.** No screen behavior changes. The 94-test Phase-0 suite must stay green after every task.
- **No DB schema/migration changes.** (Deleting a *dead* function from a schema module is DB-neutral code cleanup and is allowed — it changes no field/table/association.)
- **`mix precommit` must pass** (`compile --warnings-as-errors`, `deps.unlock --unused`, `format`, `test`). Note: `precommit` also reformats pre-existing repo-wide drift — after running it, `git restore` any file this plan did not intentionally change (pre-existing drift is a separate housekeeping MR).
- **Verify-before-delete.** Before deleting any function, grep both `<.name` (HEEx) and `name(` (call) forms across `lib/` and `test/` and confirm zero call sites in the same step.
- **Stacks on Phase 0** (`test/phase0-foundation`). Branch: `refactor/phase1-foundation`.

---

### Task 1: Purge confirmed dead code

**Files:**
- Modify: `lib/estimate_web/components/core_components.ex` (delete `header/1` ~line 413, `simple_form/1` ~line 764)
- Modify: `lib/estimate/estimation_engine/task.ex` (delete dead `priority_label/1` ~lines 29-33)
- Test: existing suite (no new test; deletion is verified by grep + green suite + warnings-as-errors compile)

**Interfaces:**
- Consumes: nothing.
- Produces: nothing (pure removal).

- [ ] **Step 1: Prove all three are dead**

Run:
```bash
cd /Users/kradecki/development/git/dac.digital/estimate
for fn in header simple_form; do
  echo "== $fn =="; grep -rn "<\.$fn\b\|[^.]\b$fn(" lib test | grep -v "def $fn" | grep -v "def_$fn"
done
echo "== Task.priority_label =="; grep -rn "priority_label" lib/estimate lib/estimate_web test | grep -iE "task\.priority_label|EstimationEngine\.Task"
```
Expected: no real call sites for `header(`/`<.header`, none for `simple_form(`/`<.simple_form` (a self-referential `@doc` example line in core_components does not count), and no qualified callers of `EstimationEngine.Task.priority_label`. If any real caller appears, STOP and report — that function is not dead.

- [ ] **Step 2: Delete `header/1` and `simple_form/1` from core_components.ex**

Delete the entire `@doc`+`attr`/`slot`+`def header(assigns) do ... end` block (the header component, ~line 405-427) and the entire `@doc`+`attr`/`slot`+`def simple_form(assigns) do ... end` block (~line 746-782). Delete their doc/attr preamble too, not just the `def`.

- [ ] **Step 3: Delete dead `priority_label/1` from the Task schema**

In `lib/estimate/estimation_engine/task.ex`, delete these 5 lines (~29-33):
```elixir
  def priority_label("must"), do: "Must"
  def priority_label("should"), do: "Should"
  def priority_label("could"), do: "Could"
  def priority_label("wont"), do: "Won't"
  def priority_label(_), do: "Must"
```
Do not touch the schema, fields, changeset, or any other function in this file.

- [ ] **Step 4: Compile with warnings-as-errors and run the suite**

Run: `mix compile --warnings-as-errors --force && mix test`
Expected: compiles clean (no "function X/1 is unused" or undefined-function errors), 94 tests / 0 failures. If compile reports any of the deleted functions is referenced, a call site was missed in Step 1 — restore and investigate.

- [ ] **Step 5: Commit**

```bash
git add lib/estimate_web/components/core_components.ex lib/estimate/estimation_engine/task.ex
git commit -m "refactor: remove dead header/1, simple_form/1, Task.priority_label/1

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Merge `LiveHelpers` into `AuthHelpers`

**Files:**
- Modify: `lib/estimate_web/auth_helpers.ex` (add `require_admin/2`)
- Delete: `lib/estimate_web/live_helpers.ex`
- Modify: 11 LiveView files (remove `import EstimateWeb.LiveHelpers`)
- Test: existing 94-test suite (covers all 11 screens)

**Interfaces:**
- Consumes: `EstimateWeb.AuthHelpers.admin?/1` (already defined), `Phoenix.LiveView.put_flash/3`.
- Produces: `EstimateWeb.AuthHelpers.require_admin/2` — same signature/behavior as the old `LiveHelpers.require_admin/2`, now auto-imported into every `:live_view` (because `estimate_web.ex`'s `live_view/0` already does `import EstimateWeb.AuthHelpers`).

Context: `require_admin/2` is currently the ONLY function in `LiveHelpers`, manually imported in 11 files. `admin?/1` (in `AuthHelpers`) is already auto-imported into every LiveView via `estimate_web.ex`. Moving `require_admin/2` into `AuthHelpers` makes it auto-available too, so the 11 explicit imports become redundant.

- [ ] **Step 1: Add `require_admin/2` to `AuthHelpers`**

Replace the body of `lib/estimate_web/auth_helpers.ex` with:
```elixir
defmodule EstimateWeb.AuthHelpers do
  @moduledoc false

  import Phoenix.LiveView, only: [put_flash: 3]

  alias Estimate.Accounts.Membership

  def admin?(%{role: role}), do: role in Membership.admin_roles()
  def admin?(_), do: false

  def require_admin(socket, fun) do
    if admin?(socket.assigns.current_membership),
      do: fun.(),
      else: {:noreply, put_flash(socket, :error, "Not authorized")}
  end
end
```

- [ ] **Step 2: Delete the old module**

```bash
git rm lib/estimate_web/live_helpers.ex
```

- [ ] **Step 3: Remove the 11 redundant imports**

Remove the line `import EstimateWeb.LiveHelpers` (and any now-orphaned blank line) from each of these files:
```
lib/estimate_web/live/templates_live/index.ex
lib/estimate_web/live/templates_live/show.ex
lib/estimate_web/live/roles_live/index.ex
lib/estimate_web/live/settings_live/trash.ex
lib/estimate_web/live/settings_live/ai.ex
lib/estimate_web/live/settings_live/index.ex
lib/estimate_web/live/settings_live/email.ex
lib/estimate_web/live/settings_live/members.ex
lib/estimate_web/live/settings_live/currencies.ex
lib/estimate_web/live/customer_live/show.ex
lib/estimate_web/live/customer_live/index.ex
```
First confirm that set is exhaustive:
```bash
grep -rln "import EstimateWeb.LiveHelpers" lib
```
Every file it lists must have the import removed. Do NOT add any import for `require_admin` — it now arrives via `use EstimateWeb, :live_view`.

- [ ] **Step 4: Compile with warnings-as-errors and run the suite**

Run: `mix compile --warnings-as-errors --force && mix test`
Expected: clean compile (no "undefined function require_admin/2", no "unused import"), 94 tests / 0 failures. The Phase-0 smoke tests mount every one of these 11 screens, so green here proves `require_admin/2` resolves everywhere it's used.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: merge LiveHelpers into AuthHelpers; drop 11 redundant imports

require_admin/2 now auto-imported via EstimateWeb :live_view, same as admin?/1.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Create the canonical `EstimateWeb.Format` module

**Files:**
- Create: `lib/estimate_web/format.ex`
- Test: `test/estimate_web/format_test.exs` (create)

**Interfaces:**
- Consumes: `Decimal`, `Number.Currency`.
- Produces (the canonical formatting API that cluster PRs will migrate onto):
  - `format_cost(Decimal.t(), currency | nil) :: String.t()`
  - `format_rate(rate, currency | nil) :: String.t()`
  - `format_hours(Decimal.t()) :: String.t()` — zero → `""`, whole → integer string, else 1-dp
  - `format_hours_with_unit(Decimal.t()) :: String.t()` — zero → `"0h"`, else `"<1dp>h"`
  - `format_percent(Decimal.t()) :: integer()`
  - `parse_decimal(term()) :: Decimal.t()` — arity 1, defaults to `Decimal.new(0)`
  - `parse_decimal(term(), Decimal.t()) :: Decimal.t()` — arity 2, caller-supplied default
  - `decimal_to_number(Decimal.t()) :: integer() | float()`

These are faithful copies of the existing bodies (from `EstimatorLive.Helpers`, plus the `format_hours_h` variant from `estimation_dashboard.ex` and the `parse_decimal/2` variant from `project_live/show.ex`). This task ONLY creates + tests the module; it does not change any existing call site. `Format` is intentionally NOT imported app-wide yet (that happens in the final cleanup once clusters have migrated their calls off the old locations, to avoid same-name import collisions with `EstimatorLive.Helpers`).

- [ ] **Step 1: Write the module**

Create `lib/estimate_web/format.ex`:
```elixir
defmodule EstimateWeb.Format do
  @moduledoc """
  Canonical presentation formatters (currency, hours, percent, decimals).

  Consolidates formatting logic previously scattered across LiveViews and
  `EstimatorLive.Helpers`. Callers migrate onto this module cluster-by-cluster;
  once migration is complete the old copies are removed and this module is
  imported app-wide.
  """

  @doc "Formats a monetary Decimal with a currency's symbol/position. Zero → \"-\"."
  def format_cost(decimal, currency) do
    if Decimal.compare(decimal, 0) == :eq do
      "-"
    else
      symbol = if currency, do: currency.symbol, else: "$"
      position = if currency, do: currency.symbol_position, else: "prefix"

      case position do
        "suffix" ->
          Number.Currency.number_to_currency(decimal, unit: "", format: "%n") <> symbol

        _ ->
          Number.Currency.number_to_currency(decimal, unit: symbol)
      end
    end
  end

  @doc "Formats an hourly rate like `$120/h`, honoring currency symbol position."
  def format_rate(rate, nil), do: "$#{rate}/h"

  def format_rate(rate, currency) do
    case currency.symbol_position do
      "suffix" -> "#{rate}#{currency.symbol}/h"
      _ -> "#{currency.symbol}#{rate}/h"
    end
  end

  @doc "Hours for tables: zero → \"\", whole → integer, otherwise 1 decimal place."
  def format_hours(decimal) do
    cond do
      Decimal.compare(decimal, 0) == :eq ->
        ""

      Decimal.rem(decimal, 1) |> Decimal.compare(0) == :eq ->
        decimal |> Decimal.round(0) |> Decimal.to_integer() |> to_string()

      true ->
        decimal |> Decimal.round(1) |> Decimal.to_string()
    end
  end

  @doc "Hours with a unit suffix: zero → \"0h\", otherwise `\"<1dp>h\"`."
  def format_hours_with_unit(decimal) do
    if Decimal.compare(decimal, 0) == :eq do
      "0h"
    else
      "#{decimal |> Decimal.round(1) |> Decimal.to_string()}h"
    end
  end

  @doc "Rounds a percentage Decimal to a whole integer."
  def format_percent(decimal), do: decimal |> Decimal.round(0) |> Decimal.to_integer()

  @doc "Parses a value to Decimal, defaulting to 0 on any failure."
  def parse_decimal(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, ""} -> decimal
      {decimal, remainder} -> if String.trim(remainder) == "", do: decimal, else: Decimal.new(0)
      :error -> Decimal.new(0)
    end
  end

  def parse_decimal(value) when is_number(value), do: Decimal.new(value)
  def parse_decimal(_), do: Decimal.new(0)

  @doc "Parses a value to Decimal, returning `default` on nil/empty/failure."
  def parse_decimal(nil, default), do: default
  def parse_decimal("", default), do: default

  def parse_decimal(value, default) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, _} -> decimal
      :error -> default
    end
  end

  def parse_decimal(value, _default), do: value

  @doc "Converts a Decimal to an integer when whole, otherwise a float."
  def decimal_to_number(decimal) do
    if Decimal.equal?(Decimal.rem(decimal, 1), 0) do
      Decimal.to_integer(decimal)
    else
      Decimal.to_float(decimal)
    end
  end
end
```

- [ ] **Step 2: Write the failing test**

Create `test/estimate_web/format_test.exs`:
```elixir
defmodule EstimateWeb.FormatTest do
  use ExUnit.Case, async: true

  alias EstimateWeb.Format

  defp dec(n), do: Decimal.new(n)

  describe "format_cost/2" do
    test "zero renders a dash" do
      assert Format.format_cost(dec(0), nil) == "-"
    end

    test "prefix currency (nil → $)" do
      assert Format.format_cost(dec(1500), nil) =~ "$"
      assert Format.format_cost(dec(1500), nil) =~ "1,500"
    end

    test "suffix currency appends the symbol" do
      currency = %{symbol: "zł", symbol_position: "suffix"}
      result = Format.format_cost(dec(1500), currency)
      assert String.ends_with?(result, "zł")
      assert result =~ "1,500"
    end
  end

  describe "format_rate/2" do
    test "nil currency uses $ prefix" do
      assert Format.format_rate(120, nil) == "$120/h"
    end

    test "prefix currency" do
      assert Format.format_rate(120, %{symbol: "€", symbol_position: "prefix"}) == "€120/h"
    end

    test "suffix currency" do
      assert Format.format_rate(120, %{symbol: "zł", symbol_position: "suffix"}) == "120zł/h"
    end
  end

  describe "format_hours/1" do
    test "zero → empty string" do
      assert Format.format_hours(dec(0)) == ""
    end

    test "whole → integer string" do
      assert Format.format_hours(dec(5)) == "5"
    end

    test "fractional → one decimal place" do
      assert Format.format_hours(Decimal.new("5.5")) == "5.5"
    end
  end

  describe "format_hours_with_unit/1" do
    test "zero → 0h" do
      assert Format.format_hours_with_unit(dec(0)) == "0h"
    end

    test "whole → one-decimal with h suffix" do
      assert Format.format_hours_with_unit(dec(5)) == "5.0h"
    end

    test "fractional → one-decimal with h suffix" do
      assert Format.format_hours_with_unit(Decimal.new("5.5")) == "5.5h"
    end
  end

  describe "format_percent/1" do
    test "rounds to whole integer" do
      assert Format.format_percent(Decimal.new("15.4")) == 15
      assert Format.format_percent(Decimal.new("15.6")) == 16
    end
  end

  describe "parse_decimal/1" do
    test "parses a numeric string" do
      assert Decimal.equal?(Format.parse_decimal("12.5"), Decimal.new("12.5"))
    end

    test "garbage → 0" do
      assert Decimal.equal?(Format.parse_decimal("abc"), dec(0))
    end

    test "nil → 0" do
      assert Decimal.equal?(Format.parse_decimal(nil), dec(0))
    end

    test "number input" do
      assert Decimal.equal?(Format.parse_decimal(7), dec(7))
    end
  end

  describe "parse_decimal/2" do
    test "nil → supplied default" do
      assert Format.parse_decimal(nil, :fallback) == :fallback
    end

    test "empty string → supplied default" do
      assert Format.parse_decimal("", :fallback) == :fallback
    end

    test "valid string → parsed decimal" do
      assert Decimal.equal?(Format.parse_decimal("9.9", dec(0)), Decimal.new("9.9"))
    end

    test "invalid string → supplied default" do
      assert Format.parse_decimal("nope", :fallback) == :fallback
    end
  end

  describe "decimal_to_number/1" do
    test "whole → integer" do
      assert Format.decimal_to_number(dec(10)) === 10
    end

    test "fractional → float" do
      assert Format.decimal_to_number(Decimal.new("10.5")) === 10.5
    end
  end
end
```

- [ ] **Step 3: Run the test**

Run: `mix test test/estimate_web/format_test.exs`
Expected: PASS. If `format_cost` currency assertions fail on separators/formatting, adjust the *test's* expectation to what `Number.Currency` actually returns (the module body is a verbatim copy of the shipping code, so its output is by definition the current behavior) — do not change the module body.

- [ ] **Step 4: Full suite + warnings-as-errors**

Run: `mix compile --warnings-as-errors --force && mix test`
Expected: 94 + 24 = 118 tests (approx), 0 failures. `Format` is a new module with public functions only — no "unused" warnings.

- [ ] **Step 5: Commit**

```bash
git add lib/estimate_web/format.ex test/estimate_web/format_test.exs
git commit -m "feat: add canonical EstimateWeb.Format module

Consolidates currency/hours/percent/decimal formatters. Call-site migration
happens per-cluster; not yet imported app-wide.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:** Plan 2 covers the *safe, non-speculative* slice of spec §5 "shared foundation": dead-code purge ✓, merge `live_helpers`→`auth_helpers` ✓, `EstimateWeb.Format` creation ✓. Deliberately deferred (documented deviation, not gaps): `<.badge>` + primitives (`page_header`/`empty_state`/`breadcrumb`/`settings_card`/`auth_input`) → created born-with-adopters in their first cluster PR; `<.input>` radio + `<.button>` expansion → with the auth/settings clusters that need them; `current_scope` + `app_shell` + on_mount `active_tab` → a dedicated cross-cutting migration plan (they touch every LiveView once and warrant their own gated plan); formatter call-site migration → per-cluster (semantic variants need per-screen judgment).

**Placeholder scan:** none. Task 1 Step 1 and Task 2 Step 3 include concrete verification greps with explicit stop conditions; all code is complete.

**Type consistency:** `require_admin/2` signature preserved from the deleted module. `Format` function names/arities in the Interfaces block match the module body and the test. `format_hours_with_unit/1` (not `format_hours_h`) is the canonical name for the suffix variant — used consistently.
