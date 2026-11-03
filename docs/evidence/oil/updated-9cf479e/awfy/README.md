# AWFY Cog/Oil results

Adapter: `scripts/awfy_cog.py`, driven by
`python3 scripts/bench_compare_oil.py bounce json havlak --trials 5`.

- VMs: stock Cog and Oil built from OpenSmalltalk `9cf479e` (see `builds.json`),
  clang 18, same Squeak 6.1-23976 image as every other run here.
- Sources: AWFY upstream `74306fec`, vendored flat under
  `benchmark/awfy/smalltalk/upstream/` with per-file SHA-256 in its
  `provenance.json`; loaded by upstream's own `SomLoader-Compiler.st`.
- Workload: upstream's own Som sources, NOT the Harding ports in
  `benchmark/awfy/<case>/`. Upstream Json verifies its own fixture; the ports'
  `JsonChecks` assertions are not run here.

Indicative per-pass medians (5 measured trials, discarded warm-up, measured
zero-work subtraction). The host was shared with other work and was not
CPU-isolated, so treat the ratios as indicative:

| Workload | passes | Cog ms/pass | Oil ms/pass | Cog/Oil |
|---|---:|---:|---:|---:|
| Bounce | 2000 | 0.1803 | 0.0765 | 2.36x |
| Json | 200 | 6.5595 | 5.3589 | 1.22x |
| Havlak | 3 | 694.25 | 824.18 | 0.84x |

Havlak is the one case where Oil is slower here, and a separate run at three
passes per measurement (`havlak-results.json`, `havlak.txt`) reproduces it
(694.25 vs 824.18 ms/pass), so it is not an artefact of timing one long run. The
figure is still a steady-state rate over the checked full-size graph
(1605 loops / 5213 nodes) only — it says nothing about Oil's JIT in general, and
nothing about the Harding AWFY ports, which are different programs.

`comparison-results.json` (single-pass Havlak) and `havlak-results.json`
(three-pass) retain every sample, command, VM version and hash. `tests.txt` is
the focused `REQUIRE_OSVM=1 nimble testBenchmarkPorts` run; `comparison.txt` is
the single-pass run's stdout.
