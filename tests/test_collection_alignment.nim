import std/unittest
import ../src/harding/core/types
import ../src/harding/interpreter/vm
import ./stdlib_test_support

var interp = newSharedStdlibInterpreter()

proc evaluate(source: string): NodeValue =
  let (value, error) = interp.doit(source)
  doAssert error.len == 0, error
  value

suite "Shared collection protocol":
  test "selector queries return Symbols and preserve compatibility aliases":
    check evaluate("Object selectors includes: #printString").boolVal
    check evaluate("Object classSelectors includes: #new").boolVal
    check evaluate("Object selectors size = Object methods size").boolVal
    check evaluate("(Object selectors at: 0) isKindOf: Symbol").boolVal

  test "Bag inherits traversal while preserving multiplicity and species":
    check evaluate("""
      b := Bag new.
      b addAll: #(1, 1, 2).
      ((b select: [:x | x = 1]) size = 2) and: [
        ((b collect: [:x | x + 1]) species = Bag) and: [
          (b includesAll: #(1, 1)) and: [(b includesAll: #(1, 1, 1)) not]
        ]
      ]
    """).boolVal

  test "Interval inherits traversal with Array results":
    check evaluate("""
      range := 1 to: 4.
      ((range collect: [:x | x * 2]) last = 8) and: [
        (range sum = 10) and: [range includesAll: #(2, 4)]
      ]
    """).boolVal

  test "SortedCollection preserves its comparator for filtered results":
    check evaluate("""
      sorted := SortedCollection sortBlock: [:a :b | a > b].
      sorted add: 1. sorted add: 3. sorted add: 2.
      filtered := sorted select: [:x | x > 1].
      (filtered at: 0) = 3 and: [filtered size = 2]
    """).boolVal

  test "String traversal yields single-character Strings":
    check evaluate("""
      text := "abc".
      ((text collect: [:ch | ch size]) sum = 3) and: [
        (text first = "a") and: [(text last = "c") and: [text includes: "bc"]]
      ]
    """).boolVal

  test "String filtering returns String and collection returns Array":
    check evaluate("""
      (("abc" select: [:ch | ch ~= "b"]) = "ac") and: [
        (("abc" reject: [:ch | ch = "b"]) = "ac") and: [
          (("abc" collect: [:ch | ch size]) isKindOf: Array) and: ["abc" reverse = "cba"]
        ]
      ]
    """).boolVal

  test "empty Strings and block errors preserve ordinary protocol":
    check evaluate("""
      ("" first isNil) and: [
        ("" last isNil) and: [("" asArray isEmpty) and: [
          ["abc" collect: [:ch | Error signal: "stop"]] on: Error do: [:e | true]
        ]]
      ]
    """).boolVal
