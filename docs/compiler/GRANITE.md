# Granite: the Harding compiler

Granite compiles Harding to Nim, then to a native binary. This document states
what compiles today, how the two engines share one AST, what the compiled
representation guarantees, and where the known gaps are.

It replaces five overlapping documents. Their measured detail is preserved in
`research/compiler/`:

| Was | Now at |
|---|---|
| `GRANITE_STATUS.md` | `research/compiler/GRANITE_STATUS.md` (work record, per-slice evidence) |
| `GRANITE_STDLIB_COMPILATION.md` | `research/compiler/GRANITE_STDLIB_COMPILATION.md` (design rationale) |
| `GRANITE_EXAMPLE_AUDIT.md` | `research/compiler/GRANITE_EXAMPLE_AUDIT.md` (coverage report at its revision) |
| `TYPE_INFERENCE_FEEDBACK.md` | §Inference below; detail archived |
| `TRUST_OBSERVED_TYPES.md` | §Inference below; detail archived |

Optimisation slices — what was tried, what it measured, what was rejected — are
indexed in [GRANITE_PERFORMANCE.md](GRANITE_PERFORMANCE.md). Compiled
representation contracts for collections and JSON are in
[GRANITE_RUNTIME.md](GRANITE_RUNTIME.md).

## Two engines, one AST

Source is canonical. The interpreter is the reference implementation; Granite
compiles the same AST and must produce the same answers. That agreement is
enforced mechanically rather than reviewed by hand:

```sh
nimble harding
nim c -p:external -o:granite src/harding/compiler/granite.nim
python3 scripts/test_granite_parity.py            # all cases
python3 scripts/test_granite_parity.py qualified_super   # focused
```

The parity runner builds each case, runs both engines, and compares output
against an explicit expected result in its own directory under `build/parity/`.
A timeout, failed build, failed engine or wrong output fails the run. **Missing
binaries fail rather than skip.**

The current suite is 117 cases. One case has a build timeout in a full sweep and
passes in 11 seconds on an isolated rerun, so the honest statement is "117 cases
pass across the sweep and rerun, not in one uninterrupted run".

`examples/manifest.json` is the second gate: every `.hrd` under `examples/` and
`benchmark/`, plus every Harding fence in the website Markdown, is inventoried
and executed with reviewed stdout (`nimble testExamples`). Known compiler
failures are listed explicitly and are not counted as successes.

## What compiles

### The standard library

Granite loads the stdlib into an interpreter, then walks the interpreter's own
**source index** to find every class and side a library file defines. There is no
maintainer's list of classes to compile: adding a class to `lib/` adds it to the
compilation set, provided discovery covers that directory.

- Discovery covers `lib/core/` and `lib/standard/`. Optional libraries under
  `lib/{gui,web,mummyx,reactive,process,mysql,corral,granite}` are not covered by
  that claim.
- Each library definition goes through the ordinary method pipeline, so a
  library method gets the same block capture, non-local return, slot access and
  integer-region treatment as user code.
- A program's own definition **wins**: application definitions replace lifted
  bodies, so the ordinary override rule is the only rule.
- A `<primitive selector>` stays a leaf. The emitted body calls the Nim
  implementation registered for that selector; `src/harding/compiler/primitive_abi.nim`
  is the entire table, and a primitive with no entry is reported as a
  compile-time gap rather than silently dropped or re-implemented.

`granite compile` prints one line per unresolved definition:

```
stdlib gap: <Class>>>selector (<primitive name>)
```

The current tree reports **zero** gaps on a hello-world compile.
`tests/test_stdlib_compilation.nim` asserts that invariant through the
compiler's own definition walk, so a new library method that cannot be compiled
fails the suite instead of becoming the next silent divergence.

Zero gaps establishes *declaration coverage for the loaded library*, not
semantic completeness. Selector-specific fallbacks remain in `runtime.nim` and
specialized sends remain in codegen; their audit is unfinished.

Storage is separate from methods. Classes the runtime represents natively
(immediates, `String`, `Array`, `Table`, `Set`, `Block`, `Object`) keep that
representation and its allocator. Other library classes get an ordinary
generated layout from their live slot list, so `Bag`, `SortedCollection`,
`Interval`, `Library`, `FileStream` and `TestCase` compile as real objects.

### Language surface

Covered with executed parity:

- message sends in all three forms, cascades, and implicit returns (compiled
  methods answer `self` on fallthrough; class-side returns preserve the actual
  class receiver);
- first-class and escaped blocks with shared mutable capture cells, including
  write-only enclosing temporaries and capture through specialized control-flow
  and named-access nodes;
- non-local return, with `BlockCannotReturn` for a return to a finished home;
- class-side methods, inherited lookup, factories, overridden `new`, and
  class-side and qualified `super`;
- multiple inheritance with declaration-order depth-first parent walking and a
  cycle guard, matching interpreter lookup order; `addSuperclass:` at runtime;
- `super<Parent>`, lexical, on instance and class side and through blocks;
  invalid and indirect-ancestor qualifiers fail in both engines;
- exceptions: handler results, `pass`, `retry`, synchronous notifications, and
  `ensure:` running exactly once on normal completion, errors and non-local
  returns, nested innermost-first;
- catchable `MessageNotUnderstood` from generic instance/class/super lookup and
  from a missing dynamic `perform:` target, instead of nil;
- `perform:`/`perform:with:`/`perform:with:with:`, `respondsTo:`,
  `doesNotUnderstand:` on the normal work queue;
- built-in collection construction (`Array`/`Table`/`Set`/`String`
  `new`/`new:`/`new:withAll:`, table literals, `add:`, `includes:`), array and
  set query protocol, `Bag`;
- `json{...}` literals building JSON strings natively, `Json stringify:`,
  `Json parse:` with nested scalars/arrays/tables, cycle detection, and
  round-tripping;
- `class`, `className`, `class name`, `superclassNames` in declaration order,
  and `isKindOf:` searching all parent branches;
- `System arguments` without the executable name; `withIndexDo:` with
  zero-based index; `asNumber` preferring Integer then Float;
- `Log` and `FileStream` logging through ordinary dispatch;
- declared slot contracts enforced at allocation, `::` writes, generated setters
  and reflective `at:put:` — see [DECLARED_SLOTS.md](../DECLARED_SLOTS.md).

### Engine boundary and mixed mode

Compiled and interpreted code call each other through explicit binding:

- generated instance and class-side shims expose compiled bodies to interpreter
  dispatch, preserving the actual class receiver for inherited sends;
- explicitly bound instance sends check live method resolution before
  cache/native dispatch, so runtime replacements and subclass overrides fall back
  correctly;
- engine selection uses receiver ownership rather than source reconstruction or
  retrying nil results;
- interpreted methods and VM block entry points invoke compiled callbacks with
  0–3 arguments, validating arity before the pointer call;
- explicit native-instance binding validates layout and exposes authoritative
  native fields to interpreted methods, slot reflection, JSON and shallow
  cloning, with no mirror slot array;
- statically named allocations in bound methods use the receiver's live `new`
  protocol; uppercase global reads and writes go through the host VM, preserving
  library bindings and protected names;
- bound builtin helper sends consult the host first, so runtime overrides hold,
  while operands are evaluated once before routing.

`--mixed` keeps unbound code on the interpreter. Mixed-mode dispatch coverage is
incomplete; see gaps below.

### Granite inside the VM

The `Granite` class exposes the same pipeline to in-VM callers, so Builder can
compile from a running image. Both entry points share the core pipeline
(`COMPILATION_PIPELINE.md`); keeping them from diverging is ongoing work.

## Inference and slot contracts

Type information is **advisory by default**. Nothing here narrows storage or
changes a program's answer.

**Static candidates** (`src/harding/compiler/slot_inference.nim`) combine three
sources of evidence within the analysed module: literal and `Class new` writes,
call-site arguments propagated into method parameters, and return values of
`self`/`super` sends propagated into further expressions.

**Interpreter feedback** records the types a training run actually observed. The
two are reconciled; a numeric contradiction is reported rather than auto-widened.
See [DECLARED_SLOTS.md](../DECLARED_SLOTS.md) for the enforced part and
`research/compiler/GRANITE_SLOT_TYPE_INFERENCE.md` for the measured feasibility of
inferring slot types, including why inference rather than declaration must carry
the workload.

**Opt-in specialisation to observed types** deliberately changes the artifact's
contract:

```sh
./harding --type-feedback build/profile.json benchmark/richards.hrd
./granite build benchmark/richards.hrd --dir:build/trained \
  --type-feedback:build/profile.json --trust-observed-types \
  --inference-report:build/trained/report.json
```

The built binary is specialised to the types seen in the training run. A program
whose runtime types differ from the profile can then behave differently from the
interpreter. That is the point of the flag, and the reason it is not the default.
`nimble testTypeFeedback` and `nimble testSlotContracts` validate both modes.

## Known gaps

Ordered by what a user is most likely to hit.

| Gap | Consequence |
|---|---|
| Object JSON plan caching | Slot layouts, inherited representation hooks and class JSON specs work natively; the effective field selection is rebuilt per write rather than cached. |
| Collection conformance | `SortedCollection` and `Bag` compile from stdlib source. Their full Smalltalk-80 selector, species and equality conformance is not established. |
| Mixed mode | `--mixed` dispatch does not cover every path; unbound code runs interpreted. |
| Collection identity and layout | Mutation aliasing is covered; general identity/layout parity and cyclic-object lifetime are not. |
| Reflection | Class-slot support and general reflection parity remain open. Method-list reflection works; source reflection from the language does not exist in either engine. |
| Diagnostic parity | Uncaught compiled errors run `defaultAction`, print the header, and exit non-zero; diagnostic/stack-trace *formatting* differs between engines. |
| Processes across the boundary | Process boundaries and legacy re-entrant native invocation are unverified. |
| Frozen stdlib | The freeze gate (`config/granite-frozen.json`, `nimble testFrozen`) is experimental: syntactic dependency closure, a manifest and a local receipt. Dynamic closure, whole-stdlib compilation and automatic mixed startup are not established. |
| Automatic instance binding, layout migration, cross-engine control transfers, generated bootstrap replay, sealing | Open; PLAN.md section 6 owns the design. |

`--seal-frozen` rejects subsequent native registry writes and direct application
redefinitions before reflection. It does not prove alias/dynamic mutation safety,
does not seal VM classes, and does not protect direct Nim access. It is not full
redefinition enforcement.

## Performance

Current cross-engine numbers are in
[performance/BENCHMARKS.md](../performance/BENCHMARKS.md). The short version:
Granite is roughly two orders of magnitude faster than Harding's own release
interpreter and materially slower than Cog, GNU Smalltalk, CPython and native Nim
on the recorded workloads. Being compiled via Nim does not currently imply
Python-level performance.

Every optimisation slice, its measurement and its rejected alternatives are
indexed in [GRANITE_PERFORMANCE.md](GRANITE_PERFORMANCE.md).

## Validation entry points

```sh
nimble harding                    # interpreter
nim c -p:external -o:granite src/harding/compiler/granite.nim
python3 scripts/test_granite_parity.py
nimble testExamples               # example audit, both engines
nimble testTypeFeedback
nimble testSlotContracts
nimble testFrozen
```

The nimble test tasks mask failures with `|| true`; inspect actual test output or
use direct `nim c -r` for focused validation. A green task exit is not proof that
tests passed.

Validation is normally run under both ARC and ORC when touching proxy lifetime,
callbacks or cross-thread services. Do not treat a headless test as an
event-loop or UI acceptance test.
