# Harding Notebook

A complete GTK4 desktop application written entirely in Harding: layout, model,
persistence and every event handler live in [`notebook.hrd`](notebook.hrd).
There is no application-specific Nim.

## Run it

```sh
# Interpreted
nimble harding_gtk
./build/harding_gtk demos/notebook/notebook.hrd

# Compiled to a native executable
nim c -p:external -o:granite src/harding/compiler/granite.nim
./granite build --gtk demos/notebook/notebook.hrd \
  --dir:build/notebook -o:build/notebook/notebook
./build/notebook/notebook
```

Both runs use the same source and the same shared GTK protocol. The native
binary needs only GTK4 and its normal system libraries: no Harding binary, no
`.hrd` sources, and no interpreter startup.

## What it does

- Searchable note sidebar with a single-selection list.
- Title entry and multiline body editor in a resizable split pane.
- Icon-labelled toolbar: new, duplicate, delete, undo-delete, pin, save.
- The archived view is a real `GtkToggleButton`: GTK reports its pressed state
  to accessibility tools and the status line names the current view.
- Explicit Save with the note count and the saved path reported in the status
  line; the title bar shows the document, not a modal workflow.
- Seed "Welcome" note on a fresh data file, so the first window is never empty.

Writes are explicit: the application never silently autosaves. The storage path
is `--data <path>`, so a demo run cannot overwrite real notes:

```sh
./build/notebook/notebook --data build/notebook/notes.json
```

## Self-tests

Both run without a display and are the regression entry points:

```sh
# Model, filtering, sorting, undo and JSON persistence
./harding demos/notebook/notebook.hrd -- --self-test

# The same model plus real widgets: build the window, drive list selection,
# edit title and body, pin, save and reload
./build/harding_gtk demos/notebook/notebook.hrd -- --self-test --gui-test \
  --data build/notebook/selftest.json
```

`python3 -m unittest tests.test_notebook_application` runs the same two paths in
both engines and asserts identical output, that GTK reports no `CRITICAL`
warnings, and that no callback error is raised. `nimble testGtkApplications`
includes it.

## Structure of the source

| Part | What it covers |
|---|---|
| `Note` | Fields, matching for search, JSON row conversion |
| `Notebook` | Collection operations, filtering/sorting, undo-delete, versioned persistence |
| `NotebookApp` | Window construction, list/editor synchronisation, actions, status |
| `--self-test` | Model and persistence assertions |
| `--gui-test` | Widget-level assertions against the real event loop |

## Things worth knowing

- Cascades (`a msg; msg2`) send **every** message to `a`, as in classic
  Smalltalk, and answer the last message's result — so the toolbar can cascade
  its `add:` calls regardless of what `append:` answers.
- A method without `^` answers **self**, not its last expression, so every
  factory in the model ends with `^instance` and setters need nothing.
- No trailing periods are needed at end of line or block, and unary results need
  no parens inside keyword arguments.
- A bare identifier inside an array literal (`#(a)`) is the symbol `#a` in both
  engines. Use `array{a}` when you mean the variable's value.

- Programmatic editor updates are wrapped by an `updating` guard. Setting a
  entry or text view's text emits the same `changed` signals a user edit does,
  so an unguarded handler would write the stale editor back over the note.
- The list box gets real `GtkListBoxRow` children through the shared backend;
  appending a plain label renders a zero-sized row.
- Widgets and signal handlers are released when the session ends; the backend
  test asserts the resource counters return to zero after repeated runs.

## Current limits

GtkSourceView highlighting, VTE and tree views are not part of the standalone
protocol. Close confirmation is supported by the backend (`onCloseRequest:`) but
the notebook currently permits the close and saves. See
[GTK coverage](../../docs/GTK_SUPPORT.md) for the remaining work.
