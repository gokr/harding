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
- `lib/core/Bag.hrd`: unordered multiset; duplicates counted, `occurrencesOf:`
  multiplicity, `remove:` drops one occurrence, species-preserving queries,
  `removeAll` clearing. Adopts the Iterable protocol by defining its methods
  explicitly rather than inheriting the mixin.
- `lib/standard/Interval.hrd`: interval iteration and query methods.
- `lib/standard/SortedCollection.hrd`: sorted insertion, custom comparator,
  sequence queries and transformations, composed over an Array.

Bag is defined for both engines. OrderedCollection is deliberately not added:
Array already serves that ordered/growable role, and a second class would
duplicate protocol without agreement. LinkedList, Association, Dictionary,
IdentityDictionary and IdentitySet are still absent. Table and
Array may supply overlapping behavior; coverage must be assessed by operation,
not by simply matching class names.

## Native parity evidence

`array_query_protocol` checks Array reject:, detect:/ifNone:, inject:into:,
any/all/none predicates, short-circuit callback counts, empty inputs, emptiness
checks, and collect: with a separately bound callback. These pass in both engines.
Additional table_query_protocol and set_query_protocol cases cover their callback
arity, result counts, predicates and folds. collection_aliasing covers aliases,
cloning, literal/JSON mutation, equality and builtin class reflection. Derived
collections and the full selector surface are not established by these cases.

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

Original native result: `0`, `nil`, versus interpreter `1`, `9`. Shared Instance
storage now preserves aliases for constructors, literals, JSON parsing and helper
results; collection_aliasing passes. This repairs existing reference semantics.

## Gap matrix (source-level audit)

| Protocol family | Harding coverage | Missing or different |
|---|---|---|
| Enumeration | do:, collect:, select:, reject:, detect:/ifNone:, inject:into: | Generic superclass protocol is Iterable, not Collection |
| Membership/counting | includes:, size, isEmpty, occurrencesOf:, includesAll: | remove:ifAbsent: absent; Array has no removal-by-value |
| Bulk adding | addAll: on Iterable/Array, native for Array/Table/Set | addAll: species edge cases beyond Array/Table/Set unverified |
| Conversion | Set asArray, Array asSortedCollection:/asSortedCollection | asBag/asOrderedCollection and general asSet conversion absent |
| Sequence access | at:/put:, first, last, indexOf:, copyFrom:to:, findFirst:, findLast:, reverseDo: | replaceFrom:to:with:startingAt: absent |
| Ordered mutation | Growable Array add:, removeFirst/removeLast/removeAt: | addFirst:, add:before:/after: and dedicated OrderedCollection absent |
| Sets | Set membership, remove:, union:/intersection:/difference:, asArray, Iterable protocol natively | IdentitySet absent; hash/equality compatibility needs explicit tests |
| Bags | No dedicated class | Multiplicity and occurrence protocol absent |
| Dictionaries | Table keyed access, absent callbacks, values, associations, keysAndValuesDo: | Association objects and IdentityDictionary absent; callbacks use key/value rather than Smalltalk Dictionary value-only enumeration |
| Sorted collections | Comparator, insertion, transformations, copy | Complete species and comparator-preservation conformance unverified |
| Intervals | Bounds/step, traversal, reversed and queries | Complete sequence protocol and immutable-operation failures unverified |
| Equality | Current Array/Table equality is identity | Smalltalk sequence value equality/hash is not adopted silently |
| Search failure | detect: answers nil; indexOf: answers nil | Smalltalk's default error and not-found index conventions differ |
| Strings/streams | Existing String and FileStream protocols | Full Character/Stream hierarchy compatibility is outside this collection slice |

Coverage added in this slice: Iterable addAll:/includesAll:/occurrencesOf:/isEmpty/
notEmpty (with Array addAll: answering its argument), Array findFirst:/findLast:/
reverseDo:, native Array removeAt:/removeFirst/removeLast, Table values/associations/
at:/removeKey:, and native Set remove:/union:/intersection:/difference:/asArray plus
the element-callback Iterable protocol. Native bulk_sequence_protocol and
set_algebra_protocol regressions pass in both engines. SortedCollection remains an
interpreter-only stdlib class: pure compiled programs do not load `.hrd` stdlib
sources, so `SortedCollection new` is unavailable natively. That is a compilation
scope limitation, not a missing selector.

Conclusion: Harding covers the commonly used higher-order operations but **does
not implement the whole Smalltalk-80 collection protocol**. Closing the matrix
requires agreed class/hierarchy, equality/hash, indexing and failure contracts,
then selector-by-selector runtime and Granite regressions. Adding missing methods
without those contracts would give superficial rather than behavioral coverage.

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
