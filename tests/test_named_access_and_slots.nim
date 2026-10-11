import std/[unittest, tables, strutils]
import ../src/harding/core/types
import ../src/harding/core/scheduler
import ../src/harding/interpreter/vm

proc newInterp(): Interpreter =
  result = newInterpreter()
  initGlobals(result)
  initProcessorGlobal(result)
  loadStdlib(result)

suite "Message not understood and error: signal":
  test "doesNotUnderstand: raises a catchable Error":
    var interp = newInterp()
    let (value, err) = interp.doit("""
      Result := [ UnknownThing someUnknownMessage ] on: Exception do: [:ex | "caught" ].
      Result
    """)
    check(err.len == 0)
    check(value.kind == vkString)
    check(value.strVal == "caught")

  test "error: signals a catchable Error carrying the message":
    var interp = newInterp()
    let (value, err) = interp.doit("""
      Result := [ Object new error: "boom" ] on: Error do: [:ex | ex message ].
      Result
    """)
    check(err.len == 0)
    check(value.kind == vkString)
    check(value.strVal == "boom")

  test "uncaught message not understood is reported, not fatal":
    var interp = newInterp()
    let (_, err) = interp.evalStatements("nil someUnknownMessage")
    check(err.len > 0)
    check(err.contains("someUnknownMessage"))

  test "signal from a nested doesNotUnderstand unwinds to the handler":
    var interp = newInterp()
    let (value, err) = interp.doit("""
      Inner := Object derive.
      Inner>>boom [ ^ self noSuchMethodAtAll ].
      Result := [ Inner new boom ] on: Exception do: [:ex | "caught-nested" ].
      Result
    """)
    check(err.len == 0)
    check(value.kind == vkString)
    check(value.strVal == "caught-nested")

suite "Named access (::)":
  test "reads a public slot on the object itself":
    var interp = newInterp()
    let (value, err) = interp.doit("""
      P := Object derivePublic: #(x).
      P>>initialize [ x := 5. ^ self ].
      I := P new initialize.
      I::x
    """)
    check(err.len == 0)
    check(value.kind == vkInt)
    check(value.intVal == 5)

  test "writes a public slot":
    var interp = newInterp()
    let (value, err) = interp.doit("""
      P := Object derivePublic: #(x).
      P>>initialize [ x := 1. ^ self ].
      I := P new initialize.
      I::x := 42.
      I::x
    """)
    check(err.len == 0)
    check(value.kind == vkInt)
    check(value.intVal == 42)

  test "read:write: grants selective access":
    var interp = newInterp()
    let (value, err) = interp.doit("""
      C := Object derive: #(z) read: #(z) write: #(z) superclasses: #().
      C>>initialize [ z := 3. ^ self ].
      I := C new initialize.
      I::z := 8.
      I::z
    """)
    check(err.len == 0)
    check(value.kind == vkInt)
    check(value.intVal == 8)

  test "private slot is not accessible from outside":
    var interp = newInterp()
    let (value, err) = interp.doit("""
      P := Object derive: #(secret).
      Result := [ (P new)::secret ] on: Exception do: [:ex | "denied" ].
      Result
    """)
    check(err.len == 0)
    check(value.kind == vkString)
    check(value.strVal == "denied")

  test "table :: names map to the documented string key":
    var interp = newInterp()
    let (value, err) = interp.doit("""
      Tbl := #{"name" -> "Alice", "age" -> 30}.
      Tbl::name
    """)
    check(err.len == 0)
    check(value.kind == vkString)
    check(value.strVal == "Alice")

  test "table :: write creates a new string key":
    var interp = newInterp()
    let (value, err) = interp.doit("""
      Tbl := Table new.
      Tbl::city := "NYC".
      Tbl at: "city"
    """)
    check(err.len == 0)
    check(value.kind == vkString)
    check(value.strVal == "NYC")

  test "library :: binding resolves by name":
    var interp = newInterp()
    let (value, err) = interp.doit("""
      L := Library name: "L".
      L at: "B" put: 42.
      L::B
    """)
    check(err.len == 0)
    check(value.kind == vkInt)
    check(value.intVal == 42)

suite "Inherited slots keep their layout":
  test "inherited slots keep parent-first ordering":
    # The JSON serializer walks slot names by index, so a wrong order shows up
    # as swapped values rather than as an error.
    var interp = newInterp()
    let (value, err) = interp.doit("""
      Person := Object derivePublic: #(name).
      Employee := Person derivePublic: #(role).
      E := Employee new.
      E name: "Alice".
      E role: "Engineer".
      Json stringify: E
    """)
    check(err.len == 0)
    check(value.kind == vkString)
    let namePos = value.strVal.find("\"name\":\"Alice\"")
    let rolePos = value.strVal.find("\"role\":\"Engineer\"")
    check(namePos >= 0)
    check(rolePos >= 0)
    check(namePos < rolePos)

  test "inherited and own slots round-trip independently":
    var interp = newInterp()
    let (value, err) = interp.doit("""
      Person := Object derivePublic: #(name).
      Employee := Person derivePublic: #(role).
      E := Employee new.
      E name: "Alice".
      E role: "Engineer".
      (E name) & "/" & (E role)
    """)
    check(err.len == 0)
    check(value.kind == vkString)
    check(value.strVal == "Alice/Engineer")

  test "json serialization uses the correct slot for inherited fields":
    var interp = newInterp()
    let (value, err) = interp.doit("""
      Person := Object derivePublic: #(name).
      Employee := Person derivePublic: #(role).
      E := Employee new.
      E name: "Alice".
      E role: "Engineer".
      Json stringify: E
    """)
    check(err.len == 0)
    check(value.kind == vkString)
    check(value.strVal.contains("\"name\":\"Alice\""))
    check(value.strVal.contains("\"role\":\"Engineer\""))

  test "three-level inheritance keeps every slot distinct":
    var interp = newInterp()
    let (value, err) = interp.doit("""
      A := Object derivePublic: #(a).
      B := A derivePublic: #(b).
      C := B derivePublic: #(c).
      I := C new.
      I a: 1.
      I b: 2.
      I c: 3.
      ((I a printString) & "/" & (I b printString) & "/" & (I c printString))
    """)
    check(err.len == 0)
    check(value.kind == vkString)
    check(value.strVal == "1/2/3")
