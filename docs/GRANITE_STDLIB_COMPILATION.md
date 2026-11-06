# Compiling the standard library with Granite

Status: **library method bodies compile; declared primitives remain the only
hand-written leaf.** The design this extends is [PLAN.md](../PLAN.md) section 6
("Frozen stdlib and the engine boundary").

## The problem

A Granite-compiled program used to have three implementations of collection and
value behaviour, which had to agree by hand: the Harding standard library
(`lib/**/*.hrd`), the interpreter's primitives, and a builtin table of
`of "selector"` arms in `src/harding/runtime/runtime.nim`.

Any selector the runtime did not hand-implement was a `MessageNotUnderstood` in
compiled code while the identical program worked interpreted:

```
./harding  prog.hrd   ->  sum: 6
./granite build prog.hrd && ./prog   ->  MessageNotUnderstood: sum
```

Every engine divergence found while building `demos/notebook` came from that
structure, not from a single mistake — `add:` answering differently in three
places, `printString` quoting in one engine and not the other, `indexOf:`
answering nil for arrays, `println` routing through `printString` compiled and
`toString` interpreted, `superclassNames` answering symbols on one path and
strings on another. Each was patched by hand; the next one appeared the same
way, because the duplication was structural.

## Goal

**One source of truth.** A Granite-compiled program executes the same
`lib/**/*.hrd` method bodies the interpreter executes, so "compiled" changes
*how* a method runs, never *what* it answers.

## What is implemented

Granite loads the stdlib into an interpreter, then walks the interpreter's own
**source index** to find every class and side a library file defines. There is
no maintainer's list of classes to compile: adding a class to `lib/` adds it to
the compilation set.

For each library definition the ordinary method pipeline runs. The class model
is shared with application classes, so a library method gets the same block
capture, non-local return, slot access and integer-region treatment as one the
user wrote. Two properties follow:

- **A library method the program overrides wins.** Application definitions
  replace lifted bodies in the generated registry, so the ordinary override
  rule is the only rule.
- **A primitive stays a leaf.** A `<primitive selector>` declaration compiles
  literally: the emitted body is a call to the Nim implementation registered for
  that selector. `src/harding/compiler/primitive_abi.nim` is the entire table.
  Nothing else in the compiler names a selector, and a primitive that has no
  entry is reported as a compile-time gap rather than silently dropped or
  re-implemented.

Storage is deliberately separate from methods. Classes the runtime represents
natively (immediates, `String`, `Array`, `Table`, `Set`, `Block`, `Object`) keep
that representation and its allocator; other library classes get an ordinary
generated layout from their live slot list, so `Bag`, `SortedCollection`,
`Interval`, `Library`, `FileStream`, `TestCase` and friends compile as real
objects.

Many collection and string selector implementations have been removed from
`runtime.nim`. The runtime still contains selector-specific fallback paths and
codegen still contains specialized sends; their final audit is unfinished.
Zero reported gaps establishes declaration coverage for the loaded core/standard
library, not semantic completeness or the absence of every duplicate path.

## Non-goals

- Not shipping a compiled Bona, image persistence or live redefinition policies.
  Those stay with PLAN.md section 6.
- Not deleting the representation primitives. They are the declared leaf of a
  `<primitive>` method, not a second definition of a Harding method.
- Not changing language semantics. Any semantic difference uncovered on the way
  is a defect to report, not a decision to make inside this work.

## Coverage

`granite compile` reports a line per unresolved definition on stderr:

```
stdlib gap: <Class>>>selector (<primitive name>)
```

The current tree reports **zero** gaps on a hello-world compile: every method a
library file defines either compiles from source or resolves to a declared
primitive. `tests/test_stdlib_compilation.nim` asserts exactly that invariant
through the compiler's own `stdlibMethodDefinitions`, so a new library method
that cannot be compiled fails the suite instead of becoming the next silent
divergence.

Method and class counts are not a coverage contract: they depend on the loaded
library inventory. Discovery currently covers `lib/core/` and `lib/standard/`,
not every optional library under `lib/`.

## Boundary

Three rules keep the source of truth single:

1. **A definition in `lib/` is a method.** It compiles.
2. **A `<primitive selector>` declaration is a leaf.** It emits a call to the Nim
   proc named in `primitive_abi.nim`. A selector missing from that table is a
   gap, not an invitation to write a second implementation.
3. **No second implementation of a Harding body.** This is the target invariant.
   The remaining runtime fallbacks and codegen fast paths still need auditing
   against it. Dispatch, native storage and explicit primitive leaves remain.

`--mixed` remains the development fallback and is unaffected: it boots an
interpreter and routes unknown sends to it.

## Staged plan

The work landed in four steps, each validated by the parity runner:

1. **Integer slice** — ten source-backed Integer methods (`factorial`, `gcd:`,
   `lcm:`, ...) compiled through the ordinary pipeline, with no replacement
   allocator. This proved the mechanism and exposed two structural blockers:
   codegen skipped methods whose owner had no generated object type, and runtime
   dispatch skipped compiled registrations for immediate values.
2. **Value slice** — Float, Boolean/True/False, UndefinedObject, String and
   Symbol, with live superclass edges emitted separately from allocation so
   inherited Boolean methods resolve on immediates.
3. **Collection slice** — Array, Table, Set, Iterable, Comparable, Number,
   Equatable, Bag, SortedCollection, Interval. Bag and SortedCollection get
   generated layouts from their live slot lists; the parity cases no longer
   inline library source into the application.
4. **Discovery and closure** — class discovery moved from a maintainer's list to
   the interpreter's source index; class-side aliases the VM publishes on the
   metaclass are lifted too. Host selectors have gained primitive declarations,
   but a complete VM-only-selector audit remains outstanding.

## Open

- **Counterpart conformance.** Specialized helpers such as `nt_plus` and the
  integer-region inlining are fast paths over the same primitive the compiled
  method calls, so agreement is structural rather than tested per helper. A
  differential test over the fast path and the compiled body would close it.
- **Interpreter-side duplication.** `src/harding/interpreter/vm.nim` still
  implements some value primitives (`primitivePlusValueImpl` and friends) that
  `src/harding/core/value_primitives.nim` also provides. Collapsing them is the
  same boundary applied to the interpreter, not a compiled-code concern.
- **`--mixed` and frozen builds** keep their previous path: they still rely on
  the host. Bringing the same closure to a checked frozen build is the remaining
  checklist item for image-style packaging.
