# Practical performance baselines: CPython, GNU Smalltalk and native Nim

## Current results

Runtime revision `61e18c3`, CPython 3.12.3, GNU Smalltalk 3.2.5 (non-JIT),
Nim 2.2.12/GCC 13.3.0 release ARC, Intel Core Ultra 7 165U. Five measured
alternating trials plus a discarded warm-up. Milliseconds per checked pass,
paired zero-work startup baseline removed:

| Workload | Granite | CPython | GNU Smalltalk | Native Nim |
|---|---:|---:|---:|---:|
| Richards | 33.845 | 4.773 | 2.728 | 0.168 |
| DeltaBlue | 60.013 | 6.929 | 7.837 | 0.165 |
| Queens | 111.412 | 13.824 | 9.308 | 0.276 |

Granite is ~7.1–8.7x slower than this CPython port, ~7.7–12.4x slower than
GNU Smalltalk, and ~202–403x slower than the explicit native Nim representation.
These are workload results, not language-wide rankings. In particular, being
compiled via Nim does not currently imply Python-level performance.

Median raw process totals (different repetition counts, do not compare columns
as if they represented the same amount of work):

| Workload | Granite, 30 passes | CPython, 300 | GST, 1,000 | Nim, 2,000 |
|---|---:|---:|---:|---:|
| Richards | 1.016 s | 1.447 s | 2.738 s | 0.336 s |
| DeltaBlue | 1.802 s | 2.093 s | 7.846 s | 0.332 s |
| Queens | 3.344 s | 4.156 s | 9.313 s | 0.554 s |

Evidence: `build/bench-compare-practical/run-gne5ie02/results.json`. An initial
run (`run-k1c801uk`) gave similar ordering, with Granite ~8.1–8.8x slower than
CPython; the final run adds explicit per-pass native Queens verification and
negative-repetition validation. No runtime changes were made between runs. Cog
and Node timings from the earlier fresh run remain in `BENCHMARK_COMPARISON_CURRENT.md`; do not splice those
non-contemporaneous medians into this table as a paired experiment.

## Scope

`bench_compare_practical.py` compares the same checked workloads in CPython,
GNU Smalltalk, Granite and native Nim. This complements the separate Cog/Node
comparison; those engines are not remeasured by this runner.

- Richards: 1,000 idle iterations, six task priorities, packet order and
  arithmetic `xor16` helper retained; verification requires 2,322 queued and
  928 held packets per pass.
- DeltaBlue: chain/projection size 100, LIFO worklists, the pinned Octane strength
  mapping (including required -> weakest), ten plan executions per change,
  chain and projection checks, projection sum 223,305, explicit graph cleanup.
- Queens: exhaustive search of all 92 solutions with linked placement objects.
  The faster first-solution SOM/AWFY workload is not substituted.

## Ports and representation choices

Python is emitted by a restricted source adapter into ordinary Python classes,
method calls, fields, loops, conditionals and try/finally. It is not a message-send
interpreter. Slot accessor sends remain method calls, as in the Cog adaptation;
this is a conservative matched port rather than a maximally idiomatic Python
rewrite. Lists implement zero-based arrays. DeltaBlue retains its collection
wrapper. Integer and Float values remain Python values, with its normal numeric
semantics. There are no NumPy/native extensions, PyPy or JIT flags.

GNU Smalltalk uses native methods and control structures with the same
zero-based HBArray/OrderedCollection adapter as Cog. Its method compiler expects
bracketed method bodies. Benchmark-only HBObject supplies `new -> initialize`
because GST does not do that by default; no system-wide Object behavior is
changed. Strength globals are installed before compiling references to them.
`removeAtIndex:` is the GST spelling of the adapter's indexed removal.

Native Nim is the implementation-headroom reference: ordinary native refs,
fields, calls and loops without Harding's dynamic dispatch or NodeValue storage.
It is not a universal lower bound or a promise of semantics-preserving automatic
compilation into these layouts:

- Richards embeds the four task variants in control blocks, uses fixed packet
  arrays and passes its scheduler as a native var parameter. The task->scheduler
  cycle is absent rather than created and broken later. Arithmetic helpers,
  scheduler transitions and counters are retained.
- DeltaBlue uses native Float64 variable values and integer strength ranks,
  explicitly choosing numeric representation. It retains the planner's cycles
  and breaks them at disposal, including during error recovery. Small values in
  this workload avoid Float64 integer precision limits; this is not a policy for
  arbitrary Harding Integer slots.
- Native Queens is the existing linked-ref implementation in `bench_objects.py`.

Source licenses are retained in generated sources and copied next to run
artifacts. In particular, native DeltaBlue is GPL-2.0-or-later and is not imported
by the Harding runtime/compiler. Richards uses the pinned V8 BSD provenance,
not the differently licensed AWFY/Sun Python implementation.

## Reproduction

```sh
# Optional local GNU Smalltalk installation, no sudo or system package changes:
python3 scripts/setup_benchmark_gst.py
# Or pass --gst /path/to/gst below for an existing installation.
python3 scripts/bench_compare_practical.py --trials 5 --mm arc
nimble testBenchmarkPorts
```

GST setup downloads GNU Smalltalk 3.2.5 from ftp.gnu.org, verifies SHA-256
`06e574e818ec49f0555d948ae53b1453d8c1df59ef597dad911a4fd1ffba1cce`,
and installs only to `build/gnu-smalltalk/install`. It needs GNU awk, a C build
chain and libffi headers. On the assessed Ubuntu host gawk was missing; gawk,
libsigsegv2, bison and flex packages were downloaded and extracted into
`build/gnu-smalltalk/deps/root` with `apt-get download` and `dpkg-deb -x`.
The extracted `usr/bin` went on PATH, `usr/lib/x86_64-linux-gnu` on
LD_LIBRARY_PATH, and BISON_PKGDATADIR pointed to extracted `usr/share/bison`.
No global Python environment, system package installation or desktop setting was
changed. The build uses `-O2 -fcommon -Wno-error=implicit-function-declaration`
for compatibility with current GCC, with default GC configuration and the
included libsigsegv fallback. This build has no JIT translation enabled.

GNU Smalltalk is optional: tests explicitly skip it if absent, or fail if an
explicit BENCHMARK_GST path is invalid. The timing runner requires it unless
`--skip-gst` is supplied; it never silently labels missing data as a result.

## Timing method

Release Nim/Granite use `-d:release --mm:arc` by default; `--mm orc` is a separate
experiment. Each invocation builds fresh binaries with isolated Nim caches.
Granite does not use type-feedback specialization in this comparison.
One verified warm-up is discarded, then engine order and zero-work/work order
alternate. Each sample retains both complete process wall times, and reports
`(work - zero-work) / repetitions`; compilation is excluded. CPython/GST zero-work
runs still parse and install the same definitions. Their startup/compilation
cost is subtracted approximately, not measured as internal steady-state VM time.
Different repetition counts keep work above timer resolution.

Every process status and output is checked. This is especially important for GST,
which can print an exception on stdout and still exit zero. A printed traceback
or verification failure invalidates the run even if the process exit is zero.
Raw samples, command lines, source hashes, versions, dirty state and CPU model
are recorded under `build/bench-compare-practical/run-*/results.json`.
The host is not isolated; small differences are not portable rankings.

## Profile-guided next decision

A fresh, separate `61e18c3` release-ARC gprof run retained verified workloads for
50 passes each: `build/granite-profiles/run-93fku9xq`. Instrumented timing is not
used for speed comparisons; gprof self samples and call counts guide hypotheses.
`perf_event_paranoid=4` still prevents kernel perf sampling; no settings changed.

| Calls per checked pass | Richards | DeltaBlue | Queens |
|---|---:|---:|---:|
| Raw allocator | 594,772 | 749,525 | 1,856,421 |
| NodeValue-sequence copy helper | 362,790 | 340,926 | 747,200 |
| Native method resolution | 173,917 | 276,166 | 613,595 |

Generated C confirms the named copy helper iterates a `seq[NodeValue]`, including
recursive managed payload copying. NodeValue is a 32-byte value variant on this
host, not an immediate tagged word and not itself a heap reference. Raw allocator
counts cover all causes, not just argument buffers; do not attribute all of them
to sends. Representative self samples: Richards sequence-copy helper ~5.4%,
raw allocation/free ~8.5%; DeltaBlue resolver ~9.3%, sequence-dup helper ~6.4%;
Queens generic send ~6.3%, interner lookups ~6.3%, raw allocation/free ~8.2%.
Samples are short enough that small percentage differences are not precise.

The Richards call graph identifies a concrete avoidable source:
`xor16:with:` creates 3,578,400 sequence payloads over 50 passes in generated
hosted-builtin operand handling. `genHostedBuiltin` evaluates operands and then
constructs `@[arguments]` before calling `hostedBuiltin`, even when the operand
is an immediate Integer and that helper immediately answers `handled = false`.
This is evidence for changing *when* the argument buffer is constructed, not
permission to remove live host lookup or evaluate an operand twice.

Recommended order:

1. Prototype deferred argument materialization for hosted builtin rejection,
   preserving left-to-right evaluation, callbacks, live VM overrides, and ARC/ORC
   ownership. Retain baseline binaries and require fewer measured allocations
   plus a paired wall-time improvement before keeping it.
2. Extend borrowed/small-arity native call paths if sequence churn remains. Any
   stack-backed arguments must be copied before an escaping callee retains them.
3. Then use source-fingerprinted call/type feedback to specialize hot receiver
   sends (e.g. `current row`), with method/version guards and dynamic fallback.
   More inferred self-slot arithmetic alone did not reliably improve the three
   benchmarks in the earlier paired measurements.

No runtime optimization is included in this comparison commit. These are
profile-guided candidates, not promised gains or proof of a single bottleneck.

## Validation

`nimble testBenchmarkPorts` passes seven existing comparison-source tests and ten
new tests: executed Python/GST zero/one/repeated runs, reference counter/checksum
checks, verification failure injection, malformed-input termination, source
notices, adapter details and native Nim builds/execution under ARC and ORC.
This does not claim the complete language/runtime suite ran; runtime code is
unchanged by this comparison addition.
