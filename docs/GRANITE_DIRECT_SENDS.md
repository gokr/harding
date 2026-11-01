# Guarded unary receiver sends

## Scope and contract

Granite selects an optional baked-in target for a unary selector when the
compiled module has exactly one candidate method or generated getter. This is a
specialization candidate, not proof that every runtime receiver has that class.
No declarations, profile file, source rewriting or narrowed storage are required.
Mixed-mode code keeps existing dynamic sends.

Generated helpers bind the receiver once by normal procedure argument evaluation.
They check:

- there are no active bound compiled/interpreter classes;
- the receiver is an ordinary native proxy object, not bridged storage;
- live receiver Class identity equals the candidate's compiled Class identity;
- the method resolved for that class/selector still equals the baked-in target.

The last check is cached per helper and `compiledClassDispatchVersion`; method
and hierarchy registration invalidates it. The common valid path performs no
hash-table lookup. This replaces dispatch rather than prepending another target
resolution per send. Exact-class mismatch takes the original dynamic route.
Exceptions/identity control selectors retain their existing routes.

For generated getters the helper calls the existing direct slot-read helper,
which additionally checks native owner layout and versioned accessor identity.
Accessor replacement, foreign layout, and VM storage never become unchecked
native casts. Other methods use a direct Nim procedure call with the existing
empty-sequence ABI (`@[]`, no populated argument buffer). Nil is a successful
answer, not a signal to retry.

Specialization propagates through inlined branch/loop contexts, including the
Queens hot path `current row`, `current column`, `current previous`. Standalone
block procedures and top-level contexts are not newly specialized in this slice.
Ambiguous selectors remain generic even if a future receiver profile might
justify specializing them. Class-side sends and nonzero-arity sends are unchanged.
The failed runtime small-arity experiment is not reintroduced.

An active interpreted host disables this native fast path conservatively, even
for otherwise native receivers. Existing live interpreted dispatch then handles
replacement, runtime subclasses and callbacks. The mode is not a closed-world
or no-interpreter compilation contract; a possible `--standalone` flag is separate
work, not implemented here.

As with existing caches, supported registration/versioning APIs are required;
mutating exported method tables without registration remains unsupported.

## Measured results

Runtime baseline: `418bec5`, retained binaries in
`build/granite-profiles/run-mzpeuqfx`. Tooling-only commits through `8d1a551` do
not change that runtime. Final prototype profile/timing artifacts:
`build/granite-profiles/run-1kcce6br`.

Same-source release ARC binaries, Nim 2.2.12/GCC 13.3.0, Intel Core Ultra 7 165U.
Two retained-binary comparisons pin only the benchmark children to CPU 2
(performance core). Twelve measured alternating trials after one warm-up; thirty
verified passes per process. Includes process startup, excludes compilation:

| Workload | First before -> after ms/pass | Repeat before -> after | Throughput ratios |
|---|---:|---:|---:|
| Richards | 31.05 -> 25.77 | 38.59 -> 32.78 | 1.20x / 1.18x |
| DeltaBlue | 51.02 -> 45.11 | 75.34 -> 57.83 | 1.13x / 1.30x |
| Queens | 103.91 -> 55.27 | 117.33 -> 63.35 | 1.88x / 1.85x |

Evidence: `build/direct-send-pinned.log`, `build/direct-send-pinned-repeat.log`,
`build/compare_small_calls.py` invoked with the explicit baseline/candidate
artifact paths. The reusable profile runner separately records source/binary
hashes and paired samples. Host load is not isolated; do not extrapolate the
absolute times or splice them into the earlier cross-engine table. Performance
under ORC is not measured by these ARC tables.

Gprof call counts per verified pass (30 passes per variant):

| Workload | Resolutions before -> after | Raw allocations before -> after | String hashes before -> after |
|---|---:|---:|---:|
| Richards | 173,917 -> 104,391 | 446,813 -> 342,525 | 588,094 -> 379,518 |
| DeltaBlue | 276,166 -> 209,239 | 652,778 -> 552,386 | 1,057,165 -> 856,382 |
| Queens | 613,595 -> 123,419 | 1,326,678 -> 591,414 | 1,924,544 -> 454,016 |

These are whole-runtime counts; they are not all argument buffers. Compared with
the first prototype (which failed to propagate candidates into inline loops),
Queens now eliminates much of its accessor-dispatch traffic. Data types and
object allocation semantics are unchanged. Remaining dynamic calls and boxed
values still leave a large gap to native Nim; this is not near-native compilation.

## Validation

```sh
nimble testDirectSends
```

The executed generated-host fixture runs under ARC and ORC. It warms direct calls
and getters, replaces methods and slot accessors, tests foreign receiver classes
and subclass layout/overrides, retains collection identity, preserves nil results,
and exercises side-effecting receiver callbacks. It then binds an interpreter,
checks VM-owned dispatch and live replacement, and verifies unbinding restores
ordinary native operation. Compiler tests check inline-loop propagation and
ambiguous/mixed-mode fallback.

The wider parity sweep caught one real regression during development: helpers
used `mangleSelector`, which preserves case, while Nim identifiers are
style-insensitive, so `slotValue` and `slotvalue` collided and generated C failed
to compile. Helper names now use the case-safe `mangleSlot` encoding, with a
compiler regression test covering it. The full sweep then passed 102/102.

Broader gates use `build/direct-send-*` logs: compiler/runtime/boundary and
callback/lifetime suites under ARC/ORC, generated-host and declared-slot tests,
Richards/DeltaBlue conformance, GTK acceptance and frozen-build checks, plus the
wider parity sweep. Check the completed logs; this is not a full-suite claim.

## Next step

Re-profile before extending specialization. Ambiguous/polymorphic sites need
source-fingerprinted receiver feedback or stronger static receiver facts, not a
language restriction. Nonzero-arity direct calls would require evaluating all
operands before checking guards (arguments may mutate the method), preserving
left-to-right effects and retaining generic fallback. Native parameter/return
versions and larger unboxed regions are subsequent compiler work; selector
uniqueness alone must never become permission to bypass the guards.
