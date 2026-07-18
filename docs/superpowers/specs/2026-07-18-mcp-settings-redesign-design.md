# MCP Settings Page Redesign

**Date:** 2026-07-18
**Status:** Approved
**Scope:** `lib/estimate_web/live/settings_live/mcp.ex`, `lib/estimate_web/components/layouts.ex` (rail order), `test/estimate_web/live/settings_live/mcp_test.exs`

## Problem

1. MCP page breaks the settings design language: AI/Email use one flat card; MCP stacks cards and nests a card-in-card ("Connect from claude.ai" inset inside the API-key card, unrelated to keys).
2. MCP URL rendered twice (toggle card + claude.ai box), copyable only via invisible `select-all`.
3. Setup help (`claude mcp add …`) exists only inside the one-time new-key reveal; gone after Dismiss.
4. Rail order AI · Email · MCP splits the two AI-adjacent pages.
5. No `mcpServers` JSON snippet for Claude Desktop / Cursor / `.mcp.json`.

## Design

### Rail (layouts.ex)

Integrations order becomes **AI · MCP · Email**. Visibility rules unchanged (AI/Email admin-only, MCP for all).

### MCP page — 3 flat sibling cards (`bg-base-100 border border-base-300 rounded-xl p-6`)

Header (h1 + subtitle) unchanged.

**Card 1 — Server (admin-only).** Enabled/disabled title, explainer, Enable/Disable button. URL line REMOVED (dedupe). Non-admin + disabled: existing notice card, unchanged.

**Card 2 — Connect from claude.ai (when enabled).** Own flat card (no inset). Explainer + URL code block + copy icon-button.

**Card 3 — API clients (when enabled).** Title "API clients", subtitle "Claude Code, Claude Desktop, Cursor — authenticate with your personal key. The key acts as you: it sees exactly what you see in the app."

- Key row: prefix…, created, last-used, Regenerate/Revoke with data-confirm (unchanged), or Generate button when no key.
- New-key reveal panel (warning style): plaintext key + copy icon-button + Dismiss. Same lifecycle as today (`@new_key`, cleared on dismiss/toggle).
- **Setup snippets — always visible while enabled**, each a labeled code block with copy icon-button:
  - Claude Code: `claude mcp add --transport http estimate <url> --header "Authorization: Bearer <key>"`
  - Claude Desktop / Cursor / `.mcp.json`:
    ```json
    {
      "mcpServers": {
        "estimate": {
          "type": "http",
          "url": "<url>",
          "headers": { "Authorization": "Bearer <key>" }
        }
      }
    }
    ```
  - `<key>` = plaintext key while `@new_key` set; else literal placeholder `est_YOUR_KEY` plus hint "Generate/regenerate a key to fill this in."

### Copy mechanism

Existing app pattern (invites): `phx-click` → server `handle_event("copy_" <> what)` → `push_event("copy_to_clipboard", %{text: …})` + flash "Copied to clipboard". One event with a `value` param distinguishing url / key / cli / json. Server recomputes snippet text from assigns (never trusts client payload).

Icon buttons per app pattern: `hero-clipboard-document w-4 h-4`, color-only hover (`text-base-content/40 hover:text-base-content/70 transition-colors`), no box.

Private function components in mcp.ex: `copy_button`, `snippet` (label + code + copy). No cross-page refactor.

### Security

- Plaintext key present in snippets only while `@new_key` assigned — same exposure window as today.
- Copy events for key-bearing snippets require `@new_key` (else placeholder text is copied).
- `require_mcp_enabled` / `require_admin` guards unchanged.

### Out of scope

AI page, invites copy refactor, DB/schema changes (none needed), OAuth flows.

## Testing

Update `mcp_test.exs` (+ layouts/settings-nav test if rail order asserted elsewhere):

- Rail renders AI · MCP · Email in order.
- URL appears once (claude.ai card), not in server card.
- Snippets render with `est_YOUR_KEY` placeholder when no `@new_key`; real key after generate (diverge-then-assert, no tautology).
- Both snippets present: CLI command and mcpServers JSON (valid JSON when decoded with key substituted).
- Copy events push `copy_to_clipboard` with expected text and set flash.
- Existing guards still hold: non-admin sees no toggle; disabled non-admin sees notice; generate/revoke flows unchanged.
