# Reactive Web Rendering

Harding's current web direction is:

- generic `Html` DSL for rendering
- generic tracked state in a separate reactive library
- web-specific render caching in the web layer
- automatic cache invalidation driven by tracked state reads and writes

This replaces the earlier idea of keeping multiple rendering variants or depending on Html-specific compilation tricks.

## Layers

### Reactive layer

Located under `lib/reactive/`.

Current classes:

- `Reactive`
- `TrackedSubject`
- `TrackedValue`
- `TrackedTable`
- `TrackedList`

This layer is intentionally generic and not tied to web rendering.

Its job is to:

- maintain the current active observer
- let tracked values register reads against that observer
- notify dependents when tracked state changes
- support batching/transactions over time

### Web layer

Located under `lib/web/`.

Current cache classes:

- `RenderCache`
- `RenderEntry`

The web layer uses the reactive observer stack to capture which tracked values were read during rendering.

## How rendering works

`Component>>renderInto:` now uses an external `RenderCache`.

1. The component computes a `renderCacheKey`.
2. `RenderCache` returns a `RenderEntry` for that key and optional session key.
3. If the entry is valid, its cached HTML is appended directly.
4. If the entry is dirty, the component renders fresh output.
5. During that render, tracked reads register dependencies automatically.
6. Later writes to tracked state mark dependent entries dirty.

This means repeated renders of unchanged state can reuse cached HTML while still invalidating correctly when state changes.

## Session-specific rendering

Session-specific state should not force all rendering to become session-specific.

Instead:

- keep tracked session state separate from global/shared tracked state
- use `Component>>renderSessionKey` when a component truly needs session partitioning
- let tracked dependencies naturally determine what invalidates what

This keeps caching practical for multi-user systems.

## Why not component trees first?

An explicit parent/children component hierarchy may be useful later, but it is not required for the first working cache model.

The key mechanism is dependency tracking:

- what tracked state was read
- which render entries depend on it
- which cache entries become dirty on mutation

This dependency graph matters more than a component tree for the first implementation.

## Relationship to Html DSL

The `Html` DSL remains the authoring surface.

The current design goal is:

- keep the DSL clean and expressive
- keep caching outside component instances by default
- drive invalidation through tracked state, not manual cache management

`HtmlCanvas>><<` still exists, so buffer-style output can be mixed in when needed.

## Current Todo example

The Todo app uses:

- `TrackedList` for repository items
- `TrackedValue` inside each `TodoItem`
- `Todo*Component` cache keys for item/panel/page entries

The old Todo rendering variants were removed. The active path is now:

- `TodoItem`
- `TodoRepository`
- `TodoItemComponent`
- `TodoPanelComponent`
- `TodoPageComponent`

This keeps the example focused on the reactive state + external render cache model instead of preserving parallel rendering strategies.

This gives:

- item-level cache reuse
- page/panel invalidation when tracked todo state changes
- no need for persistent per-session component trees

## Inspirations

This model is inspired by several places:

- classic Smalltalk `Model`/dependents patterns
- spreadsheet-style dependency propagation
- MobX-style tracked reads and invalidations
- `watch_it`'s active build context idea
- `listen_it` reactive collections and transaction concepts

Relevant reading:

- `watch_it`: <https://flutter-it.dev/documentation/watch_it/getting_started>
- `watch_it` internals: <https://flutter-it.dev/documentation/watch_it/how_it_works>
- `watch_it` best practices: <https://flutter-it.dev/documentation/watch_it/best_practices>
- `listen_it` collections: <https://flutter-it.dev/documentation/listen_it/collections/introduction>

Harding is not async in the same way Flutter is, but the active-observer pattern and tracked collections map well to server-side rendering and fragment invalidation.

## Future directions

- split `lib/web/Html.hrd` support classes into one class per file
- add tracked transactions around larger model updates
- explore session-scoped cache keys in real multi-user routing
- later consider whether some tracked/computed behavior belongs in Harding as a language/runtime feature rather than remaining only a library pattern

At the moment `lib/web/Html.hrd` is still the main implementation file for the Html DSL. The old `Html2` split is gone, but the support classes still need a careful follow-up split into separate files.
