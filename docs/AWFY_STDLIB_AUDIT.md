# AWFY SOM stdlib audit

## Scope and evidence

Source audit only; no compiler, runtime, library or test changes, and no builds or
benchmark execution. Port-agent blockers must still be reproduced before deciding
implementation. Repository audited: `/home/gokr/git/harding-granite-completeness`.
Other agents own `benchmark/awfy/{bounce,havlak,json}`; those files were not edited.

Upstream: <https://github.com/smarr/are-we-fast-yet>, revision
`74306fec151070fd07157cefeacf19e7e0bcdc89`. Read `benchmarks/SOM/Core/*.som`,
`Json/JsonParser.som`, `JsonObject.som`, `HashIndexTable.som`, Havlak loop-finder,
union-find and loop classes, and `Bounce.som`/`Ball.som`. Disposable checkout:
`build/awfy-stdlib-audit/upstream`. Harding evidence: actual `lib/core/` Array,
Iterable, Table, Set, Bag, String, Integer, Number and Bootstrap; standard Interval;
VM primitives, NodeValue equality/hash and native runtime dispatch. Existing
`COLLECTION_PROTOCOL_AUDIT.md` and `GRANITE_STATUS.md` provide context, not proof
that every selector works in a standalone compiled port.

## Already supported: do not add SOM spelling aliases by default

| SOM use | Harding definition and important semantics |
|---|---|
| Array `length`, `do:` | `Array>>size`, `do:`; indices are **zero-based**. `do:` sends `value:` in ascending order and answers self. Its loop tests current size each iteration. |
| Indexed enumeration | `Array>>withIndexDo:` sends `(element, index)`, index starting at 0; snapshots size. `Integer>>to:do:` is inclusive. `to:by:do:` supports negative steps: use `n to: 0 by: (0 - 1) do:` instead of adding `downTo:do:`. Zero step is unsafe and is not needed by these ports. |
| Vector `forEach:`, `hasSome:`, `getOne:` | Array `do:`, `anySatisfy:`, `detect:` respectively. `detect:` returns the **element**, or nil; `findFirst:` returns its **index**, or nil. `reverseDo:` and `findLast:` exist. |
| Mapping/filtering/folding | Iterable `collect:`, `select:`, `reject:`, `inject:into:`, `anySatisfy:`, `allSatisfy:`, `noneSatisfy:`, `count:`, `sum`. Bootstrap attaches Iterable to Array/Table/Set. Array transformations preserve Array species. Detection and predicates short-circuit. |
| Append, drain, clear | Array `add:`, `addAll:`, `removeFirst`, `removeLast`, `removeAt:`, `removeAll`; `addAll:` answers its argument (nil is a no-op), `removeAll` clears shared storage in place and answers self. These are not Vector capacity/head-offset semantics. |
| Dictionary lookup | Table `at:`, `at:put:`, `includesKey:`, `keys`, `values`, `at:ifAbsent:`, `at:ifAbsentPut:`, present callbacks and `removeKey:` variants. Missing `at:` answers nil; distinguish stored nil using `includesKey:`. |
| Dictionary enumeration | Table `do:` and `keysAndValuesDo:` supply **key, value**, not value alone. Table `collect:` answers Array; `select:`/`reject:` answer Table. `inject:into:` callback gets accumulator, key, value. Do not apply unary Iterable callback assumptions to Table. |
| Ordinary membership | Set has add/remove/includes, size, algebra, `asArray`, and snapshot-backed `do:`. Bag deliberately retains duplicates; it is not an identity set. |
| Numeric helpers | Number `min:`, `max:`; Integer `abs`, `negated`, `//`, `\\` (modulo). SOM `%` can use existing Harding modulo syntax. |
| Json character/subsequence access | String `size`, `at:`, `from:to:`, `&`, equality and `asString` exist. Adapt SOM `charAt:`, `substringFrom:to:`, `concatenate:` locally. No Character class is required: `at:` produces a one-byte String. |

String primitive details matter more than misleading comments in `String.hrd`:
VM `primitiveStringAtValueImpl` is zero-based, byte-oriented, and answers `""`
for invalid indices. `primitiveStringFromToValueImpl` uses inclusive zero-based
bounds, answering `""` for reversed/out-of-range bounds. `indexOf:` is zero-based
and returns **-1**, not the file comment's 0, when absent; its VM value path also
returns -1 for an empty needle. Size counts bytes, not Unicode code points.
`asInteger`/`asFloat`/`asNumber` already exist, but upstream JsonNumber preserves
the numeric token as text, so converting it is not a port requirement.

## Genuine gaps and decisions

### 1. Per-element Array construction: missing convenience, not new block semantics

Upstream Bounce uses `Array new: n withAll: [ Ball new: random ]` expecting a
fresh evaluation per element. Harding's existing `new:withAll:` **stores the same
argument in every slot**, including a Block. Both VM `arrayClassNewWithAllImpl`
and native runtime `new:withAll:` implement fill-value semantics. Do not change
that selector to execute blocks: storing repeated blocks/objects is valid.

A reusable, library-only candidate is `Array class>>new: size tabulate: block`:
allocate size slots, evaluate `block value: index` exactly once per index in
ascending 0-based order, store each result, answer the Array. An explicitly named
zero-argument generator is another choice; agree one contract first. Bounce can
also allocate and fill using existing iteration, with no stdlib addition.

Tests: zero length makes zero calls; indices/order are exact; generated objects
are distinct; captured random/counter state advances once per slot; ordinary
`new:withAll:` still shares the identical object/block and never evaluates it.

### 2. Identity collections: missing explicit protocol, partially overlapping storage

There is no public IdentitySet/IdentityDictionary class or `identityHash` protocol.
However, current Table/Set keys use Nim NodeValue equality/hash, **not Harding
user-defined `=` or a user hash send** (`core/types.nim`, `objects.nim`). Ordinary
object instances compare/hash by reference there. Thus Havlak BasicBlock keys
already have identity behavior in Table; do not declare that workflow blocked
solely because a class named IdentityDictionary is absent.

This does not establish a general identity-collection contract for every value
representation. VM `==` uses reference identity for ordinary instances, value
comparison for strings/numbers, and its raw Array/Table cases are structural.
Native wrappers also require canonical retained-owner identity. Adding classes
must not silently redefine these language semantics.

If demanded outside benchmark support, define IdentitySet membership/deduplication
and IdentityDictionary lookup/replacement using the agreed `==` relation, not
`=`; absent lookup nil, `includesKey:` distinguishes stored nil, duplicate insertion
must not increase size, and clear must preserve aliases. Linear Array-backed
implementations can be library-only for ordinary-object identity; scalable hash
implementations need a compatible hash primitive and VM/Granite parity. Ordering
and collect-result species need explicit decisions: upstream SomSet `collect:`
returns Vector (preserves mapped duplicates), unlike Harding Set species behavior.

Tests: same instance twice versus distinct instances with identical slots;
instances overriding `=` to always true; stored nil; replacement; clear/aliases;
compiled objects across interpreted/native boundaries; strings and raw/wrapped
collections only after agreeing their identity contract. Do not substitute Set
for SomIdentitySet without these checks.

### 3. Strings: native parity risk, not missing interpreter substring API

JsonParser needs byte access, inclusive slices (including empty captured spans),
concatenation and string comparisons; these exist in the interpreter. Pure native
runtime dispatch has String `indexOf:` but no `from:to:` branch in
`runtime/runtime.nim`; generic stdlib compilation is not automatic. A concrete
native substring failure would therefore be a **Granite/runtime parity gap**, not
a reason to add an overlapping lib selector. Check generated calls before fixing.

String `withCapacity:` and mutating `<<` are exposed, but are unnecessary for a
faithful parser using `captureBuffer := captureBuffer & fragment`; do not rely on
unverified native mutable-buffer aliasing. General Unicode/Character/Stream APIs
are not prerequisites: upstream itself explicitly omits Unicode escape creation
and control-character ordinal validation.

Tests: first/last byte, invalid index, inclusive full/sub/empty spans, ASCII
escape concatenation, EOF distinct from an empty token, string comparison,
substring search absent/empty cases, and parse captures split by multiple escapes.
Run the same cases against both engines before claiming parity.

## Keep upstream algorithm/support classes in the ports

`Vector`, `SomSet`, `SomIdentitySet`, `SomDictionary`, `SomIdentityDictionary`,
`DictEntry`, `DictIdEntry` and Pair are AWFY Core **benchmark support algorithms**,
not a request to install similarly named stdlib classes. Preserve them locally
when their allocation/access costs are part of the workload. In particular:

- Vector has separate capacity/logical size/head, out-of-capacity reads returning
  nil, expanding indexed writes, O(1) head dequeue, and `remove:` deleting **all
  identity matches**, answering a boolean. Array removal-by-value is absent, but
  adding conventional single-occurrence `remove:` would not reproduce this.
- SomDictionary deliberately uses `customHash`, xor/unsigned-shift spreading,
  chained entries and split-bucket resizing. BasicBlock's custom hash is its name.
  These are benchmark work, not Table's required public implementation.
- Json HashIndexTable's length-based hash and byte-sized cached indices,
  JsonValue subclasses, parser capture state and ParseException stay local.
  Do not replace the measured parser with standard `Json parse:` or broaden it
  into a general JSON library repair. Upstream JsonObject even has an explicit
  unimplemented collision fallback: fidelity and extensions must be documented.
- Havlak graph/loop/union-find classes, Ball and SomRandom are domain/support
  code. Integer bitwise APIs used by their support algorithms are not defined in
  current Integer.hrd; Harding `&` means concatenation, **not bitwise and**.
  Local arithmetic equivalents are possible; any generic bit API needs agreed
  signedness/width/shift semantics and both-engine implementation/tests.

## Coordination and validation boundary

No API should be added merely to match SOM spelling. Prioritize port agents'
minimal failures: exact source, expected value, interpreter result, generated/native
result. Captured callbacks are already supported machinery (MutableCell captures,
Block `value:` arities and existing collection parity cases), not a missing
stdlib feature. Nested iteration updating an outer bounce count, callbacks
capturing random state, write-only captures, folds, early non-local returns and
callback exceptions still deserve focused regressions; a failure there belongs
to VM/codegen/runtime, not a rewritten collection loop that hides the defect.

After coordination, run focused stdlib tests and executed Granite conformance
for each agreed change; compile actual library bodies when testing library-only
additions. Include literal and separately bound callback blocks, empty inputs,
short-circuit call counts, mutable aliases and ARC/ORC where captures/ownership
are involved. Use `docs/GRANITE_STATUS.md`'s parity workflow, not a successful
code-generation-only assertion or masked nimble test exit. This audit reports
source findings and proposed tests, not new executed conformance evidence.
