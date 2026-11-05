# GTK4 applications in Harding

See [GTK support](GTK.md) for the documentation entry point, the separate Bona
bridge, and the [coverage and Notebook plan](GTK_SUPPORT.md). This guide owns
the standalone application protocol; Bona's broader widget API is not available
through `--gtk` merely because its wrappers exist in the repository.

The application source can be entirely `.hrd`: widget creation, layout, state and
callbacks. GTK's C ABI is implemented once in a shared Nim backend supplied by
Harding; applications need no handwritten Nim or generated-file edits.

## Build and run

```sh
nim c -p:external -o:granite src/harding/compiler/granite.nim
mkdir -p build/gtk-counter
./granite build --gtk --release demos/native-gtk-counter/counter.hrd \
  --dir:build/gtk-counter -o:build/gtk-counter/counter
./build/gtk-counter/counter
```

Copy just the executable to run it outside the source tree. Runtime dependencies
are GTK4 and its normal system libraries. Build dependencies are Nim 2.2.12,
`pkg-config` and GTK4 development libraries. GtkSourceView and VTE are not used.
Shared runtime modules still include interpreter support, but this path does not
start an interpreter, load stdlib source at runtime or invoke interpreted fallback.
It does not claim the binary contains zero interpreter-related machine code.

The same source runs in the GTK-enabled interpreter:

```sh
nimble harding_gtk
./build/harding_gtk demos/native-gtk-counter/counter.hrd
```

`--gtk` composes `lib/gui/Gtk.hrd` into generated definitions and registers native
counterparts before application statements. It preserves script temporaries and
explicit `Harding compile:/main:` scopes. `--mixed` and freeze-manifest builds are
currently rejected with `--gtk`; full-deliverable sealing is not established.

## Small application

```harding
GtkApplication run: "org.example.Hello" activate: [
    | window column label count |
    count := 0.
    window := GtkWindow title: "Hello" width: 360 height: 240.
    column := (GtkBox column: 12) padding: 24.
    label := (GtkLabel title: "Count: 0") expand.
    column add: label.
    column add: (GtkButton primary: "Increment" action: [
        count := count + 1.
        label text: ("Count: " & count printString)
    ]).
    window child: column.
    window present
]
```

Create widgets inside the activation block. Blocks retain captured cells after
activation returns. Use `GtkApplication quit` to end the event loop, or close the
last window normally.

## Initial protocol

| Class | Convenience API |
|---|---|
| GtkApplication | `run:activate:`, `quit` (class-side) |
| GtkWindow | `title:width:height:` (class-side), `child:`, `present`, `close`, `onCloseRequest:` |
| GtkBox | `column:`, `row:` (class-side), `add:`, `addAll:`, `equalWidth`, `removeAll` |
| GtkLabel | `text:`, `heading:`, `title:`, `muted:` (class-side), `text`, `text:`, `wrap:`, `selectable` |
| GtkButton | `label:action:`, `primary:action:`, `flat:action:`, `icon:label:action:` (class-side), `label`, `label:`, `icon:` |
| GtkToggleButton | `icon:tip:action:`, `icon:label:action:` (class-side), `state`, GTK's own pressed state |
| GtkEntry | `text:` (class-side), `text`, `text:`, `placeholderText:`, `onChanged:` |
| GtkTextView | `editable:` (class-side), `text`, `text:`, `wrapping:`, `onChanged:` |
| GtkScrolledWindow | `child:` (class-side), `child:` |
| GtkPaned | `horizontal:`, `vertical:` (class-side), `start:`, `end:`, `position:`, `resizeStart:`, `resizeEnd:` |
| GtkListBox | `singleSelection` (class-side), `append:`, `removeAll`, `selectIndex:`, `selectedIndex`, `onRowSelected:` |
| GtkWidget | `padding:`, `expand` (both axes), `wide` (horizontal), `tall` (vertical), `top`/`middle` (vertical alignment), `style:`, `visible:`, `sensitive:`, `tooltip:`, `focus`, individual margins, `setHexpand:`, `setVexpand:` |

Both adapters register the same low-level protocol from
`application_backend.nim`; high-level conveniences are the same `.hrd` methods
compiled by Granite or evaluated by the interpreter. No compiler-only selectors
are introduced.

Callback signatures are typed and an arity mismatch is rejected when the handler
is connected, never cast to an incompatible C function:

| Signal | Block | Answer |
|---|---|---|
| `clicked`, `activate`, `changed` | zero arguments | ignored |
| `row-selected` (via `onRowSelected:`) | one argument, the 0-based row index | ignored |
| `close-request` (via `onCloseRequest:`) | zero arguments | `true` allows the close, anything else vetoes it |

`connect: "clicked" do:` and `emitSignal:` remain available for button callbacks
and automation. `emitSignal:` accepts only void signals (`clicked`, `activate`,
`changed`).

Convenience setters answer the receiver, so `widget wide top` works. Cascades
are classic: every `;` message goes to the same receiver and the cascade answers
the last message's result, so `window title: "x"; setDefaultSize: 800 height: 600`
configures one window no matter what each setter answers. `^` may precede a
cascade, which is how the widget factories are written:
`^self new label: text; connect: "clicked" do: block`. A newline separates
statements, so the receiver and its first message must share a line.

Repeated parens around a unary result are unnecessary: unary binds tighter than
binary, and binary tighter than keyword, so `self setHexpand: true` needs none.
Trailing periods are also unnecessary at the end of a line or block — a newline
separates statements — but two statements on one line still need one. A method
without `^` answers **self**, not its last expression, so factories must end with
`^instance`; setters and mutators need no explicit `^self`.

Programmatic text changes emit the same `changed` signal a user edit does. A
window that loads model text into an entry or text view must guard those updates,
as `demos/notebook` does, or the handler writes the stale editor back over the
model.

## Errors and ownership

No Harding exception or return transfer may unwind through GTK's C callbacks.
The callback boundary reports failures and allows subsequent button actions.
An activation failure requests application quit so startup cannot hang. The
`run:activate:` result is an integer: GLib exit status, or 1 if any callback
failed. A script may inspect this result; the existing CLI does not implicitly
convert a returned integer into an OS exit status.

`removeAll` on a box or list box detaches and releases every child, so repeated
rebuilds of a list do not accumulate widgets or handlers. Appending to a
GtkListBox wraps the child in a `GtkListBoxRow`, which list rendering and
accessibility require. A labelled button with an icon keeps both, and the icon
is pinned to 16px so a toolbar row stays 34px tall instead of stretching to the
window.

The application session retains widgets and action blocks. On shutdown it
disconnects signals, destroys windows, releases GTK references and invalidates
retained widget wrappers. A later send through a closed wrapper fails instead
of dereferencing its old GTK pointer. Repeated application sessions are covered
by tests. Resources are retained until session exit, not reclaimed immediately
when a widget is removed. Only the GTK owning thread is supported; no green-thread
yielding, nested GTK applications, cross-thread callbacks or arbitrary widget
subclasses are promised.

This is a standalone application library. It does not replace Bona's existing
GTK bridge and must not be installed over its live `Gtk*` classes.

## Validation

```sh
nimble testGtkApplications
# Real AT-SPI actions scoped to the owned process/window:
NATIVE_GTK_ATSPI=1 nimble testGtkApplications
```

Acceptance builds ARC and ORC binaries, tests the same `.hrd` in both engines,
runs binary-only native packages with empty PATH and absent Harding home,
checks callback-error recovery, script and compile/main scopes, and optionally
clicks visible controls through AT-SPI. Backend tests check invalid arguments,
repeated startup/teardown, expired wrappers, and failed activation cleanup.
`demos/notebook` is the full worked example: searchable notes, a split editor,
save/reload and an in-app `--self-test`/`--gui-test` run in both engines.

The original Nim-shell proof remains available through `testNativeGtkDemo`.
