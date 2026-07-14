# Auth — Decompose `account_settings.ex` + `registration.ex` (render into section components)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Before editing HEEx invoke `elixir-phoenix-guide:phoenix-liveview-essentials`. Steps use checkbox (`- [ ]`).

**Goal:** Make the two busiest auth LiveViews readable by extracting their `render/1` sections into private function components in the same module — a thin `render/1` that composes `<.profile_card/>` / `<.password_card/>` / `<.two_factor_card/>` and `<.invite_code_field/>` / `<.org_name_field/>`. **Behavior-identical** (same markup emitted, same events); handlers stay in the LiveView and events bubble to them as before.

**Architecture:** Private function components (`defp name(assigns), do: ~H"..."`, called via `<.name .../>` within the same module — the pattern already used in `estimator_modals.ex`). Pure markup extraction: cut each section's HEEx into a component, declare its `attr`s, replace the section in `render/1` with the component tag passing the assigns it needs. No handler, event name, form, or assign changes.

**Tech Stack:** Elixir ~> 1.15, Phoenix.LiveView 1.1.

## Global Constraints
- **Behavior + visual identical.** The rendered HTML must be the same (this is organization, not restyle). Every `phx-click`/`phx-submit`/`phx-change`/`phx-value`/form `id`/`for` stays byte-identical, just relocated into the component. No new `phx-target` (events must keep bubbling to the LiveView).
- No DB/schema changes; no context/handler changes. `mix compile --warnings-as-errors` clean.
- Gate: the auth characterization + smoke suites stay green (esp. `account_security_test.exs`, `onboarding_test.exs`, `auth_smoke_test.exs`).
- Branch `refactor/auth-decompose`, stacked on `refactor/auth-finalize` (!6).

---

### Task 1: Decompose `account_settings.ex` (3 cards)

**Files:** Modify `lib/estimate_web/live/user_live/account_settings.ex`.

The `render/1` body has three cards (read the file for exact current line ranges): **Profile** (header w/ oauth badge, name input, disabled email display, save), **Password** (oauth-conditional header + current/new/confirm inputs + save), **2FA** (status badge, enable/disable buttons, the `@show_disable_form`-gated disable subform). Extract each into a private function component.

**Interfaces (produced, private to this module):**
- `<.profile_card name_form={@name_form} is_oauth={@is_oauth} current_user={@current_user} />`
- `<.password_card password_form={@password_form} is_oauth={@is_oauth} />`
- `<.two_factor_card totp_enabled={@totp_enabled} show_disable_form={@show_disable_form} current_user={@current_user} />`

- [ ] **Step 0:** Invoke `elixir-phoenix-guide:phoenix-liveview-essentials`.
- [ ] **Step 1:** For each card, add a private component (declare `attr`s; move the card's exact HEEx verbatim into `~H`). Example shape (fill body from the file verbatim):
```elixir
  attr :name_form, Phoenix.HTML.Form, required: true
  attr :is_oauth, :boolean, required: true
  attr :current_user, :map, required: true

  defp profile_card(assigns) do
    ~H"""
    <%!-- the exact Profile card markup, with @name_form/@is_oauth/@current_user --%>
    """
  end
```
Do the same for `password_card` (attrs `password_form`, `is_oauth`) and `two_factor_card` (attrs `totp_enabled`, `show_disable_form`, `current_user`). Keep every `phx-*`, form `for=`/`id=`, `:if` guard, and input verbatim.
- [ ] **Step 2:** Replace the three card blocks in `render/1` with:
```heex
    <.profile_card name_form={@name_form} is_oauth={@is_oauth} current_user={@current_user} />
    <.password_card password_form={@password_form} is_oauth={@is_oauth} />
    <.two_factor_card
      totp_enabled={@totp_enabled}
      show_disable_form={@show_disable_form}
      current_user={@current_user}
    />
```
(Keep the page header + outer wrapper in `render/1`.) Do NOT touch any `handle_event`/`mount`/helper.
- [ ] **Step 3:** Run `mix test test/estimate_web/live/user_live/account_security_test.exs test/estimate_web/live/account_smoke_test.exs` — green (2FA disable, password change, TOTP setup smoke all still work through the extracted components). Then full suite + `mix compile --warnings-as-errors --force`.
- [ ] **Step 4: Commit** `refactor: extract account_settings render into profile/password/2fa card components`.

---

### Task 2: Decompose `registration.ex` (branch fields)

**Files:** Modify `lib/estimate_web/live/user_live/registration.ex`.

The org/invite-code branch inside the form (the `@has_invite_code` if/else: invite-code input vs org-name input) is the extractable part. Extract the two branch bodies into private components; the toggle switch + user fields + oauth + footer stay in `render/1`.

**Interfaces (produced, private):**
- `<.invite_code_field invite_code={@invite_code} invite_code_error={@invite_code_error} />`
- `<.org_name_field org_form={@org_form} />`

- [ ] **Step 0:** Invoke `elixir-phoenix-guide:phoenix-liveview-essentials`.
- [ ] **Step 1:** Add the two private components (verbatim markup + attrs):
```elixir
  attr :invite_code, :string, required: true
  attr :invite_code_error, :string, default: nil

  defp invite_code_field(assigns) do
    ~H"""
    <%!-- the exact invite-code <.auth_input name="invite_code" ...> block, incl. its error <p> --%>
    """
  end

  attr :org_form, Phoenix.HTML.Form, required: true

  defp org_name_field(assigns) do
    ~H"""
    <%!-- the exact org-name <.auth_input field={@org_form[:name]} ...> block + the "invite team members later" helper <p> --%>
    """
  end
```
- [ ] **Step 2:** In `render/1`, replace the `@has_invite_code` branch bodies:
```heex
    <%= if @has_invite_code do %>
      <.invite_code_field invite_code={@invite_code} invite_code_error={@invite_code_error} />
    <% else %>
      <.org_name_field org_form={@org_form} />
    <% end %>
```
Keep the toggle switch, the "Organization" divider, user fields, submit, `<.oauth_section>`, and footer in `render/1`. Do NOT touch handlers.
- [ ] **Step 3:** Run `mix test test/estimate_web/live/onboarding_test.exs test/estimate_web/live/auth_smoke_test.exs` — green (registration render, invite-code toggle + submit, org path all still work). Then full suite + `mix compile --warnings-as-errors --force`.
- [ ] **Step 4: Commit** `refactor: extract registration invite-code/org-name branch into field components`.

---

## Self-Review
**Coverage:** completes the "finish auth" decomposition (option 1's structural half) — account_settings' 3 cards + registration's branch fields become named components, thinning both `render/1`s. Behavior-preserving (markup relocation only); pinned by the existing account-security + onboarding + smoke suites.
**Placeholder scan:** the component bodies are "move the exact current markup" (the implementer reads + relocates verbatim) — this is a faithful extraction, not a placeholder; attrs + composition tags are fully specified.
**Type consistency:** component names/attrs (`profile_card`/`password_card`/`two_factor_card`; `invite_code_field`/`org_name_field`) match their `render/1` call sites. All events keep bubbling to the LiveView (no `phx-target`).
