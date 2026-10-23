# Native collections and object JSON

## Representation contract

Mutable Array and Table values produced by pure Granite constructors, literals,
JSON parsing, arguments and collection helpers retain an `Instance` with
`ikArray`/`ikTable` storage. Assignment, method arguments, slots and captures copy
the reference, not the container. `clone` creates independent shallow container
storage; its elements remain shared. This preserves the interpreter contract
without changing Nim's seq/Table semantics or the global NodeValue layout.
Raw vkArray/vkTable values remain supported as transient read-only views and
compatibility inputs, not as mutable collection owners. Internal Nim consumers
should use compiledArrayElements rather than assuming an exposed arrayVal field.

`at:put:` answers the assigned value. Array writes do not append at size;
`add:` appends. Table includes: searches values; includesKey: searches keys.
Array/Table `=` follows the current interpreter's identity behavior, not a newly
introduced structural-equality policy. Builtin collection class reflection is
available. Explicit Array copying is shallow.

## Query protocol

Array native sends cover collect/select/reject, detect:/ifNone:, inject:into:,
any/all/none predicates, emptiness, and indexed iteration. Table callbacks receive
key and value; Table inject receives accumulator, key and value. Table collect
returns Array, select/reject return Table. Two-argument literal callbacks are not
lowered as Array loops. Set query behavior uses one-argument element callbacks
and retains Set species for collect/select/reject.

This is not a claim of complete stdlib compilation: derived SortedCollection and
Interval classes, all removal/bulk operations, arbitrary callback arities, mutation
during iteration, user-defined collection subclasses and mixed mode still need
broader coverage. See COLLECTION_PROTOCOL_AUDIT.md for Smalltalk-80 gaps.

## Slot layout boundary

Generated slot reads and writes dispatch through the receiver's own live class
layout (`getSlotValue`/`setSlotValue`) instead of casting `instVal.nimValue` to the
generated class. A compiled method therefore works on interpreter-owned instances,
including runtime subclasses and slots declared after code generation, and on
native instances. Native classes emit a concrete self-contained layout and accessor
for every slot, inherited fields included; registered accessors are keyed by the
concrete receiver class so an inherited native slot uses the right layout.

`::` is not lowered to `at:`/`at:put:`. Named access checks live readable/writable
permissions (raising `Error` otherwise) and handles tables directly; this preserved
`accessor_override` parity, where a hand-written parent accessor must not be shadowed
by a generated child accessor. Native-layout proxies do not yet have an interpreted
slot bridge: native objects that need interpreted slot access remain unsupported.
Compiled block callbacks can now be invoked from interpreted code (0–3 arguments),
but callbacks that require interpreted access to native slots still need that bridge.

## Object JSON

Generated code registers parent-first slot names separately from accessor
permissions. Native stringify traverses slots through compiled accessors, includes
private slots as the interpreter does, and dispatches inherited jsonRepresentation
hooks. Per-write identity tracking rejects recursive object graphs, including
multiple wrappers retaining one native owner. No global serialization state is
left behind after an error.

Class jsonExclude:, jsonOnly:, jsonRename:, jsonOmitNil:, jsonOmitEmpty:,
jsonFormat:, jsonFieldOrder:, jsonReset and jsonSpec use the shared interpreter
configuration implementations, without interpreting Harding source. Effective
specs merge parents before children; generated slot order is deterministic.
Formats support string, rawJson, symbolName and className. Native serialization
currently rebuilds its effective field selection per write rather than caching
plans; this keeps configuration changes visible and is a performance follow-up.

## Bulk and sequence protocol

Array and Iterable provide addAll: (answering its argument), includesAll:,
occurrencesOf:, isEmpty/notEmpty, findFirst:/findLast: and reverseDo:. Native owner
storage adds removeAt:/removeFirst/removeLast for Array, values/associations/at:/
removeKey: for Table, and remove:/union:/intersection:/difference:/asArray for Set.
Set query results retain Set species. Inline do:/collect:/select: lowering is now
restricted to literal Array receivers, so Table and Set keep ordinary dispatch and
therefore correct callback arity and result species.

Array removal-by-value, generic remove:ifAbsent:, replaceFrom:to:with:startingAt:,
Bag/OrderedCollection/IdentitySet and SortedCollection compilation are not covered.

## Validation

The expanded semantic runner recorded 89 passing cases after the shared-storage
and object-JSON changes (`build/capture-fix/final-full-parity.log`). Later targeted
runs cover Table literal callbacks and assigned-value returns. Runtime tests pass
under ARC and ORC and compiler tests pass. Logs remain under build/capture-fix.
The later bulk/sequence and Set-algebra additions brought the same suite to 92
passing cases, 0 failures (`build/audit-probe/verify-parity.log`). Runtime tests
pass under ARC and ORC; compiler tests pass. Neither result is evidence of
complete Smalltalk-80 conformance, a full external-library test run, or full
mixed-mode coverage.
