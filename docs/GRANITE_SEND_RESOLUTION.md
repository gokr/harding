# Single resolution per dynamic send

## Change

`sendMessage` used to detect and then dispatch a compiled method through two
helpers:

```nim
if receiverClassName.len > 0 and hasCompiledMethodInHierarchy(receiverClassName, selector):
  return dispatchCompiledMethodFromClass(receiver, receiverClassName, selector, args)
```

Both are thin wrappers around `resolveCompiledMethod(className, selector)`, so each
dynamic send that reached a compiled method resolved the same pair twice, and the
second wrapper additionally repeated `getReceiverClassName` and the bound-host
lookup. `sendMessage` now resolves once, inlines the host check (it already knows
the receiver is a native proxy, so the class-name comparison in
`dispatchCompiledMethodFromClass` is redundant) and calls the target directly.

`hasCompiledMethodInHierarchy` and `dispatchCompiledMethodFromClass` are unchanged
and still used elsewhere (`perform:`, the class-side path, and the tail of the
builtin chain), so their contracts are intact.

## Measured effect

Same-core (CPU 2) paired trials against retained baseline
`build/granite-profiles/run-ojzy1bv4` (runtime `24b594c`), 30 verified passes per
process, twelve measured alternating trials after one warm-up:

| Workload | Trial 1 | Trial 2 |
|---|---:|---:|
| Richards | **1.148x** | **1.142x** |
| DeltaBlue | **1.228x** | **1.224x** |
| Queens | 1.044x | 1.029x |

Evidence: `build/dedup-pinned.log`, `build/dedup-pinned-repeat.log`. Queens gains
least because the Boolean primitive slice already removed most of its compiled
dispatch sends.

Counts per verified pass, before → after:

| Workload | `resolveCompiledMethod` | `hasCompiledMethodInHierarchy` | `dispatchCompiledMethodFromClass` |
|---|---:|---:|---:|
| Richards | 104,391 → 63,678 | 63,674 → 22 | 40,714 → 1 |
| DeltaBlue | 209,239 → 106,325 | 104,875 → 1,451 | 104,362 → 1,448 |
| Queens | 123,419 → 103,586 | 103,585 → 2,056 | 19,833 → 0 |

Wall-time gains exceed the pure resolution saving because `resolveCompiledMethod`
feeds `walkCompiledHierarchy` → `findCompiledMethod` and its string hashing, which
does not appear as self time in the flat profile. Remaining
`getReceiverClassName`/`boundInterpretedSend` counts are one per send and are the
next candidate.

## Validation

ARC and ORC, zero failures: `test_compiled_runtime` 43, `test_engine_boundary` 35,
`test_compiled_support` 11 (logs `build/dedup-*`).

## Next candidates

The profile now shows, per send: one `getReceiverClassName`, one
`boundInterpretedSend` (whose owner lookup allocates a `seq[Class]` for the walked
path), a `getOrDefault` in the cache probe, and the argument `seq`. Also still
prominent on Richards: `getOrDefault` 6.3M/pass, `hash` 11.4M/pass, `rawAlloc`
10.3M/pass and 24.8M `eqdestroy` calls — the copy/allocation path, not dispatch.
