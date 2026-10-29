# Granite design: typed native members

Status: **proposal, no code written**. Needs sign-off before implementation because
it changes generated types and touches one language-semantics question.

End goal (agreed): Granite emits compiled Nim objects with typed Nim members, so
slot access and arithmetic on slots become native operations instead of
`NodeValue` unions and runtime lookups.

## Measured starting point

Compiled types already have real Nim fields, and slot access is already
class-indexed (slice 4). What is *not* typed is the field itself:

```nim
Class_517565656E506C6163656D656E74Obj* {.inheritable.} = object of HardingObject
  classRef*: Class
  row*: NodeValue          # <-- the gap
  column*: NodeValue
  previous*: NodeValue
```

Flat-profile shares at `7be5807`, thirty checked passes (`build/granite-profiles/run-b6uhwygi`):

| Function | Richards | DeltaBlue | Queens |
|---|---:|---:|---:|
| `hash` (string/tuple hashing) | 10.6% | 11.5% | 8.4% |
| `getSlotValue` | 4.1% | 2.2% | 3.0% |
| `setSlotValue` | 1.6% | 0.7% | ~0% |
| `hostedBuiltin` (bound-host check per op) | 0.8% | 2.2% | 1.7% |
| `rawAlloc` | 1.6% | 2.2% | 3.3% |
| `nt_plus` | ~0% | ~0% | ~0% |

Two honest conclusions that shape the plan:

1. **Deleting slot lookup entirely is worth roughly 5–8%, not 2x.** Slot access
   is not where the remaining time is. Its value is that it *unblocks* native
   arithmetic, unboxed fields, and cheaper allocation.
2. **`nt_plus` is already ~0%.** The existing `numericBindings` pass already
   compiles proven local arithmetic to machine integers. The win is extending
   that representation to slots, not inventing it.

## The semantic crux: `nil`

This is the decision that needs your agreement, and everything else follows
from it.

Today every slot defaults to `nil` and can be assigned `nil` at any time:

```harding
Point := Object derivePublic: #(x y).
p := Point new.
p x            "--> nil"
p x: nil       "legal"
```

A field declared `x: int` cannot represent nil. So typing a slot **is a
language-semantics change** unless it is opt-in. Two coherent choices:

**Option A — declaration asserts non-nil (recommended).**
`#(x: Int)` means "this slot always holds an Integer". Default becomes `0`, and
assigning `nil` is an error. Unhinted slots stay `NodeValue` and keep today's
nil behaviour. This matches how the existing `parseTypeHint` scaffolding is
shaped, and gives the programmer a way to *opt in* to performance.

**Option B — nil-capable typed slots.**
A hinted slot holds `Option[int]` or a sentinel. Preserves nil semantics but
pays a branch per access and complicates every arithmetic path. Meaningfully
slower and much more complex.

My recommendation is **Option A**, with unhinted slots unchanged. It keeps
Harding's dynamic semantics as the default and makes typing an explicit
performance contract. It is also the only option that reaches "very close to
typed Nim code".

If you prefer B, the plan still works but phases 2–3 get materially heavier.

## Existing machinery to reuse (don't rebuild)

| Piece | State |
|---|---|
| `TypeConstraint` enum + `toNimType`/`unifies`/`constraintForNode` | implemented, in use |
| `SlotDef.constraint` | field exists, populated from `parseTypeList` |
| `ClassInfo.slotIndex` (name → index) | implemented, in use |
| `parseTypeList` / `parseTypeHint` | implemented, wired into class building |
| `numericBindings` (`nrInt`/`nrFloat`/`nrBool`) | implemented, working for locals |
| `compiler/inference.nim` (173 lines) | **dead code**, never imported |

Two gaps stop it working today:

1. **The parser cannot read a type hint.** `Object derivePublic: #(x: Int)` is a
   parse error in both engines. `parseTypeHint` therefore always sees bare names.
2. **Codegen ignores `slot.constraint`.** `genClassConstants` always emits
   `NodeValue` fields regardless of what analysis concluded.

So "type-hinted slots" was scaffolded and never finished. That is good news: the
analysis vocabulary exists and is already consistent with the runtime.

## Phased plan

Each phase is independently shippable, measured, and revertable. No phase
changes interpreter behaviour.

### Phase 1 — parse and validate hints (no codegen change)

- Accept `#(x: Int, y: Float)` using the existing `parseTypeHint`.
- Populate `slot.constraint`, replacing or retiring dead `inference.nim`.
- Validate consistency: a subclass redeclaring an inherited slot must agree on
  its constraint (`unifies`); a hinted slot must not be reachable by a write of
  a different type.

Deliverable: hints parse, are recorded, are validated, generated code is
byte-identical. Zero performance risk, and it flushes out grammar questions
before they can corrupt generated types.

### Phase 2 — typed fields for hinted slots in sealed classes

- Emit `x: int` / `y: float64` / `s: string` / `b: bool` for hinted slots.
- Box only at the boundaries: the interpreter bridge (`slotGet_*`/`slotSet_*`
  wrap into `NodeValue`), `toValue()`, JSON serialization, `compiledNamedAccess`.
- Default-initialise typed slots per Option A.
- Guard: typed fields only for classes with no runtime redefinition. If a class
  is redefined, layout validation must reject the mismatch — extending the
  existing `compiledClassDispatchVersion` / `validateNativeSlots` machinery.
- **Flat-type constraint:** subclass types carry their own copy of inherited
  slots, so every generated type in the chain must agree on a slot's type. This
  must be a compile error, not a silent layout divergence.

Deliverable: hinted slots are native fields; parity holds; measured.

### Phase 3 — inference for unhinted slots

- Extend the `numericBindings` approach from locals to slots: a slot is typed
  only if **every** write in the compiled module proves the same kind, and no
  write can be nil.
- Conservative default stays `NodeValue`. Any doubt, any interpreter-side write,
  any dynamic caller → dynamic. This mirrors the existing local analysis, which
  already rejects rather than guesses.
- Report which slots were promoted, so the evidence is auditable.

Deliverable: benchmarks get typed hot slots without source annotations.

### Phase 4 — direct field access at call sites

- Where the receiver's class is statically known, emit `self[].row` directly
  rather than `getSlotValue(self, "row")`.
- Where the class is not statically known (polymorphic send), keep the
  class-indexed accessor from slice 4.
- This finally removes the remaining per-access hash and indirect call.

Deliverable: the measured slot-access and hashing share mostly disappears.

## Risks

- **Stale typed layout.** A class redefined or subclassed at runtime after a
  typed binary is built could mismatch field types. Mitigation: seal check plus
  the existing layout validation; refuse rather than reinterpret memory.
- **Wrong-slot addressing.** Already hit once with parent-first `allSlotNames`.
  Phase 1's subclass-consistency check is the guard, and the regression test
  comes before codegen in every phase.
- **Silent nil semantics change.** The Option A/B decision above; must be
  documented in the manual, not just the changelog.
- **Interpreter divergence.** The interpreter keeps `NodeValue` slots. Typed
  fields are a Granite-only representation, so any parity test must confirm the
  *observable* results match, including a hinted slot read as `0` vs `nil`.

## Validation per phase

Both-engine parity (102 cases), ARC and ORC runtime/boundary suites, Richards
and DeltaBlue conformance, GTK acceptance, and paired before/after release
timings with retained binaries — the harness in `scripts/profile_granite.py`
already does the last part. Interpreter output must be unchanged throughout.

## What this is worth

Phases 1–4 remove the slot-access and much of the hashing share (order 10%), and
make slot arithmetic native. That is real, but it does **not** close the gap to
Cog on its own — the remaining distance is dominated by allocation and by
`NodeValue` boxing of every value that crosses a method boundary. Full
"very close to typed Nim" needs Phase 4 plus a dispatch/representation story
that this document does not attempt.

I would rather say that now than promise Cog parity from typed slots.
