# JSON Serialization Plan V2: Compiled Fast Path with Declarative Class Metadata

## Goal

Provide very fast JSON serialization for Harding values and objects with these properties:

1. `Json stringify:` works for ordinary Harding objects out of the box
2. Common customizations stay declarative and compile into primitive-only execution
3. Uncommon, fully dynamic cases still have an escape hatch, but on an explicit slower path
4. The primitive writes JSON directly to a string instead of building an intermediate JSON tree

## Core Design Principles

1. **Fast path first**: The common case must execute entirely inside Nim
2. **No per-object Harding dispatch in the hot loop**: Avoid transformer blocks and custom serializer blocks during normal traversal
3. **Declarative metadata**: Class-side JSON configuration should be simple to read and compose with cascades
4. **Compiled plans**: Convert class metadata into a slot-indexed Nim plan once, then reuse it
5. **Explicit slow path**: Representation hooks are supported, but clearly separated from the fast path
6. **Direct string writer**: Serialize straight into `var string`, borrowing encoder techniques used by libraries like `jsony` and `sunny`

## Recommended Shape

Use two layers:

- `JsonSpec`: Harding-visible configuration attached to a class
- `JsonPlan`: Nim-only compiled serialization plan derived from `JsonSpec` and the class layout

`Json stringify:` should:

1. Handle primitive values directly
2. Handle Arrays and Tables directly
3. For ordinary objects, look up the class plan and serialize from that plan
4. Only use a fallback representation hook when the class plan says it must

## What Stays in the Primitive Fast Path

These customizations are common enough and simple enough to compile into the plan:

- include all slots by default
- exclude selected slots
- include only selected slots
- rename JSON keys
- omit `nil` fields
- omit empty fields
- reorder output fields
- apply built-in formatter symbols that the primitive can handle without message sends

### Built-in Formatter Symbols

Formatters should be symbolic and finite, not arbitrary Harding blocks.

Initial formatter set:

- `#string` - emit value as JSON string
- `#rawJson` - embed a trusted JSON fragment without re-escaping
- `#symbolName` - serialize a symbol by its name
- `#className` - serialize a class by its name

Possible later additions for supported proxy types:

- `#iso8601`
- `#unixSeconds`
- `#unixMillis`

Only add built-in formatters that the primitive can execute entirely in Nim.

## What Moves to the Slow Path

These remain supported, but should not be mixed into the fast path design:

- arbitrary per-slot transformer blocks
- full custom serializer blocks
- computed fields that require sending Harding messages during traversal
- object-specific conditional logic beyond simple omit rules

For these cases, use a representation hook such as `jsonRepresentation`.

## Configuration API

Configuration should be class-side, cascade-friendly, and declarative.

```harding
# Default behavior: all slots in slot order
Person := Object derive: #(name email age).

# Configure after derive: to keep JSON separate from the object model API
User := Object derive: #(id username email password createdAt avatarUrl)
    ; jsonExclude: #(password)
    ; jsonRename: #{
        #username -> "userName"
    }
    ; jsonOmitNil: #(avatarUrl)
    ; jsonFormat: #{
        #createdAt -> #iso8601
    }.
```

### Proposed Class-Side Messages

```harding
Class>>jsonSpec
Class>>jsonExclude: slotNames
Class>>jsonOnly: slotNames
Class>>jsonRename: mappings
Class>>jsonOmitNil: slotNames
Class>>jsonOmitEmpty: slotNames
Class>>jsonFormat: mappings
Class>>jsonFieldOrder: slotNames
Class>>jsonReset
```

Notes:

- slot names should be symbols in Harding code, then compiled to slot indexes in Nim
- `jsonRename:` is clearer than `jsonMap:` for field renaming
- `jsonReset` must invalidate the compiled plan cache

## Fallback Protocol

For cases that cannot stay inside the primitive, support one explicit representation protocol.

```harding
Invoice>>jsonRepresentation [
    ^ #{
        "id" -> id.
        "lineCount" -> lines size.
        "total" -> (self totalAsString).
    }
]
```

Behavior:

- if a class does not define the fallback hook, normal plan-based serialization is used
- if a class defines the fallback hook, the plan records that once and routes to the slow path
- the slow path may allocate Tables, Arrays, or strings and may send Harding messages

This keeps fallback flexibility without paying for dynamic dispatch in the common case.

## Out-of-the-Box Behavior

Without any JSON configuration:

- `Json stringify:` serializes Numbers, Strings, Booleans, `nil`, Arrays, and Tables as expected
- ordinary objects serialize as JSON objects using `class.allSlotNames` in slot order
- inherited slots are included
- slot names become JSON keys as-is

Optional convenience API:

```harding
Object>>toJson [
    ^ Json stringify: self
]
```

This is preferable to requiring an opt-in mixin for the baseline behavior.

## Nim Architecture

### Class Metadata

The Harding-visible spec should be attached to the class, not stored in a global table keyed by class name.

Reasons:

- class names are not a stable identity
- redefinition can change slot layouts
- stale metadata is harder to invalidate when keyed only by name

Suggested additions to `Class` metadata:

```nim
type
  JsonFormatKind* = enum
    jfkNone,
    jfkString,
    jfkRawJson,
    jfkSymbolName,
    jfkClassName,
    jfkIso8601,
    jfkUnixSeconds,
    jfkUnixMillis

  JsonSpec* = ref object
    excludedSlots*: seq[string]
    includedOnly*: seq[string]
    renamedSlots*: Table[string, string]
    omitNilSlots*: seq[string]
    omitEmptySlots*: seq[string]
    slotFormats*: Table[string, JsonFormatKind]
    fieldOrder*: seq[string]
    useRepresentationHook*: bool

  JsonFieldPlan* = object
    slotIndex*: int
    outputKey*: string
    outputKeyPrefix*: string
    omitNil*: bool
    omitEmpty*: bool
    formatKind*: JsonFormatKind

  JsonPlanKind* = enum
    jpkSlots,
    jpkRepresentationHook

  JsonPlan* = ref object
    kind*: JsonPlanKind
    fields*: seq[JsonFieldPlan]
    compiledForClassVersion*: int
    compiledForJsonVersion*: int
```

Recommended class fields:

- `jsonSpec*: JsonSpec`
- `jsonConfigVersion*: int`
- `cachedJsonPlan*: JsonPlan`

If storing the plan directly on `Class` is awkward, use a Nim table keyed by class identity, not class name.

### Plan Compilation

Compile `JsonSpec` into `JsonPlan` once per class version.

Compilation should:

1. Start from `class.allSlotNames`
2. Resolve symbol names to slot indexes
3. Validate unknown slot names early
4. Merge inherited JSON metadata with child overrides
5. Precompute each field's output key and key prefix such as `"userName":`
6. Produce the final output field order once
7. Record whether the class uses fallback representation

This avoids repeated hash lookups and repeated slot-name checks during serialization.

### Primitive Writer

Do not build a `JsonNode` tree for object serialization.

Instead:

```nim
proc writeJsonValue(interp: var Interpreter, val: NodeValue, out: var string,
                    state: var JsonWriteState)

proc writeJsonObjectFast(interp: var Interpreter, inst: Instance, out: var string,
                         state: var JsonWriteState)
```

`JsonWriteState` should track:

- visited object identities for cycle detection
- recursion depth
- optional flags for future pretty-print support

### Primitive Skeleton

```nim
proc primitiveJsonStringifyImpl(interp: var Interpreter, self: Instance,
                                args: seq[NodeValue]): NodeValue {.nimcall.} =
  if args.len < 1:
    return NodeValue(kind: vkString, strVal: "null")

  var out = newStringOfCap(128)
  var state = initJsonWriteState()
  writeJsonValue(interp, args[0], out, state)
  NodeValue(kind: vkString, strVal: out)
```

### Fast Object Serialization

```nim
proc writeJsonObjectFast(interp: var Interpreter, inst: Instance, out: var string,
                         state: var JsonWriteState) =
  let plan = getOrCompileJsonPlan(inst.class)

  case plan.kind
  of jpkRepresentationHook:
    writeJsonObjectFromRepresentation(interp, inst, out, state)
  of jpkSlots:
    if state.enterInstance(inst):
      out.add '{'
      var emitted = 0
      for field in plan.fields:
        let slotValue = inst.slots[field.slotIndex]

        if field.omitNil and slotValue.kind == vkNil:
          continue

        if field.omitEmpty and isJsonEmpty(slotValue):
          continue

        if emitted > 0:
          out.add ','
        out.add field.outputKeyPrefix
        writeFormattedJsonValue(interp, slotValue, field.formatKind, out, state)
        inc emitted
      out.add '}'
      state.leaveInstance(inst)
    else:
      raiseJsonCycleError()
```

## Direct Writer Requirements

The writer should borrow proven encoder techniques used by `jsony` and `sunny`:

- append directly to a mutable string
- escape strings without allocating temporary `JsonNode`s
- fast integer writing without allocating via `$` in the hot path where practical
- reuse precomputed `"key":` prefixes
- support raw JSON passthrough as an explicit formatter kind

## Representation Hook Behavior

The fallback hook should be simple and predictable.

Suggested contract:

- `jsonRepresentation` returns a Harding value that `Json stringify:` already understands
- usually a Table, Array, primitive, or nested combination of those
- the primitive calls it once, then serializes the returned value normally

This is slower than the slot plan path, but still straightforward.

## Semantics That Should Be Defined Up Front

### Cycles

- default behavior: raise a JSON serialization error with a useful message
- do not silently recurse forever
- do not silently replace cycles with `null`

### Unsupported Values

If a value cannot be serialized directly, fail with a clear error.

Examples:

- blocks
- methods
- unsupported Nim proxy objects
- file handles or GUI objects without explicit formatters

### Table Keys

Define this explicitly.

Recommended rule:

- allow String and Symbol keys directly
- optionally allow Number and Boolean keys by string coercion if desired
- reject everything else with an error

### Inheritance

Recommended merge behavior:

- parent JSON metadata is inherited
- child metadata overrides parent metadata for the same slot
- child `jsonOnly:` replaces the inherited inclusion set rather than merging ambiguously

### Output Order

Recommended order:

1. explicit `jsonFieldOrder:` slots first
2. remaining included slots in class slot order

That keeps output deterministic and easy to reason about.

## API Examples

### Default Serialization

```harding
Person := Object derive: #(name email age).

person := Person new
    name: "Alice"
    ; email: "alice@example.com"
    ; age: 30.

Json stringify: person.
# => {"name":"Alice","email":"alice@example.com","age":30}
```

### Sensitive Fields

```harding
User := Object derive: #(id email passwordHash role)
    ; jsonExclude: #(passwordHash).
```

### Renames and Omit Rules

```harding
ApiUser := Object derive: #(id username avatarUrl bio)
    ; jsonRename: #{
        #username -> "userName"
    }
    ; jsonOmitNil: #(avatarUrl)
    ; jsonOmitEmpty: #(bio).
```

### Raw JSON Embedding

```harding
ApiEnvelope := Object derive: #(status payload)
    ; jsonFormat: #{
        #payload -> #rawJson
    }.
```

### Explicit Fallback

```harding
Invoice := Object derive: #(id lines taxRate).

Invoice>>jsonRepresentation [
    ^ #{
        "id" -> id.
        "lineCount" -> lines size.
        "taxRate" -> taxRate.
        "total" -> self totalString
    }
]
```

## Integration with Existing `Json stringify:`

The current primitive already handles simple values, Arrays, and Tables. It should be extended rather than replaced by a second object serializer API.

Recommended behavior for `Json stringify:`:

- Numbers -> JSON number
- Strings -> escaped JSON string
- Booleans -> `true` or `false`
- `nil` -> `null`
- Arrays -> JSON array
- Tables -> JSON object
- ordinary objects -> compiled class plan
- representation-hook classes -> slow fallback

This keeps the user-facing API small and predictable.

## Performance Model

### Fast Path

- O(n) over included fields
- direct slot index access
- no per-field method dispatch
- no per-field hash lookup after plan compilation
- no intermediate `JsonNode` allocation

### Slow Path

- one Harding dispatch to `jsonRepresentation`
- then ordinary serialization of the returned value

### Plan Compilation Cost

- paid once per class layout and JSON config version
- amortized across all instances of that class

## Migration Plan

### Phase 1: Direct Writer

1. Refactor `Json stringify:` internals to write directly into `var string`
2. Improve primitive string escaping and numeric writing
3. Keep existing behavior for primitives, Arrays, and Tables

### Phase 2: Class Metadata

1. Add `JsonSpec` metadata to `Class`
2. Add class-side configuration methods
3. Add invalidation via `jsonConfigVersion`

### Phase 3: Compiled Plans

1. Add `JsonPlan` compilation from `JsonSpec`
2. Cache plan by class identity and version
3. Serialize ordinary objects through the compiled slot plan

### Phase 4: Slow Fallback

1. Add `jsonRepresentation` support
2. Route classes that need dynamic representation through the fallback path
3. Document the performance difference clearly

### Phase 5: Extended Formatters

1. Add `#rawJson`
2. Add safe built-in formatter kinds as needed
3. Add tests for omit rules, renames, inheritance, and cycles

## Concrete Implementation Checklist

This section maps the design onto the current repository structure so implementation can proceed file by file.

### `src/harding/core/types.nim`

- Add JSON metadata fields to `Class` near the existing metadata and cache fields:
  - `jsonSpec*: JsonSpec`
  - `jsonConfigVersion*: int`
  - `cachedJsonPlan*: JsonPlan`
- Add the new JSON support types near the object-model definitions:
  - `JsonFormatKind`
  - `JsonSpec`
  - `JsonFieldPlan`
  - `JsonPlanKind`
  - `JsonPlan`
- Initialize the new JSON fields in `newClass` so every class starts with a clean JSON state.
- Ensure replacement or rebuilt classes preserve or intentionally reset JSON metadata in a predictable way.
- Add small helpers that will be useful across the implementation:
  - `proc getJsonSpec*(cls: Class): JsonSpec`
  - `proc invalidateJsonPlan*(cls: Class)`
  - `proc hasCachedJsonPlan*(cls: Class): bool`

Checklist:

1. Extend the `Class` definition without disturbing existing method-cache logic
2. Initialize JSON fields in `newClass`
3. Add plan invalidation helpers in the same module as class metadata helpers
4. Keep the new metadata ASCII-only and warning-free

### `src/harding/interpreter/objects.nim`

This file is the best place for class-side JSON configuration primitives because it already owns class derivation and class mutation behavior.

- Add native class-side implementations for:
  - `jsonSpec`
  - `jsonExclude:`
  - `jsonOnly:`
  - `jsonRename:`
  - `jsonOmitNil:`
  - `jsonOmitEmpty:`
  - `jsonFormat:`
  - `jsonFieldOrder:`
  - `jsonReset`
- Reuse existing extraction patterns like `extractSlotNamesFromArray` and `extractStringValue`.
- Add small helpers for decoding Harding Tables into Nim tables for rename and format config.
- Every config mutation must call `invalidateJsonPlan(cls)` and bump `jsonConfigVersion`.
- When class layout changes through existing class-building APIs, also invalidate JSON plans:
  - `createDerivedClass`
  - `classSlotsImpl`
  - `classParentsImpl`
  - any path that replaces or mutates a class layout

Checklist:

1. Register the new class-side selectors alongside the existing `derive:` family in `initCoreClasses`
2. Add native implementations that mutate class-attached `JsonSpec`
3. Validate slot names early and raise clear errors for unknown slots
4. Invalidate JSON plans whenever a class layout or JSON config changes
5. Decide whether `jsonSpec` returns a real Harding object, or keep it internal and expose only mutator messages

### `src/harding/interpreter/vm.nim`

This is the core implementation file for the writer and integration with `Json stringify:`.

- Replace the current `primitiveJsonStringifyImpl` `JsonNode` builder with a direct string writer.
- Add writer helpers near the existing JSON primitive code:
  - `writeJsonString`
  - `writeJsonNumber`
  - `writeJsonArray`
  - `writeJsonTable`
  - `writeJsonObjectFast`
  - `writeFormattedJsonValue`
  - `writeJsonValue`
- Add `JsonWriteState` with:
  - visited-instance tracking for cycle detection
  - recursion depth
  - any future output flags
- Add plan compilation helpers:
  - `getOrCompileJsonPlan`
  - `compileJsonPlan`
  - slot-name-to-index resolution helpers
  - inheritance merge helpers for `JsonSpec`
- Update the `vkInstance` branch so ordinary objects serialize through `writeJsonObjectFast` instead of `%val.toString()`.
- Keep Array and Table handling in the same primitive so the user-facing API stays `Json stringify:`.

Checklist:

1. Land direct writer refactor first without changing object semantics yet
2. Add cycle detection before enabling object traversal
3. Switch `ikObject` serialization from `toString()` fallback to class-plan traversal
4. Keep primitive-only formatters in a dedicated `case` on `JsonFormatKind`
5. Raise explicit JSON serialization errors instead of silently coercing unsupported objects

### `lib/standard/Json.hrd`

This file is currently only a thin placeholder. It should become the user-facing API layer.

- Add optional convenience methods such as:
  - `Object>>toJson`
  - class-side comments or examples for JSON config usage
- If the class-side JSON configuration API is implemented in Nim, `Json.hrd` can remain thin and document the surface area.
- If you want JSON config available automatically in normal sessions, decide whether `Json.hrd` should be loaded from `lib/standard/Bootstrap.hrd`.

Checklist:

1. Keep the public API minimal
2. Avoid implementing the hot path in Harding code
3. Decide whether JSON support is opt-in by `load:` or part of standard bootstrap

### `lib/standard/Bootstrap.hrd`

- Decide whether to load `lib/standard/Json.hrd` automatically.
- If yes, update bootstrap and test any startup assumptions.
- If no, document clearly that `Json stringify:` exists natively while convenience helpers live in `Json.hrd`.

Checklist:

1. Pick one loading story and document it clearly
2. Keep bootstrap changes minimal unless automatic `Object>>toJson` is required

### `tests/test_json_literal.nim`

This file already covers literal parsing and the current `Json stringify:` baseline. It should be expanded or split.

- Keep existing literal and basic stringify tests intact
- Add object serialization tests for:
  - default slot serialization
  - inherited slots
  - exclude rules
  - rename rules
  - omit nil
  - omit empty
  - field order
  - symbol and class formatting where supported
  - cycle detection errors
  - unsupported-value errors
- Add regression tests for objects that currently rely on the `toString()` fallback, so behavior changes are intentional and reviewed

Recommended split:

- leave parser/literal tests in `tests/test_json_literal.nim`
- add runtime object serialization coverage in a new `tests/test_json_serialization.nim`

Checklist:

1. Add fast-path tests before enabling advanced formatters
2. Add cycle and failure tests early so error semantics are pinned down
3. Keep expected JSON strings compact and deterministic

### Existing app code using handwritten `toJson`

There are already handwritten serializers in files such as:

- `badminton-buddy/Models/User.hrd`
- `badminton-buddy/Models/Booking.hrd`
- `badminton-buddy/Models/PartnerRequest.hrd`

These are useful migration targets after the primitive path works.

Checklist:

1. Do not change app code until primitive object serialization is stable
2. Then convert one or two models to declarative JSON config as proof of fit
3. Use those migrations to decide whether `jsonRepresentation` is needed immediately or can wait

## Suggested Delivery Order

To reduce risk, implement in this order:

1. `vm.nim`: direct writer for existing primitive, arrays, and tables
2. `types.nim`: add `JsonSpec` and `JsonPlan` metadata to `Class`
3. `objects.nim`: add class-side JSON config APIs and invalidation
4. `vm.nim`: compile plans and serialize ordinary objects through them
5. `tests/test_json_serialization.nim`: add coverage for default and configured object output
6. `Json.hrd` and optionally `Bootstrap.hrd`: expose `Object>>toJson` and finalize loading story
7. slow fallback protocol only after the fast path is stable

## Important Implementation Notes for Harding

- Keep the fast path entirely in Nim; do not add per-slot message sends in `primitiveJsonStringifyImpl`
- Be careful with class replacement paths such as `classSlotsImpl`; a replacement class must not accidentally lose or corrupt JSON metadata
- The current interpreter architecture is stackless, so do not make `jsonRepresentation` the first milestone if it requires awkward native-to-Harding re-entry
- Prefer introducing the representation hook after the direct writer and class-plan path are already solid
- Reuse existing lookup and class-version patterns where possible instead of inventing a second invalidation model

## Non-Goals for V2

These are useful, but should not block the initial fast-path design:

- pretty printing
- arbitrary transformer blocks in the hot path
- custom serializer blocks in the hot path
- schema generation
- parser syntax changes for slot annotations

## Summary of Key Changes from the Earlier Plan

- store JSON metadata on the class or by class identity, not by class name
- replace global name-keyed config lookup with compiled plans
- replace `jsonMap:` with `jsonRename:`
- remove arbitrary block transformers from the fast path design
- remove custom serializer blocks from the fast path design
- use a direct string writer instead of `JsonNode` construction
- make ordinary object serialization work by default through `Json stringify:`
- keep one explicit fallback protocol for cases that need full dynamic control
