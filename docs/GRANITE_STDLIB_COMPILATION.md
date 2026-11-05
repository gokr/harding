# Compiling the standard library with Granite

Status: **plan, not implemented.** Tracked as the next Granite work item. The
design this extends is [PLAN.md](../PLAN.md) section 6 ("Frozen stdlib and the
engine boundary"); this document scopes the one part that section leaves open —
whole-stdlib compilation — and records why it is the right next step.

## The problem

A Granite-compiled program has three implementations of collection and value
behaviour, and they must agree by hand:

| Implementation | Where | Coverage |
|---|---|---|
| Harding standard library | `lib/**/*.hrd` | 395 methods |
| Interpreter primitives | `src/harding/interpreter/` | 136 of those declared `<primitive>` |
| Compiled runtime builtins | `src/harding/runtime/runtime.nim` | 169 `of "selector"` arms |

Granite parses **only the input file**. It loads the stdlib into an interpreter
to obtain an accurate class model for analysis, then discards those method
bodies: generated output contains procs for the methods the user wrote and none
for `Array>>sum`, `Array>>count:` or `SequenceableCollection>>after:`.

The consequence is that any selector the runtime does not hand-implement is a
`MessageNotUnderstood` in compiled code — while the identical program works
interpreted:

```
./harding  prog.hrd   ->  sum: 6
./granite build prog.hrd && ./prog   ->  MessageNotUnderstood: sum
```

Every engine divergence found while building `demos/notebook` came from this
structure, not from any single mistake:

- `add:` answered the collection in two implementations and the element in a
  third;
- `printString` quoted a string in one engine and not the other;
- `indexOf:` handled strings only, answering nil for every array;
- `println` routed through `printString` compiled and `toString` interpreted;
- `superclassNames` answered symbols on one path and strings on another.

Each was fixed by hand, in one or more places. The next one will appear the same
way. Parity tests catch these after the fact; they cannot prevent them, because
the duplication is structural.

## Goal

**One source of truth.** A Granite-compiled program should execute the same
`lib/**/*.hrd` method bodies the interpreter executes, so that "compiled" changes
*how* a method runs, never *what* it answers. Concretely: after this work, no
selector may exist in `lib/` that is missing from a compiled program, and the
hand-written builtin table in `runtime.nim` becomes an optimisation, never a
definition.

## Non-goals

- Not shipping a compiled Bona, image persistence or live redefinition policies.
  Those stay with PLAN.md section 6.
- Not deleting the native builtins. They stay as fast paths, guarded by
  conformance against the compiled stdlib (see "Counterparts" below).
- Not changing language semantics. Any semantic difference uncovered on the way
  is a defect to report, not a decision to make inside this work.

## Current coverage, and why "just bind the classes" is not enough

`--mixed` already reaches stdlib code, by keeping an interpreter alive and
routing unknown sends to it. Measured on a trivial program:

| Build | Startup | Stdlib coverage |
|---|---|---|
| `granite build` | ~3 ms | 169 selectors |
| `granite build --mixed` | ~2.15 s | 100% |

`--mixed` boots an interpreter and loads the stdlib on every run. That is
acceptable for a development build and not acceptable as the definition of
"compiled", which is why it is not the answer.

Binding a chosen set of classes (Array, Table, Set, …) is also not the answer: it
reproduces the same partial-duplication problem class by class, and leaves the
next unbound class with exactly today's behaviour. The gap must be closed by
*compiling the dependency closure*, which is why PLAN.md section 6 already says
freezing is meaningful only as a closure, not per file.

## Approach

Compile the stdlib method bodies into the program, using the machinery that
already exists for user classes.

Granite already loads the stdlib into an interpreter and has, for every stdlib
class, the `BlockNode`s that `loadStdlib` parsed. Emitting those bodies through
the existing code generator gives each stdlib method a native proc, a
`registerCompiledMethod` entry and an interpreted-to-compiled shim — exactly what
a user class gets today:

```
proc Class_4172726179_nt_sum*(self: NodeValue, args: seq[NodeValue]): NodeValue
registerCompiledMethod("Array", "sum", Class_4172726179_nt_sum)
proc shim_Class_4172729299_nt_sum*(interp: var Interpreter, self: Instance, ...)
```

What makes this feasible rather than a rewrite:

- **The ASTs already exist.** `loadStdlib` parses `lib/**/*.hrd` at compile time.
  No new parser path is needed; the work is lifting `Class.methods` /
  `Class.classMethods` bodies into the compilation unit.
- **The codegen already handles the language.** The bodies are ordinary Harding;
  the generator already compiles closures, cascades, `::`, non-local returns and
  primitives for user code.
- **The boundary already exists.** Shims, live method guards, deoptimisation and
  the value-based host send are implemented and tested (`PLAN.md` §6 steps 1-3,
  `tests/test_engine_boundary.nim`).
- **Primitives already resolve.** A `<primitive primitiveX>` declaration must
  continue to reach the interpreter/native implementation rather than being
  compiled as an empty body; the existing primitive registration is the hook.

The delta is a *dependency closure and ordering* problem more than a codegen
problem, which is the honest risk assessment: the generator is proven, the
scheduling of stdlib compilation is not.

## Staged plan

Each stage must leave the tree green: `nimble test`, the parity runner and
`tests/test_engine_boundary.nim` under ARC and ORC. Stages are ordered so the
riskiest dependency work is validated early with a small closure.

### Stage 1 — compile one closed slice

Pick the smallest closure that is still meaningful and compile it for real:
`Object`, `Boolean`/`True`/`False`, `UndefinedObject`, `Integer`, `String`.
These have few dependencies and many primitives, so they exercise the "primitive
body must stay a primitive" path.

Deliverable: a program using `Integer>>factorial`-style stdlib methods that has
no native-only builtin for them, passing parity. Keep the existing native
builtins in place; they should now be *redundant* rather than *load-bearing*.

### Stage 2 — dependency closure and ordering

Compile `Iterable`, `Array`, `Table`, `Set`, `Bag`, `SortedCollection` together
with their parents. This is where the real questions live:

- **Method body references** to classes not yet compiled must resolve to shims,
  not to a missing method. Reuse the existing dynamic-send path.
- **Mixins** (`Iterable`, `Comparable`, `Equatable`, `Printable`) are not modelled
  by native class creation (recorded in PLAN.md §6 step 4). Either teach the
  compiled class model to flatten mixin methods into participants, or compile
  mixin methods per participating class. Decide here, with tests.
- **`copyEmpty`/species** and other `self class`-dependent methods must work
  compiled; this is a live check on class identity across the boundary.

Deliverable: `stdlib_bag` and `stdlib_sorted_collection` parity cases pass
*without* inlining the stdlib source in the test. That inlining is today's
workaround and its removal is the acceptance signal for this stage.

### Stage 3 — counterparts become optimisations, and are checked

Keep the native implementations of hot selectors (`at:`, `add:`, `size`,
arithmetic) but make them *checked counterparts*: each one must have an executed
conformance case against the compiled-from-source version, in the discipline
`examples/manifest.json` and `scripts/check_frozen.py` already establish. A
counterpart without a passing case fails the build.

This is where the divergence class dies: `printString`, `add:` and `indexOf:`
today are three unchecked copies; after this stage they are one definition plus
checked fast paths.

### Stage 4 — startup, size and the `--mixed` decision

Measure and record: binary size, startup time, and the parity suite runtime
before and after. Then decide `--mixed`'s future:

- keep it as a development mode with the source-replay bootstrap it has, or
  retire it once plain `granite build` covers the stdlib.

Either way, record the decision here with the measurements.

### Stage 5 — remove the workarounds

- Delete the "inline the stdlib source into the parity case" hack from
  `scripts/test_granite_parity.py` (`stdlib_bag`, `stdlib_sorted_collection`).
- Reduce the builtin table in `runtime.nim` to selectors that genuinely need
  native representation, each with a conformance case.
- Update `docs/GRANITE_STATUS.md`, this document and `PLAN.md` §6 step 5.

## Risks

| Risk | Assessment | Mitigation |
|---|---|---|
| Compile time grows with the stdlib closure | Real. The stdlib is ~400 methods; Nim compile is the dominant cost today (~13 s for a trivial program after codegen changes). | Measure per stage; compile only the reachable closure, not every class. |
| Binary size | Real, same cause. | Stage 4 measures it; closure-only compilation keeps it bounded. |
| Two class models (interpreter's and the compiled one) drift | The existing risk, unchanged. | Class identity checks in `bindNativeInstanceTo` already refuse mismatched layouts. |
| Primitive declarations compile as empty bodies | Highest technical risk: it would silently change behaviour. | Stage 1 covers primitive-heavy classes first, with parity cases. |
| Mixins not modelled natively | Known open item in PLAN.md §6. | Stage 2 must decide and test it before collections depend on it. |
| Cache interaction | The per-site cache caches negative resolutions; a newly compiled stdlib method must invalidate them. | Existing `compiledClassDispatchVersion` machinery; add a regression that compiles after a cache warm. |

## Acceptance criteria

1. A compiled program reaches **every** public stdlib method; a generated
   inventory check compares the selectors in `lib/**/*.hrd` against the compiled
   program's registered methods and fails on any gap.
2. The parity runner passes with no stdlib source inlined into any case.
3. `tests/test_engine_boundary.nim` passes under ARC and ORC.
4. Startup for a trivial compiled program stays within ~2x of today's ~3 ms.
5. `docs/GRANITE_STATUS.md` records measured before/after numbers, and no claim of
   completeness is made beyond what the inventory check proves.

## What this does not fix

Delegation alone would not fix engine divergence; only a single definition does.
Equally, this work will not find every divergence by itself — it removes the
*cause*. The parity suite remains the detector, and any divergence it surfaces
during this work is a bug to report under the interpreter/language gate, not
something to resolve by adjusting expectations.
