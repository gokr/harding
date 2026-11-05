# GTK coverage and Harding Notebook

## Scope and evidence

This source audit covers the standalone protocol in `lib/gui/Gtk.hrd` and
`src/harding/gui/gtk/application_backend.nim`, its interpreted/native adapters,
and Bona's registrations in `bridge.nim` and wrapper files in `lib/gui/gtk4/`.
Coverage here means a registered path exists, not that every operation has
passed interactive acceptance. Validation results are recorded separately.

[GTK overview](GTK.md) is the documentation entry point;
[GTK applications](GTK_APPLICATIONS.md) owns standalone build commands, API and
lifecycle contracts. This document owns the gap inventory and implementation
checklist, not another copy of those instructions.

## Coverage inventory

| Capability | Standalone, both engines | Bona interpreter bridge |
|---|---|---|
| Application activation / quit | Shared GtkApplication protocol | Nim host owns application lifecycle |
| Windows | Title, size, child, present, close, close-request veto | Also icons and destruction helpers |
| Box layout | Row/column, append, prepend, remove-all, spacing, homogeneous | Also individual removal |
| Base widget | Margins, expansion, horizontal center, CSS add/remove, visibility, sensitivity, focus, tooltip | Visibility, size request, tooltip, alignment, CSS add/remove |
| Labels / buttons | Text, wrapping, selectable; button labels and actions | Labels, button actions and icons |
| Entry | New, text get/set, placeholder, `changed` via `connect:do:` | New, text get/set, placeholder; no dedicated changed helper registered |
| Scrolling / split panes | ScrolledWindow and Paned (position, resize flags) | ScrolledWindow and Paned |
| Lists | ListBox with real rows, insert/clear, single selection, row-selected index callback | ListBox insertion, clearing, selection and row-selected callback |
| Multiline editing | TextView with buffer text, wrapping, editability and change callback | TextView, TextBuffer and SourceView |
| Keyboard / pointer events | Missing | Key-controller shortcuts and right-click gestures |
| Dialogs | Missing | GTK4 alerts and confirmations with response callbacks |
| Menus | Missing | GTK4 custom popovers/context menus; traditional menu classes are GTK3-only |
| Terminal | Missing | GTK4 VTE integration |
| Toggle buttons | `GtkToggleButton` with icons and GTK-owned pressed state | Not used by Bona |
| General GTK4 widget catalog | Missing | Partial; not a generated full binding |
| Arbitrary signal marshalling | Not supported | Not supported by generic connector |
| Native executable without runtime application source | Covered by the counter and notebook packages | Builder embedded-interpreter packaging remains separate work |

Missing standalone capabilities also include file dialogs, actions/accelerators,
header bars, stacks, check buttons, dropdowns, modern list models/views, images
and drawing. This is a workflow inventory, not a percentage of GTK's entire API.

## Contracts and risks preserved by the shared backend

- **One shared protocol:** reusable selectors live in the common backend and are
  registered in both adapters. Conveniences stay in Harding. There are no
  compiler-only application selectors, and the two class sets are never loaded
  together.
- **Argument validation:** kinds, arities and enum ranges are checked before any
  C call, so a type error raises a Harding-visible `ValueError` rather than
  reaching the ABI.
- **Callback ABI:** `clicked`/`activate`/`changed` are void handlers; `row-selected`
  passes a one-based-index integer argument (0-based); `close-request` returns a
  veto and answers from the block's truthiness. A block of the wrong arity is
  rejected at connection time, not cast.
- **Reentrancy:** programmatic text updates emit the same `changed` signals a
  user edit does. The notebook wraps them in an `updating` guard; a UI that sets
  entry or buffer text from a model needs the same guard.
- **Ownership:** widgets and handlers live until session exit, and `removeAll`
  detaches children and releases their owners so repeated list rebuilds do not
  accumulate state. Expired wrappers fail loudly.
- **Error boundaries:** no Harding error or return transfer unwinds through C
  frames. A failed action reports on stderr and leaves later actions usable; a
  failure in the activation block quits the loop instead of hanging.
- **List rows:** `gtk_list_box_append` needs a `GtkListBoxRow`; appending a plain
  child produces a zero-sized, invisible row.
- **Shutdown:** the event loop exits explicitly and repeated startup/teardown
  returns the resource counters to zero under ARC and ORC.
- **Threading:** GTK stays on its owning thread; no nested loops, cross-thread
  callbacks or cancellable evaluation.

## Harding Notebook

[`demos/notebook`](../demos/notebook/) is a complete application in Harding
source: model, filtering, versioned JSON persistence and every handler. The same
`notebook.hrd` runs in `harding_gtk` and as a `granite build --gtk` binary.

Implemented:

- Searchable single-selection sidebar, title entry, wrapped multiline body and
  resizable split.
- New, duplicate, delete, undo-delete, pin, archive and archived-view.
- Explicit save with status text, close permitted, seed welcome note.
- Guarded editor synchronisation and stable document ids.

Delivered by this work:

- Entry, TextView, ScrolledWindow, Paned and ListBox in the shared backend.
- Typed change/row-selected/close-request callbacks and argument validation.
- `removeAll` child release and list-row wrapping.
- Compiled `File` class protocol and a compiled-block answer fix (a final
  `ifTrue:ifFalse:` in a block body previously answered nil).

### Remaining work

1. **Dirty state and close confirmation.** The UI neither marks unsaved changes
   nor asks on close (it saves and allows the close). The backend already
   supports the required `onCloseRequest:` veto; this needs a dirty flag, a
   typed confirmation, and a test for cancel-then-continue.
2. **Categories (UI).** Categories are modelled and listed but not editable or
   filterable from the window.
3. **Import/export.** Only the local JSON file is supported.
4. **Keyboard shortcuts and actions.** Buttons only; no accelerators or menus.
5. **Native packaging.** Binary-only execution away from the source tree needs
   its own package test, and the system dependency contract (GTK version) needs
   documenting.
6. **Array-literal identifier semantics.** `#(a)` evaluates to the symbol `#a`
   in the interpreter and to the value of `a` in Granite. This is a language
   divergence awaiting a decision, so the demo avoids bare-identifier literals;
   it is not a GTK issue and was not worked around in the parser.
7. **Real-pointer acceptance.** Automated tests drive signals; AT-SPI mouse
   clicks on list rows report zeroed extents on this Wayland session, so row
   selection is verified through the real signal rather than a pointer click.

Each future slice needs focused regressions plus `nimble testGtkApplications`.
Do not report a skipped GUI test as a pass.

Bona consolidation is a separate follow-up: first stabilize the common
application protocol, then assess migration of individual Bona wrappers without
replacing its live classes, scheduler ownership or tool behavior in one step.

## Validation

Baseline before this work (`build/gtk-audit/baseline.log`): six shared-backend
tests, native lifecycle under ARC and ORC, and four application/package tests.
AT-SPI was not enabled.

After the protocol extension and the notebook (`build/gtk-audit/after.log`):

- Shared backend: eight tests (two new) under ARC and ORC.
- Native lifecycle test under ARC and ORC.
- `test_pure_gtk_application.py` and `test_notebook_application.py`: the counter
  and notebook, each interpreted and compiled, with identical output.
- Granite parity cases `block_conditional_answer` and `file_class_protocol`.
- Live AT-SPI session: "New note" click changed the rendered count, title and
  body text set through the accessibility bridge persisted on Save, and the
  written JSON matched the typed values.
