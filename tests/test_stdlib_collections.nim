#
# test_stdlib_collections.nim - Tests for advanced collection functionality
# Includes: Arrays - Advanced, Tables - Advanced
#

import std/unittest
import ../src/harding/core/types
import ../src/harding/interpreter/vm
import ./stdlib_test_support

# Shared interpreter initialized once for all suites
var sharedInterp = newSharedStdlibInterpreter()

suite "Stdlib: Arrays - Advanced":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "removeAt: removes element at index":
    let result = interp.evalStatements("""
      Arr := Array new.
      Arr add: 10.
      Arr add: 20.
      Arr add: 30.
      Arr removeAt: 1.
      Result := Arr size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 2)

  test "withIndexDo: passes element and index":
    let result = interp.evalStatements("""
      Arr := #(10 20 30).
      sum := 0.
      Arr withIndexDo: [:elem :idx | sum := sum + idx].
      Result := sum
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 3)

  test "copyFrom:to: extracts subarray":
    let result = interp.evalStatements("""
      Arr := #(10 20 30 40 50).
      Sub := Arr copyFrom: 1 to: 3.
      Result := Sub size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 3)

  test "copyFrom:to: contains correct elements":
    let result = interp.evalStatements("""
      Arr := #(10 20 30 40 50).
      Sub := Arr copyFrom: 1 to: 3.
      Result := Sub at: 0
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 20)

  test "indexOf: returns 0-based index of element":
    let result = interp.evalStatements("""
      Arr := #(10 20 30).
      Result := Arr indexOf: 20
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 1)  # 0-based index

  test "indexOf: returns nil when not found":
    let result = interp.evalStatements("""
      Arr := #(10 20 30).
      Result := Arr indexOf: 99
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInstance)

  test "removeFirst removes and returns first element":
    let result = interp.evalStatements("""
      Arr := Array new.
      Arr add: 10.
      Arr add: 20.
      First := Arr removeFirst.
      Result := First
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 10)

  test "removeLast removes and returns last element":
    let result = interp.evalStatements("""
      Arr := Array new.
      Arr add: 10.
      Arr add: 20.
      Last := Arr removeLast.
      Result := Last
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 20)

  test "includes: returns true for present element":
    let (result, err) = interp.doit("#(1 2 3) includes: 2")
    check(err.len == 0)
    check(result.kind == vkBool)
    check(result.boolVal == true)

  test "includes: returns false for absent element":
    let (result, err) = interp.doit("#(1 2 3) includes: 99")
    check(err.len == 0)
    check(result.kind == vkBool)
    check(result.boolVal == false)

  test "sorted returns elements in ascending order":
    let result = interp.evalStatements("""
      Arr := #(3 1 4 1 5 9 2 6).
      Sorted := Arr sorted.
      Result := Sorted first
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 1)

  test "sorted: with custom block sorts descending":
    let result = interp.evalStatements("""
      Arr := #(3 1 4 1 5 9 2 6).
      Sorted := Arr sorted: [:a :b | a > b].
      Result := Sorted first
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 9)

suite "Stdlib: Tables - Advanced":
  var interp {.used.}: Interpreter

  setup:
    interp = sharedInterp

  test "at:ifAbsent: returns value when key present":
    let result = interp.evalStatements("""
      T := Table new.
      T at: "key" put: "value".
      Result := T at: "key" ifAbsent: [ "missing" ]
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "value")

  test "at:ifAbsent: evaluates block when key absent":
    let result = interp.evalStatements("""
      T := Table new.
      Result := T at: "missing" ifAbsent: [ "default" ]
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "default")

  test "at:ifAbsent: preserves self inside absent block":
    let result = interp.evalStatements("""
      Probe := Object derive: #(table).
      Probe>>initialize [
        table := Table new.
        ^ self
      ].
      Probe>>lookupMissing [
        ^ table at: "missing" ifAbsent: [ self className ]
      ].

      Result := Probe new initialize lookupMissing
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "Probe")

  test "at:ifPresent: evaluates block when key present":
    let result = interp.evalStatements("""
      T := Table new.
      T at: "name" put: "Alice".
      Result := T at: "name" ifPresent: [:v | v uppercase]
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkString)
    check(result[0][^1].strVal == "ALICE")

  test "at:ifPresent: returns nil when key absent":
    let result = interp.evalStatements("""
      T := Table new.
      Result := T at: "missing" ifPresent: [:v | v]
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInstance)

  test "do: iterates over key-value pairs":
    let result = interp.evalStatements("""
      T := Table new.
      T at: "a" put: 1.
      T at: "b" put: 2.
      T at: "c" put: 3.
      sum := 0.
      T do: [:k :v | sum := sum + v].
      Result := sum
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 6)

  test "values returns array of all values":
    let result = interp.evalStatements("""
      T := Table new.
      T at: "x" put: 10.
      T at: "y" put: 20.
      Result := T values size
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 2)

  test "removeKey: removes a key-value pair":
    let result = interp.evalStatements("""
      T := Table new.
      T at: "key" put: "value".
      T removeKey: "key".
      Result := T includesKey: "key"
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == false)

  test "isEmpty returns true for empty table":
    let result = interp.evalStatements("""
      T := Table new.
      Result := T isEmpty
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == true)

  test "notEmpty returns true after adding entry":
    let result = interp.evalStatements("""
      T := Table new.
      T at: "x" put: 1.
      Result := T notEmpty
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkBool)
    check(result[0][^1].boolVal == true)
