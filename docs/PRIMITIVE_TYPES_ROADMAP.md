# Primitive representations and specialized containers

Status: agreed roadmap, not a list of implemented features. The intended end
state is type-inferred native Nim code where possible, with dynamic storage and
dispatch at uncertain boundaries. Harding values remain objects with protocols;
native representation does not make their classes non-extensible.

## Current scalar target

| Harding type | Granite representation | Notes |
|---|---|---|
| Integer | `int` | Currently machine-sized, not Python's arbitrary-precision integer |
| Float | `float64` | Existing floating-point value kind |
| Boolean | `bool` | Shared representation for true/false, retaining language class identity |
| String | `string` | Preserve Harding text semantics at the boundary |
| Symbol | native payload with Symbol tagging at boundaries | Semantically distinct from String; empty literal is `#""` |

Declared primitive slots reject nil and incompatible writes. Float accepts
Integer writes by conversion, but Integer does not implicitly accept Float.
Rejected writes signal a catchable Error and preserve the old value. Defaults
are 0, 0.0, false, empty String and empty Symbol respectively. Object-constrained
slots accept nil and instances of the declared class or subclasses, including
multiple-parent ancestry. Dynamic slots remain unrestricted. Defaults are applied
at allocation, including `basicNew`, before ordinary `initialize` behavior.
These are the approved contract; enforcement parity is work in progress.

## Candidate additional scalars

| Candidate | Possible Nim representation | Motivating uses |
|---|---|---|
| Signed fixed-width integers | `int8` through `int64` | Binary formats, FFI, predictable storage |
| Unsigned fixed-width integers | `uint8` through `uint64` | Networking, bit fields, FFI |
| Byte | `uint8` | Binary data; decide whether this is a distinct type or alias |
| Single-precision float | `float32` | Graphics, audio, dense numeric datasets |
| Unicode character | `Rune` (a library type) | Code-point operations, not byte indexing |
| Complex number | `Complex[T]` (a library type) | Scientific computation |

These are candidates, not syntax or API commitments. Add them for demonstrated
uses rather than mirroring every Nim type. Specify width, signedness, overflow,
conversion, equality, serialization and FFI behavior explicitly. Do not inherit
semantics accidentally from debug/release overflow settings. Rune is not a
Unicode grapheme; character indexing needs its own language decision.

## Specialized arrays: first expansion after the scalar contract

Illustrative APIs, not implemented selectors:

```harding
pixels := ByteArray new: 4096.
samples := Float64Array new: 1000.
```

Candidate backing stores:

- ByteArray: contiguous `seq[uint8]` storage.
- IntegerArray: contiguous `seq[int]` storage.
- Float64Array: contiguous `seq[float64]` storage.

These avoid a NodeValue per element, reduce memory use, and improve locality.
Native loop generation can follow once element types are known. Fixed-length
Nim `array[N, T]` representations can be considered later for vectors and
embedded structures; they are not automatically the representation of every
Harding Array.

Ordinary Array remains heterogeneous, mutable and reference-sharing. Specialized
arrays should also have explicit identity, mutation and aliasing rules. A managed
owner around native storage can preserve shared identity; simply exposing Nim
sequence value-assignment behavior would not suffice. Define allocation defaults,
bounds checks, element conversion/rejection, cloning, slices and foreign-buffer
ownership before implementing the containers. Never share one mutable empty
default between unrelated instances by accident.

## Foreign pointers and handles

Nim separates managed `ref T` from unmanaged `ptr T` / `pointer`:

- Managed references are appropriate for ordinary Harding objects. Nil-capable
  object references do not require an Option wrapper; valid representation alone
  does not prove a dereference safe or eliminate all checks.
- Opaque foreign handles should be the first FFI exposure: explicit lifetime and
  close/dispose protocols, with invalid-handle checks.
- Freely dereferenceable pointers and pointer arithmetic belong only in an
  explicitly unsafe interface, if a concrete FFI need justifies them.

Specify ownership, nullability, invalidation after close, bounds, alignment and
thread access. Keep managed owners alive while borrowed memory is in use. Do not
encode foreign pointers as Integers or disguise them as managed references.
Validate ARC/ORC lifetime and callback behavior, including failure cleanup.

## Priority and next steps

1. Finish the existing scalar-slot contract consistently in interpreter and
   Granite, with tests for every write route and defaults.
2. Continue obvious static inference, then interpreter-sourced type feedback
   collected during unit tests. Profiles complement proofs; they are not complete
   coverage and require guarded fallback where assumptions remain speculative.
3. Measure representative annotated/inferred benchmark builds against retained
   baselines; do not infer speed from native storage alone.
4. Add ByteArray, then numeric arrays, as the first expansion of built-in native
   representations.
5. Add fixed-width scalars for an actual binary/FFI use case.
6. Introduce opaque foreign handles before considering unsafe raw pointers.

Real Nim inheritance, typed object references and multi-parent layouts remain
separate compiler design work. This roadmap does not require changing ordinary
Array semantics or forcing every developer to supply type declarations.

Related evidence and prior proposals: `GRANITE_DIRECT_SLOTS.md`,
`GRANITE_TYPED_MEMBERS_DESIGN.md`, and `GRANITE_SLOT_TYPE_INFERENCE.md`. The latter
contain historical proposals; the approved contract summarized here supersedes
conflicting earlier nil/default suggestions.
