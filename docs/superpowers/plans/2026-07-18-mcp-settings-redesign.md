# MCP Settings Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure `/settings/mcp` into 3 flat cards with explicit copy buttons and always-visible setup snippets (CLI + `mcpServers` JSON), and reorder the settings rail to AI · MCP · Email.

**Architecture:** Pure LiveView render + event changes in one LV module (`SettingsLive.Mcp`) plus a link-order swap in the shared `settings_rail` layout component. Copy uses the app's established server-push pattern: `phx-click` → `handle_event("copy", …)` → `push_event("copy_to_clipboard", %{text: …})` + info flash. No schema/context changes.

**Tech Stack:** Phoenix 1.8 LiveView, HEEx, Tailwind/daisyUI tokens, Jason (already a dep), ExUnit + `Phoenix.LiveViewTest`.

**Spec:** `docs/superpowers/specs/2026-07-18-mcp-settings-redesign-design.md`

## Global Constraints

- Card shell class (all 3 cards): `bg-base-100 border border-base-300 rounded-xl p-6` (+ `mb-6` on all but last).
- Copy icon-buttons: `hero-clipboard-document` at `w-4 h-4`, color-only hover `text-base-content/40 hover:text-base-content/70 transition-colors` — no bg, no border, no rounded box.
- Flash text on every successful copy: exactly `Copied to clipboard`.
- Placeholder key literal: exactly `est_YOUR_KEY`.
- Copy event handler recomputes text from socket assigns; never trusts client-sent text.
- Card ids: `mcp-server-card`, `mcp-claude-ai`, `mcp-api-clients` (tests scope on these).
- Existing auth guards (`require_admin`, `require_mcp_enabled`) and key lifecycle (`@new_key` one-time reveal, cleared on dismiss/toggle) unchanged.
- Test style: follow `[[feedback-characterization-no-tautology]]` — e.g. flash absent at mount before asserting a handler sets it; scope selectors to card ids, not whole-page `=~`.
- Commits: extremely concise messages + `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>` trailer.

---

### Task 1: Rail reorder AI · MCP · Email

**Files:**
- Modify: `lib/estimate_web/components/layouts.ex:124-140` (Integrations group inside `settings_rail/1`)
- Test: `test/estimate_web/live/settings_nav_test.exs`

**Interfaces:**
- Consumes: existing `sidebar_child_link` component, `#settings-rail` DOM id.
- Produces: nothing consumed by later tasks (independent).

- [ ] **Step 1: Write the failing order test**

Add to the `describe "settings rail"` block in `test/estimate_web/live/settings_nav_test.exs`:

```elixir
test "integrations group orders AI before MCP before Email", %{conn: conn, org: org} do
  {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/settings")

  rail = view |> element("#settings-rail") |> render()

  {ai, _} = :binary.match(rail, "/settings/ai")
  {mcp, _} = :binary.match(rail, "/settings/mcp")
  {email, _} = :binary.match(rail, "/settings/email")

  assert ai < mcp, "AI link must precede MCP link"
  assert mcp < email, "MCP link must precede Email link"
end
```

(`setup :register_and_log_in_org_owner` already applies — owner sees all three links.)

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/estimate_web/live/settings_nav_test.exs`
Expected: 1 failure — `MCP link must precede Email link` (current order is AI · Email · MCP).

- [ ] **Step 3: Swap link order in the layout**

In `lib/estimate_web/components/layouts.ex`, inside the Integrations `<div class="space-y-0.5">`, move the MCP link between AI and Email so the group reads:

```heex
<.sidebar_child_link
  :if={admin?(@current_membership)}
  navigate={~p"/org/#{@org_id}/settings/ai"}
  label="AI"
  active={@settings_page == :ai}
/>
<.sidebar_child_link
  navigate={~p"/org/#{@org_id}/settings/mcp"}
  label="MCP"
  active={@settings_page == :mcp}
/>
<.sidebar_child_link
  :if={admin?(@current_membership)}
  navigate={~p"/org/#{@org_id}/settings/email"}
  label="Email"
  active={@settings_page == :email}
/>
```

No attribute changes — only position.

- [ ] **Step 4: Run tests to verify pass**

Run: `mix test test/estimate_web/live/settings_nav_test.exs`
Expected: all pass (existing presence/visibility tests are order-agnostic).

- [ ] **Step 5: Commit**

```bash
git add lib/estimate_web/components/layouts.ex test/estimate_web/live/settings_nav_test.exs
git commit -m "feat: settings rail orders AI · MCP · Email

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Restructure MCP page into 3 flat cards

**Files:**
- Modify: `lib/estimate_web/live/settings_live/mcp.ex` (render/1 only)
- Test: `test/estimate_web/live/settings_live/mcp_test.exs`

**Interfaces:**
- Consumes: existing assigns `@mcp_url`, `@api_key`, `@new_key`, `@current_organization`, `@current_membership`; existing events `toggle_mcp`, `generate_key`, `revoke_key`, `dismiss_new_key`.
- Produces: card ids `mcp-server-card`, `mcp-claude-ai`, `mcp-api-clients`; a `<div id="mcp-setup-snippets">` placeholder div at the end of the api-clients card (empty in this task — Task 3 fills it). Task 3 relies on these ids.

- [ ] **Step 1: Update existing tests + add structure tests (failing)**

In `test/estimate_web/live/settings_live/mcp_test.exs`:

Replace the test `"shows the claude.ai connector instructions"` with:

```elixir
test "claude.ai card shows the connector URL; server card does not", %{conn: conn, org: org} do
  {:ok, lv, html} = live(conn, ~p"/org/#{org.id}/settings/mcp")

  assert html =~ "Connect from claude.ai"
  # URL lives only in the claude.ai card's <code>; the admin server card
  # must no longer render it (dedupe).
  assert has_element?(lv, "#mcp-claude-ai code", url(~p"/mcp"))
  refute lv |> element("#mcp-server-card") |> render() =~ url(~p"/mcp")
end
```

Add to the same `describe "personal key"` block:

```elixir
test "enabled page renders the three cards for an admin", %{conn: conn, org: org} do
  {:ok, lv, _html} = live(conn, ~p"/org/#{org.id}/settings/mcp")

  assert has_element?(lv, "#mcp-server-card")
  assert has_element?(lv, "#mcp-claude-ai")
  assert has_element?(lv, "#mcp-api-clients")
  # claude.ai block is a sibling card, not nested inside the api-clients card
  refute lv |> element("#mcp-api-clients") |> render() =~ "Connect from claude.ai"
end

test "member on an enabled org sees connect cards but no server toggle card", %{org: org} do
  member = user_fixture()
  membership_fixture(member, org, "member")
  conn = log_in_user(build_conn(), member)

  {:ok, lv, _html} = live(conn, ~p"/org/#{org.id}/settings/mcp")

  refute has_element?(lv, "#mcp-server-card")
  assert has_element?(lv, "#mcp-claude-ai")
  assert has_element?(lv, "#mcp-api-clients")
end
```

- [ ] **Step 2: Run tests to verify failures**

Run: `mix test test/estimate_web/live/settings_live/mcp_test.exs`
Expected: the 3 new/changed tests fail (`#mcp-claude-ai` etc. not found); all others still pass.

- [ ] **Step 3: Rewrite render/1**

Replace the entire `~H` template in `lib/estimate_web/live/settings_live/mcp.ex` with:

```heex
<div class="max-w-4xl mx-auto">
  <div class="mb-8">
    <h1 class="text-2xl font-bold text-base-content">MCP Server</h1>
    <p class="mt-1 text-base-content/60">
      Expose read-only org data to MCP clients (Claude Code, Claude Desktop, Cursor…)
    </p>
  </div>

  <div
    :if={admin?(@current_membership)}
    id="mcp-server-card"
    class="bg-base-100 border border-base-300 rounded-xl p-6 mb-6"
  >
    <div class="flex items-center justify-between">
      <div>
        <h2 class="text-sm font-medium text-base-content">
          {if @current_organization.mcp_enabled,
            do: "MCP server is enabled",
            else: "MCP server is disabled"}
        </h2>
        <p class="mt-1 text-sm text-base-content/60">
          Members authenticate with personal API keys that inherit their access. Disabling
          instantly rejects every key.
        </p>
      </div>
      <button
        phx-click="toggle_mcp"
        class={[
          "px-4 py-1.5 text-sm rounded-md font-medium transition-colors",
          if(@current_organization.mcp_enabled,
            do: "bg-error/10 text-error hover:bg-error/20",
            else: "bg-neutral text-neutral-content hover:bg-neutral/90"
          )
        ]}
      >
        {if @current_organization.mcp_enabled, do: "Disable", else: "Enable"}
      </button>
    </div>
  </div>

  <div
    :if={!@current_organization.mcp_enabled && !admin?(@current_membership)}
    class="bg-base-100 border border-base-300 rounded-xl p-6"
  >
    <p class="text-sm text-base-content/60">
      The MCP server is disabled for this organization. Ask an admin to enable it.
    </p>
  </div>

  <div
    :if={@current_organization.mcp_enabled}
    id="mcp-claude-ai"
    class="bg-base-100 border border-base-300 rounded-xl p-6 mb-6"
  >
    <h2 class="text-sm font-medium text-base-content">Connect from claude.ai</h2>
    <p class="mt-1 text-sm text-base-content/60 mb-3">
      Add a custom connector with this URL — you'll sign in and pick this organization. No key needed.
    </p>
    <code class="block font-mono text-sm bg-base-200/60 rounded-lg p-3 select-all">{@mcp_url}</code>
  </div>

  <div
    :if={@current_organization.mcp_enabled}
    id="mcp-api-clients"
    class="bg-base-100 border border-base-300 rounded-xl p-6"
  >
    <h2 class="text-sm font-medium text-base-content">API clients</h2>
    <p class="mt-1 text-sm text-base-content/60 mb-4">
      Claude Code, Claude Desktop, Cursor — authenticate with your personal key.
      The key acts as you: it sees exactly what you see in the app.
    </p>

    <div :if={@new_key} class="mb-4 p-4 bg-warning/10 border border-warning/30 rounded-lg">
      <p class="text-sm font-medium text-base-content mb-2">
        Copy your key now — it will not be shown again.
      </p>
      <code class="block font-mono text-sm break-all select-all mb-3">{@new_key}</code>
      <button
        phx-click="dismiss_new_key"
        class="text-sm text-base-content/60 hover:text-base-content"
      >
        Dismiss
      </button>
    </div>

    <div :if={@api_key} class="flex items-center justify-between">
      <div class="text-sm text-base-content/70 font-mono">
        {@api_key.key_prefix}…
        <span class="ml-3 font-sans text-base-content/50">
          created {Calendar.strftime(@api_key.inserted_at, "%Y-%m-%d")}
        </span>
        <span :if={@api_key.last_used_at} class="ml-3 font-sans text-base-content/50">
          last used {Calendar.strftime(@api_key.last_used_at, "%Y-%m-%d %H:%M")} UTC
        </span>
      </div>
      <div class="flex items-center gap-2">
        <button
          phx-click="generate_key"
          data-confirm="This invalidates your current key. Continue?"
          class="px-3 py-1.5 text-sm rounded-md border border-base-300 hover:bg-base-200 transition-colors"
        >
          Regenerate
        </button>
        <button
          phx-click="revoke_key"
          data-confirm="Revoke your API key?"
          class="px-3 py-1.5 text-sm rounded-md text-error hover:bg-error/10 transition-colors"
        >
          Revoke
        </button>
      </div>
    </div>

    <button
      :if={@api_key == nil}
      phx-click="generate_key"
      class="px-4 py-1.5 bg-neutral text-neutral-content text-sm rounded-md hover:bg-neutral/90 transition-colors font-medium"
    >
      Generate API Key
    </button>

    <div id="mcp-setup-snippets"></div>
  </div>
</div>
```

Notes vs current code: URL `<p>` removed from server card; claude.ai block promoted from inset to sibling card `#mcp-claude-ai` (code block gets the `bg-base-200/60 rounded-lg p-3` treatment the inset box used to provide); reveal panel loses the `claude mcp add` snippet (returns in Task 3 as an always-visible snippet); `#mcp-setup-snippets` is an empty anchor Task 3 fills. `handle_event`/`mount`/guards untouched.

- [ ] **Step 4: Run the full file**

Run: `mix test test/estimate_web/live/settings_live/mcp_test.exs`
Expected: all pass. Watch specifically: `"generate shows plaintext once; remount shows only prefix"` (reveal panel still renders plaintext) and `"toggling MCP off clears the shown-once plaintext key"`.

- [ ] **Step 5: Commit**

```bash
git add lib/estimate_web/live/settings_live/mcp.ex test/estimate_web/live/settings_live/mcp_test.exs
git commit -m "refactor: MCP settings page as 3 flat cards, URL deduped

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Setup snippets + copy buttons + copy event

**Files:**
- Modify: `lib/estimate_web/live/settings_live/mcp.ex`
- Test: `test/estimate_web/live/settings_live/mcp_test.exs`

**Interfaces:**
- Consumes: card ids from Task 2; assigns `@mcp_url`, `@new_key`; app.js `phx:copy_to_clipboard` window listener (exists).
- Produces: event `handle_event("copy", %{"what" => "url" | "key" | "cli" | "json"})`; private helpers `cli_snippet/2`, `json_snippet/2`, `display_key/1`; private components `snippet/1`, `copy_button/1`. Nothing later depends on them.

- [ ] **Step 1: Write failing tests**

Add a new describe block to `test/estimate_web/live/settings_live/mcp_test.exs` (inside it, reuse the enabled-org setup used by `describe "personal key"`):

```elixir
describe "setup snippets and copy" do
  setup %{org: org} do
    {:ok, org} = Organizations.update_mcp_settings(org, %{mcp_enabled: true})
    %{org: org}
  end

  test "snippets render with placeholder key before any key exists", %{conn: conn, org: org} do
    {:ok, lv, html} = live(conn, ~p"/org/#{org.id}/settings/mcp")

    snippets = lv |> element("#mcp-setup-snippets") |> render()
    assert snippets =~ "claude mcp add --transport http estimate"
    assert snippets =~ "mcpServers"
    assert snippets =~ "est_YOUR_KEY"
    # hint shown only while no plaintext key is on screen
    assert snippets =~ "placeholder"
    refute html =~ "Copied to clipboard"
  end

  test "after generate, snippets carry the real key; after remount, placeholder again", %{
    conn: conn,
    org: org
  } do
    {:ok, lv, _} = live(conn, ~p"/org/#{org.id}/settings/mcp")

    html = lv |> element("button", "Generate API Key") |> render_click()
    assert [_, key] = Regex.run(~r/(est_[A-Za-z0-9_-]{43})/, html)

    snippets = lv |> element("#mcp-setup-snippets") |> render()
    assert snippets =~ "Bearer #{key}"
    refute snippets =~ "est_YOUR_KEY"

    {:ok, lv2, _} = live(conn, ~p"/org/#{org.id}/settings/mcp")
    snippets2 = lv2 |> element("#mcp-setup-snippets") |> render()
    refute snippets2 =~ key
    assert snippets2 =~ "est_YOUR_KEY"
  end

  test "copy url pushes clipboard payload and flashes", %{conn: conn, org: org} do
    {:ok, lv, html} = live(conn, ~p"/org/#{org.id}/settings/mcp")
    refute html =~ "Copied to clipboard"

    html =
      lv
      |> element(~s(button[phx-click="copy"][phx-value-what="url"]))
      |> render_click()

    assert_push_event(lv, "copy_to_clipboard", %{text: text})
    assert text == url(~p"/mcp")
    assert html =~ "Copied to clipboard"
  end

  test "copy json yields valid mcpServers JSON with the real key after generate", %{
    conn: conn,
    org: org
  } do
    {:ok, lv, _} = live(conn, ~p"/org/#{org.id}/settings/mcp")
    html = lv |> element("button", "Generate API Key") |> render_click()
    assert [_, key] = Regex.run(~r/(est_[A-Za-z0-9_-]{43})/, html)

    lv |> element(~s(button[phx-click="copy"][phx-value-what="json"])) |> render_click()

    assert_push_event(lv, "copy_to_clipboard", %{text: json})

    assert %{
             "mcpServers" => %{
               "estimate" => %{
                 "type" => "http",
                 "url" => mcp_url,
                 "headers" => %{"Authorization" => auth}
               }
             }
           } = Jason.decode!(json)

    assert mcp_url == url(~p"/mcp")
    assert auth == "Bearer #{key}"
  end

  test "copy cli pushes the claude mcp add command with placeholder when no reveal", %{
    conn: conn,
    org: org
  } do
    {:ok, lv, _} = live(conn, ~p"/org/#{org.id}/settings/mcp")

    lv |> element(~s(button[phx-click="copy"][phx-value-what="cli"])) |> render_click()

    assert_push_event(lv, "copy_to_clipboard", %{text: text})

    assert text ==
             ~s(claude mcp add --transport http estimate #{url(~p"/mcp")} ) <>
               ~s(--header "Authorization: Bearer est_YOUR_KEY")
  end

  test "copy key pushes the plaintext only while revealed; forged copy without reveal is a no-op",
       %{conn: conn, org: org} do
    {:ok, lv, _} = live(conn, ~p"/org/#{org.id}/settings/mcp")

    # forged: no key generated, button not rendered → handler must not crash/flash
    html = render_click(lv, "copy", %{"what" => "key"})
    refute html =~ "Copied to clipboard"

    html = lv |> element("button", "Generate API Key") |> render_click()
    assert [_, key] = Regex.run(~r/(est_[A-Za-z0-9_-]{43})/, html)

    html =
      lv
      |> element(~s(button[phx-click="copy"][phx-value-what="key"]))
      |> render_click()

    assert_push_event(lv, "copy_to_clipboard", %{text: ^key})
    assert html =~ "Copied to clipboard"
  end

  test "unknown copy target is a no-op", %{conn: conn, org: org} do
    {:ok, lv, _} = live(conn, ~p"/org/#{org.id}/settings/mcp")

    html = render_click(lv, "copy", %{"what" => "bogus"})
    refute html =~ "Copied to clipboard"
  end
end
```

- [ ] **Step 2: Run tests to verify failures**

Run: `mix test test/estimate_web/live/settings_live/mcp_test.exs`
Expected: every new test fails (`#mcp-setup-snippets` empty, no copy buttons, no `"copy"` handler → the forged-event tests fail with an unhandled-event crash, which is the correct failing signal).

- [ ] **Step 3: Implement snippets, components, and copy handler**

In `lib/estimate_web/live/settings_live/mcp.ex`:

3a. Replace `<div id="mcp-setup-snippets"></div>` with:

```heex
<div id="mcp-setup-snippets" class="mt-6 pt-6 border-t border-base-300">
  <h3 class="text-sm font-medium text-base-content mb-1">Setup</h3>
  <p :if={@new_key == nil} class="text-sm text-base-content/60 mb-3">
    <code class="font-mono text-xs">est_YOUR_KEY</code>
    is a placeholder — generate or regenerate a key to fill it in.
  </p>
  <p :if={@new_key} class="text-sm text-base-content/60 mb-3">
    Snippets below include your new key.
  </p>
  <.snippet
    label="Claude Code"
    text={cli_snippet(@mcp_url, display_key(@new_key))}
    what="cli"
  />
  <.snippet
    label="Claude Desktop / Cursor / .mcp.json"
    text={json_snippet(@mcp_url, display_key(@new_key))}
    what="json"
  />
</div>
```

3b. In the claude.ai card, wrap the URL code block with a copy button (replace the bare `<code>` line):

```heex
<div class="flex items-start gap-2">
  <code class="flex-1 block font-mono text-sm bg-base-200/60 rounded-lg p-3 select-all">{@mcp_url}</code>
  <.copy_button what="url" />
</div>
```

3c. In the new-key reveal panel, put the key and a copy button on one row (replace the bare key `<code>` line):

```heex
<div class="flex items-start gap-2 mb-3">
  <code class="flex-1 block font-mono text-sm break-all select-all">{@new_key}</code>
  <.copy_button what="key" />
</div>
```

3d. Add private components above `mount/3`:

```elixir
attr :what, :string, required: true

defp copy_button(assigns) do
  ~H"""
  <button
    phx-click="copy"
    phx-value-what={@what}
    class="shrink-0 text-base-content/40 hover:text-base-content/70 transition-colors"
    aria-label="Copy to clipboard"
    title="Copy"
  >
    <.icon name="hero-clipboard-document" class="w-4 h-4" />
  </button>
  """
end

attr :label, :string, required: true
attr :text, :string, required: true
attr :what, :string, required: true

defp snippet(assigns) do
  ~H"""
  <div class="mb-4 last:mb-0">
    <div class="text-xs font-medium text-base-content/60 mb-1">{@label}</div>
    <div class="flex items-start gap-2">
      <code class="flex-1 block font-mono text-xs bg-base-200/60 rounded-lg p-3 break-all whitespace-pre-wrap select-all">{@text}</code>
      <.copy_button what={@what} />
    </div>
  </div>
  """
end
```

3e. Add the copy handler next to the other `handle_event` clauses, and helpers at the bottom of the module:

```elixir
@impl true
def handle_event("copy", %{"what" => what}, socket) do
  case copy_text(what, socket.assigns) do
    nil ->
      {:noreply, socket}

    text ->
      {:noreply,
       socket
       |> push_event("copy_to_clipboard", %{text: text})
       |> put_flash(:info, "Copied to clipboard")}
  end
end
```

```elixir
@placeholder_key "est_YOUR_KEY"

# Copy payloads are recomputed from assigns — the client only names a target.
defp copy_text("url", %{mcp_url: url}), do: url
defp copy_text("key", %{new_key: key}), do: key
defp copy_text("cli", %{mcp_url: url, new_key: key}), do: cli_snippet(url, display_key(key))
defp copy_text("json", %{mcp_url: url, new_key: key}), do: json_snippet(url, display_key(key))
defp copy_text(_, _), do: nil

defp display_key(nil), do: @placeholder_key
defp display_key(key), do: key

defp cli_snippet(url, key) do
  ~s(claude mcp add --transport http estimate #{url} --header "Authorization: Bearer #{key}")
end

defp json_snippet(url, key) do
  Jason.encode!(
    %{
      "mcpServers" => %{
        "estimate" => %{
          "type" => "http",
          "url" => url,
          "headers" => %{"Authorization" => "Bearer " <> key}
        }
      }
    },
    pretty: true
  )
end
```

(`copy_text("key", …)` returns `nil` when `@new_key` is `nil` — the case clause then skips push + flash, which is what the forged-event test asserts.)

- [ ] **Step 4: Run the full file**

Run: `mix test test/estimate_web/live/settings_live/mcp_test.exs`
Expected: all pass, including pre-existing tests. If `"generate shows plaintext once; remount shows only prefix"` fails on the remount refute: check the snippets are rendering `display_key(@new_key)` and not the stored key — remount must show `est_YOUR_KEY`.

- [ ] **Step 5: Full suite + format**

Run: `mix format && mix test`
Expected: no formatting diff beyond touched files; full suite green.

- [ ] **Step 6: Commit**

```bash
git add lib/estimate_web/live/settings_live/mcp.ex test/estimate_web/live/settings_live/mcp_test.exs
git commit -m "feat: MCP setup snippets (CLI + mcpServers JSON) with copy buttons

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Browser verification

**Files:** none (verification only)

- [ ] **Step 1: Dev-verify in the preview browser**

Start dev server via preview_start name `estimate` (`.claude/launch.json`, port 4000; needs docker postgres `estimate-postgres` on 5499 running). Log in as `ui-verify@example.com` / `hello_world!` (org "UI Verify Org"; this user is org owner there). Visit that org's `/settings/mcp` and verify: rail order AI · MCP · Email; three flat cards; URL once, with copy button; generate key → reveal panel + snippets show real key; each copy button flashes "Copied to clipboard"; dismiss → snippets fall back to `est_YOUR_KEY`. Screenshot for the user.
