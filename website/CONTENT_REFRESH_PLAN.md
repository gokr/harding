# Website Content Refresh Plan

This plan summarizes what changed in Harding since the website content was last
substantially refreshed, and what the site should now communicate more clearly.

## Scope

Focus on active website content only:

- `website/content/index.md`
- `website/content/features.md`
- `website/content/docs.md`

Research docs under `docs/research/` are intentionally out of scope.

## Major Changes Since The Last Real Website Refresh

The site currently under-represents several additions that landed after the
earlier website content updates.

### 1. Web Stack

- MummyX HTTP server support
- request handling on scheduler-backed green workers
- HTMX fragment responses and out-of-band updates
- reactive server rendering with `RenderCache` + tracked state
- live-editable Todo app as the canonical web example

Key commits/features in this area include:

- `5adecfc` / `0aa2b0b` / `30b8665` / `942c084`
- `5c9d4dc` through `13c2149`
- `e853b1b`, `a747772`, `3189303`, `086daf6`

### 2. Language And Core Model

- direct slot access `::`
- canonical derive APIs
- lexical `self` cascade fix
- `&` as concatenation
- comma-separated `#(...)` literals
- simpler active Html rendering API

Representative commits:

- `870e4bd`
- `3189303`
- `2f1a2f8`
- `d30c131`, `e8cd0f1`

### 3. JSON And APIs

- `json{...}` literal support
- compiled JSON serialization for objects
- JSON API server tutorial and examples

Representative commits:

- `2ebf02c`
- `9fda881`
- `4aafdab`

### 4. External Libraries And Package Story

- external library management via `harding lib`
- BitBarrel moved external
- SQLite registry/docs
- Nim-Harding package workflow

Representative commits:

- `570349e`
- `ea4351e`
- `a28eae6`
- `75532cd`

### 5. IDE / Tooling

- Bona Application Builder
- stronger Browser / Inspector / GTK callback handling
- app templates and package examples

Representative commits:

- `c2cbdf1`
- `2aa0593`, `7abc3d2`, `1ecb74e`
- `75532cd`, `7d1dfa9`

## Recommended Messaging Updates

### Homepage (`website/content/index.md`)

Current homepage still leans too much on older class-definition examples and
does not clearly advertise Harding's current web/runtime story.

Update goals:

- Replace hero snippet with canonical current syntax
- Mention MummyX + HTMX + reactive server rendering
- Mention external libraries / package model
- Mention Granite + interpreted VM as two execution paths
- Mention Bona Browser / Builder as current tools

Suggested homepage framing:

- "Smalltalk feeling, modern tooling"
- native compilation with Granite
- file-based and git-friendly
- reactive server-rendered web apps
- external library ecosystem

### Features Page (`website/content/features.md`)

This page needs the biggest accuracy pass.

Update goals:

- Remove outdated syntax and examples
- Replace deprecated examples like `deriveWithAccessors:` in primary feature copy
- Add dedicated sections for:
  - direct slot access `::`
  - MummyX web support
  - reactive `RenderCache` model
  - JSON literals / serialization
  - external libraries
  - Application Builder / IDE tooling

### Docs Page (`website/content/docs.md`)

Update goals:

- Improve the "New in Current Runtime" section
- Link more prominently to:
  - `docs/MUMMYX.md`
  - `docs/REACTIVE_WEB_RENDERING.md`
  - `docs/API_SERVER_TUTORIAL.md`
  - `docs/NIM_PACKAGE_TUTORIAL.md`
  - `docs/BONA_WEB_TODO.md`
- Add a small "If you want to build web apps" subsection
- Add a small "If you want to build/install external libraries" subsection

## Recommended New Website Pages

### `website/content/web.md`

Proposed new page for:

- MummyX
- HTMX
- reactive rendering model
- Todo example
- fragment + OOB response flow

### `website/content/packages.md`

Proposed new page for:

- external library model
- `harding lib list`
- `harding lib install`
- Nim package integration
- BitBarrel / SQLite / MySQL / NimCP examples

## Accuracy Pass Checklist

### `index.md`

- [ ] Replace hero snippet with canonical syntax
- [ ] Add web/runtime/package bullets
- [ ] Mention Builder in tooling summary
- [ ] Mention `&` and comma array literals only if needed in visible snippets

### `features.md`

- [ ] Replace deprecated accessor-generation examples
- [ ] Update exception snippets to current string concat syntax
- [ ] Add direct slot access section
- [ ] Add web/reactive rendering section
- [ ] Add JSON and external library sections
- [ ] Add Builder/tooling section

### `docs.md`

- [ ] Expand "New in Current Runtime"
- [ ] Add web docs links
- [ ] Add package/library docs links
- [ ] Mention current examples worth starting from

## Suggested Sequencing

### Pass 1: Accuracy

Do first:

- `website/content/index.md`
- `website/content/features.md`
- `website/content/docs.md`

Goal: no stale syntax, no stale claims, no missing core capabilities.

### Pass 2: Coverage Expansion

Add:

- `website/content/web.md`
- `website/content/packages.md`

### Pass 3: Presentation Polish

Then improve:

- homepage framing
- navigation structure
- feature grouping
- examples chosen for first impressions

## Recommendation

The highest-value next move is an accuracy pass across the three existing pages.
Only after that should we add new pages for web and package workflows.
