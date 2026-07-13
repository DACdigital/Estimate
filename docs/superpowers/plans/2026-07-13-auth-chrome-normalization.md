# Auth Cluster — Chrome Normalization (`<.auth_header>` / `<.auth_submit>` / `<.oauth_section>`)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Before writing component/HEEx code invoke `elixir-phoenix-guide:phoenix-liveview-essentials`; before a `_test.exs` invoke `:testing-essentials`. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Extract three shared chrome components and adopt them across the 7 centered auth-card screens, DRYing the repeated heading / submit-button / OAuth-section markup and converging its drift (subtitle `/60` vs `/70`, heading margins `mb-8`/`mb-2`/`mb-4`, submit top-margins) to one canonical look.

**Architecture:** Continuation of the approved combined structure + visual-normalization pass for the auth cluster. Behavior preserved (pinned by the merged auth characterization suite + smoke tests); appearance converges to canonical. Settings-layout screens (`account_settings.ex`, `totp_setup.ex`) remain OUT (settings cluster). Alt-links footer (variant-heavy) and `registration.ex`/`account_settings.ex` decomposition are deferred to follow-ups.

**Tech Stack:** Elixir ~> 1.15, Phoenix 1.8, Phoenix.LiveView 1.1, existing `<.or_divider>`/`<.google_button>` components.

## Global Constraints
- Behavior-preserving; visual convergence accepted. No event/param/flash/redirect/route change. Controller-post forms (login, totp_verification) keep `phx-update="ignore"` and their `action=`/`method="post"` — only the inner heading/button/oauth markup changes.
- No DB schema/migration changes; no new deps.
- Gate: auth characterization + smoke suites stay green; `mix compile --warnings-as-errors` clean. (Note: `mix test` unmatched-path prints a non-fatal warning — treat "did not match any file" as a stop-and-fix.)
- Branch `refactor/auth-chrome`, off merged master.

**Canonical values (converge to these):**
- Heading: `text-3xl font-bold text-center text-base-content`; margin `mb-2` when a subtitle follows, else `mb-8`. (Drop the `mb-4` outlier in `join_request_live/new.ex:91`.)
- Subtitle: `text-center text-base-content/60 mb-8` (converge the `/70` invite/join subtitles to `/60`).
- Submit: `w-full py-3 px-4 bg-neutral text-neutral-content font-medium rounded-lg hover:bg-neutral/90 transition-colors` (drop ad-hoc `mt-6`/`mt-2` — the form's `space-y-4` provides spacing).
- OAuth: `<.or_divider />` + `<div class="space-y-3"><.google_button href={~p"/auth/google"} /></div>`.

---

### Task 1: chrome components + tests

**Files:**
- Modify: `lib/estimate_web/components/core_components.ex` (add `auth_header/1`, `auth_submit/1`, `oauth_section/1` near `auth_input/1`)
- Test: `test/estimate_web/components/auth_chrome_test.exs` (create)

**Interfaces (produced, auto-imported via CoreComponents):**
- `<.auth_header title="...">` with optional `<:subtitle>...</:subtitle>` slot.
- `<.auth_submit loading="Saving...">Label</.auth_submit>` (loading → `phx-disable-with`; omit for controller-post buttons).
- `<.oauth_section href={~p"/auth/google"} />`.

- [ ] **Step 0:** Invoke `elixir-phoenix-guide:phoenix-liveview-essentials`; then `:testing-essentials` before the test.

- [ ] **Step 1: Add the components**
```elixir
  @doc """
  Centered auth-card heading with an optional subtitle.

  ## Examples

      <.auth_header title="Create your account" />
      <.auth_header title="Forgot your password?">
        <:subtitle>We'll send a reset link to your inbox</:subtitle>
      </.auth_header>
  """
  attr :title, :string, required: true
  slot :subtitle

  def auth_header(assigns) do
    ~H"""
    <h1 class={[
      "text-3xl font-bold text-center text-base-content",
      if(@subtitle != [], do: "mb-2", else: "mb-8")
    ]}>
      {@title}
    </h1>
    <p :if={@subtitle != []} class="text-center text-base-content/60 mb-8">
      {render_slot(@subtitle)}
    </p>
    """
  end

  @doc """
  Full-width primary submit button for auth-card forms.

  ## Examples

      <.auth_submit loading="Creating account...">Create Account</.auth_submit>
      <.auth_submit>Continue with Email</.auth_submit>
  """
  attr :loading, :string, default: nil, doc: "phx-disable-with text; omit for controller-post forms"
  attr :rest, :global
  slot :inner_block, required: true

  def auth_submit(assigns) do
    ~H"""
    <button
      type="submit"
      phx-disable-with={@loading}
      class="w-full py-3 px-4 bg-neutral text-neutral-content font-medium rounded-lg hover:bg-neutral/90 transition-colors"
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  OAuth divider + Google button for auth-card screens.

  ## Examples

      <.oauth_section href={~p"/auth/google"} />
  """
  attr :href, :string, required: true

  def oauth_section(assigns) do
    ~H"""
    <.or_divider />
    <div class="space-y-3">
      <.google_button href={@href} />
    </div>
    """
  end
```
Note: `phx-disable-with={nil}` renders no attribute (HEEx omits nil attrs), so `<.auth_submit>` without `loading` is a plain submit button — correct for the login / totp_verification controller-post forms.

- [ ] **Step 2: Test** — create `test/estimate_web/components/auth_chrome_test.exs`:
```elixir
defmodule EstimateWeb.CoreComponents.AuthChromeTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias EstimateWeb.CoreComponents

  test "auth_header without subtitle uses mb-8 and no <p>" do
    html = render_component(&CoreComponents.auth_header/1, %{title: "Create your account", subtitle: []})
    assert html =~ "Create your account"
    assert html =~ "mb-8"
    refute html =~ "text-base-content/60"
  end

  test "auth_header with subtitle uses mb-2 heading + /60 subtitle" do
    html =
      render_component(&CoreComponents.auth_header/1, %{
        title: "Forgot your password?",
        subtitle: [%{inner_block: fn _, _ -> "We'll send a reset link" end}]
      })

    assert html =~ "Forgot your password?"
    assert html =~ "mb-2"
    assert html =~ "text-center text-base-content/60 mb-8"
    assert html =~ "We&#39;ll send a reset link" or html =~ "We'll send a reset link"
  end

  test "auth_submit with loading sets phx-disable-with" do
    html =
      render_component(&CoreComponents.auth_submit/1, %{
        loading: "Creating account...",
        inner_block: [%{inner_block: fn _, _ -> "Create Account" end}]
      })

    assert html =~ ~s(phx-disable-with="Creating account...")
    assert html =~ "Create Account"
    assert html =~ "bg-neutral"
  end

  test "auth_submit without loading omits phx-disable-with" do
    html =
      render_component(&CoreComponents.auth_submit/1, %{
        inner_block: [%{inner_block: fn _, _ -> "Continue with Email" end}]
      })

    refute html =~ "phx-disable-with"
    assert html =~ "Continue with Email"
  end

  test "oauth_section renders divider + google button" do
    html = render_component(&CoreComponents.oauth_section/1, %{href: "/auth/google"})
    assert html =~ "/auth/google"
  end
end
```

- [ ] **Step 3:** Run `mix test test/estimate_web/components/auth_chrome_test.exs`. If a `render_component` slot-shape assertion mismatches actual output, adjust the TEST to real output (component bodies are canonical). Then `mix compile --warnings-as-errors --force` clean.

- [ ] **Step 4: Commit**
```bash
git add lib/estimate_web/components/core_components.ex test/estimate_web/components/auth_chrome_test.exs
git commit -m "feat: add auth chrome components (header, submit, oauth_section)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Adopt on anonymous auth-card screens

**Files (modify):** `registration.ex`, `login.ex`, `forgot_password.ex`, `reset_password.ex` (all `lib/estimate_web/live/user_live/`).

Per screen, replace the raw chrome with the components (read each screen for the exact heading text / submit label):
- **registration.ex** — `<h1 ...mb-8>Create your account</h1>` → `<.auth_header title="Create your account" />`; submit button (`phx-disable-with="Creating account..."`) → `<.auth_submit loading="Creating account...">Create Account</.auth_submit>`; the `<.or_divider/>` + google `<div>` block → `<.oauth_section href={~p"/auth/google"} />`.
- **login.ex** — heading → `<.auth_header title="Log in to EstiMate" />`; submit (controller-post, no `phx-disable-with`) → `<.auth_submit>Continue with Email</.auth_submit>`; oauth block → `<.oauth_section href={~p"/auth/google"} />`. Keep the `<form action=... method="post" phx-update="ignore">` wrapper unchanged.
- **forgot_password.ex** — `<h1 ...mb-2>` + subtitle `<p ...>` → `<.auth_header title="...">` `<:subtitle>...</:subtitle>` `</.auth_header>`; submit (`phx-disable-with="Sending..."`) → `<.auth_submit loading="Sending...">...</.auth_submit>`. No oauth.
- **reset_password.ex** — heading (`mb-8`, no subtitle) → `<.auth_header title="Reset Password" />`; submit (`Resetting...`) → `<.auth_submit loading="Resetting...">Reset Password</.auth_submit>`. No oauth.

Do NOT touch the alt-links footer `<p class="mt-8 ...">` blocks (deferred). Do NOT touch forms/inputs/events.

- [ ] **Step 1:** Invoke `elixir-phoenix-guide:phoenix-liveview-essentials`; apply the replacements (converge margins/colors to canonical via the components).
- [ ] **Step 2:** `mix test test/estimate_web/live/user_live/password_reset_test.exs test/estimate_web/live/auth_smoke_test.exs test/estimate_web/controllers/user_session_controller_test.exs test/estimate_web/components/auth_chrome_test.exs` — all green.
- [ ] **Step 3:** Full suite + `mix compile --warnings-as-errors --force`. Green.
- [ ] **Step 4: Commit** `refactor: adopt auth chrome components on anonymous auth-card screens`

---

### Task 3: Adopt on invite / join-request / TOTP-verify

**Files (modify):** `invite_live/accept.ex`, `join_request_live/new.ex`, `user_live/totp_verification.ex`.

These have **multiple render branches** (invite: 3 headings; join: 3 headings incl. the `mb-4` outlier + `/70` subtitles). Replace EACH branch's heading (+ subtitle) with `<.auth_header>`, converging `/70`→`/60` and dropping the `mb-4` outlier. Replace submit buttons with `<.auth_submit>` (invite/join register branches use `loading="Creating account..."`; other action buttons use their existing label + appropriate loading text, or none for non-disabling ones). Replace the invite/join OAuth blocks with `<.oauth_section href={~p"/auth/google"} />`. For **totp_verification.ex** (controller-post): heading + subtitle → `<.auth_header>`; submit (no `phx-disable-with`) → `<.auth_submit>...</.auth_submit>`; keep `phx-update="ignore"` + `@use_backup` conditional; no oauth.

- [ ] **Step 1:** Invoke `elixir-phoenix-guide:phoenix-liveview-essentials`; apply per-branch. Preserve every event/link/`@use_backup`/readonly and the alt-links footers (deferred).
- [ ] **Step 2:** `mix test test/estimate_web/live/onboarding_test.exs test/estimate_web/controllers/user_session_controller_test.exs test/estimate_web/live/auth_smoke_test.exs` — green (invite email-forcing must still pass).
- [ ] **Step 3:** Full suite + compile. Green.
- [ ] **Step 4: Commit** `refactor: adopt auth chrome components on invite/join/TOTP-verify`

---

## Self-Review
**Coverage:** DRYs + converges the auth heading / submit / OAuth chrome across the 7 auth-card screens via 3 components. Deferred (documented): alt-links footer (variant-heavy: single / double `Sign Up | Sign In` / "Back to login"), `registration.ex`/`account_settings.ex` decomposition, non-atomic-registration fix, settings-layout screens.
**Placeholder scan:** components + tests complete; adoption is a concrete per-screen mapping (implementer supplies each screen's literal heading text/label, read from the file).
**Consistency:** `auth_header` (title + optional subtitle slot), `auth_submit` (optional loading), `oauth_section` (href) used uniformly. Controller-post forms keep their wrappers; only inner chrome swapped.
**Visual convergence (intended):** subtitle `/70`→`/60`; heading `mb-4` outlier→canonical; submit `mt-*` dropped. Recommend a browser pass on the 7 screens after merge.
