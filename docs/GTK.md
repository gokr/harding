# GTK support in Harding

This is the entry point for GTK documentation. Harding has two GTK4 bridges;
they share class names but are not interchangeable or safe to load together.

## Choose a path

| Goal | API and host | Guide |
|---|---|---|
| Write a standalone application entirely in Harding; interpret or compile the same source | `lib/gui/Gtk.hrd`, `harding_gtk`, `granite build --gtk` | [GTK applications](GTK_APPLICATIONS.md) |
| Develop Bona tools in its live interpreter | `lib/gui/gtk4/`, `initGtkBridge`, Bona host | [Bona bridge](#bona-bridge) below |
| Review current coverage and the Notebook implementation plan | Both bridges, with explicit gaps | [Coverage and Notebook plan](GTK_SUPPORT.md) |
| Install editor syntax highlighting | GtkSourceView language definition | [GtkSourceView](GTKSOURCEVIEW.md) |
| Review Bona defects and acceptance evidence | IDE workflows and runtime integration | [Bona assessment](BONA_ASSESSMENT.md) |

The native wrapper is handwritten Nim over GTK's C ABI, not a complete generated
GObject-introspection binding. Having a raw declaration in `ffi.nim` does not
make that feature callable from Harding. A public feature needs registration,
argument conversion, a matching callback ABI where applicable, ownership rules,
and tests.

## Standalone applications

Start with [GTK applications](GTK_APPLICATIONS.md), including the runnable
counter. Application layout, state and handlers can all be `.hrd`; reusable
platform bindings remain Nim. Both interpreted and Granite adapters use
`src/harding/gui/gtk/application_backend.nim` and the same Harding convenience
methods. Applications need no app-specific Nim shell.

The initial protocol covers activation, windows, boxes, labels and buttons.
It is not yet a general desktop application toolkit. In particular, entries,
list selection and multiline editing from the Bona bridge are not available
through this protocol. [Coverage](GTK_SUPPORT.md) distinguishes implemented
features from planned additions.

Native packages require system GTK4 and its normal transitive dependencies,
not GtkSourceView or VTE. Source-free native execution is tested; this is
separate from Bona Builder's planned embedded-interpreter packaging mode.

## Bona bridge

Bona's interpreter bridge is registered in
`src/harding/gui/gtk/bridge.nim`. It creates the native classes first, then
`loadGtkWrapperFiles` adds conveniences from `lib/gui/gtk4/`. Bona loads its IDE
tools separately from `lib/gui/bona/`. Do not load standalone `Gtk.hrd` into
this interpreter: it defines another set of `Gtk*` classes.

### Build and dependencies

```sh
nimble bona
```

Bona requires GTK4, GtkSourceView 5 and the **GTK4** VTE library
(`libvte-2.91-gtk4.so.0`). The GTK3 VTE library is not a substitute. See
[Bona assessment](BONA_ASSESSMENT.md) and
[tools and debugging](TOOLS_AND_DEBUGGING.md) for dependency and build details.

Bona's host owns application initialization and the event loop. The following
is an example for an already initialized Bona interpreter, not a standalone
script for ordinary `harding`:

```harding
| window content button |
window := GtkWindow new.
window title: "Bona bridge example".
window setDefaultSize: 480 height: 240.
content := GtkBox vertical.
content setSpacing: 12.
button := GtkButton newLabel: "Click me".
button clicked: [Transcript showCr: "Clicked"].
content append: button.
window setChild: content.
window present
```

### Available areas

The bridge registers windows, boxes, buttons, entries, labels, scrolled windows,
split panes, list boxes, text views and buffers, source views, VTE terminals,
keyboard helpers, GTK4 alerts and popovers. The detailed inventory and remaining
limitations are in [GTK support](GTK_SUPPORT.md).

Use the registered protocol and `.hrd` wrappers as the selector reference;
raw Nim function names and previous documentation examples are not API promises.
For example, entry text is `text` / `text:` / `placeholderText:`, list selection
uses `onRowSelected:`, and keyboard shortcuts use `onKey:modifiers:do:`.

### Callbacks and lifetime

`widget.nim` maintains widget proxies and instance-to-widget lookup tables.
Proxies retain Harding callback blocks and interpreter references. Callback
execution goes through `invokeGtkCallbackBlock` and `evalCallbackNonFatal`:
a failing host callback must report an error rather than terminate Bona.

The generic `connect:do:` path is not an arbitrary signal marshaller. Signals
with arguments or return values need a dedicated ABI-correct adapter. Use the
typed helpers already provided for lists, keys, gestures and dialogs; do not
connect a generic void callback to a signal that expects a Boolean result.
Similarly, arbitrary `emitSignal:` calls are not a safe general-purpose signal
emission API.

Do not infer complete lifetime safety from a proxy's `destroyed` flag or the
existence of lookup tables. Validation and cleanup differ between wrappers;
controller, dialog and buffer ownership must be checked independently.
[Coverage and risks](GTK_SUPPORT.md) records the audit boundary.

### Text editing in Bona

`GtkTextView` and `GtkSourceView` provide `text`, `text:`,
`insertText:at:`, `selectRangeFrom:to:`, `insertTextAtSelectedEnd:` and
`getSelectionEnd`. SourceView also provides line numbers, tab width and
`selectedText` (selection or current line).

Workspace Do It evaluates selected text or the current line and reports the
result to Transcript. Print It inserts the result after the selection and
selects it. These are IDE workflows, not standalone GTK application selectors.
See the [Bona assessment](BONA_ASSESSMENT.md) for tested behavior and outstanding
acceptance work.

### Desktop integration

GTK4 window icons use icon-theme names (`iconName:`), not file paths.
Bona's host creates its GtkApplication with ID `org.harding-lang.bona`.
`nimble install_bona` installs the binary and desktop integration. The legacy
GTK3-only menu and icon-file paths do not establish GTK4 support.

## Validation

Standalone protocol, both engines, ARC/ORC and binary-only packages:

```sh
nimble testGtkApplications
NATIVE_GTK_ATSPI=1 nimble testGtkApplications
```

Bona's bridge and tools have separate suites:

```sh
nim c -r --out:build/test_gui_automation tests/test_gui_automation.nim
nim c -r --out:build/test_bona_models tests/test_bona_models.nim
```

A test that skips for a missing display is not GUI acceptance. Direct signal
emission and model tests do not replace real event-loop and accessibility
interaction. Record exact commands and results, including skipped cases;
do not infer whole-Bona acceptance from the standalone counter suite.
