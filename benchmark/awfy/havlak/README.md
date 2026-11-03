# AWFY SOM Havlak (Harding)

Upstream: https://github.com/smarr/are-we-fast-yet
Pinned revision: `74306fec151070fd07157cefeacf19e7e0bcdc89`.
Sources: `benchmarks/SOM/Havlak/` and `benchmarks/SOM/Core/`.
Original sources and their Google Apache-2.0 and SOM MIT notices are retained
in `upstream/`; each adapted class retains its original notice as well.

`havlak.hrd` contains definitions. `driver.hrd` contains the configurable
workload (dummy loops, extra finder iterations, parallel/middle/inner loops).
Run `python3 benchmark/awfy/havlak/run.py 1 0 1 1 1` for a small graph.
`run.py --assemble-only` prints a standalone source path for either engine.
To assemble and validate, run `python3 tests/test_awfy_havlak.py` from the
checkout. All generated sources, caches and executables use `build/awfy-havlak`.
Set `AWFY_HAVLAK_FULL=1` for all five exact upstream workloads:

| Dummy iterations | Loops | Nodes |
| ---: | ---: | ---: |
| 1 | 1605 | 5213 |
| 15 | 1647 | 5213 |
| 150 | 2052 | 5213 |
| 1500 | 6102 | 5213 |
| 15000 | 46602 | 5213 |

These use 50 extra finder runs and graph parameters 10,10,5, exactly as SOM.
The default tests use scaled graphs, not substituted algorithms.

## Adaptation

`port.py <pinned checkout>` regenerates the checked-in definitions. It changes
class/method syntax, lowercase constant selectors, trailing-underscore slot
names, adds explicit self returns (SOM's default), translates string
concatenation and supplies the unused argument Harding passes to ifNotNil:.
`HavlakArray` preserves SOM's 1-based indexing without changing the graph's
node names or DFS numbering. `downTo:do:` maps to `to:by:do:`. Vector sorting
(unused by Havlak) is omitted. The unused infinitely recursive upstream
SomIdentityDictionary class-side `new:` is omitted, leaving its inherited
constructor. Other Core algorithms, bucket splitting, traversal callbacks,
identity comparisons, and union-find object graph are retained. No typed slots.

Missing generic Integer APIs are `bitXor:`, unsigned right shift `>>>`, and
bitwise AND. Harding `&` is **not** bitwise AND. The temporary nonnegative
`HavlakBits` compatibility implementation preserves their mathematics;
power-of-two bucket masking uses remainder. This is not a performance-equivalent
bitwise implementation. Replace it with generic stdlib operations when agreed,
not compiler special cases. Required input range is nonnegative block names,
with XOR of hash and logical shift by 16, and AND of hashes with bucket masks
or one power-of-two capacity bit. The port-local Vector/Dictionary/Set remain
part of the workload, not native Table replacements.

Generic stdlib candidates: explicit bit operations and a consistent nil-block
arity contract; no shared files are modified by this port.
