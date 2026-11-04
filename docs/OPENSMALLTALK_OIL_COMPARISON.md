# OpenSmalltalk Oil: local build and checked comparison

## Status

Oil and stock Cog build and boot headless on this host. With the upstream
2026-11-03 update, both pass all three checked workloads at 300, 1,000 and 5,000
repetitions. The earlier wrong-receiver failures are retained below as historical
evidence, not current failures. Image and benchmark adapters are unchanged.

Oil is Clément Béra's lightweight optimizing extension of the 64-bit Spur Cogit,
not a Maven project. The command is `mvm`, not `mvn`. Announcement:

https://lists.squeakfoundation.org/archives/list/vm-dev@lists.squeakfoundation.org/thread/GFD6LVTNO7GAPK4A2GPDKJFBXHRPX4UV/

## Reproduction

```sh
python3 scripts/setup_benchmark_osvm.py
python3 scripts/bench_compare_oil.py --trials 7 --repetitions 5000
python3 -m unittest discover -s tests -p test_oil_benchmarks.py
```

All downloads, image copies, builds and logs stay under `build/`. No system
package changes, scheduling/heartbeat permissions or desktop changes are needed.
The comparison copies the input image and never saves it. Error handling writes
an `ERROR:` marker before quitting; process exit zero alone is not success.

Pinned source: OpenSmalltalk/opensmalltalk-vm branch `Cog`, commit
`9cf479ec02cee2bd86a1791573169b44bdd3633c` (2026-11-03). Oil uses generated
`VMMaker.oscog-cb.3850` sources; stock Cog remains `VMMaker.oscog-cb.3847`
from that same tree:

- `building/linux64x64/squeak.oil.spur/build/mvm`
- `building/linux64x64/squeak.cog.spur/build/mvm`

The build runs `scripts/updateSCCSVersions` first and forces checkout of the
version headers through its revision filter. An existing checkout at the old pin
is deliberately refused: move `build/osvm/repo` aside before rerunning setup;
do not overwrite an independently modified checkout. On this Ubuntu 24.04 host,
clang 18 needs `CFLAGS='-Wno-int-conversion -Wno-implicit-function-declaration'`:
the generated VM intentionally stores machine pointers into machine-word stack
slots, while PseudoTTYPlugin lacks a modern `login_tty` declaration. These flags
are recorded rather than silently patching generated C. Upstream's CMake build
also suppresses int-conversion diagnostics. Build flags are `-g -O2 -DNDEBUG
-DDEBUGVM=0`; optional plugins depend on available development headers.

Product VM binaries are under:

- `build/osvm/repo/products/sqcogspur64linuxht/lib/squeak/*/squeak`
- `build/osvm/repo/products/sqoilspur64linuxht/lib/squeak/*/squeak`

Image: Squeak 6.1 `23976` 64-bit, matching the announced Oil target. Archive:

https://files.squeak.org/6.1/Squeak6.1-23976-64bit/Squeak6.1-23976-64bit.zip

Archive SHA-256:
`0672833a22134810c69d7a595ad7d639ea76e49cb2ac72676a4ff7f928683410`.
Image SHA-256:
`6dd129721af23643c8a7f35550700fa628cff3cc62ec3ee107615d0fdf945fa8`.
This archive includes `SqueakV60.sources`; do not invent a `SqueakV61.sources` URL.

## Headless failures versus a hung VM

The previous investigation incorrectly inferred that a headless timeout required
an environment/session restart. The smoke launcher subsequently verified normal
headless execution. In a GUI image `Transcript` writes to Morphic and
`FileStream stdout` may be closed; an unhandled error can open an invisible
notifier instead of exiting. Use checked file output and an error handler.

The runner uses `-nodisplay -nosound`, fresh processes and disposable images,
with the existing mechanically adapted Cog benchmarks. It verifies Richards'
2,322/928 counters, DeltaBlue's projection result 223,305, and exhaustive Queens'
92 solutions. Warm-up, work and zero-work process totals are retained. Startup
subtraction on tiny batches can be very noisy.

## Updated workload checks

At `9cf479e`, all 18 runs of the matrix below pass (both clang-built VMs,
three workloads, three repetition counts). A separately built GCC 13 Oil VM
also passes all three workloads at 5,000 repetitions. Clang Oil with both
optional add-ons passes all three at 5,000 repetitions too. No VM sources,
image contents or benchmark algorithms were patched to obtain these passes.

Evidence: `docs/evidence/oil/updated-9cf479e/`, including setup output,
`stress-results.json`, `extra-results.json` and test output. Disposable images,
generated scripts and full process diagnostics remain under `build/osvm/`.

Timing uses seven measured trials plus a discarded warm-up, 5,000 repetitions,
fresh processes and measured zero-work subtraction. These are exploratory host
wall times: other build/test activity overlapped parts of the run, and the host
was not CPU-isolated. Treat ratios as indicative, not publication-quality scores;
correctness checks are independent of that timing caveat. All warm-up and
measured runs passed their answer checks; `comparison-results.json` retains the
individual samples, commands, VM versions and hashes.

| Workload | Cog ms/pass | Oil ms/pass | Cog/Oil |
|---|---:|---:|---:|
| Richards | 0.8335 | 0.5044 | 1.65x |
| DeltaBlue | 0.8198 | 0.6056 | 1.35x |
| Queens | 2.0878 | 0.9415 | 2.22x |

## Historical failures (before the upstream update)

These results used commit `0310be549c0139d972c21a6e67e48803c3fa9843`
(`VMMaker.oscog-cb.3847`), not the current setup pin.
Same Squeak 6.1 image, no optional file-ins, clang-built VMs at that source.
Each row is a separate process; these are workload checks, not timed scores:

| VM/workload | 300 passes | 1,000 passes | 5,000 passes |
|---|---|---|---|
| Stock Cog / Richards | pass | pass | pass |
| Stock Cog / DeltaBlue | pass | pass | pass |
| Stock Cog / Queens | pass | pass | pass |
| Oil / Richards | pass | pass | fail: RichardsBits class>>adaptToNumber:andSend: |
| Oil / DeltaBlue | fail: DBPlanner not indexable | pass | fail: DBCollection>>< |
| Oil / Queens | pass | fail: UndefinedObject>>row | fail: HBQueens>>adaptToNumber:andSend: |

Evidence (committed, so a cloner can inspect it without rebuilding; retained as
`.txt` because `*.log` is gitignored):
`docs/evidence/oil/stress-results.txt` and the per-process result/stderr files
under `docs/evidence/oil/stress-clang/`. The runner regenerates the same layout
under `build/osvm/stress-*`. The mixed pass/fail threshold is not a claim of a
deterministic iteration at which Oil fails. Short smoke passes do not establish
correctness under optimization or GC.

The historical long timing run also rejected Richards before producing a score:
`docs/evidence/oil/oil-compare-long.txt`, artifacts
`docs/evidence/oil/compare-long/`. Its explicit failure is
`MessageNotUnderstood: RichardsBits class>>adaptToNumber:andSend:`.
The committed setup script was then exercised for both flavors
(`docs/evidence/oil/setup-reproduced.txt`); the rebuilt Oil repeats the same
failure at that pin in `docs/evidence/oil/compare-rebuilt/results.json` with
`status: failed`.

A separate GCC 13.3.0 Oil build, same source/image, was tested to distinguish a
clang-only problem. At 5,000 passes Richards passed, but DeltaBlue failed with
`DBPlanner not indexable` and Queens with `HBQueens>>adaptToNumber:andSend:`.
Evidence: `docs/evidence/oil/gcc-stress.txt`,
`docs/evidence/oil/stress-gcc/`. Reproduce the variant with
`python3 scripts/build_oil_gcc.py` after the main setup: it reuses the generated
build script and only swaps the compiler-selection line, so no generated VM
source is edited. This does
not isolate a compiler/GC/register-allocation bug; it only rules out assuming the
problem is specific to the clang warning flags.

An attempted named-primitive optimization-tier control timed out and is not a
validated Oil-disabled control. No conclusion about the failing tier follows
from that attempt. Further isolation belongs in a minimal upstream reproduction,
not in benchmark-specific source rewrites that hide the failure.

## Optional image add-ons

The announcement recommends two optional file-ins for maximum throughput:

- attachment/4/fast-string.st (SHA-256
  `fa264a7336db2c3cddec9f1ac36865958b02dcef985547c5e458f873e9b76f3e`)
- attachment/5/closure-no-outer-context.st (SHA-256
  `c31e67fc9ad2b6b9aaa0bac2bc2312bb9c71a27561ac87054a7daf3591c81f0d`)

Attachment URLs are relative to the announcement message:
`https://lists.squeakfoundation.org/archives/list/vm-dev@lists.squeakfoundation.org/message/GFD6LVTNO7GAPK4A2GPDKJFBXHRPX4UV/`.
They are downloaded under `build/osvm/image`, not installed into the pristine
image. Pass them explicitly to the runner:

```sh
python3 scripts/bench_compare_oil.py --repetitions 3000 --addons \
  build/osvm/image/fast-string.st build/osvm/image/closure-no-outer-context.st
```

At the old `0310be5` pin both file-ins separately passed ten repetitions of
each benchmark, but combined Richards failed at 3,000 repetitions with the same
wrong-receiver error as bare Oil. Those observations predate the upstream fix.
No comparative timing score is claimed for the add-ons.

## Tooling tests and scope

Five focused Oil tests check the documented revision pin, wrapped verification,
quoting/explicit file-ins, rejection of error output with zero exit status, and
executed Cog/Oil smoke plus forced-error reporting. Smoke tests skip if optional
VMs are absent; set `REQUIRE_OSVM=1` to require local builds. They are not a VM
correctness suite. On this worktree `REQUIRE_OSVM=1 nimble testBenchmarkPorts`
ran 22 tests: 20 passed, two GNU Smalltalk tests skipped because its optional
local build was absent. This includes the executed Cog/Oil tests and ARC/ORC
native references. This is focused tooling validation, not a full language-suite
pass. The Harding runtime/compiler is unchanged.

The upstream `9cf479e` update clears the historical failure matrix on the
unchanged image and adapters. This establishes these workloads at the tested
batch sizes, not general VM correctness. AWFY Bounce/Json/Havlak are not covered
by the Cog/Oil adapter; no Oil score is claimed for them.
