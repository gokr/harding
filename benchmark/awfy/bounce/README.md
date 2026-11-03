# AWFY Bounce

Executable Harding port of AWFY SOM `Bounce`, `Ball`, and `SomRandom`, pinned to
`74306fec151070fd07157cefeacf19e7e0bcdc89` at
<https://github.com/smarr/are-we-fast-yet>.
`upstream/provenance.json` records exact source SHA-256 digests. Upstream files
are unmodified, including copyright/permission notices; `upstream/LICENSE.md`
is the upstream repository license overview. The source notices refer to an
`AUTHORS.md` file which is absent from that upstream revision.

The benchmark creates 100 fresh Ball instances, updates all of them 50 times,
and prints `1331`. Ball state, update/clamping order and RNG seed are preserved.
There are no type declarations. The nested `to:do:` / collection `do:` hot loop
and captured `bounces` accumulator are preserved. Bounce derives from Object
instead of the external SOM harness's Benchmark base; its benchmark and
verifyResult: protocol remain intact.

Syntax/API adaptations:

- SOM `%` becomes Harding `\\` modulo.
- SOM integer `& 65535` becomes remainder modulo 65536: exactly equivalent for
  this positive 16-bit generator. Harding `&` concatenates; no bitwise API exists.
- SOM `Array new:withAll:` evaluates a generator per element; Harding fills with
  the argument itself (even a block). Allocate then fill with inclusive,
  zero-based `to:do:` to preserve distinct balls and RNG call order. A generic
  tabulation constructor would be useful but is not needed for this port.
- Explicit `^ self` preserves SOM initialization receiver results.

## Run and validate

From `/home/gokr/git/harding-granite-completeness`:

```sh
./harding /home/gokr/git/harding-granite-completeness/benchmark/awfy/bounce/bounce.hrd
python3 -B /home/gokr/git/harding-granite-completeness/benchmark/awfy/bounce/compare.py
python3 -B /home/gokr/git/harding-granite-completeness/tests/test_awfy_bounce.py -v
```

The comparator imports the pinned upstream Python implementation unchanged;
only its driver is local. The test checks source digests, Python result,
ARC/ORC interpreters, repeated runs/verification/RNG, and retained `./granite`
code generation followed by separate ARC/ORC Nim builds. All logs, interpreter
binaries, generated code, and caches stay under `build/awfy-bounce/`. It never
rebuilds or overwrites root compiler binaries.

## Validation status

Bounce now passes in the interpreter and natively under ARC and ORC, and the
pinned upstream Python comparator agrees (1331).

The port originally exposed a generic code-generation defect: selector strings
were emitted unescaped, so `\\` produced `closing " expected` in generated Nim.
That was fixed in the compiler (all dynamic selector emission sites now escape),
pinned by `tests/test_selector_escaping.py`. The port keeps its own modulo
selector and was not rewritten to dodge the bug.
