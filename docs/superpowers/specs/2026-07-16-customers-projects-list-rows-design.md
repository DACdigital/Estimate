# Customers + Projects list rows — redesign spec

Date: 2026-07-16
Status: approved in brainstorm (mockups: `.superpowers/brainstorm/96813-1784181243/content/`)

## Problem

Customers index feels unfinished despite sharing the Projects layout skeleton. Root causes:

1. One-line rows in a two-line template — `description` usually empty, so rows are tall, sparse, ragged.
2. No right-side anchor — cryptic `IT EUR` micro-codes at 40% opacity vs Projects' colored status pill.
3. Triple identity redundancy on the left edge — avatar initials + key column + name say the same thing three times; bare customer key (unlike Projects' composite key) adds no info.
4. Monochrome avatars — all 6 `@customer_gradients` are emerald/teal/green/cyan; zero per-row recognition.
5. Zero relationship data — header says "Manage your customer relationships", rows show none.

## Decisions (user-approved)

- Direction: "fill the row", variant **A** (key in meta line) — picked from mockups.
- Project-count pill on customer rows: **yes**; always rendered, `0 projects` extra-muted (hiding at 0 re-creates the ragged right edge).
- Country: 2-letter code only, moved into meta line. No flags.
- Avatars: one broad **entity palette** shared by customer + project avatars; **user avatars keep purple family**; `:pending` unchanged.
- Projects index adopts the same anatomy (its key column dies too) — consistency both ways.
- Right-side order on both screens: `currency · pill · pencil` (Projects' current order; Customers flips).

## Shared row anatomy

```
[avatar :lg]  Name (text-sm font-medium truncate)          CUR  [pill]  ✎
              meta line (always present, truncate)
```

- Whole row stays a `navigate` link to show page; pencil stays admin-only patch to `:edit` (Customers) / edit route (Projects).
- Card container, row padding, borders, hover: unchanged.

### Customers meta line

- `description` if present — `text-sm text-base-content/60` (as today).
- Else `KEY · CC · domain` — key + country code in `font-mono text-xs text-base-content/40`, domain `text-base-content/55`; `·` separators at /25. Missing parts omitted (e.g. `BRG · US` when no website).
- `domain` = `website_url` minus scheme, leading `www.`, trailing slash/path. Pure web-layer helper fn (place per existing `live/helpers` convention) + unit tests.
- Separate `w-12` key column: **removed**.

### Projects meta line

- `COMPOSITE-KEY · Customer Name` — key mono muted, customer name `text-sm /60`.
- Replaces both the `w-20` key column and the current customer-name subtitle. Status pill, filter pills, watchtower: unchanged.

### Count pill (Customers)

- `N projects` / `1 project` / `0 projects`; same shape as status pill (`text-xs px-2 py-0.5 rounded-full`), neutral `bg`-muted styling; `0 projects` drops text emphasis further (e.g. /40).

## Data

- `CRM.list_customers/1,2` additionally returns per-customer project count — LEFT JOIN + `count` (or `select_merge` subquery). Keep `Repo.ensure_org_context`, org filter, ordering, `default_currency` preload, watchtower filter intact.
- Expose count as `field :project_count, :integer, virtual: true` on `CRM.Customer` (schema-module-only change; **no migrations/DB changes** — respects data-model constraint).

## Avatars (`core_components.ex`)

- New `@entity_gradients` (~12 gradients, broad hue spread: sky/blue, amber/orange, violet/purple, emerald/teal, rose/pink, cyan/sky, indigo/blue, orange/red, teal/cyan, fuchsia/purple, lime/green, blue/indigo).
- `:customer` → entity palette (replaces `@customer_gradients`). New `:project` type → entity palette; add `type={:project}` at project avatar call sites (sweep call sites during implementation).
- Default (user) keeps `@user_gradients`; `:pending` unchanged. Selection stays `:erlang.phash2(seed, len)`.

## Out of scope

Modals, watchtower banners, empty states, show pages, sorting, search, initials algorithm, any DB schema change.

## Testing

- Update index LV tests touching removed key columns; add coverage: count pill (0/1/N), meta-line fallback chain (desc → key·cc·domain → partial), domain helper units, avatar type→palette mapping.
- Follow characterization no-tautology rule (diverge assigns from mount defaults before asserting).
