# Granite profiling: bounded instance-method resolution cache

## Identity-keyed send caches for native receivers

Send caches were keyed by receiver class *name*: every hit resolved the class
name and then compared two strings. Method resolution itself is name-based, and
the registration version already invalidates entries on any install or
replacement, so an instance receiver can be keyed by its class identity instead.
A hit then compares one pointer and calls the cached target; the cached negative
path reuses the identity's name for the builtin chain.

Class-side, builtin-value and unbound native receivers keep the name-keyed path,
so selector semantics for `perform:`, the exception protocol and late binding are
unchanged. Two distinct Class objects with the same name still share resolution
(a pointer miss falls through to the name entry, which answers the same target).

Pinned alternating pairs against `run-moqha29e`, candidate `run-z7ezo7hx`:
**DeltaBlue 3.45% faster (26/31)**, Queens 0.87% faster (18/31), Richards 0.33%
faster (17/31); 21-pair run agreed at 3.85%/2.22%/0.05% (`build/dispatch-ptr-pinned*.log`).
Only DeltaBlue is outside local noise; the other two are unchanged rather than
regressed.

## Getter-pair arithmetic and class-side reference parameters

Reference inference now applies to class-side methods using getter receivers,
without mistaking their metaclass receiver for an instance-slot owner. Two
immutable entry-guarded reference parameters can supply native Integer getter
operands. Both getter method identities and native storage accessors are checked
before field reads; any failure runs ordinary getter sends left to right.
No arbitrary receiver expressions or callbacks are moved across the guards.

This reaches DeltaBlue's `DBStrength class>>stronger:than:` and `weaker:than:`:

```nim
# Shape with names shortened; result retains the dynamic method ABI.
if rankReferenceGuard(left) and rankReferenceGuard(right):
  NodeValue(kind: vkBool, boolVal:
    Strength(left.compiledOwner)[].rank < Strength(right.compiledOwner)[].rank)
else:
  # Existing dynamic getter sends and comparison.
```

DeltaBlue's reference parameter count grows from seven to eleven, with two native
getter-pair expressions in generated code. The repeated-result boxing has gone
inside these expressions, but entry guards, class-method dispatch and the boxed
result remain. Pinned 21-pair measurement versus `run-bvdxlsjj`, candidate
`run-moqha29e` (`build/gp-pinned.log`) is neutral: Richards 0.12% slower (10/21),
DeltaBlue 0.29% slower (8/21), Queens 0.28% faster (12/21). No speedup is claimed.

Executed integration under ARC/ORC covers native operands, subclass fallback,
Float-returning getter replacement, two side effects in left-to-right fallback
order, accessor replacement and interpreter-bound class-side calls. The new
getter-pair parity case also covers custom receivers and nil. Compiler (120),
runtime (48), boundary (39), stdlib (6) and slot-inference (32) suites pass under
both managers. Broad parity passes 129/129 (`build/gp-full-parity.log`). Generated
benchmark programs verify 30 release-ORC passes each. This is not a full
repository-suite claim.

## Getter receiver evidence and direct reference reads

A unique generated getter now proposes its receiver class for a method parameter,
in addition to evidence from declared-slot writes. This remains speculative:
non-signaling argument guards check actual conformance, and nil or unmatched
receivers use the existing dispatch/fallback at the read. Getter results still
retain their dynamic `NodeValue` ABI; a runtime replacement is not forced into
the declared field type.

The additional entry takes an owning `Instance`. A reference getter helper checks
method identity and native layout directly on that reference, then reads the
field without first constructing a boxed receiver. A boxed receiver is constructed
only on fallback. Helpers are emitted lazily for getters actually reached by
specialized bindings, rather than generating wrappers for every slot. The boxed
method/slot guards keep their original hot-path structure; reference overloads
have equivalent checks and share version invalidation.

Inspection of the retained final candidate `run-bvdxlsjj`: Richards grows from
one to three reference parameters and emits two reference helpers; DeltaBlue
six to seven and two helpers; Queens has none. These still cover only a small
part of graph traversal. The first broad implementation regressed Richards and
DeltaBlue by ~3–4% in local pinned tests. Lazy helper emission and preserving boxed
checks reduced the final comparison to Richards 0.56% slower (6/21), DeltaBlue
0.00% slower (11/21), Queens 0.14% slower (10/21) against `run-7ec4jixy`
(`build/receiver-final-pinned.log`). No execution-time improvement is claimed.
This keeps the inference foundation without claiming broader native execution
than the generated code actually reaches.

The initial broad sweep passes 128/128 (`build/rg-full-parity.log`). Later lazy
helper emission and preservation of boxed guards pass focused compiler (119),
runtime (48), boundary (39), stdlib (6), slot-inference (32), and executed native
reference/direct-slot integration under ARC and ORC. Generated benchmark programs
verify 30 release-ORC passes each. The new reference-getter parity case also
passes separately, including its ORC execution. This is not a full repository-suite
claim.

## Reference parameters and getter-to-store fusion

Slot-contract writes propose object parameter types. A method's additional native
variant accepts owning `Instance` parameters after a non-signaling entry guard
checks actual class conformance or nil. Failed guards run the original body:
a method can handle an incompatible argument before ever writing a slot, so the
guard must not raise. Assigned parameters, captured bindings, shadowing and
conflicting contracts are excluded. Numeric and reference parameters share one
variant rather than multiplying combinations.

A matching parameter can flow directly into a native reference field. The store
still checks receiver layout, slot accessor identity, host routing and the
registration version captured at method entry. Callbacks can replace methods or
accessors between entry and store; a changed epoch or accessor takes the checked
ordinary store. Other operations and returns box only at their existing ABI
boundaries; this is not yet a wholly reference-typed method ABI.

Compatible generated object getters can also feed a reference field directly:

```nim
let sourceReceiver = evaluateReceiverOnce()
if getterMethodAndLayoutGuard(sourceReceiver) and destinationLayoutGuard(self):
  let reference = Source(sourceReceiver.instVal.compiledOwner)[].item
  Destination(self.instVal.compiledOwner)[].item = reference
  compiledObjectSlotValue(reference)  # assignment result only
else:
  # Ordinary getter and checked store; no receiver re-evaluation.
```

The getter-result path is guarded at the actual read, not inferred unconditionally
from its selector: a replacement returning an incompatible value still executes
and raises at the original checked store. Nil, subclasses and VM-backed storage
retain their normal semantics.

Generated benchmark inspection: Richards gains one `Instance` parameter,
DeltaBlue six, Queens none. No compatible getter-to-store fusion appears in these
benchmark sources yet; the executed reference integration test covers it.
Pinned 21-pair comparisons against `run-vpkcd3hp`, candidate `run-7ec4jixy`:
Richards 1.30% slower, then 0.23% slower; DeltaBlue 0.06%/0.22% faster;
Queens 0.13% faster/0.17% slower (`build/object-abi-pinned*.log`). No benchmark
speedup is claimed. This widens connected native reference regions but reaches
only a small fraction of the measured graph traffic so far.

The initial full sweep passes 126/126 (`build/object-abi-full-parity.log`); the
new parameter/getter parity case passes separately. Compiler 116, runtime 47,
boundary 39, stdlib 6 and slot-inference 32 pass under ARC/ORC. Executed reference
integration also verifies missing arguments, incompatible-argument early handling,
mutation/capture exclusions, subclass receiver fallback, receiver side effects,
method/accessor replacement after warmup and callback-time setter replacement.
Final conservative numeric-binding exclusions and the expanded bound-host tests
pass the focused compiler/reference suites under both memory managers.

## Compact owning storage for declared object slots

Declared object contracts now generate an `Instance` field rather than a
`NodeValue`. On this host that is an 8-byte owning reference instead of a
32-byte variant. A checked write retains the original instance (including its
`compiledOwner`); reads reuse it without creating another wrapper. Nil is stored
as an empty reference, and invalid writes are rejected before replacing storage.
Generated subclasses and interpreted instances remain accepted by the existing
class contract. This changes storage, not interpreter behavior or slot semantics.

This is deliberately not yet `link: Packet`. Each generated class currently has
an independent layout rooted at `HardingObject`, so Harding subclasses cannot
safely be cast to their parent's generated Nim type. Retaining `Instance` avoids
that invalid cast while narrowing the storage. Typed method signatures and direct
native-owner references require a further guarded representation/ABI step.

Object contracts were added to already-defined class references in the two
benchmarks. Forward/self references are not added: interpreter resolution of
symbolic class declarations currently needs an already-bound class. Arrays and
genuinely dynamic slots remain unchanged. Measured native object sizes:

| Class | Before bytes | After bytes |
|---|---:|---:|
| RichardsTaskControlBlock | 176 | 152 |
| RichardsDeviceTask | 96 | 72 |
| RichardsHandlerTask | 128 | 80 |
| RichardsScheduler | 224 | 176 |
| DBVariable | 232 | 184 |
| DBConstraint | 96 | 72 |
| DBBinaryConstraint | 168 | 96 |
| DBScaleConstraint | 232 | 112 |
| DBPlan | 64 | 40 |

Artifacts: `build/object-layout-sizes.log`. Both size builds use identical typed
benchmark source. Old compiler `run-juuf3_tj/granite` produced the retained
`build/object-storage-baseline` binaries; the candidate is `run-vpkcd3hp`.
The first compact-storage candidate (`run-vu_nb6jm`) was near neutral. Its longer
profile showed repeated hierarchy traversal on contract writes. The final helper
accepts nil/exact-class references directly and retains the old checked hierarchy
path for other cases, including subclasses.

Pinned alternating 21 pairs, 30 verified passes (`build/object-ref-final-pinned.log`):
Richards **11.01% faster (19/21)** versus the old compiler on the *same typed
source*. DeltaBlue and Queens are neutral. A separate end-to-end comparison with
the previously untyped benchmarks (`build/object-ref-end-to-end.log`) is neutral
for all three: Richards 0.47% slower, DeltaBlue 0.34% slower, Queens 0.39% slower
by median pair. Added contract checks offset storage savings, so no end-to-end
benchmark speedup is claimed for this slice.

Executed native/VM bridge tests cover ownership after the creating scope ends,
identity, alias mutation, nil, subclasses, inherited slots, rejection without
mutation, method and direct slot access, accessor replacement and a bound host
under ARC/ORC. Runtime arguments and getter results still cross `NodeValue`
boundaries; narrower field storage alone cannot remove those costs.
Focused compiler/runtime/boundary/stdlib/slot-inference suites pass under ARC/ORC;
all three generated benchmarks verify 30 release-ORC passes. The new compact-slot
case also passes both-engine parity and executes under ORC. The broad sweep
passes 125/125 (`build/object-storage-parity.log`) on the initial compact-storage
candidate; the later exact-class helper fast path passes the focused suites and
new compact-slot regression. This is not a full repository-suite claim.

The final checked native comparison (`build/native-compare/run-5u_cbj5v`, seven
pairs, 300 passes) measures Richards 16.403/5.513/0.210 ms per pass for
Granite/CPython/native Nim and DeltaBlue 19.213/5.809/0.149 ms. Paired native time
ratios are 74.00x and 127.18x respectively. These remain representation-reference
comparisons, not proof of semantics-equivalent native speedups.

## Where the remaining gap is, measured against hand-written Nim

`scripts/bench_compare_native_nim.py` runs Granite, the mechanically translated
CPython, and the hand-written Nim port under `benchmark/native/` on matched
workloads. Per pass, 300 passes, release ARC, pinned (historical measurements):

| Workload | Granite | CPython | Native Nim | Granite/Native | CPython/Native |
|---|---:|---:|---:|---:|---:|
| Richards | 13.171 ms | 4.269 ms | 0.165 ms | 79.68x | 25.83x |
| DeltaBlue | 19.624 ms | 7.211 ms | 0.163 ms | 120.74x | 44.37x |

Native Nim is ~80-120x faster than the generated program, so Granite is roughly
3-4x further from idiomatic Nim than CPython is. Queens is the exception and is
already near CPython; these two workloads are the remaining gap.

The native port's representation is an important difference:

```nim
Packet = ref object          # our generated RichardsPacket fields:
  link: Packet               #   link: NodeValue   <- boxed ref
  identity, kind, datum: int #   datum/identity/kind: int
  data: array[4, int]        #   data: NodeValue   <- boxed Array
```

At that revision only scalar slots narrowed to native fields. Object references,
arrays and tables still used `NodeValue`. The compact-storage slice above now
narrows declared object fields, but not their method arguments/results.

These native ports are representation references, **not semantic-parity oracles**:
Richards embeds task variants and fixed arrays and avoids scheduler back-reference
cycles; DeltaBlue uses Float64 values and integer strength ranks. The large timing
gap cannot be attributed entirely to boxing. The comparison runner now checks all
stdout/stderr, verifies retained source/binary hashes and writes each run into a
separate directory; earlier runs did not enforce those output checks externally.
A checked 300-pass/7-pair run (`build/native-compare/run-5a5tf4rl/results.json`)
reports Granite/native paired time ratios 89.09x (Richards) and 131.28x (DeltaBlue)
for the initial compact-storage candidate. Absolute native timing is especially
sensitive to startup and host variation. Use these as structural references, not
as a measured upper bound on a semantics-preserving compiler improvement.

## Derived parameters for native regions

`numericParameterCandidates` only proposed a parameter when an operator used it
directly. Richards' `xor16:with:` writes `a := left` and then divides `a`, so
`left` never met an operator and the whole method stayed boxed. Two additions:

- `enablingParameters` seeds each parameter as Integer and keeps it when some
  temporary becomes provably numeric that otherwise was not. Seeding is
  speculative; the existing entry guard still checks the runtime argument kind
  and falls back to the dynamic body for anything else.
- `//` now keeps the Integer representation. It is Harding integer division and
  still routes through `compiledIntegerDiv`, which signals DivisionByZero exactly
  as `nt_slashslash` does, so a zero divisor is a Harding error rather than a Nim
  Defect. `/` stays dynamic because it may produce a Float.

`xor16:with:` now generates as `proc (...hardingNative_left: int,
hardingNative_right: int)` with every local as `int`.

Pinned ARC, 30 verified passes, 21 pairs against `run-vrg6psq3`, candidate
`run-juuf3_tj`: Richards **13.01% faster (21/21)**; Queens 0.54% slower (6/21)
and DeltaBlue 0.98% slower (8/21), both within local noise and unchanged in
generated code beyond parameter selection.

Two mistakes worth recording, both caught by measuring: the first version
replaced the positional candidates instead of adding to them, which dropped
Queens from 10 native bodies to 2 and doubled its runtime; the second passed the
parameter-exclusion list where the captured-name list belongs, so every temporary
was excluded and nothing specialized. A pre-existing compiled/interpreter
difference also surfaced: `//` on a Float returns `nil` when compiled while the
interpreter raises MessageNotUnderstood. That reproduces at the previous commit
and is unrelated to this change.

## Source-derived nil condition chains

The compiler expands pure `Object>>notNil`/`isNil` self-call chains from their
loaded ASTs, through source-defined equality to identity comparison and
source-defined Boolean negation. This is not an unconditional nil-pointer test:
every expanded receiver method and both Boolean negation bodies must still match
the compiled source registrations. Exact native receivers are checked; changed
methods, class-specific overrides, VM-owned objects and bound hosts fall back.
The receiver expression is evaluated once by the generated condition helper.

Expected class identities are cached per registration version. The first
prototype repeatedly called `compiledClassValue` inside dependency guards and
left hash lookups prominent in the profile; caching identities removed that
self-inflicted cost without dropping dependency validation. It still generates
an exact-class case split, so this remains a guarded region, not yet a typed
whole-loop receiver.

Release ARC, 30 verified passes, 21 pinned pairs, baseline `run-hpbdni50`, final
candidate `run-vrg6psq3`, `build/nn-final-pinned.log`: Queens **46.69% faster
(21/21)**, Richards **15.31% faster (19/21)**, DeltaBlue 0.60% faster (13/21,
inconclusive). Profiled cached-send calls in Queens fall from 6,563,344 to
1,661,584; native nil guards, typed getter guards, boxed object lifetime and
allocation remain. Short gprof samples cannot precisely rank closely sized costs.

### Startup check and longer repetitions

The 30-pass run measured Granite zero-work medians of 1.97–2.60 ms, under 0.5%
of total run time. CPython zero-work medians were 10.16–15.61 ms (3–9%). Thus
startup did not explain Granite's gap; it made the raw ratio look slightly better
than the startup-subtracted ratio.

Absolute per-pass times swung by up to 2.5x between runs (`run-js2aedg2` Queens
16.97 ms/pass versus `run-vk3mupyc` 43.16 ms/pass), and CPython swung with it
(13.17 versus 28.21). That is host load and clock variation, not program
behaviour. Paired ratios were far more stable: repeated runs of one candidate
agreed at 2.22x/2.24x and at 1.03x/1.16x. Report ratios, not absolute times.

Ratios are Granite net time divided by CPython net time, so lower is better.
"Previous" is `run-hpbdni50` (Boolean specialization only); "Final" is
`run-vrg6psq3`. Each row is one independent 300-pass run except where noted.

| Candidate | Richards | DeltaBlue | Queens |
|---|---:|---:|---:|
| Previous, 100 passes (`run-nth6r55k`) | 4.23x | 3.13x | 2.22x |
| Previous (`run-55saao3s`) | 4.05x | 3.24x | 2.24x |
| Nil, before identity caching (`run-cp39fiwz`) | 3.95x | 3.46x | 1.74x |
| Final, CPU 2 (`run-js2aedg2`) | 3.49x | 3.33x | **1.03x** |
| Final, CPU 13 (`run-vk3mupyc`) | 4.04x | 3.28x | **1.16x** |

Queens is now roughly **1.0-1.2x** CPython's time across two independent runs of
the same binary. Individual Queens pairs ranged 0.78-1.61x, so this is parity
within measurement noise, not a demonstrated win. Richards (~3.5-4.0x) and
DeltaBlue (~3.2-3.5x) are largely unchanged and remain the real gap.

Longer runs removed startup contamination but not CPU contention; on this shared
host no ratio should be treated as portable. Artifacts: `run-nth6r55k`,
`run-55saao3s`, `run-cp39fiwz`, `run-js2aedg2`, `run-vk3mupyc` under
`build/python-pinned/`.

## Source-derived Boolean conditions and the CPython gap

Native Boolean projections are derived from the loaded `True` and `False`
Harding method ASTs. A single literal/argument return can be compiled as a native
Boolean body; arbitrary sends, side effects, temporaries and multi-statement
methods are not accepted. The current selector is `|`. No Boolean truth table is
reimplemented in the runtime. Both receiver-class method registrations are
version-checked before entry, and interpreter-bound execution retains ordinary
dispatch. A changed source definition changes the native body; runtime method
replacement disables it until the original registrations are restored.

Only a condition composed of proven numeric comparisons and these pure Boolean
calls qualifies. Both operands are bound eagerly, left to right. It therefore
cannot introduce Nim short-circuit behavior, hide side effects in arbitrary
operands, or speculate past a callback. Queens' guarded region now carries its
numeric differences through comparisons and connective calls as native values.

Release ARC, 30 checked passes, 21 pinned alternating before/after pairs:
`run-k7uq6tkw` versus `run-hpbdni50`, `build/bn-pinned.log`:
Queens **15.44% faster (18/21)**; Richards 0.46% slower (8/21), DeltaBlue 0.78%
faster (12/21), with no conclusive gain for those two workloads.

The Queens profile no longer shows executed `nt_pipe` calls; `nt_not` remains
at 2,922,480 calls through `Object>>notNil`, with zero sampled self time in this
short profile.
Remaining costs include strings/class-name extraction, boxed copies, cached sends,
`Object>>notNil`/identity equality, linked-object access and allocation. Short
sampling profiles are approximate; inlined call-graph arcs are not exact counts.
Richards and DeltaBlue still show substantial copy/destroy/allocation costs and
object/collection sends rather than a dominant arithmetic kernel.

### Matched CPython comparison

`python3 scripts/bench_compare_python_pinned.py <retained-run> --trials 15`
compares retained, hash-verified Granite binaries to the mechanically translated
Python versions of the same algorithm. Typed slot declarations are accepted by
the Python adapter, retaining slot names, ordering and workload checks. This is
not the upstream AWFY Python program and not a claim of complete language parity.
Both engines run 30 passes, with answer checks, CPU 2 affinity, one discarded
warmup, alternating engine order and alternating work/zero-work order. Raw
process time includes startup; net time subtracts the measured zero-work run.

Artifacts: `build/python-pinned/run-g85jdu4f/results.json`,
`build/bn-cpython.log`; CPython 3.12 (see the exact version in the artifact).

| Workload | Granite raw ms/pass | CPython raw | Paired time ratio | Granite net | CPython net | Net ratio |
|---|---:|---:|---:|---:|---:|---:|
| Richards | 17.449 | 4.572 | 3.84x | 17.361 | 4.105 | 4.22x |
| DeltaBlue | 19.705 | 6.512 | 3.02x | 19.636 | 5.982 | 3.24x |
| Queens | 23.410 | 11.165 | **2.10x** | 23.326 | 10.863 | **2.16x** |

Ratios are medians of paired ratios, not ratios of the marginal medians. Host
load is uncontrolled, so these are local observations rather than portable
scores. The previous ~3–4x Queens gap has narrowed materially, but CPython
parity is not reached. The next large opportunity is typed nullable receiver
flow across `notNil`/`previous` and recursive call boundaries, with guards at
region boundaries rather than replacing Harding methods with native shortcuts.

## Unobserved result write-backs are omitted

A method-wide identifier-read count is compared with reads rewritten inside a
native getter region. If all reads of a result occur in that prefix/condition,
its native value need not be copied back to the outer boxed local. Captured
bindings are already excluded; missing scope information retains the store.
Any read in a branch, subsequent statement, return, nested closure or other
region conservatively retains it. This is a limited liveness proof, not general
dead-store elimination across control flow.

Generated-code comparison shows exactly two deleted assignments in Queens:
`distance = NodeValue(...)` and `delta = NodeValue(...)`. Richards and DeltaBlue
have byte-identical generated Nim before and after this change.

Pinned 21-pair trials against `run-yzy8gufu`, candidate `run-k7uq6tkw`:
`build/live-pinned.log` found Queens 1.99% faster (15/21),
`build/live-pinned2.log` found 2.89% faster (16/21). Richards was within noise;
DeltaBlue measured 2.24% and 0.76% slower despite identical generated code.
Consequently this is evidence of a smaller Queens gain, with no performance
claim for the other workloads. Marginal Queens medians in the second run were
35.904→35.609 ms/pass; percentages are median paired reductions.

Focused suites pass under ARC and ORC: compiler (111), runtime (47), boundary
(39), stdlib compilation (6), and slot inference. All three generated benchmark
programs also run 30 answer-checked passes under release ORC. Executed region
regressions preserve branch, loop-condition and returned-result observations;
direct-slot integration exercises both managers. The broad parity sweep passes
123/123 (`build/live-full-parity.log`), with the subsequently expanded
loop-condition case also passing separately under ARC and ORC.

## Getter results remain native through the following conditional

The next region pass recognizes a pure assignment prefix of an inlined block
followed by a numeric conditional. Guards validate the generated typed getters
before the prefix runs. Getter receivers must be uncaptured lexical bindings,
not arbitrary expressions. No callbacks occur between these checks and field
reads. Each difference is computed into a native `let`, which the conditional
uses directly instead of redispatching arithmetic and equality on `NodeValue`s.

Outer boxed locals are synchronized after each assignment, preserving values
visible to branch bodies, subsequent statements and later iterations. The region
does not speculate through callbacks, escaping captures, arbitrary receiver
expressions or block-local scopes. Guard failure executes the original prefix
and conditional; no operation is replayed after partially running a fast path.
Boolean `|` remains a Harding send, preserving eager evaluation and replacement.

For Queens, the generated fast branch now has the shape (names shortened):

```nim
if not hostRoutingActive() and rowGuard(current) and columnGuard(current):
  let nativeDistance = r - Placement(current.instVal.compiledOwner)[].row
  distance = NodeValue(kind: vkInt, intVal: nativeDistance)
  let nativeDelta = c - Placement(current.instVal.compiledOwner)[].column
  delta = NodeValue(kind: vkInt, intVal: nativeDelta)
  # Comparisons use nativeDelta/nativeDistance, not the boxed outer locals.
  # Boolean connectives and branch bodies keep their ordinary code generation.
else:
  # Original assignments and conditional.
```

Pinned alternating pairs, 30 verified passes, 21 trials:
`run-85rqp6ga` versus `run-hqcxtf39`, `build/region-pinned.log`:

| Workload | Before median ms/pass | After | Median pair result |
|---|---:|---:|---|
| Richards | 21.626 | 21.909 | 0.97% faster, 12/21 (inconclusive) |
| DeltaBlue | 23.370 | 23.132 | 0.15% faster, 12/21 (inconclusive) |
| Queens | 33.630 | 28.226 | **16.55% faster, 19/21** |

The final build (`run-yzy8gufu`, `build/region-final-pinned.log`, 21 pairs)
measured Queens 32.664→27.438 ms/pass, **16.17% faster (21/21 pairs)**;
Richards 0.25% slower (8/21) and DeltaBlue 0.29% slower (9/21), both within
local noise. No improvement is claimed for those two workloads.

Percentages are medians of pairwise reductions, not ratios of marginal medians.
The profile's executed `nt_minus` count falls from 2,450,880 to 0, and `nt_eq`
from 10,275,150 to 2,922,510. The remaining cost includes `notNil`, Boolean sends,
layout/method/accessor checks, and allocation. Profile artifacts are retained in
the candidate run; percentages from short gprof samples remain approximate.

Focused validation: compiler 109, runtime 47, boundary 39 and stdlib compilation
6 pass under ARC/ORC. Direct-slot integration covers changed numeric kinds,
method/accessor replacement, Boolean replacement and a getter restoring its own
registration between iterations under both managers. Result-region parity tests
also cover receiver changes, branch writes, outer-result visibility and fallback
side effects. The broad sweep passes 123/123 (`build/region-full-parity.log`);
subsequent conservative eligibility checks were covered by the focused suites.

## Native parameter variants and typed getter arithmetic

Numeric uses propose Integer parameter candidates. A separate validation pass
rejects assignments, captures, escaping blocks and shadowing. These candidates
are not proofs: the public compiled entry checks argument kinds and that no
interpreter host is active, then calls an additional body with native `int`
parameters. Non-Integer calls keep the original generated body. Both bodies
come from the same Harding AST, not hand-written method implementations.

Unique generated Integer getters can feed native arithmetic without boxing the
field first. A receiver/method guard plus the slot-accessor guard preserve
layout safety, inheritance fallback and replacement invalidation. Receiver and
operand evaluation order is retained and the receiver expression runs once,
including when a guard fails. The result is still boxed; propagation through
that result and through recursive calls is not implemented by this slice.
Tests cover Float/custom-object fallback, captured/assigned parameters,
receiver side effects, inherited layout fallback, missing arguments, runtime
compiled-method and slot-accessor replacement, and interpreter-bound calls.
Compiler tests (107), compiled runtime (47), engine boundary (39), stdlib
compilation (6) and value dispatch (1) pass under ARC and ORC; the direct-slot
integration host also runs under both memory managers. The full Granite parity
sweep passes **122/122** (`build/getter-full-parity.log`); this is not a claim
that every repository test suite passes.

Generated numeric parameter bodies increase from zero to 8/9/10 in
Richards/DeltaBlue/Queens. Generated Nim grows by about 12/12/17 KB respectively;
this is bounded body duplication, not a combinatorial set of type signatures.

The first parameter-only experiment regressed Queens by 3.91% (2/15 improving
pairs). Connecting the getter then made the combined slice 8.21% faster on Queens
(12/15 pairs); Richards 1.23% faster (11/15), DeltaBlue 0.89% faster (8/15), with
the latter two not strong evidence. Baseline `run-mgrjc_rh`, combined candidate
`run-d9220rir`, 30 verified passes, pinned alternating 15 trials,
`build/getter-pinned.log`. Final-tree remeasurement against the same baseline
(`run-85rqp6ga`, `build/getter-final-pinned.log`, 15 pairs) found Queens 8.56%
faster (11/15), Richards 0.71% faster (9/15), DeltaBlue 0.33% faster (9/15).
A second, 21-pair comparison (`build/getter-final-pinned21.log`) found Queens
8.43% faster (16/21), Richards 0.08% faster (11/21), DeltaBlue 0.53% slower
(9/21). Only Queens provides a substantial signal; the other two remain
inconclusive. Marginal before/after medians are 35.728/32.596 ms per pass for
Queens; the reported percentage is the median of pairwise time reductions.

The Queens gprof flat-profile call count for `nt_minus` fell from 7,352,640 in
the typed-slot baseline to 2,450,880 in the combined candidate. `nt_eq` remains
about 10.3M calls: `distance` and `delta` still cross a boxed result boundary.
Sampling percentages and inlined call-graph arcs are not exact operation counts.

A fully native numeric kernel is demonstrated in
[GRANITE_NATIVE_KERNEL_DEMO.md](GRANITE_NATIVE_KERNEL_DEMO.md), including the
verbatim generated Nim and an isolated comparison against idiomatic Nim.

## Inlined-branch locals become native Nim

Numeric binding analysis only discovered assignments written directly in a
method body, and only tracked them through `nkBlock` regions. Inline control
blocks arrive from the parser as **block-valued literals** (`nkLiteral` with
`vkBlock`), and that branch rejected every candidate unconditionally - so a
loop counter assigned inside an inlined `ifFalse:` was never even considered.
Discovery now follows the same regions the emitter inlines (branches, loops,
literal control blocks without non-local returns) and treats only genuinely
escaping closures as opaque.

Native locals also no longer box a value they immediately unbox: when target and
expression are both proven numeric, the emitted assignment is the plain Nim
expression. Queens' hot method changed from a boxed counter assigned through
`(NodeValue(kind: vkInt, intVal: 0)).intVal` and a `while isTruthy(...)` test to:

```nim
var column = 0
while (column < 8):
  column = (column + 1)
```

`total` in the same method stays dynamic, correctly: it sums a recursive send
whose result is not proven numeric.

Pinned alternating pairs, 21 trials, idle host (`build/inline-numeric-pinned2.log`,
baseline `run-2vho6bzq`, candidate `run-mgrjc_rh`):

| Workload | Before | After | Result |
|---|---:|---:|---|
| Richards | 17.144 | 17.363 | 0.99% more time, 4/21 pairs |
| DeltaBlue | 18.973 | 19.077 | 0.19% (noise), 9/21 |
| Queens | 37.020 | 36.137 | **2.70% less time, 21/21** |

Queens is a consistent gain. Richards is a small consistent regression: its hot
paths pass native values into dynamic sends, so each such use now constructs a
`NodeValue` where it previously passed an already-boxed local. Recorded rather
than hidden; unboxing method parameters is what removes that cost.

Compiler (103), runtime (47) and engine-boundary (39) suites pass under ARC and ORC.

## Static slot evidence reaches the guarded native path

The guarded numeric path was only enabled for `static+observations`, so a
program compiled without a feedback run got no guarded native slot arithmetic at
all — even when module analysis was conclusive. It now also accepts `static`
evidence. This is safe for this path specifically because it is *guarded*: the
emitted code re-checks the live field kind and falls back to the dynamic send,
so a later Float, nil or reflective write stays correct. It does not narrow
storage; `--trust-observed-types` remains the opt-in that changes the field type.

Measured effect on generated code: DeltaBlue goes from 0 to 12 guarded native
slot paths (`DBVariable#value`, `DBStrength#rank`, `DBVariable#mark`, ...).
Queens and Richards gain none, because their arithmetic operates on a
**parameter** (`r`) and an **accessor send** (`current row`) rather than a direct
slot read. An earlier diagnosis incorrectly blamed `initial:Nil` for blocking
narrowing. `reconcile` only considers `write:` events: allocation-time nil is
not a conflicting write. `QueenPlacement#column`'s 2,056 nil initializations do
not by themselves reject its Integer candidate. Actual nil reads, initialization
order and nullable storage still need consideration before narrowing storage.

Pinned 15-trial comparison against `run-2hcd5dgl` (`build/static-unbox-pinned.log`)
was taken with the host at load ~5.5 and is therefore not a usable result:
Richards 3.10%, DeltaBlue 0.58%, Queens 0.54% by median pair, but with 10/15,
9/15 and 8/15 improving pairs the Directional signal is weak. Re-measurement on
an idle host is required before claiming a benchmark gain. Granite parity is
119/119 on this tree.

## Quiet-host profile and scalar connective leaves

Re-profiling on an otherwise idle host (load ~0.8, versus the 5–6 load most of
this document's numbers were taken under) changed the picture twice.

**First, the resolution cache needs no more work.** gprof attributes 6.5M
`walkCompiledHierarchy` calls to `sendMessageCached`, which looks like the cache
failing on nearly every send. Instrumenting the real binary disproved that:
3 verified Queens passes produced **216,712 cache hits, 11 misses and 19
hierarchy walks**. The gprof arc was an artifact (the resolver is inlined, so its
callee count is attributed to the caller and inflated). Lesson recorded: gprof
call-graph arcs are not call counts when the callee is inlined — measure the
counter, not the arc.

**Second, the real remaining dispatch cost is calling `sendMessage` at all.**
Queens still enters generic dispatch 10.9M times per profile (30 passes),
roughly 362k per pass and ~5x its 72k cached sends. The callers are scalar
leaves: `nt_pipe` 4.9M and `nt_not` 2.9M — 7.8M of the 10.9M — each paying the
full generic path (host check, class-name computation, resolution) to run a
compiled `True`/`False` body that is already registered.

`nt_pipe`/`nt_not` now resolve the compiled `True>>|`, `False>>|`, `True>>not`
and `False>>not` bodies once per `compiledClassDispatchVersion` and call them
directly for Boolean receivers. Nothing is reimplemented: `findCompiledMethod`
returns the registered proc, so a replaced method is picked up on the next send.
Non-Boolean receivers keep ordinary dispatch, and a bound interpreter host keeps
the original path because an interpreted replacement must win there.

Pinned alternating pairs, 15 trials, 30 verified passes per run, idle host
(`build/bool-quiet-pinned.log`, baseline `run-wkvh_nlc`, candidate `run-2hcd5dgl`):

| Workload | Before | After | Result |
|---|---:|---:|---|
| Richards | 29.624 | 28.073 | 3.01% less time, 12/15 pairs |
| DeltaBlue | 27.289 | 26.749 | 0.51% noisier/neutral, 7/15 |
| Queens | 38.095 | 35.927 | **6.27% less time, 14/15** |

An earlier attempt at this same change measured as noise under load 5–6 and was
reverted rather than kept unproven. Runtime (47) and engine-boundary (39) suites
pass under ARC and ORC.

## Integer parameter mutation in guarded regions

The native Integer-region planner now accepts reassignment of Integer method
parameters when every assignment remains inside the supported, callback-free
Integer subset. Parameters are copied into native locals within the guarded
region; the existing class, method, slot and argument-kind guards still select
the ordinary compiled body for other receivers or kinds. Tests cover mutation,
loops, incompatible Float fallback and planner refusal for unsupported writes.

The pinned 15-pair comparison `build/native-param-pinned.log`, baseline
`run-w6v1trxl`, candidate `run-v7umwx0z`, found Richards 2.0% faster,
DeltaBlue 0.5% slower and Queens 1.69% slower by median pair. This noisy result
does not establish a benchmark gain; the change widens eligible regions only.
Inspecting the retained generated Nim found **zero** instance-side
`integerCall_*_native` regions in all three benchmark programs in either build.
Thus these workloads do not execute the new parameter-mutation path; a targeted
microbenchmark and broader, sound eligibility analysis are still needed.

## Exception-protocol classification guard

Generic sends to instances now check whether the selector can belong to the
built-in exception protocol before querying exception-class ancestry. Every
selector that protocol handles still follows the original path, including user
method overrides; unrelated selectors use ordinary compiled lookup. This avoids
ancestry lookups without duplicating a Harding method. Runtime tests (46) and
engine-boundary tests (39) pass under ARC/ORC.

Paired release ARC, 30 passes, 15 trials pinned to CPU 2: Richards 17.165→17.037
ms/pass (median pair 1.84% less time, 12/15 pairs), DeltaBlue 18.835→18.060
(3.98%, 15/15), Queens 40.515→37.857 (5.65%, 15/15). Logs and samples:
`build/exception-guard-pinned.log`, `build/pinned-paired.json`, baseline
`run-buj91ln3`, candidate `run-w6v1trxl`. A later attempt to combine the
exception cache's two hash lookups into one regressed Queens in pinned trials
(`build/exception-single-pinned.log`) and was discarded. Host load is
uncontrolled; these are local observations, not portable guarantees.

## Dependent numeric locals

The numeric-binding pass now recognizes a local initialized from an earlier
proven numeric local or arithmetic expression. The existing definite-initialization,
assignment-kind and closure/shadow checks still apply; removing a source candidate
also removes its dependents. Parameters and slots are not inferred by this change.
Focused compiler tests pass under ARC and ORC and the executed
`numeric_dependent_locals` and `numeric_method_locals` parity cases pass.

Five unpinned alternating release ARC trials against `run-urxplov2`
(`build/granite-profiles/run-n6s9i7wl`) produced Richards 20.14→19.34,
DeltaBlue 20.22→20.84 and Queens 44.73→43.99 ms/pass. These mixed, noisy
results do not establish a performance improvement. More representative
candidate-count and isolated timing evidence is needed.

The later combined inference/block change uses native Boolean conditions in
statement-position literal `whileTrue:`/`whileFalse:` and `ifTrue:` branches
when numeric operands are already proven. Literal blocks were already inlined;
this avoids boxing their proven conditions, not an additional closure. Native
compiled-block invocation also borrows the existing argument array; VM callbacks
retain the owned-sequence adapter and arity checks. Focused block lifetime tests
pass under ARC/ORC. The separate compiled-support suite still has the two baseline
failures noted below; the block invocation/arity tests in it pass. Regressions also
cover statement-position `ifTrue:`/`ifFalse:` conditions and native block arities
1–3, including the VM's sequence callback adapter.

A pinned 11-trial comparison of the combined change against `run-urxplov2`
(`build/inference-block-pinned.log`) found Richards 0.20% faster, DeltaBlue
0.20% slower and Queens 0.67% slower by median pair: no demonstrable gain on
these workloads. The unpinned profile artifacts are `run-buj91ln3`.

## Zero-copy argument ABI

Compiled methods read their arguments and never retain them, so `CompiledProc`
takes `args: openArray[NodeValue]`. A generated call site passes a stack array
(`[a, b]` or the shared empty `emptyNodeArgs`), and the helpers in
`compiled_support` do the same, so a send allocates no argument sequence. The
interpreter boundary and genuinely cold helpers (JSON specs, file calls,
logging) still take an owned `seq`; the conversion happens only at those leaves.
Registration overloads keep the seq form working for hand-written callers, and
those pay one sequence each.

A borrowed parameter must never bind to a temporary: `var p {.cursor.} =
(if args.len > 0: args[i] else: <temp>)` dangled as soon as the temporary's
storage died. The fallback is now the module-level `hardingMissingArg`, and
both branches are stable locations for exactly the call's lifetime. Calling a
compiled method with too few arguments is covered by a regression.

### Measurements

Queens, 30 verified passes: `newSeqPayload` fell from 11.06M to 0.31M and
`rawAlloc` from 15.4M to 7.6M calls. Pinned alternating pairs, 15 trials:
Richards 3.7% faster, DeltaBlue 5.0% faster, Queens 9.5% faster (Queens 15/15
pairs). Granite parity is 117/117 on this tree; engine-boundary (39) and
compiled-runtime (46) pass under ARC and ORC.

Two pre-existing `test_compiled_support` failures reproduce at `a1bbea0`, so
they are not from this work.

## Reading the numbers in this document

Percentages are **time** changes: `-5%` means the work completed in 5% less
time, i.e. it was 5% faster. Nothing in this file reports a negative percentage
as an improvement in throughput. Paired comparisons count how many before/after
trials got faster, which is the sanity check on the median.

## Borrowed parameters and two-way send caches

Two follow-ups after the dispatch slice, both general (neither adds a Harding
method implementation):

1. **Read-only parameters are borrowed.** A method parameter that the body never
   assigns and that is not captured as a shared cell is emitted with
   `{.cursor.}`, so ARC does not copy the value on entry or destroy it on return.
   `args` outlives the call, so the borrow is valid. Assigned and captured
   parameters keep owned bindings.
2. **Per-site caches hold two receiver classes.** `CompiledSendCache` keeps an
   alternate `(class, target, negative)` slot. A one-entry cache misses on every
   other send at a site that alternates receiver classes (`True`/`False` at a
   conditional site, notably). A different selector clears the entries rather
   than reusing a target; `tests/test_compiled_runtime.nim` covers that
   regression.

### Measurements

Measured with `build/pinned_compare.py`, which pins the benchmark process to CPU
2 and alternates before/after order; this host's unpinned run-to-run spread
reached ±10%, which was wide enough to hide or invent effects. Medians below are
from 15 trials per case; the same comparison drew the opposite sign for
DeltaBlue in one earlier round, so that case is reported as neutral.

| Slice | Richards | DeltaBlue | Queens |
|---|---:|---:|---:|
| Borrowed parameters | 1.6% faster | 1.9% faster | 7.8% faster |
| Two-way send cache | 2.1% faster | neutral | 5.0% faster |

The Queens gains agree across repeated runs; Richards is small but consistent;
DeltaBlue is inside noise for the second slice. These are local paired
observations, not portable guarantees.

## Generated-send caching and the inline host guard

After the memo, generated code still called the uncached entry points:
`guardedSend_*` fallbacks and inline sends emitted `sendMessageBound`, which
re-resolves on every send (10.9M calls on Queens) and re-enters the hosting
path.

1. `genSend` and the inline class-message path in `codegen/expression.nim`, and
   the `guardedSend_*` fallback in `codegen/module.nim`, now emit
   `cachedSendBound`. Dispatch order is unchanged — the per-site cache still
   defers to live resolution, replacement and version bumps.
2. `hostedBuiltinDeferred` tests `hostRoutingActive()` (one inlined registry
   length check) before building an argument buffer. A pure-native program no
   longer constructs a buffer per operator; when a host is bound, the previous
   per-receiver lookup runs unchanged, and the check is repeated per call.

Neither change adds a Harding method implementation: they select the existing
compiled body or declared primitive.

### Measurements

Paired release ARC trials, 30 verified passes, one warmup discarded, median
wall time per pass, no startup subtraction. Cumulative across the four slices
(each measured against the binary it replaced):

| Workload | Baseline | + guard | + closure fix | + memo | + cached sends |
|---|---:|---:|---:|---:|---:|
| Richards | 36.09 | 32.38 | 30.45 | 29.16 | **21.57** |
| DeltaBlue | 32.51 | 30.63 | 27.06 | 26.07 | **22.17** |
| Queens | 107.82 | 95.47 | 81.94 | 74.95 | **51.22** |

Last slice: 21.5% / 5.7% / 24.4% faster (Richards/DeltaBlue/Queens), 7/7 pairs each.
Cumulative against the baseline: 40% / 32% / 52% faster.

Correctness: `scripts/test_granite_parity.py` passes **117/117** on the final
binary (`build/cachedsend-parity.log`); engine-boundary (39) and
compiled-runtime (45) tests pass under ARC and ORC. Host not isolated or
CPU-pinned; these are local paired observations.

Remaining hot spots on Queens: the benchmark body itself (~23%), the compiled
`True/False` methods reached through `nt_pipe`/`nt_not` (~13% combined), and
`sendMessage`/resolution (~11%). Further gains need type-directed unboxing of
locals and wider send specialization, not more resolution caching.

## Allocation-free resolution and memoized lookup

Re-profiling at `a1bbea0` after the unbound-send guard showed
`resolveCompiledMethod` still allocating a closure environment on **every**
entry, 16,591,692 times on Queens, all discarded on cache hits: the nested
`walkCompiledHierarchy` closure captured `selector`.

Two changes, both preserving lookup order and version invalidation:

1. The cache-miss hierarchy walk is a separate top-level proc
   (`compiledMethodOwner`). A nested proc is not captured any more, so a hit
   allocates nothing.
2. A 16-entry thread-local direct-mapped memo keyed on the class/selector pair,
   indexed by string lengths and confirmed by string equality (no hashing on the
   hit path), is checked before the interned-ID table. Both are cleared by the
   same `compiledClassDispatchVersion` bump that already guarded the cache.

A collision only costs a cache miss because the hit test compares both strings;
`tests/test_engine_boundary.nim` covers an intentional collision and a live
method replacement after the memo is warm.

### Measurements

Paired release ARC trials, 30 verified passes per run, one warmup discarded;
median process wall time per pass, no startup subtraction. Two separate paired
runs, each against the binary it replaced:

| Workload | After guard | + closure fix | After memo |
|---|---:|---:|---:|
| Richards | 36.09 ms | 30.45 ms | 29.16 ms |
| DeltaBlue | 32.51 ms | 27.06 ms | 26.07 ms |
| Queens | 107.82 ms | 81.94 ms | 74.95 ms |

Versus the immediately preceding binary, the closure fix gave ~4.9%/8.0%/9.7%
and the memo ~0.3%/4.4%/8.6% (Richards/DeltaBlue/Queens; Richards is within
noise, 5/7 pairs improved). An earlier memo comparison was discarded because
correctness-test compilation ran concurrently and inflated the baseline to
41.03/30.18/112.64 ms; only the re-measured clean run is reported here.

Profiled calls over 30 Queens passes: `nimNewObj` inside resolution disappears,
string hashing falls from 48.8M to 17.5M, and `getOrDefault` (33.2M calls) leaves
the flat profile. The remaining largest entries are the benchmark body
(`canPlaceRow:column:after:`), the generic `sendMessage` and argument
allocation. Host was not isolated or CPU-pinned.

Validation: engine-boundary tests (39, ARC and ORC), compiled-runtime tests (45,
ARC and ORC), and the focused parity suite. No full-suite claim.

## Generic unbound-send guard (current stdlib pipeline)

Baseline `a1bbea0`, retained `build/granite-profiles/run-d6ig3mm_`; candidate
`build/granite-profiles/run-xacgaeta`. `sendMessage` now checks the live
`boundCompiledClasses` registry before entering `boundInterpretedSend`. When a
host is bound, the existing live interpreter method lookup is unchanged; the
check is repeated on every send. No Harding method or primitive is reimplemented.

Seven alternating paired release ARC trials, 30 verified passes each, one
warmup discarded; median process wall time per pass, no startup subtraction:

| Workload | Baseline ms | Candidate ms | Median reduction | Improved pairs |
|---|---:|---:|---:|---:|
| Richards | 36.094 | 32.383 | 10.3% | 7/7 |
| DeltaBlue | 32.505 | 30.627 | 5.8% | 7/7 |
| Queens | 107.818 | 95.468 | 11.5% | 7/7 |

The host was not isolated or CPU-pinned; results are a local paired observation,
not a portable speedup guarantee. Raw trials and checked outputs are in the
candidate `results.json` and timing files. The candidate's post-change Queens
`-pg` profile still verifies 92. The baseline reports 16,715,044 calls to
`boundInterpretedSend`; the candidate reports none on this pure-native workload.
The profiled build overlapped correctness compilation, so sampled percentages are
not used as timing evidence. Engine-boundary tests (37, including the new
bind/detach regression) and compiled-runtime tests (45) pass under both ARC and
ORC; logs are `build/hostguard-boundary-{arc,orc}.log` and
`build/hostguard-runtime-{arc,orc}.log`. Four focused interpreter/native
parity cases also pass (`build/hostguard-parity.log`); no full-suite result is
claimed.

Baseline runtime revision: `732716d`. Scope: a single runtime optimization;
no benchmark-specific specialization or language-semantic changes.

## Profiles

`perf` could not access even `task-clock` with this host's
`perf_event_paranoid=4`. No kernel settings or privileges were changed. Release
ARC binaries were built with GCC `-pg` and inspected with `gprof`; uninstrumented
release binaries were retained separately for timing.

Thirty verified repetitions of Richards, DeltaBlue and exhaustive Queens show
allocation, string hashing, hierarchy traversal and dynamic dispatch as material
costs. Baseline flat profiles put string hashing at ~7–9% self samples and raw
allocation at ~7–10%. This is sampling evidence, not precise attribution:
profiling instrumentation changes runtime costs, allocator counts include
runtime temporaries, and gprof's inferred inclusive costs are not independent
measurements.

## Change

Native instance-method resolution now uses a thread-local table keyed by
`(lookup start class name, selector)`:

- Positive and negative results are reused by generic instance dispatch,
  method-existence checks, and monomorphic send-cache misses.
- A mismatch with `compiledClassDispatchVersion` clears the table before lookup.
  Supported method/class/hierarchy registration paths already increment it.
- The table clears at 4,096 entries, preventing arbitrary selector traffic from
  growing it without bound. It retains names/procedure values, not receivers.
- Live interpreted lookup still occurs before cached native dispatch. Warm native
  entries do not mask interpreted replacement or runtime-subclass overrides.
- Lookup start class remains part of the key, preserving explicit super sends,
  multiple-parent declaration order and cyclic-graph termination.
- Class-side method resolution is unchanged. No thread-safety promise is added
  for concurrent mutation of the existing process-global registries. Direct
  writes to exported registry tables bypassing registration/versioning remain
  unsupported, as they were for the pre-existing monomorphic send caches.

The cache trades additional hash lookups and a bounded table for fewer hierarchy
walks and temporary allocations. Profiled counts before/after, thirty repetitions:

| Workload | Hierarchy walks before | After | Raw allocator calls before | After |
|---|---:|---:|---:|---:|
| Richards | 8,199,792 | 2,982,341 | 66,668,391 | 46,682,638 |
| DeltaBlue | 12,584,668 | 4,299,795 | 98,468,749 | 63,399,751 |
| Queens | 28,806,365 | 10,398,524 | 215,086,482 | 144,377,631 |

Hierarchy walks drop ~64–66%, allocator calls ~30–36%. Hash calls increase
slightly; this is not an elimination of hashing or allocation overhead.

## Paired uninstrumented measurements

Same generated Nim source and build flags for each before/after pair:
Nim 2.2.12, GCC 13.3.0, `-d:release --mm:arc`, Intel Core Ultra 7 165U, Linux
x86-64. Seven measured alternating trials, thirty passes per process; one checked
warm-up per variant discarded. Output and stderr were checked every run. Process
wall-time medians divided by 30 (no startup subtraction):

| Workload | Before ms/pass | After ms/pass | Throughput ratio | Time reduction |
|---|---:|---:|---:|---:|
| Richards | 84.499 | 69.744 | 1.212x | ~17.5% |
| DeltaBlue | 119.871 | 97.629 | 1.228x | ~18.6% |
| Queens | 231.525 | 194.961 | 1.188x | ~15.8% |

Host load was not isolated. Before/after ranges overlap (Richards before
~70–134 ms, after ~61–93 ms); these are initial paired observations, not exact
portable speedups. All seven Queens and DeltaBlue paired observations improved;
Richards improved in six of seven. Do not compare their absolute times directly
with the earlier Cog table from another run. This reduces part of the measured
cost, but the large Cog gap remains.

Evidence under `build/granite-profile-slice/`: `manifest.json` (source hashes and
baseline revision), per-case `before`/`after` binaries, `gprof.stdout`,
`after-gprof.stdout`, generated Nim, checked outputs and `paired-results.json`.
Scratch drivers: `build/profile_granite_slice.py`,
`build/measure_resolution_cache.py`, `build/profile_resolution_after.py`.

Reusable runner for future slices:

```sh
# Before editing runtime code; retains uninstrumented baseline and optional gprof:
python3 scripts/profile_granite.py --profile --mm arc
# After editing; supply the printed previous artifact directory:
python3 scripts/profile_granite.py --compare build/granite-profiles/run-BASE --mm arc
```

The reusable runner snapshots sources, checks retained binary hashes, records
revision/toolchain/dirty state, and alternates timing order. Profile and timing
binaries are separate. It is not a benchmark score or a permission workaround.
The runner's profile and comparison modes were exercised with checked one-pass
smoke runs (`run-lfep6w7d`, `run-pc4b990g`). Their short, noisy timings are not
used as optimization evidence; the table above uses the retained thirty-pass
before/after binaries.

## Validation and remaining work

Focused runtime tests exercise late method installation after a negative lookup,
method replacement, parent-order changes, explicit-super starts, cycles,
capacity clearing, initializer installation after a cached miss, nil results,
reentrancy and evaluation-once behavior. Existing engine-boundary suites check
interpreted replacements and subclass overrides after native cache warming.
Runtime/support/boundary/reentrant-return/block-lifetime/base-allocation suites
pass under ARC and ORC (40/10/34/16/15/2 tests respectively).
Richards and DeltaBlue both-engine ARC/ORC conformance tasks pass, as do thirteen
focused executed parity cases. Four real GTK accessibility acceptances also
pass (both engines under ARC/ORC), alongside backend cleanup/package checks.
This is not a complete suite pass.

The first freeze conformance sweep encountered a shared default Nim-cache linker
collision on `class_factory` while another parity sweep built the same module
name. Its log records undefined type-info symbols, not a Harding result mismatch.
The diagnosed rerun uses isolated per-invocation Nim caches; evidence is recorded
under `build/resolution-frozen-isolated.log` (12/12 declared conformance cases
passed) and `build/resolution-frozen-build-isolated.log` (separate build tests).
Do not infer freeze success from the failed initial gate. The wider parity
sweep runs in batches with progress recorded in
`build/resolution-parity-batches.json`; the log, not a task exit alone, determines
which cases completed.

The next slice should re-profile before choosing another target. Remaining
hashing, slot-access lookup and allocation are visible candidates, not yet
measured optimization results. Keep bound host lookup and live-layout checks;
do not remove them merely because pure-native benchmarks do not use them.

## Second slice: exception-class ancestry guard

Re-profiling at `d7b1328` showed the first cache had removed most hierarchy
walks, but one caller still dominated: `isCompiledExceptionClass` ran a whole
graph traversal on nearly every send, because ordinary sends reached it before
any fast rejection. On Queens it accounted for 10,398,511 of 10,398,524 walks.

Two graph-independent corrections, no semantic change:

- `signal:` is now tested before the ancestry predicate. A class can only enter
  the built-in exception protocol for `signal:`, so other selectors never pay for
  the lookup.
- The ancestry answer is cached in a bounded thread-local table keyed by class
  name and invalidated by `compiledClassDispatchVersion`, like the resolution
  cache. It stores booleans, not class or receiver references.

Profiled counts for thirty checked repetitions:

| Workload | Hierarchy walks before | After | Raw allocator calls before | After |
|---|---:|---:|---:|---:|
| Richards | 2,982,341 | 14,986 | 46,682,638 | 34,417,771 |
| DeltaBlue | 4,299,795 | 96,653 | 63,399,751 | 42,494,180 |
| Queens | 10,398,524 | 15 | 144,377,631 | 102,783,598 |

Paired uninstrumented ARC trials against retained `d7b1328` binaries, same
methodology (seven measured alternating trials, thirty checked passes each):

| Workload | Before ms/pass | After ms/pass | Throughput ratio | Time reduction |
|---|---:|---:|---:|---:|
| Richards | 64.665 | 52.643 | 1.228x | ~18.6% |
| DeltaBlue | 94.866 | 70.212 | 1.351x | ~26.0% |
| Queens | 185.194 | 152.419 | 1.215x | ~17.7% |

The baseline in this table is the retained `run-ua7weblb` binaries, whose
medians in that run were 66.94/96.24/203.61 ms. A separate slice-one baseline
measured different absolute times; compare within a paired table only.

Evidence: `build/granite-profiles/run-ua7weblb` (baseline),
`run-21l77yc5` (paired comparison), `run-a2wno529` (post-change profiles).

Validation for this slice: `test_compiled_runtime` (42 tests, ARC and ORC),
including new cases for a cached non-exception answer that must be invalidated by
adding an `Exception` parent and for a class-side `signal:` method on an ordinary
class. Engine-boundary, reentrant-return, block-lifetime, compiled-support and
base-allocation suites run under ARC and ORC. Richards and DeltaBlue two-engine
conformance, the 102-case parity sweep, and GTK acceptance are re-run for the
combined change set.

## Third slice: closure allocation in bound-host lookup

Profiling at `d56287c` showed `boundClassFor` at ~15% of Queens time with
39,553,086 calls. Raw allocator counts had risen while hierarchy walks fell, and
Queens was allocating 102.8M objects for a benchmark that mainly builds linked
placements.

The cause was structural, not a cache miss: `boundClassFor` tested
`boundCompiledClasses.len == 0` for an early return, but defined its traversal as
a nested proc capturing `visited`. Nim therefore allocated a closure environment
on entry to every call — 39.5M allocations, all discarded unread by the early
return in a pure compiled program.

The traversal became a top-level proc taking `visited` as a `var` parameter, and
the guard is `{.inline.}`. Traversal order, the cycle guard and the early return
are unchanged; only the closure allocation is removed.

Profiled counts for thirty checked repetitions:

| Workload | Raw allocator calls before | After | `nimNewObj` before | After |
|---|---:|---:|---:|---:|
| Richards | 34,417,771 | 24,483,763 | 19,559,649 | 9,625,641 |
| DeltaBlue | 42,494,180 | 28,334,090 | 29,166,890 | 15,006,800 |
| Queens | 102,783,598 | 63,230,512 | 73,794,835 | 34,241,749 |

`boundClassFor` no longer appears in the flat profile.

Paired uninstrumented ARC trials against retained `d56287c` binaries, seven
measured alternating trials, thirty checked passes each:

| Workload | Before ms/pass | After ms/pass | Throughput ratio | Time reduction |
|---|---:|---:|---:|---:|
| Richards | 49.273 | 45.190 | 1.090x | ~8.3% |
| DeltaBlue | 70.699 | 60.862 | 1.162x | ~13.9% |
| Queens | 153.014 | 130.311 | 1.174x | ~14.8% |

Richards gains least because its remaining cost is dominated by hashing and
allocation elsewhere, which this slice does not address.

Evidence: `build/granite-profiles/run-2obisa53` (baseline),
`run-f0lkjgd9` (paired comparison), `run-lkztylzf` (post-change profiles).

## Cumulative position

Paired measurements accumulate but are not one continuous run, and each table
uses its own baseline; do not sum the percentages. The same-session
`run-2obisa53` baseline and these post-change medians indicate roughly:

| Workload | At `732716d` | Current |
|---|---:|---:|
| Richards | ~64.7 ms | ~45.2 ms |
| DeltaBlue | ~94.9 ms | ~60.9 ms |
| Queens | ~185.2 ms | ~130.3 ms |

Order-of-magnitude gaps to Cog from the earlier comparison (roughly 0.57/0.66/
0.16 ms for adapted Richards/DeltaBlue/Towers and 1.99 ms for Queens) remain
large. Production-quality value representation (unboxing), allocation strategy
and slot dispatch are still unaddressed; they are larger, riskier changes than
the three mechanical slices above and need separate agreement.

## Fourth slice: slot accessor lookup (Level 1 of direct slot access)

Goal context: the intended end state for Granite is compiled Nim objects with
typed Nim members, so slot access eventually becomes a direct field access with
no runtime lookup at all. This slice is the first mechanical step in that
direction; it does not change field types yet.

Compiled types already carry real Nim fields:

```nim
Class_...Obj* {.inheritable.} = object of HardingObject
  classRef*: Class
  row*: NodeValue
  column*: NodeValue
  previous*: NodeValue
```

But every access was emitted as `getSlotValue(self, "row")`, and the hot path
built `getReceiverClassName(self) & "::" & slotName` — a fresh string allocation
plus a hash plus a table probe plus an indirect call — before reaching an
accessor whose body is a plain pointer cast. Note also that Granite emits **flat**
types: each class is `object of HardingObject` carrying its own copy of all
inherited slots, and language inheritance lives in the dispatch tables. A
receiver cast to another class's generated type would therefore read the wrong
memory, so any direct access must be guarded on the receiver's actual class.

Change: accessors are additionally indexed by `(class identity, slot name)` in a
flat table, keyed by the resolved `Class` pointer the instance already carries.
The name-keyed tables stay canonical and still serve live-bound instances, whose
class identity belongs to the interpreter. A miss on a compiled class answers nil
rather than falling through to a name lookup that cannot succeed.

Rejected first attempt: indexing as `Table[pointer, Table[string, accessor]]`.
Looking up a value in the outer table **copies** the inner `Table`, which became
519M deep copies at ~11% of runtime — a ~1.8x regression on all three workloads.
That design was measured, discarded, and is recorded here so it is not retried.

Paired uninstrumented ARC trials against retained `ebea5fd` binaries, seven
measured alternating trials, thirty checked passes each:

| Workload | Before ms/pass | After ms/pass | Throughput ratio | Time reduction |
|---|---:|---:|---:|---:|
| Richards | 54.860 | 48.785 | 1.125x | ~11.1% |
| DeltaBlue | 87.687 | 78.736 | 1.114x | ~10.2% |
| Queens | 154.666 | 139.671 | 1.107x | ~9.7% |

Evidence: `build/granite-profiles/run-2obisa53` (baseline),
`run-g3rqxtkt` (paired comparison). The regressed attempt's profiles remain in
`run-o1i86_gi` as the record of the rejected design.

### Where Level 1 stops, and what Level 2 needs

This removes the per-access string allocation but still pays one hash and one
hash-table probe per slot read/write, plus an indirect call through the accessor
proc. Closing that needs the access to be resolved at compile time rather than
looked up at run time, which in turn needs the field types to be known — i.e. it
converges with Level 2:

- Slot type inference (`row: int`, `previous: Class_QueenPlacement`) so
  arithmetic and field loads compile to native operations instead of `NodeValue`
  unions and `nt_plus` calls.
- A boxing fallback for slots whose runtime type is not pinned, and a bridge so
  the interpreter still observes `NodeValue` slots on adopted native instances.
- Generated-code changes, hence invalidation when a class is redefined at runtime.

That is a materially larger and riskier change than any slice so far; it should
start with a written design agreement before code.


## Interned native resolution keys

Baseline revision: `60f9844`. Native resolution now interns class and selector
names into thread-local uint32 IDs, packs the pair into one uint64, and uses one
`withValue` probe. A cached nil is still a resolved negative answer. The existing
4,096-answer bound remains; an 8,192-name bound clears both interner and answers
before IDs can be reused. IDs never escape this thread-local resolution cache.
Version invalidation, hierarchy traversal order, explicit-super starts, and live
interpreter dispatch before native lookup are unchanged. No Class identity or
language Symbol representation is changed. Process-global registration remains
subject to its existing concurrency contract.

### Paired measurements and attribution

Retained baseline `run-2xhzmmd2`, candidate `run-vmnvc9ne`; seven alternating
measured trials, ten verified passes per process, release ARC:

| Workload | Before ms/pass | After ms/pass | Elapsed reduction |
|---|---:|---:|---:|
| Richards | 35.633 | 31.351 | ~12.0% |
| DeltaBlue | 52.905 | 46.982 | ~11.2% |
| Queens | 107.618 | 94.577 | ~12.1% |

An ablation retained a string-pair key but replaced `hasKey` plus `[]` with one
`withValue` probe (`run-tuzvl7z1`). That alone reduced time ~8.5–12.2% versus the
same original baseline, so it would be misleading to credit all of the gain to
interning. Direct comparison of interned keys against the one-probe string cache
(`run-qt8if0c9`, eleven alternating trials, twenty verified passes):

| Workload | Single string-pair probe | Interned IDs | Elapsed reduction |
|---|---:|---:|---:|
| Richards | 32.606 | 30.949 | ~5.1% |
| DeltaBlue | 52.480 | 52.223 | ~0.5% |
| Queens | 108.680 | 107.204 | ~1.4% |

The smaller differences are not strong portable speedup claims. Host load was
not isolated; compare only within each paired table. Generated benchmark sources
and expected output are identical within each comparison, and retained binaries
are hash-checked by `scripts/profile_granite.py`.

Gprof call counts normalized per benchmark pass, baseline versus interned keys:

| Workload | String hash calls before | After | Raw allocations before | After |
|---|---:|---:|---:|---:|
| Richards | 936,008 | 588,115 | 594,868 | 594,808 |
| DeltaBlue | 1,609,640 | 1,057,202 | 749,690 | 749,587 |
| Queens | 3,151,749 | 1,924,548 | 1,856,462 | 1,856,436 |

String hashing falls ~34–39%; allocation counts barely change. The earlier
proposal that interning would remove ~149M allocations was not supported: the
profile's allocation totals were whole-runtime counts, not allocations caused by
resolution keys. String-to-ID lookups still hash strings on every resolution;
full hash elimination would require carrying IDs at send sites and receivers.
Neither that broader representation change nor argument-buffer work is included.

### Validation

`test_compiled_runtime` adds a regression that forces multiple ID-recycling
cycles with distinct class/selector pairs, then checks positive and negative
answers and late method replacement. Existing tests retain hierarchy order,
cycles, capacity clearing, and live replacement coverage. Passed gates (logs
use `build/intern-*`):

- ARC/ORC runtime (43), support (10), engine-boundary (34), reentrant-return
  (16), block-lifetime (15) and base allocation (2) tests per memory manager.
- Richards and DeltaBlue both-engine conformance tasks; 102/102 wider parity
  cases, executed in recorded batches.
- Four GTK application acceptance tests and two generated-boundary tests.
- Twelve freeze conformance cases with isolated Nim caches; seven frozen-build
  tests.

These named gates are not a full repository suite claim.


## Deferred hosted-builtin argument materialization

Baseline runtime `61e18c3` (comparison/tooling-only HEAD `601ebee` has the same
runtime). `genHostedBuiltin` already binds operands once, left to right. It now
passes those bound values to a hygienic template that selects the interpreted
host *before* constructing `@[arguments]`. The runtime selection predicate is
shared with the eager compatibility entry, so native immediates, native proxies,
identity operations, native collections and unbound owners retain exactly the
same routing rules. The interpreted path still receives an ordinary owned seq,
not a stack buffer or borrowed arguments. Nil results remain successful sends.

The template keeps a cursor alias of the already-evaluated receiver. A first
version copied that managed variant and increased copy-helper counts; the alias
removes that extra copy while the caller's operand binding owns the value across
the call. No receiver or argument evaluation is deferred or repeated.

### Allocation evidence

Gprof call counts normalized per verified pass, release ARC. Baseline
`run-93fku9xq` (50 passes), final candidate `run-gzs5m071` (30 passes):

| Workload | Raw allocations before | After | Sequence payloads before | After |
|---|---:|---:|---:|---:|
| Richards | 594,772 | 446,813 | 283,725 | 135,754 |
| DeltaBlue | 749,525 | 652,778 | 331,193 | 197,247 |
| Queens | 1,856,421 | 1,326,678 | 1,057,538 | 527,789 |

Raw allocations fall ~25%/~13%/~29%; sequence payload allocation falls
~52%/~40%/~50%. The NodeValue-sequence copy-helper count stays effectively
unchanged after removing the extra wrapper copy. This change removes avoidable
buffer allocations, not all argument copies or the managed NodeValue ABI.

### Wall-time evidence and variability

Early unpinned timings overlapped test compilation and were unstable. Retained
binary-only repeats also varied (including a Richards regression); do not claim
a universal speedup from those medians. To reduce migration between this host's
heterogeneous cores, two later comparisons pinned only the benchmark child to
CPU 2, a performance core. No system priority, governor or desktop settings were
changed. Eleven alternating measured trials, 30 verified passes per invocation,
one warm-up discarded, identical source snapshots and hash-checked baseline:

| Workload | First pinned before -> after ms/pass | Repeat before -> after | Reduction range |
|---|---:|---:|---:|
| Richards | 38.760 -> 36.854 | 33.432 -> 31.778 | ~4.9–5.0% |
| DeltaBlue | 56.346 -> 50.713 | 52.077 -> 51.483 | ~1.1–10.0% |
| Queens | 101.093 -> 94.835 | 108.829 -> 100.788 | ~6.2–7.4% |

Richards/Queens improve in both same-core repeats. DeltaBlue's wall-time gain is
not stable enough for a strong speedup claim despite fewer allocations. This is
not an order-of-magnitude change, does not close the CPython gap, and is not
comparable to the separate cross-engine table by mixing medians.

Evidence: `build/deferred-pinned.log`, `build/deferred-pinned-repeat.log`,
`run-gzs5m071/pinned-paired.json` (latest repeat), initial `run-d0pt402n` profiles
and `build/deferred-retained*.log` show the intermediate/noisy attempts.
`build/measure_deferred_pinned.py` records the affinity and per-trial samples.

### Validation and next step

New tests count deferred buffer construction for native/hosted/unbound sends,
check retained values and live method replacement, and assert generated operand
bindings precede selection. Existing generated-boundary tests execute immediate
and VM-owned operands, custom operators, nil replacement, callbacks and
exactly-once effects under ARC/ORC. Passed final gates (logs under
`build/deferred-final-*`):

- Compiler basic 84, runtime 43, support 10, boundary 35, reentrant-return 16,
  block-lifetime 15 and base-allocation 2 tests per memory manager (ARC/ORC).
- Slot contract task and type-feedback/specialization task, including generated
  native/hosted executions under ARC/ORC; two generated-boundary tests.
- Richards and DeltaBlue both-engine conformance; four GTK acceptance tests.
- Twelve isolated-cache freeze conformance cases and seven frozen-build tests.

The final wider parity sweep passed 102/102 in recorded batches
(`build/deferred-final-parity.log`). Interpreter core (57) and load/evaluate
regressions also pass under ARC/ORC. This is named-gate validation, not a blanket
full suite claim.

Re-profile after this slice. The profile still shows sequence copies and generic
sends: consider a borrowed/small-arity native ABI or guarded receiver-call clones
only after separating their actual costs. More arithmetic slot candidates alone
are not evidence for another representation change. LuaJIT-related design
lessons and boundaries are recorded in `GRANITE_LUAJIT_NOTES.md`.
