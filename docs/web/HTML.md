# HTML, components and reactive rendering

Harding's web rendering stack, in three layers that are deliberately separate:

1. **`Html`** — a Seaside-style DSL that builds markup. It renders directly,
   immediately, and knows nothing about caching.
2. **Tracked state** (`lib/reactive/`) — a generic observer/dependency layer,
   used for web rendering but not specific to it.
3. **`Component` + `RenderCache`** (`lib/web/`) — caches rendered HTML per
   component and invalidates cache entries from tracked-state reads and writes.

The reason for the split is that invalidation is the hard part, and it depends on
*what state a render actually read*, not on the shape of a component tree.

This document replaces `HTML_CANVAS_STATUS.md` (a phase-1 status snapshot) and
`REACTIVE_WEB_RENDERING.md` (the design note that introduced the current
model). Both are preserved in `docs/research/web/`.

## The `Html` DSL

Use the canvas builder in `lib/web/Html.hrd`.

### Buffer style: `Html render:` and `Html canvas:`

```harding
Html render: [:h |
  h div: [ h h1: "Hello" ]
]
```

`canvas:` renders its block and returns the markup. The builder supports
attribute cascades, so several attributes apply to one open tag:

```harding
Html render: [:h |
  h class: "card"; id: "todo-panel".
  h div: [
    h h1: "Todo List".
    h p: "Welcome!"
  ]
]
```

### What the builder supports

- **Attributes** — `class:` accumulates multiple classes with a space separator;
  `id:`, `style:`, `attr:value:` for the generic case. `nil` attributes are
  omitted rather than printed.
- **Content kinds** — strings are escaped automatically; blocks are evaluated
  immediately (not cached); `h << "raw HTML"` and `h raw: "..."` emit unescaped
  markup.
- **Container tags** — `div`, `span`, `p`, `h1`–`h6`, `section`, `article`,
  `header`, `footer`, `main`, `aside`, `nav`, `ul`, `ol`, `li`, `form`, `button`,
  `label`, `a`, `strong`, `em`, `b`, `i`, `code`, `pre`, `blockquote`.
- **Void tags** — `input`, `br`, `hr`, `img`, `meta`, `link`.
- **Boolean attributes** — `disabled`, `checked`, `selected`, `readonly`,
  `required`, `autofocus`, `multiple`.
- **Composition** — `&` concatenates rendered fragments; `HtmlCanvas>> <<` mixes
  buffer-style output into a fragment.

## Tracked state

`lib/reactive/` holds a generic layer, not tied to web rendering:

| Class | Role |
|---|---|
| `Reactive` | the observer stack |
| `TrackedSubject` | base tracked state with dependents |
| `TrackedValue` | a single tracked value |
| `TrackedTable` | tracked keyed collection |
| `TrackedList` | tracked ordered collection |

It maintains the current active observer, lets tracked values register reads
against that observer, notifies dependents on change, and supports batching over
time.

## Rendering with a cache

`Component>>renderInto:` uses an **external** `RenderCache`. The component does
not own the cache and does not manage invalidation manually:

1. the component computes a `renderCacheKey`;
2. `RenderCache` returns a `RenderEntry` for that key, plus an optional session
   key;
3. if the entry is valid, its cached HTML is appended directly;
4. if the entry is dirty, the component renders fresh output;
5. during that render, tracked reads register dependencies automatically;
6. later writes to tracked state mark the dependent entries dirty.

So repeated renders of unchanged state reuse cached HTML, and a state change
invalidates exactly the entries that read it.

### Session-specific rendering

Session state should not force *all* rendering to become session-specific:

- keep tracked session state separate from global or shared tracked state;
- use `Component>>renderSessionKey` only when a component genuinely needs
  session partitioning;
- let tracked dependencies decide what invalidates what.

This keeps caching practical for multi-user server rendering.

### Reference application

`examples/web/todo/` uses `TrackedList` for repository items, `TrackedValue`
inside each `TodoItem`, and `Todo*Component` cache keys for item, panel and page
entries. The active path is `TodoItem`, `TodoRepository`, `TodoItemComponent`,
`TodoPanelComponent`, `TodoPageComponent`. Parallel rendering variants were
removed rather than kept alongside.

Editing those components live in Bona while the server runs is documented in
[gtk/BONA.md](../gtk/BONA.md).

## What was deliberately not built

Recorded because each was implemented or planned and then dropped. Do not
reintroduce them without a new argument:

- **Template-structure caching inside `Html`.** The builder renders directly;
  caching belongs one layer up.
- **Dynamic holes in cached templates.** Replaced by component-level caching plus
  tracked-state invalidation.
- **Auto-generated HTML cache keys.** A component states its own key.
- **Parallel rendering variants** in the Todo example.
- **A component tree as the primary invalidation mechanism.** An explicit
  parent/children hierarchy may be useful later, but dependency tracking is what
  makes the cache correct, and a tree does not provide it.

## Design influences

Recorded as influences, not as claims of equivalence: classic Smalltalk
`Model`/dependents, spreadsheet-style dependency propagation, MobX-style tracked
reads and invalidations, Flutter's `watch_it` active-build-context idea, and
`listen_it`'s reactive collections and transactions. Harding is not async the way
Flutter is, but the active-observer pattern and tracked collections map well to
server-side rendering and fragment invalidation.

## Known follow-ups

- `lib/web/Html.hrd` is still one implementation file holding `Html`,
  `HtmlCanvas`, `HtmlTagBuilder` and `HtmlRawFragment`. A one-class-per-file split
  is a pending cleanup.
- Tracked transactions around larger model updates are not implemented.
- Session-scoped cache keys have not been exercised in real multi-user routing.
- It is an open question whether some tracked/computed behavior belongs in the
  language or runtime rather than remaining a library pattern.

## Validation

```sh
nimble testStdlib
nim c -r tests/test_web_html_template_cache.nim
nim c -r tests/test_html_render_cache.nim
nim c -r tests/test_html_canvas.nim
```

The Html suites exercise direct rendering, component nesting, and cache reuse and
invalidation. MCP bridge data structures are covered by the MCP suite, not by the
rendering suites.
