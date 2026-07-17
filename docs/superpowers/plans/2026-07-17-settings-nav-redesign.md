# Settings Navigation Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Collapse the sidebar's six settings links into one "Settings" entry and give the settings area a grouped, role-aware, slide-in secondary rail.

**Architecture:** A new `Layouts.settings_rail/1` function component renders between the global sidebar and page content whenever the LiveView assigned `:settings_page` (all settings LVs do; Trash gains the missing assign). The rail carries a stable DOM id so LiveView's morphdom persists it across settings-to-settings navigations — the CSS entry animation plays only on first insert. Sidebar's SETTINGS group becomes a single `sidebar_link`.

**Tech Stack:** Phoenix 1.8 LiveView 1.1, HEEx, Tailwind 4 (`assets/css/app.css`), existing `admin?/1` helper.

**Spec:** `docs/superpowers/specs/2026-07-17-settings-nav-redesign-design.md`

## Global Constraints

- Groups and order, verbatim: **Workspace**: General · Members · Currencies · Trash — **Integrations**: AI · Email · MCP.
- Role visibility: Trash/AI/Email links render ONLY for `admin?(@current_membership)` (owner/admin). Hidden, not locked. Member rail = General · Members · Currencies · MCP.
- Rail root: `id="settings-rail"`, entry animation 180ms ease-out, fade + 12px slide from left (`@keyframes settings-rail-in`). No exit animation. No replay between settings pages (guaranteed by the stable id + shared `:org_scoped` live_session — do not add JS).
- Routes, page modules, and authz behavior unchanged. No data-model changes.
- Sidebar entry: icon `hero-cog-6-tooth`, label "Settings", href `~p"/org/#{@org_id}/settings"`, active when `assigns[:active_tab] == :settings` (every settings LV already assigns it).
- Tests: no-tautology discipline — member-visibility tests use a real `membership_fixture(member, org, "member")`; absence assertions must be scoped to `#settings-rail` (or run where the rail is absent) so they can't pass vacuously.
- `mix format` before every commit; `git add` only files the task touched (never `-A`). Commit style: extremely concise, conventional prefixes.
- Work on branch `settings-nav` (created in Task 1 Step 1 from master).

## File Structure

| File | Responsibility |
|---|---|
| `lib/estimate_web/components/layouts.ex` (modify) | new `settings_rail/1` component next to the existing sidebar link components |
| `lib/estimate_web/components/layouts/app.html.heex` (modify) | render rail beside `<main>`; replace SETTINGS group with single entry |
| `lib/estimate_web/live/settings_live/trash.ex` (modify) | add missing `:settings_page` assign |
| `assets/css/app.css` (modify) | `settings-rail-in` keyframes + `.settings-rail-enter` class |
| `test/estimate_web/live/settings_nav_test.exs` (create) | rail visibility/role/absence + sidebar collapse tests |

---

### Task 1: Settings rail — component, layout wiring, CSS, Trash assign

**Files:**
- Modify: `lib/estimate_web/components/layouts.ex` (after `sidebar_child_link/1`, ~line 68)
- Modify: `lib/estimate_web/components/layouts/app.html.heex:202-206` (the `<main>` block)
- Modify: `lib/estimate_web/live/settings_live/trash.ex:104` (assign)
- Modify: `assets/css/app.css` (append)
- Test: `test/estimate_web/live/settings_nav_test.exs`

**Interfaces:**
- Consumes: `sidebar_child_link/1` (label/href/active attrs), `admin?/1` (imported in `:html` via `EstimateWeb.AuthHelpers`), assigns provided by the `:org_scoped` live_session (`:org_id`, `:current_membership`, `:settings_page`).
- Produces: `Layouts.settings_rail/1` with attrs `org_id :string (required)`, `settings_page :atom (required)`, `current_membership :map (required)`; rail root `#settings-rail`; CSS class `settings-rail-enter`. Task 2 relies on the rail being the ONLY place settings child links exist on settings pages.

- [ ] **Step 1: Branch**

```bash
git checkout -b settings-nav
```

- [ ] **Step 2: Write the failing tests**

Create `test/estimate_web/live/settings_nav_test.exs`:

```elixir
defmodule EstimateWeb.SettingsNavTest do
  use EstimateWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Estimate.AccountsFixtures

  setup :register_and_log_in_org_owner

  defp rail_link(org, page), do: ~s(#settings-rail a[href="/org/#{org.id}/settings#{page}"])

  describe "settings rail" do
    test "admin sees both groups with all 7 items", %{conn: conn, org: org} do
      {:ok, view, html} = live(conn, ~p"/org/#{org.id}/settings")

      assert has_element?(view, "#settings-rail")
      assert html =~ "Workspace"
      assert html =~ "Integrations"

      for page <- ["", "/members", "/currencies", "/trash", "/ai", "/email", "/mcp"] do
        assert has_element?(view, rail_link(org, page)), "missing rail link for #{page}"
      end
    end

    test "member rail hides Trash, AI and Email", %{conn: _conn, org: org} do
      member = user_fixture()
      membership_fixture(member, org, "member")
      conn = log_in_user(build_conn(), member)

      {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/settings")

      assert has_element?(view, "#settings-rail")

      for page <- ["", "/members", "/currencies", "/mcp"] do
        assert has_element?(view, rail_link(org, page)), "missing rail link for #{page}"
      end

      for page <- ["/trash", "/ai", "/email"] do
        refute has_element?(view, rail_link(org, page)), "member must not see #{page}"
      end
    end

    test "rail is absent outside settings", %{conn: conn, org: org} do
      {:ok, view, _html} = live(conn, ~p"/org/#{org.id}")

      refute has_element?(view, "#settings-rail")
    end

    test "trash page renders the rail with trash active", %{conn: conn, org: org} do
      {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/settings/trash")

      assert has_element?(view, "#settings-rail")
      # active styling comes from sidebar_child_link's active class (font-medium)
      assert has_element?(view, rail_link(org, "/trash") <> ".font-medium")
    end

    test "rail carries the entry animation class", %{conn: conn, org: org} do
      {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/settings")

      assert has_element?(view, "#settings-rail.settings-rail-enter")
    end
  end
end
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `mix test test/estimate_web/live/settings_nav_test.exs`
Expected: FAIL — no `#settings-rail` anywhere (5 failures; the "absent outside settings" test may pass trivially now, that's fine — it becomes discriminating once the rail exists).

- [ ] **Step 4: Add the component**

In `lib/estimate_web/components/layouts.ex`, directly after `sidebar_child_link/1` (~line 68), add:

```elixir
  @doc """
  Secondary navigation rail for the settings area.

  Rendered by the app layout whenever the LiveView assigned `:settings_page`.
  The stable DOM id lets morphdom persist the element across settings-to-settings
  live navigations, so the entry animation plays only when settings is entered.
  """
  attr :org_id, :string, required: true
  attr :settings_page, :atom, required: true
  attr :current_membership, :map, required: true

  def settings_rail(assigns) do
    ~H"""
    <aside
      id="settings-rail"
      class="settings-rail-enter w-52 shrink-0 border-r border-base-300 bg-base-100 px-4 py-6 overflow-y-auto"
    >
      <div class="px-3 pb-1.5 text-xs font-semibold uppercase tracking-wider text-base-content/40">
        Workspace
      </div>
      <div class="space-y-0.5">
        <.sidebar_child_link
          href={~p"/org/#{@org_id}/settings"}
          label="General"
          active={@settings_page == :general}
        />
        <.sidebar_child_link
          href={~p"/org/#{@org_id}/settings/members"}
          label="Members"
          active={@settings_page == :members}
        />
        <.sidebar_child_link
          href={~p"/org/#{@org_id}/settings/currencies"}
          label="Currencies"
          active={@settings_page == :currencies}
        />
        <.sidebar_child_link
          :if={admin?(@current_membership)}
          href={~p"/org/#{@org_id}/settings/trash"}
          label="Trash"
          active={@settings_page == :trash}
        />
      </div>

      <div class="px-3 pb-1.5 pt-6 text-xs font-semibold uppercase tracking-wider text-base-content/40">
        Integrations
      </div>
      <div class="space-y-0.5">
        <.sidebar_child_link
          :if={admin?(@current_membership)}
          href={~p"/org/#{@org_id}/settings/ai"}
          label="AI"
          active={@settings_page == :ai}
        />
        <.sidebar_child_link
          :if={admin?(@current_membership)}
          href={~p"/org/#{@org_id}/settings/email"}
          label="Email"
          active={@settings_page == :email}
        />
        <.sidebar_child_link
          href={~p"/org/#{@org_id}/settings/mcp"}
          label="MCP"
          active={@settings_page == :mcp}
        />
      </div>
    </aside>
    """
  end
```

(If `admin?/1` or `~p` are unavailable in `Layouts`, check the top of `lib/estimate_web/components/layouts.ex` — it should `use EstimateWeb, :html`, which imports both. If it uses a narrower macro, add `import EstimateWeb.AuthHelpers` and `use Phoenix.VerifiedRoutes` accordingly — but check first, don't assume.)

- [ ] **Step 5: Wire the rail into the layout**

In `lib/estimate_web/components/layouts/app.html.heex`, replace the page-content block:

```heex
    <!-- Page content -->
    <main class="flex-1 overflow-y-auto p-8">
      <.flash_group flash={@flash} />
      {@inner_content}
    </main>
```

with:

```heex
    <!-- Page content (settings pages get the secondary rail) -->
    <div class="flex-1 flex overflow-hidden">
      <.settings_rail
        :if={assigns[:settings_page]}
        org_id={@org_id}
        settings_page={@settings_page}
        current_membership={@current_membership}
      />
      <main class="flex-1 overflow-y-auto p-8">
        <.flash_group flash={@flash} />
        {@inner_content}
      </main>
    </div>
```

- [ ] **Step 6: Trash assign + CSS**

In `lib/estimate_web/live/settings_live/trash.ex` (~line 104), extend the mount pipeline:

```elixir
       |> assign(:active_tab, :settings)
       |> assign(:settings_page, :trash)
```

Append to `assets/css/app.css`:

```css
/* Settings rail entry animation — plays only when the rail is first inserted;
   morphdom keeps #settings-rail alive across settings-to-settings navigation. */
@keyframes settings-rail-in {
  from {
    opacity: 0;
    transform: translateX(-12px);
  }
  to {
    opacity: 1;
    transform: none;
  }
}

.settings-rail-enter {
  animation: settings-rail-in 180ms ease-out;
}
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `mix test test/estimate_web/live/settings_nav_test.exs`
Expected: 5 tests, 0 failures.

- [ ] **Step 8: Commit**

```bash
mix format
git add lib/estimate_web/components/layouts.ex lib/estimate_web/components/layouts/app.html.heex lib/estimate_web/live/settings_live/trash.ex assets/css/app.css test/estimate_web/live/settings_nav_test.exs
git commit -m "feat: grouped role-aware settings rail w/ entry animation"
```

---

### Task 2: Collapse sidebar settings group to a single entry

**Files:**
- Modify: `lib/estimate_web/components/layouts/app.html.heex:71-110` (the SETTINGS group `<div>`)
- Test: `test/estimate_web/live/settings_nav_test.exs` (append describe)

**Interfaces:**
- Consumes: Task 1's rail (settings child links now live there); `sidebar_link/1`; `active_tab == :settings` assigned by all seven settings LVs.
- Produces: global sidebar with exactly one settings entry.

- [ ] **Step 1: Write the failing tests**

Append to `test/estimate_web/live/settings_nav_test.exs` (inside the module, after the existing describe):

```elixir
  describe "global sidebar" do
    test "has a single Settings entry, no expanded settings links", %{conn: conn, org: org} do
      # Dashboard: rail is absent, so any settings child link found here would
      # be a leftover of the old expanded sidebar group.
      {:ok, view, html} = live(conn, ~p"/org/#{org.id}")

      assert has_element?(view, ~s(a[href="/org/#{org.id}/settings"]), "Settings")

      for page <- ["/members", "/currencies", "/ai", "/email", "/mcp"] do
        refute has_element?(view, ~s(a[href="/org/#{org.id}/settings#{page}"])),
               "old sidebar link to settings#{page} still present"
      end

      refute html =~ "AI Integration"
    end

    test "Settings entry is active on settings pages", %{conn: conn, org: org} do
      {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/settings/mcp")

      # sidebar_link active state renders bg-base-200 on the anchor
      assert has_element?(view, ~s(a[href="/org/#{org.id}/settings"].bg-base-200), "Settings")
    end
  end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/estimate_web/live/settings_nav_test.exs`
Expected: the two new tests FAIL (old expanded links still in the sidebar); the five Task-1 tests still pass.

- [ ] **Step 3: Replace the sidebar group**

In `lib/estimate_web/components/layouts/app.html.heex`, replace the entire SETTINGS group block (the `<div class="pt-4 mt-4 border-t border-base-content/10">` containing the "Settings" header and the six `sidebar_child_link`s — currently lines ~71-110) with:

```heex
      <div class="pt-4 mt-4 border-t border-base-content/10">
        <.sidebar_link
          :if={assigns[:org_id]}
          href={~p"/org/#{@org_id}/settings"}
          icon="hero-cog-6-tooth"
          label="Settings"
          active={assigns[:active_tab] == :settings}
        />
      </div>
```

- [ ] **Step 4: Run the nav tests, then the full suite**

Run: `mix test test/estimate_web/live/settings_nav_test.exs`
Expected: 7 tests, 0 failures.

Run: `mix test`
Expected: 0 failures. If any existing test asserted the old sidebar markup (e.g. a link to `/settings/ai` from a non-settings page), update that assertion to target the rail on a settings page instead — and list the change in your report.

- [ ] **Step 5: Commit**

```bash
mix format
git add lib/estimate_web/components/layouts/app.html.heex test/estimate_web/live/settings_nav_test.exs
git commit -m "feat: sidebar settings group -> single Settings entry"
```

---

### Task 3: Verification sweep + browser proof + merge prep

**Files:** none new.

- [ ] **Step 1: Static + suite**

Run: `mix format --check-formatted && mix compile --warnings-as-errors && mix test`
Expected: all green.

- [ ] **Step 2: Browser verification (dev server, seed login)**

Dev server runs via `.claude/launch.json` name `estimate` (port 4000); login `ui-verify@example.com` / `hello_world!` (org "UI Verify Org", user is owner/admin). Verify:
1. Dashboard: sidebar shows single "Settings" entry (cog icon); no expanded settings links; no rail.
2. Click Settings → General opens; rail slides in (Workspace: General/Members/Currencies/Trash · Integrations: AI/Email/MCP); "Settings" highlighted in sidebar.
3. Navigate rail: General → MCP → Trash — rail does NOT re-animate between pages, active item follows.
4. Back to Dashboard → rail gone; re-enter Settings → animation plays again.
5. Screenshot the settings area for the record.

- [ ] **Step 3: Spec cross-check**

Confirm each spec section landed: single entry ✓, groups+order ✓, role matrix (member via test) ✓, Trash linked + assign ✓, animation contract (class + keyframes + morphdom persistence) ✓, routes/authz untouched ✓.

- [ ] **Step 4: Finish**

Use superpowers:finishing-a-development-branch (merge `settings-nav` → master locally per house pattern, re-run suite, delete branch).
