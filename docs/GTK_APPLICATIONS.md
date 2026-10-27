# GTK4 applications in Harding

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
| GtkWindow | `title:width:height:` (class-side), `child:`, `present`, `close` |
| GtkBox | `column:`, `row:` (class-side), `add:`, `equalWidth` |
| GtkLabel | `text:`, `heading:`, `title:`, `muted:` (class-side), `text`, `text:`, `wrap:` |
| GtkButton | `label:action:`, `primary:action:` (class-side), `label`, `label:` |
| GtkWidget | `padding:`, `expand`, `style:`, `center`, individual margins, `setHexpand:`, `setVexpand:` |

Both adapters register the same low-level protocol from
`application_backend.nim`; high-level conveniences are the same `.hrd` methods
compiled by Granite or evaluated by the interpreter. No compiler-only selectors
are introduced. `connect: "clicked" do:` and `emitSignal: "clicked"` are
available for button callbacks and automation. Only the zero-argument void
`clicked` and application `activate` callback signatures are supported initially.
Other signal signatures are rejected, not cast to an incompatible C function.

## Errors and ownership

No Harding exception or return transfer may unwind through GTK's C callbacks.
The callback boundary reports failures and allows subsequent button actions.
An activation failure requests application quit so startup cannot hang. The
`run:activate:` result is an integer: GLib exit status, or 1 if any callback
failed. A script may inspect this result; the existing CLI does not implicitly
convert a returned integer into an OS exit status.

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
The original Nim-shell proof remains available through `testNativeGtkDemo`.
