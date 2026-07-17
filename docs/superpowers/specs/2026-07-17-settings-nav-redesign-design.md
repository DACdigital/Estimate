# Settings Navigation Redesign — Design

**Date:** 2026-07-17
**Status:** Approved (brainstorm + visual mockups), pending implementation plan

## Goal

De-clutter the global sidebar and give settings an intuitive, role-aware home. The six flat settings links collapse into one **Settings** entry; the settings area gets a Linear-style **secondary rail** grouped by concern, animated on entry, with members and admins each seeing exactly what they can use.

## Decisions (from brainstorm + mockups)

| Question | Decision |
|---|---|
| Structure | One "Settings" sidebar entry → settings area with secondary rail beside content (mockup option A) |
| Grouping | **Workspace**: General · Members · Currencies · Trash — **Integrations**: AI · Email · MCP |
| Trash | Gets a rail link (fixes today's orphaned page), admin-only |
| Role experience | Admin-only items **hidden, not locked** (existing philosophy). Member rail: General (read-only page), Members, Currencies, MCP. Admin rail: all 7 |
| Animation | Rail slides in on entering settings: 180ms ease-out, fade + 12px from left. No replay between settings pages. No exit animation |
| Mobile | No mobile-specific work (app has no mobile drawer today) |
| Routes / data model | Unchanged. No new pages; MCP/AI/Email/General/Members/Currencies/Trash keep their URLs and internals |

## UI Structure

**Global sidebar** (`lib/estimate_web/components/layouts/app.html.heex`): the SETTINGS group block (currently 6 `sidebar_child_link`s under a group header) is replaced by a single top-level entry — cog icon, label "Settings", `href={~p"/org/#{@org_id}/settings"}`, active when `assigns[:active_tab] == :settings` (every settings LV already assigns this). Dashboard/Customers/Projects/Library untouched.

**Settings rail**: rendered by the app layout only when `assigns[:settings_page]` is present (settings LVs assign it; non-settings LVs don't — exception: `SettingsLive.Trash` currently assigns only `active_tab` and must additionally get `assign(:settings_page, :trash)`). Sits between global sidebar and content: fixed-width (~13rem) column, group headers in the existing tiny-uppercase style, items styled like current `sidebar_child_link` with the same active treatment keyed on `@settings_page` (`:general | :members | :currencies | :trash | :ai | :email | :mcp`). Admin-only items (`Trash`, `AI`, `Email`) wrapped in the existing `admin?/1` gate. Implemented as one function component (e.g. `Layouts.settings_rail/1`) so the layout stays thin.

**Content column**: unchanged pages; each keeps its own `h1` header.

## Animation Contract

- CSS keyframes `settings-rail-in` in `assets/css/app.css`: `from {opacity: 0; transform: translateX(-12px)}` → `to {opacity: 1; transform: none}`, 180ms ease-out, applied to the rail root.
- The rail root carries a **stable DOM id** (`id="settings-rail"`). All settings LVs share the `:org_scoped` live_session and layout; LiveView morphdom persists the element across settings-to-settings navigations, so the keyframe plays only when the rail is first inserted (entering settings from elsewhere) — no flicker or replay while moving between settings pages. Leaving settings removes it instantly (no exit animation), consistent with every other page switch.

## Role Matrix (rail visibility)

| Item | Member | Admin |
|---|---|---|
| General | ✓ (page read-only) | ✓ |
| Members | ✓ | ✓ |
| Currencies | ✓ | ✓ |
| Trash | hidden | ✓ |
| AI | hidden | ✓ |
| Email | hidden | ✓ |
| MCP | ✓ (personal key) | ✓ |

Page-level guards are already in place (AI/Email/Trash mount-redirect non-admins; events `require_admin`-gated) — the rail only mirrors them; no authz change.

## Error Handling

None new — navigation only. Deep links to admin pages keep their existing redirect+flash behavior.

## Testing

- Layout: admin sees the single Settings entry + full rail (7 items incl. Trash); member rail omits Trash/AI/Email (discriminating assertions on absence); rail absent on non-settings pages (e.g. Dashboard); old sidebar settings links gone.
- Regression: existing settings LV tests keep passing (routes/pages untouched); update any test asserting the old sidebar link markup.
- Animation is CSS-only — assert the rail element carries the animation class/id, not the visual.
- Follow no-tautology discipline for visibility assertions (member fixtures with real role rows).

## Out of Scope

Mobile drawer, Library-section changes, merging settings pages, exit animations, breadcrumbs.
