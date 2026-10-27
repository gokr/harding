# Native GTK counter proof

A GTK4 executable with Granite-compiled Harding state and action blocks.
The counter starts at zero; Increment and Reset update the GTK label. A third
button deliberately raises a Harding error to exercise callback recovery.

## Build and run

Requires Nim 2.2.12, Python 3, `pkg-config`, GTK4 development/link libraries,
and a GTK-compatible graphical session. At runtime it requires GTK4 and its
normal transitive system dependencies. It does **not** require GtkSourceView,
VTE, a Harding binary, application `.hrd` files or the repository.

From the worktree root:

```sh
nim c -p:external -o:granite src/harding/compiler/granite.nim
python3 scripts/build_native_gtk_demo.py --release
./build/native-gtk-counter/native-gtk-counter
# Optional: --mm orc, --dir build/another-directory
```

Copy only the resulting executable to another directory to run it there.

## Acceptance

```sh
nimble testNativeGtkDemo
# Optional real accessibility actions, scoped to each test process by PID:
NATIVE_GTK_ATSPI=1 nimble testNativeGtkDemo
nim c -r --out:build/test_native_gtk_model tests/test_native_gtk_model.nim
```

The test builds an ARC debug binary and an ORC release binary, removes their generated build directories,
then runs each binary three times from a package directory containing only the
executable, with no PATH or Harding home. `--self-test` exercises real GTK
signals and the GLib event loop: increment/reset label text, error recovery,
window destruction, and signal closure release. It also asserts no hybrid
interpreter or scheduler was initialized. It is not a replacement for an
interactive/AT-SPI usability test. Missing display/build dependencies skip the
acceptance test explicitly. The optional accessibility test requires system
Python (`/usr/bin/python3`) with PyGObject and AT-SPI and a matching desktop
session bus; it clicks Increment, Reset and the deliberate-error button and
checks the accessible label, then closes only the owned window. The model test
runs the same `.hrd` source in the interpreter with a test view.

## Scope and limits

- `counter_model.hrd`: application state, formatting and captured action blocks,
  compiled by Granite. It uses an ordinary `CounterView>>text:` interface which
  can also be supplied by an interpreted test view.
- `native_gtk_counter.nim`: handwritten GTK shell, label adapter, native registry
  initialization and C callback exception barrier. The connection registry keeps
  compiled closures and a reference to the label alive until GLib destroys each
  signal closure.
- `scripts/build_native_gtk_demo.py`: stages the shell beside generated Nim and
  builds the native executable. No runtime source loading or VM bootstrap occurs.

This proves a natively compiled GUI program assembled from a native shell and a
compiled Harding model. It is **not** yet a GTK backend for `granite build app.hrd`:
widget construction remains handwritten Nim and the existing interpreter GTK
wrappers are not compiled. The shared Granite support library still imports VM
modules for mixed-mode support; this proof avoids interpreter execution but does
not claim the executable contains no interpreter-related machine code.

Next: make a checked native counterpart for the required existing GTK protocol,
move UI construction into Harding, and retain this binary-only package test as
the acceptance contract. Do not introduce compiler-only selectors.
