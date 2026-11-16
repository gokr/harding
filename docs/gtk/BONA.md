# Bona: the Harding IDE

Bona is a GTK4 IDE written in Harding. It runs its own interpreter with a live
GTK bridge, so tools are Harding code that can be edited while the IDE runs.

`gtk/GTK.md` is the documentation entry point for GTK in general. This document
covers the IDE: what each tool does, how to work in it, what the workflows are,
and what is still broken.

The full assessment that produced the fixes below — including the original
reproductions, validation logs and source citations — is in
`research/gui/BONA_ASSESSMENT.md`. It describes the pre-fix baseline plus the
hardening log, so read it as history, not as current state.

## Build and run

```sh
nimble bona              # debug
nimble bona_release      # release
nimble bona_mummyx       # with the MummyX HTTP server, for web workflows
./bona
```

Bona requires GTK4, GtkSourceView 5 and the **GTK4** VTE library
(`libvte-2.91-gtk4.so.0`). The GTK3 VTE library is not a substitute. On a host
without GTK4 VTE, extract the runtime package locally and point both
`LIBRARY_PATH` (link) and `LD_LIBRARY_PATH` (run) at it; installing
`libvte-2.91-gtk4-0` system-wide removes the need.

```sh
nimble install_bona      # installs ~/.local/bin/bona plus desktop integration
```

The host creates its GtkApplication with ID `org.harding-lang.bona`. GTK4 window
icons use icon-theme names (`iconName:`), not file paths.

## Tools

| Tool | Purpose | Notes |
|---|---|---|
| Launcher | main window and navigation | window icon and desktop integration through `install_bona` |
| Transcript | output console | bounded history retained while closed, restored on reopen; class-side `contents` for BonaMCP |
| Workspace | code editor with Do It / Print It / Inspect It | reads/writes `workspace-<id>.hrd` in the working directory |
| Browser | four-pane class/method browser | source-backed editing with validated, atomic, targeted writes |
| Inspector | object slot viewer | drills into nested objects |
| Builder | creates and builds an application skeleton | embedded-interpreter packaging is the target mode |

### Workspace

Do It evaluates the selected text, or the current line when nothing is selected,
and **reports the result to Transcript**. Print It inserts the result after the
selection and selects it. Inspect It opens the result in Inspector.

Workspace persists to `workspace-<id>.hrd` in the process working directory and
can delete an empty workspace file on save or close. **Redirect it** with
`Workspace filePath: <abs path>` in any automated or test session, or you will
overwrite a developer's workspace. The GUI automation tests do this and assert
the repository root stays clean.

### Browser

Browser saves through a parser-delimited targeted edit
(`src/harding/interpreter/source_editor.nim`, reached as
`Harding editSourceFile:owner:selector:replacement:delete:`), then writes
atomically. It preserves:

- unrelated classes in the same file;
- statements and comments outside the edited definition;
- class-side methods and methods added in extension files;
- Unicode and CRLF content;
- duplicate definitions that are not the edit target.

An invalid edit is rejected before anything is written. Browser refresh defers
while source is dirty, so an open pane never discards an unsaved edit.

Two limits are real:

- **Syntax validation is not transactional runtime validation.** The parser
  accepts a definition that may still fail at runtime; the write already
  happened.
- **Source reflection is line-based** and counts brackets without respecting
  strings or comments. It is not a general-purpose source rewriter. Do not point
  destructive editing at repository sources — use a disposable copy.

### Inspector

Shows an object's slots and values, and drills into nested objects. Private
slots stay inaccessible, and that rejection is catchable.

### Builder

Builder New creates an application skeleton and registers the class. The
embedded-interpreter packaging path (one executable containing application
sources plus the Harding interpreter, runnable without the source tree or a
separate `harding` binary) is the agreed first packaging mode; Granite
compilation remains a separate backend Builder can select later.

## Live-editing a web application

Bona with MummyX is a live Smalltalk-style development loop. From a Workspace in
a `nimble bona_mummyx` build:

```harding
Harding load: "lib/mummyx/Bootstrap.hrd".
Harding load: "lib/web/Bootstrap.hrd".
Harding load: "lib/web/todo/Bootstrap.hrd".

TodoApp resetRepository.
TodoApp startOn: 8080.
```

`startOn:` is the non-blocking form, which is what a Workspace needs. From a CLI
session use `TodoApp serveForeverOn: 8080` or `TodoApp serve` instead.

That load path matters for Browser visibility: it creates named `Web` and
`WebTodo` libraries, so the classes appear in Browser instead of existing only as
top-level globals.

Then open `http://127.0.0.1:8080` and edit methods in Browser:

- `TodoApp class>>home:`, `createTodo:`, `toggleTodo:`, `deleteTodo:`
- `TodoPageComponent>>bodyMarkup`, `TodoPanelComponent>>render`,
  `TodoItemComponent>>render`, `TodoItemComponent>>metaText`
- `TodoItem>>title:`, `TodoItem>>toggleCompleted`

Save the method, then refresh the page or trigger the htmx action again. Code
inside an existing handler is picked up without restarting the server.

Route *declarations* are different: after editing
`TodoApp class>>installRoutesOn:` or `TodoApp>>installRoutes`, evaluate

```harding
TodoApp reloadRoutes.
```

To stop, evaluate `TodoServer stop.`; add `TodoApp resetRepository.` for a fresh
data set. The UI serves a vendored DaisyUI stylesheet. Rendering uses tracked
state in `lib/reactive/` plus web-specific external caching in `RenderCache`
(see [web/HTML.md](../web/HTML.md)). The repository is in-memory; replacing it
with BitBarrel or MySQL mainly affects `TodoRepository` and `TodoItem`
construction.

## Embedded interpreter and host safety

Tools run inside a live interpreter that Bona owns. Two rules follow from that.

- **A host callback must never quit the IDE.** Anything reached through a GTK
  callback uses `evalCallbackNonFatal` (see `invokeGtkCallbackBlock`), so one
  mistake in a handler reports an error instead of terminating the process. This
  differs deliberately from a CLI run, where an uncaught signal runs
  `defaultAction` and exits with the `=== Uncaught Exception ===` banner (except
  `MessageNotUnderstood`).
- **Evaluation shares the caller's world.** `Object evaluate:` returns a
  structured `{ok, value, error}` result and shares globals, source indexing and
  scheduler ownership with the caller, which is what makes it safe for Bona tools
  and MCP dispatch. `Object eval:` keeps its older plain-value/error-string
  behavior for compatibility; new code uses `evaluate:`.

Evaluation is **not cancellable**: an in-flight `Object evaluate:` cannot be
interrupted.

## BonaMCP

Bona exposes a semantic MCP server so an agent or external client can drive the
tools. `research/BONA_MCP.md` records the protocol design and its history.

Scheduler-bound startup ordering and coordinated shutdown remain open work. The
recorded assessment does not contain a successful acceptance run in the tested
startup path: repeated `BonaMCP startOn:` attempts terminated Bona with SIGSEGV
before a connection was established, and a GDB capture stopped in Pango/GTK
layout without establishing the root cause. Treat MCP lifecycle as unproven.
For black-box GUI automation of Bona itself, the harness uses an accessibility
(AT-SPI) MCP instead — see `AGENTS.md`.

## Known gaps

From the assessment, the GTK coverage audit and subsequent testing. Each is a
work item, not an accepted limitation.

| Gap | Detail |
|---|---|
| Nested `on:do:` parity | Resume-related expression parity and a few tool error paths need focused regressions. |
| Source-free reload | Reflection/display for reloading an edited image is incomplete; syntax validation is not transactional. |
| MCP lifecycle | Scheduler-bound BonaMCP startup and coordinated shutdown are not implemented. Inspector, Browser and Builder have not all been exercised through it. |
| Embedded-interpreter packaging | The agreed first packaging mode is not built yet; Builder still produces a skeleton, not a self-contained executable. |
| Close confirmation | The UI saves and allows the close instead of asking. The backend supports the required `onCloseRequest:` veto, so this needs a dirty flag, a typed confirmation, and a cancel-then-continue test. |
| Debugger in the IDE | Stack-frame display is not implemented. |
| Full acceptance coverage | The GUI automation suite covers models and workflows; it is not a complete black-box acceptance test of every tool. |

Bona's broader widget surface — entries, list selection, multiline editing,
dialogs, popovers, VTE terminals, key controllers — is **not** available through
the standalone `harding_gtk` protocol. The two bridges share class names and must
not be loaded together; see `gtk/GTK.md`.

## Validation

```sh
nim c -r --out:build/test_bona_models tests/test_bona_models.nim
nim c -r --out:build/test_gui_automation tests/test_gui_automation.nim
nim c -r --out:build/test_source_editor tests/test_source_editor.nim
nim c -r --out:build/test_load_and_eval tests/test_load_and_eval.nim
```

Focused logs belong in `build/bona-hardening/`. Validate under ARC and ORC when
touching proxy lifetime, callbacks or cross-thread services.

A test that skips for a missing display is **not** GUI acceptance. Direct signal
emission and model tests do not replace real event-loop and accessibility
interaction. Record exact commands and results, including skipped cases, and do
not infer whole-IDE acceptance from the standalone GTK counter suite.

For live acceptance testing with the `gnome-ui` MCP: launch with
`GTK_A11Y=atspi`, keep the process owned by the harness rather than a bare shell
background job, set boundaries to Bona, and re-discover elements after each
change — AT-SPI paths and snapshot ids are not durable. `get_element_text` has
returned empty text despite nonzero character counts, so cross-check through
`Atspi.Text.get_text` and do not report success from an action's `success` flag
alone. Use a disposable working directory or redirect the workspace file.
