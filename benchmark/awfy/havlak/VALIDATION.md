# Validation evidence

Entry: `python3 tests/test_awfy_havlak.py`. Artifacts/logs: `build/awfy-havlak/`.

Status: Havlak passes in the interpreter and natively under ARC and ORC.

- Scaled conformance and workload cases match pinned AWFY Python and the
  interpreter, including identity/union-find/collection callback behaviour.
- Full-size graph native ARC matches the interpreter exactly:
  `1 0 10 10 5` -> `Havlak loops=1605 nodes=5213`.

Assemble the standalone source with `python3 benchmark/awfy/havlak/run.py
--assemble-only` (it interleaves the driver's temporaries), then compile that:

```sh
./granite compile build/awfy-havlak/standalone.hrd --dir:build/havlak-native -o:prog
```

## Gaps this port exposed (both fixed generically)

1. Native `Integer>>to:do:` descended when the start exceeded the end. An empty
   Vector traversal sends `1 to: 0 do:`, so the callback ran twice and a later
   `union:` reached nil. The interpreter runs zero iterations
   (`tests/test_native_integer_iteration.py`).
2. Native `Integer>>to:by:do:` was missing entirely; negative steps were
   unavailable in compiled code.

These are runtime parity fixes, not benchmark workarounds: no selector was
renamed and the port keeps its arithmetic bit-emulation locally, because Harding
`&` is concatenation. A general bitwise API is still absent by design; the port's
nonnegative 16/32-bit masks use modulo arithmetic instead.

Full upstream workloads are encoded in the source verifier and run through
`tests/test_awfy_havlak.py`; no timing claim is made.
