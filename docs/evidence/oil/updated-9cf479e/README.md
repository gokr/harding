# Oil upstream update verification

Source: OpenSmalltalk/opensmalltalk-vm `Cog`,
`9cf479ec02cee2bd86a1791573169b44bdd3633c`.

- `builds.json`: binary hashes and VM-reported versions for stock Cog, clang Oil
  and GCC Oil. Build setup: `python3 scripts/setup_benchmark_osvm.py`, then
  `python3 scripts/build_oil_gcc.py`.
- `stress-results.json`: old failure matrix, 18 checked processes (300, 1000,
  5000 passes of each workload on stock Cog and clang Oil). Each result is
  checked by `bench_compare_oil.checked_driver` and `bench_compare.execute`.
  Per-process result and stderr files are retained alongside it.
- `extra-results.json`: GCC Oil and clang Oil with both announcement add-ons,
  5000 passes of each workload, six checked processes. Add-on hashes are in
  `docs/OPENSMALLTALK_OIL_COMPARISON.md`.
- `tests.txt`: `REQUIRE_OSVM=1 nimble testBenchmarkPorts` (20 passed, two optional
  GNU Smalltalk tests skipped).

Inputs: pristine Squeak 6.1-23976, unchanged Richards/DeltaBlue/Queens adapters.
VM executions use disposable image copies, `-nodisplay -nosound`, never save,
and reject missing/error/wrong output even when exit status is zero. Original
image SHA-256 remains
`6dd129721af23643c8a7f35550700fa628cff3cc62ec3ee107615d0fdf945fa8`.

Timing is exploratory wall-clock timing, not an idle-host publication run:
other build/test activity overlapped part of the comparison. Do not infer
upstream bug causality, general VM correctness, or AWFY coverage from these
workload-specific results. Historical failures remain in sibling evidence
folders and are not overwritten.
