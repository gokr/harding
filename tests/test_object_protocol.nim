import std/unittest
import ../src/harding/core/types
import ../src/harding/interpreter/vm
import ./stdlib_test_support

var interp = newSharedStdlibInterpreter()
proc evaluate(source: string): NodeValue =
  let (value, error) = interp.doit(source)
  doAssert error.len == 0, error
  value

suite "Object hashing and copying":
  test "Table and Set use object hash and equality overrides":
    check evaluate("""
      ValueKey := Object derivePublic: #(value).
      ValueKey>>hash [ ^value ].
      ValueKey>>= other [ (other isKindOf: ValueKey) ifFalse: [^false]. ^value = other value ].
      a := ValueKey new. a value: 4.
      b := ValueKey new. b value: 4.
      table := Table new. table at: a put: "one".
      table at: b put: "two".
      set := Set new. set add: a. set add: b.
      (table size = 1) and: [(table at: a) = "two" and: [set size = 1]]
    """).boolVal

  test "native resources are refused with a catchable error":
    check evaluate("""
      [Process current deepCopy. false] on: Error do: [:e | true]
    """).boolVal

  test "deep copied Tables preserve shared values":
    check evaluate("""
      child := Array new. child add: 1.
      source := Table new. source at: "a" put: child. source at: "b" put: child.
      target := source deepCopy.
      ((target at: "a") == (target at: "b")) and: [((target at: "a") == child) not]
    """).boolVal

  test "identity hash is stable; value hashes agree for equal strings":
    check evaluate("""
      x := Object new.
      (x identityHash = x identityHash) and: ["same" hash = ("sa" & "me") hash]
    """).boolVal

  test "shallow copy shares children but not outer storage":
    check evaluate("""
      child := Array new. child add: 1.
      parent := Array new. parent add: child.
      copied := parent shallowCopy.
      ((copied == parent) not) and: [(copied first == child) and: [copied size = 1]]
    """).boolVal

  test "deep copy preserves aliases and cycles":
    check evaluate("""
      child := Array new. child add: 1.
      parent := Array new.
      parent add: child. parent add: child. parent add: parent.
      copied := parent deepCopy.
      ((copied == parent) not) and: [
        ((copied first == child) not) and: [
          (copied first == (copied at: 1)) and: [(copied at: 2) == copied]
        ]
      ]
    """).boolVal

  test "copy invokes postCopy once and shallowCopy does not":
    check evaluate("""
      CopyProbe := Object derivePublic: #(value).
      CopyProbe>>postCopy [ value := value + 1. ^self ].
      x := CopyProbe new. x value: 7.
      y := x copy.
      z := x shallowCopy.
      (x value = 7) and: [(y value = 8) and: [z value = 7]]
    """).boolVal

  test "object graph copy keeps class and separates slot references":
    check evaluate("""
      GraphProbe := Object derivePublic: #(left, right).
      x := GraphProbe new.
      child := Array new. child add: 4.
      x left: child. x right: x.
      y := x deepCopy.
      (y class == GraphProbe) and: [(y right == y) and: [(y left == child) not]]
    """).boolVal
