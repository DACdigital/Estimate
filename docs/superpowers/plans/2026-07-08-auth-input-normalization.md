# Auth Cluster — `<.auth_input>` Normalization

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Before writing any component/HEEx or `_test.exs`, invoke `elixir-phoenix-guide:phoenix-liveview-essentials` (and `:testing-essentials` for tests). Steps use checkbox (`- [ ]`) syntax.

**Goal:** Replace the 7 divergent raw auth-input markup patterns across the centered auth-card screens with a single canonical `<.auth_input>` component — DRYing ~17 inputs and unifying their (currently drifted) styling to one look.

**Architecture:** New `<.auth_input>` function component in `core_components.ex`, styled to the dominant "Class A" pattern (the auth-card look). Adopt it across the 7 `:auth`-layout screens. This is a **combined structure + visual-normalization** pass (user-approved): appearance on the drifted screens (login/forgot Class B, TOTP code inputs, invite readonly email) converges to the canonical style. **Behavior is unchanged** and stays pinned by the auth characterization suite (MR !3) + Phase-0 smoke tests. Settings-layout screens (`account_settings.ex`, `totp_setup.ex`) are OUT — they belong to the settings cluster.

**Tech Stack:** Elixir ~> 1.15, Phoenix 1.8, Phoenix.LiveView 1.1, Phoenix.HTML.FormField, ExUnit.

## Global Constraints

- **Behavior-preserving; visuals may converge.** No flash string, redirect, event, param name, or field `name=` may change. Input *styling* converges to the canonical look (that's the point). Every screen must still submit the same params.
- **Password inputs must never echo their value** (security). `<.auth_input>` omits `value` for `type="password"` regardless of source. (This makes `reset_password.ex`'s password field stop echoing — an intentional, accepted normalization + security improvement.)
- **Preserve every functional attr** on each input verbatim: `required`, `readonly`, `maxlength`, `minlength`, `inputmode`, `autocomplete`, `autofocus`, `pattern`. These ride through `<.auth_input>`'s `:rest`.
- **Preserve error TEXT** (tests assert on it): field errors via `translate_error`, explicit-string errors (`@invite_code_error`, TOTP `@error`) via the `error` attr.
- **No DB schema/migration changes. No new deps.**
- Gate: the auth characterization suite (`test/estimate_web/live/user_live/*`, `.../controllers/user_session_controller_test.exs`, `.../onboarding_test.exs`) + smoke suite must stay green. `mix compile --warnings-as-errors` clean.
- Branch `refactor/auth-forms`, stacked on `test/auth-characterization` (MR !3).

---

### Task 1: `<.auth_input>` component

**Files:**
- Modify: `lib/estimate_web/components/core_components.ex` (add `auth_input/1`)
- Test: `test/estimate_web/components/auth_input_test.exs` (create)

**Interfaces:**
- Produces: `auth_input/1` — a function component (auto-imported app-wide via `EstimateWeb.CoreComponents`). Two call conventions:
  - Form-backed: `<.auth_input field={@form[:email]} type="email" placeholder="Email Address" required />`
  - Raw + explicit error: `<.auth_input name="code" value={@code} error={@error} type="text" placeholder="000000" class="font-mono text-center" maxlength="6" />`

- [ ] **Step 0:** Invoke `elixir-phoenix-guide:phoenix-liveview-essentials`, then `:testing-essentials` before writing the test.

- [ ] **Step 1: Add the component** (place near `input/1` in `core_components.ex`):

```elixir
  @doc """
  Auth-card text/email/password input: placeholder-driven (no visible label),
  the shared auth styling, and inline error text.

  Accepts either a `field` (Phoenix.HTML.FormField) — errors are read and
  translated from it — or a raw `name`/`value` plus an explicit `error` string
  (for inputs not backed by a changeset, e.g. TOTP codes, invite codes).

  Password inputs never echo their value.

  ## Examples

      <.auth_input field={@form[:email]} type="email" placeholder="Email Address" required />
      <.auth_input name="code" value={@code} error={@error} placeholder="000000"
        class="font-mono tracking-[0.5em] text-center" maxlength="6" inputmode="numeric" />
  """
  attr :field, Phoenix.HTML.FormField, default: nil
  attr :type, :string, default: "text"
  attr :name, :string, default: nil
  attr :value, :any, default: nil
  attr :placeholder, :string, default: nil
  attr :error, :string, default: nil, doc: "explicit error for non-form-backed inputs"
  attr :class, :string, default: nil, doc: "extra input classes appended to the base"

  attr :rest, :global,
    include: ~w(required readonly disabled maxlength minlength inputmode autocomplete autofocus pattern)

  def auth_input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(:field, nil)
    |> assign_new(:name, fn -> field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> assign(:field_errors, Enum.map(errors, &translate_error/1))
    |> auth_input()
  end

  def auth_input(assigns) do
    assigns = assign_new(assigns, :field_errors, fn -> [] end)

    ~H"""
    <div>
      <input
        type={@type}
        name={@name}
        value={if @type == "password", do: nil, else: @value}
        placeholder={@placeholder}
        class={[
          "w-full px-4 py-3 border rounded-lg text-base-content placeholder-base-content/60",
          @class,
          if(@error || @field_errors != [], do: "border-error", else: "border-base-content/20")
        ]}
        {@rest}
      />
      <p :if={@error} class="mt-1 text-sm text-error">{@error}</p>
      <p :for={msg <- @field_errors} class="mt-1 text-sm text-error">{msg}</p>
    </div>
    """
  end
```

- [ ] **Step 2: Write the test** — create `test/estimate_web/components/auth_input_test.exs`:

```elixir
defmodule EstimateWeb.CoreComponents.AuthInputTest do
  use EstimateWeb.ConnCase, async: true

  import Phoenix.Component, only: [to_form: 1]
  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias EstimateWeb.CoreComponents

  defp form_field(params, key) do
    to_form(params, as: :user)[key]
  end

  test "renders a raw input with name, placeholder, and base classes" do
    html =
      render_component(&CoreComponents.auth_input/1,
        name: "code",
        value: "123",
        placeholder: "000000",
        type: "text"
      )

    assert html =~ ~s(name="code")
    assert html =~ ~s(placeholder="000000")
    assert html =~ ~s(value="123")
    assert html =~ "border-base-content/20"
    refute html =~ "border-error"
  end

  test "renders an explicit error and switches the border" do
    html =
      render_component(&CoreComponents.auth_input/1,
        name: "invite_code",
        error: "Invalid or expired invite code"
      )

    assert html =~ "Invalid or expired invite code"
    assert html =~ "border-error"
  end

  test "password type never echoes a value" do
    html =
      render_component(&CoreComponents.auth_input/1,
        type: "password",
        name: "user[password]",
        value: "supersecret"
      )

    refute html =~ "supersecret"
  end

  test "appends extra classes" do
    html = render_component(&CoreComponents.auth_input/1, name: "code", class: "font-mono text-center")
    assert html =~ "font-mono"
    assert html =~ "text-center"
  end

  test "field-backed input renders translated field errors" do
    field = form_field(%{"email" => "bad"}, :email)
    field = %{field | errors: [{"can't be blank", []}]}

    html = render_component(&CoreComponents.auth_input/1, field: field, type: "email")

    assert html =~ ~s(name="user[email]")
    assert html =~ "border-error"
    assert html =~ "can&#39;t be blank" or html =~ "can't be blank"
  end

  test "passes through functional attrs" do
    html =
      render_component(&CoreComponents.auth_input/1,
        name: "code",
        maxlength: "6",
        inputmode: "numeric",
        required: true
      )

    assert html =~ ~s(maxlength="6")
    assert html =~ ~s(inputmode="numeric")
    assert html =~ "required"
  end
end
```

- [ ] **Step 3:** Run `mix test test/estimate_web/components/auth_input_test.exs`. Expected: PASS (6). If `render_component` needs `used_input?` to treat the field as used, and the field-error test shows no error, set the field's `errors` and ensure the assertion matches the actual translated/HTML-escaped output (adjust the expected string to the real render — the component body is canonical). Then `mix compile --warnings-as-errors --force` clean.

- [ ] **Step 4: Commit**
```bash
git add lib/estimate_web/components/core_components.ex test/estimate_web/components/auth_input_test.exs
git commit -m "feat: add <.auth_input> auth-card form input component

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Adopt on the anonymous auth-card screens

**Files (modify):** `registration.ex`, `login.ex`, `forgot_password.ex`, `reset_password.ex` (all under `lib/estimate_web/live/user_live/`).

Replace each raw `<input>...</input>` block (input + its wrapping `<div>` + its `<p :for>`/`<p :if>` error) with a single `<.auth_input>`. Mapping (exact — preserve every attr):

**registration.ex**
- name (33-45) → `<.auth_input field={@form[:name]} type="text" placeholder="Full Name" required />`
- email (47-59) → `<.auth_input field={@form[:email]} type="email" placeholder="Email Address" required />`
- password (61-72) → `<.auth_input field={@form[:password]} type="password" placeholder="Password" required />`
- invite_code (98-110) → `<.auth_input name="invite_code" value={@invite_code} error={@invite_code_error} type="text" placeholder="e.g. XK7F2MPA" maxlength="8" class="font-mono tracking-wider uppercase" />`
- organization[name] (112-125) → keep the trailing helper `<p class="mt-1 text-xs...">` OUTSIDE the component; input → `<.auth_input field={@org_form[:name]} type="text" placeholder="Organization Name" required />` (leave the "You can invite team members later" `<p>` right after it).

**login.ex** (Class B → canonical; no error rendering existed, and there's still no form errors here — fine)
- email (21-30) → `<.auth_input field={@form[:email]} type="email" placeholder="Email Address" required />`
- password (32-40) → `<.auth_input type="password" name="user[password]" placeholder="Password" required />` (no field/value — uncontrolled, preserved)

**forgot_password.ex**
- email (17-26) → `<.auth_input field={@form[:email]} type="email" placeholder="Email Address" required />`

**reset_password.ex**
- password (26-38) → `<.auth_input field={@form[:password]} type="password" placeholder="New password" required />`
- password_confirmation (40-52) → `<.auth_input field={@form[:password_confirmation]} type="password" placeholder="Confirm new password" required />`

- [ ] **Step 1:** Invoke `elixir-phoenix-guide:phoenix-liveview-essentials`. Apply the replacements above. Do not touch the `<form>` tags, headings, submit buttons, oauth sections, or any `phx-*`/event wiring — only the input blocks.
- [ ] **Step 2:** Run the gating tests:
  `mix test test/estimate_web/live/user_live/password_reset_test.exs test/estimate_web/live/user_live/auth_smoke_test.exs test/estimate_web/controllers/user_session_controller_test.exs`
  Expected: all green (login controller, forgot/reset flows, smoke). If a test asserted a specific error string, confirm it still renders via `<.auth_input>`.
- [ ] **Step 3:** Full suite `mix test` + `mix compile --warnings-as-errors --force`. Expected green.
- [ ] **Step 4: Commit**
```bash
git add lib/estimate_web/live/user_live/registration.ex lib/estimate_web/live/user_live/login.ex lib/estimate_web/live/user_live/forgot_password.ex lib/estimate_web/live/user_live/reset_password.ex
git commit -m "refactor: adopt <.auth_input> on anonymous auth-card screens

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Adopt on invite / join-request / TOTP-verify

**Files (modify):** `invite_live/accept.ex`, `join_request_live/new.ex`, `user_live/totp_verification.ex`.

**invite_live/accept.ex**
- name (44-56) → `<.auth_input field={@form[:name]} type="text" placeholder="Full Name" required />`
- email (58-71, readonly variant) → `<.auth_input field={@form[:email]} type="email" placeholder="Email Address" required value={@form[:email].value || @invite.email} readonly={@invite.email != nil} class={if @invite.email, do: "bg-base-200 text-base-content/60"} />` (preserve the readonly + muted-bg behavior; `value` override is needed here because it falls back to `@invite.email`)
- password (73-84) → `<.auth_input field={@form[:password]} type="password" placeholder="Password" required />`

**join_request_live/new.ex**
- name (54-66) → `<.auth_input field={@form[:name]} type="text" placeholder="Full Name" required />`
- email (68-80) → `<.auth_input field={@form[:email]} type="email" placeholder="Email Address" required />`
- password (82-93) → `<.auth_input field={@form[:password]} type="password" placeholder="Password" required />`

**totp_verification.ex** (raw code inputs, no form; use `name`)
- backup-code input (25-34) → `<.auth_input name="code" type="text" placeholder="Backup code" class="font-mono" autocomplete="one-time-code" autofocus />`
- TOTP-code input (36-47) → `<.auth_input name="code" type="text" placeholder="000000" class="text-center font-mono text-lg tracking-[0.5em]" maxlength="6" inputmode="numeric" autocomplete="one-time-code" autofocus />`

- [ ] **Step 1:** Invoke `elixir-phoenix-guide:phoenix-liveview-essentials`. Apply replacements. Do not change `<form>` tags, `phx-update="ignore"`, `@use_backup` conditionals, headings, or buttons.
- [ ] **Step 2:** Run gating tests:
  `mix test test/estimate_web/live/onboarding_test.exs test/estimate_web/controllers/user_session_controller_test.exs test/estimate_web/live/auth_smoke_test.exs`
  Expected green (invite email-forcing test especially — the readonly email must still submit `invite.email`; the forced-email + refute-typed-value assertions must still pass).
- [ ] **Step 3:** Full suite + `mix compile --warnings-as-errors --force`. Green.
- [ ] **Step 4: Commit**
```bash
git add lib/estimate_web/live/invite_live/accept.ex lib/estimate_web/live/join_request_live/new.ex lib/estimate_web/live/user_live/totp_verification.ex
git commit -m "refactor: adopt <.auth_input> on invite/join/TOTP-verify screens

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:** DRYs the dominant auth-input duplication (Class A ×11 + Class B ×3 + TOTP code inputs + invite readonly) into one `<.auth_input>`, adopted on all 7 auth-card screens. Deferred (documented): auth chrome (`<.auth_header>`/`<.auth_submit>`/`<.oauth_section>`/`<.auth_alt_links>`) → follow-up normalization plan; `account_settings.ex` + `totp_setup.ex` inputs → settings cluster (settings layout, not auth card); `registration.ex`/`account_settings.ex` decomposition → follow-up.

**Placeholder scan:** none — component + tests are complete; adoption is an exact per-input mapping table with all attrs specified.

**Type/consistency:** `auth_input/1` attrs (`field`/`type`/`name`/`value`/`placeholder`/`error`/`class`/`rest`) match every adoption call in Tasks 2–3. Password no-echo handled centrally. Explicit-error path used for `@invite_code_error` + TOTP `@error`; field-error path for changeset-backed inputs.

**Visual-normalization note (intentional, user-approved):** login/forgot inputs converge from Class B token-order to canonical; TOTP code inputs gain the canonical base + keep their mono/tracking extras; reset password stops echoing its value. These are the accepted appearance/behavior convergences. Recommend a manual visual pass on the 7 screens after merge (or via the preview tool) since tests assert behavior, not pixels.
