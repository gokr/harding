# Declared slot contract

This document records the approved semantics implemented in interpreter and
Granite. It supersedes earlier exploratory nil/default proposals in
`GRANITE_TYPED_MEMBERS_DESIGN.md` and `GRANITE_SLOT_TYPE_INFERENCE.md`.

```harding
Banana := Object derivePublic: #().
Record := Object derivePublic: #{#quantity -> Integer, #weight -> 5.25,
    #enabled -> Boolean, #label -> "hello world", #status -> #"",
    #fruit -> Banana, #extra -> nil}.
```

Table keys are Symbols or Strings. Bare keys retain normal expression evaluation;
there is no parser change or implicit quoting. The table form is accepted by
`derive:`, `derivePublic:`, selective read/write forms and compatibility wrappers.
Array-based declarations remain dynamic and initially nil.

## Defaults and writes

| Declaration value | Stored kind | Initial value | Accepted writes |
|---|---|---|---|
| Integer class | Integer | `0` | Integer |
| Float class | Float | `0.0` | Float or Integer converted to Float |
| Boolean class | Boolean | `false` | Boolean |
| String class | String | `""` | String |
| Symbol class | Symbol | `#""` | Symbol |
| Primitive literal | That literal's kind | The literal itself | Same rules as its class |
| Other class | Object constraint | nil | nil or declared-class/subclass instance |
| nil | Dynamic | nil | Any value |

Primitive slots reject nil, including both runtime representations of nil.
There is no implicit Float-to-Integer conversion or String-to-Symbol conversion.
Symbol payloads may use Nim string storage but remain Symbols at language
boundaries. An empty Symbol literal is `#""`, equivalent to `"" asSymbol`.

Defaults are installed during allocation, including `basicNew`. `new` still
invokes ordinary `initialize`; an initializer can replace a default with another
valid value. No mandatory initialization chain or implicit super call is added.
Defaults and constraints resolve in declared parent order through the superclass
graph, including secondary parents, with cycle protection.

A rejected write signals a catchable Harding `Error` before changing storage.
The old value is preserved and the right-hand expression is evaluated once.
Ordinary assignment, generated setters, `::` and reflective `at:put:` share the
storage validation. Existing assignment/setter result conventions are retained;
Float conversion concerns the stored value, not a new return-value convention.

## Engine implementation

`SlotContract` in core types carries the primitive kind or an object Class
reference. A common normalizer checks a proposed value without mutating storage.
VM-owned/bridged writes validate in `writeInstanceSlot`; `SlotTypeError` is
translated to a Harding `Error` at the VM work-frame boundary, using the existing
stackless handler mechanism. No native try/finally is introduced in primitives.

Granite decodes table declarations structurally, rather than splitting default
strings on whitespace. Reflection preserves inherited contracts and defaults,
including secondary-parent fields. Native Integer/Float/Boolean/String/Symbol
fields use checked boxing/unboxing accessors. Object-constrained fields remain
NodeValue fields with validation; this is not typed Nim reference inheritance.
Native object ancestry uses Granite's registered language hierarchy, not Nim
layout inheritance. Interpreted conformance follows live Class identity.

The native bridge checks declared kinds before adoption and snapshots contracts
alongside slot names. Later layout or contract drift is rejected instead of
reinterpreting typed storage. Rebuilding/loading different declarations requires
a compatible bridge; this change does not introduce live field migration.

Arrays, Tables, Blocks and other non-scalar classes used as declaration values
are object constraints, not new unboxed container representations. Mutable
collection literals are not slot-default factories. Specialized arrays remain
future work in `PRIMITIVE_TYPES_ROADMAP.md`.

## Validation

```sh
nimble testSlotContracts
```

This builds Granite and executes core storage regressions plus generated host
and language tests under ARC/ORC. The language fixture compares both engines
against explicit expected output, not just against one another. It covers
primitive/class/literal defaults, `basicNew` versus `new`, nil/wrong-kind
rejection, preservation, conversion, private/public/selective/compatibility forms,
Symbols, escaped String defaults, subclass/secondary-parent conformance,
inherited defaults and exactly-once effects. Core tests cover lookup cycles and
both nil encodings; the native host tests exercise bridge contract drift.

Validation for this change set (`build/contract-*` logs):

- Final ARC/ORC runs: storage 5, compiled runtime 42, boundary 34, reentrant
  returns 16, block lifetime 15, support 10, base allocation 2, slot inference 14,
  compiler basic 84 and compiler blocks 29 tests per memory manager.
- Explicit-results contract fixture and direct-slot embedded-host tests pass
  under ARC/ORC; legacy declared-default parity passes seven cases.
- Richards/DeltaBlue conformance tasks pass; wider parity passes 102/102 in
  recorded batches, not one uninterrupted invocation.
- GTK application acceptance and generated-boundary suites pass. The core group
  reports 18 PASS results with no failure markers (its task can mask failures).
- Isolated-cache freeze conformance passes 12 cases and frozen-build tests pass
  seven tests.

These named gates are not a blanket claim that the full repository suite ran.

## Next work

With declared-slot behavior defined consistently, inference can target an explicit
contract. Static inference should first improve obvious parameter/assignment and
self/super return propagation. Interpreter-collected, source-fingerprinted type
feedback then complements static evidence. Neither a selector-set candidate nor a
partial test profile proves that an unannotated dynamic slot can safely become
non-nullable; speculative specialization must retain safe fallback. Inference
must not silently rewrite source into a stricter declaration merely because one
training run observed a single kind.
