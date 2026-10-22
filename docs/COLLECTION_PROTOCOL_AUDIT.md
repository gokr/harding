# Collection protocol audit

## Scope and status

This is an initial source inventory, not a conformance claim. The comparison
baseline is the Smalltalk-80 collection hierarchy and its instance-side protocol;
modern additions such as `anySatisfy:` are useful but are not evidence of original
Smalltalk-80 conformance. Method presence, interpreter behavior, native compiled
behavior, result species, failures and callback/return behavior need separate
checks. A complete reference-selector matrix and executed tests remain pending.

Harding intentionally uses zero-based indexing. Its growable Array also serves
some roles of Smalltalk's OrderedCollection, and Table is dictionary-like.
Those differences must be documented rather than silently changed for parity.

## Current source inventory

- `lib/core/Iterable.hrd`: species/copyEmpty, collect:, select:, reject:, detect:,
  detect:ifNone:, inject:into:, anySatisfy:, allSatisfy:, noneSatisfy:, sum, count:.
- `lib/core/Array.hrd`: indexed access/mutation, append/removal, iteration,
  first/last/indexOf:, slices, copying, testing and conversion helpers.
- `lib/core/Table.hrd`: keyed storage, key/value iteration, dictionary-specific
  collect/select/reject and query implementations.
- `lib/core/Set.hrd`: membership, insertion/removal, union/intersection/difference,
  conversion and iteration; adopts Iterable through bootstrap.
- `lib/standard/Interval.hrd`: interval iteration and query methods.
- `lib/standard/SortedCollection.hrd`: sorted insertion, custom comparator,
  sequence queries and transformations, composed over an Array.

Dedicated Bag, OrderedCollection, LinkedList, Association, Dictionary and
IdentityDictionary classes are not established by this inventory. Table and
Array may supply overlapping behavior; coverage must be assessed by operation,
not by simply matching class names.

## Native parity evidence

`array_query_protocol` checks Array reject:, detect:/ifNone:, inject:into:,
any/all/none predicates, short-circuit callback counts, empty inputs, emptiness
checks, and collect: with a separately bound callback. These pass in both engines.
This is an Array slice, not proof that Table/Set or derived collections work.

Mutation aliasing, structural versus identity equality, species preservation,
builtin reflection, invalid indices/keys, iteration during mutation, inherited
methods, callback errors/cleanup and non-local returns need dedicated coverage.
Native literal-block collect:/select:/do: lowering also needs comparison with
ordinary dynamic sends, including receiver return values and overrides.

## Confirmed native mutation discrepancy

```smalltalk
a := Array new.
b := a.
a add: 7.
b size println.
t := Table new.
u := t.
t at: "x" put: 9.
(u at: "x") println.
```

Interpreter: `1`, `9`. Native: `0`, `nil`. Runtime mutations copy value storage,
and codegen writes the result back only to the named receiver. Shared collection
storage must cover constructors, literals, JSON parsing, helpers and inline loops;
fixing one mutation selector alone cannot preserve aliases. This is an existing
reference-semantics defect, not a proposed language change.

## Smalltalk-80 comparison checklist

- Collection: adding/removing, bulk operations, occurrence counting, membership,
  enumeration, collect/select/reject/detect/inject, conversions and species.
- SequenceableCollection: first/last, indexed access, forward/reverse traversal,
  searching, slices, replacement, concatenation and equality/hash contracts.
- OrderedCollection: insertion/removal at either end and relative to an element.
- Set/Bag: uniqueness versus multiplicity, algebra, occurrence counts and hashing.
- Dictionary/Association: key/value association protocol, absent-key behavior,
  associationsDo:, keysAndValuesDo:, key lookup/removal and identity-key variants.
- SortedCollection: ordering policy, insertion invariants and transformation species.
- Interval: bounds, step, empty/descending ranges and immutability policy.
- Streams and characters/string sequencing: audit separately and explicitly mark
  their relationship to the collection protocol.

Missing APIs and discrepancies affecting language behavior require a proposed
contract before implementation. In particular, detect: currently answers nil
when absent, whereas traditional Smalltalk signals failure without ifNone:.
