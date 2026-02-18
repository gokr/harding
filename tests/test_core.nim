import ../src/harding/core/types
import ../src/harding/interpreter/[vm]

## Core Harding Tests
## Tests fundamental language features with ARC memory management

var interp = newInterpreter()
initGlobals(interp)
loadStdlib(interp)

echo "=== Core Harding Tests ==="
echo ""

echo "Test 1: Simple arithmetic"
var result = interp.evalStatements("""
  Result := 2 + 3
""")
echo "  2 + 3 = ", result[0][^1].intVal
assert(result[0][^1].intVal == 5)

echo "Test 2: Block value"
result = interp.evalStatements("""
  Result := [ "hello" ] value
""")
echo "  [ 'hello' ] value = ", result[0][^1].strVal
assert(result[0][^1].strVal == "hello")

echo "Test 3: Boolean ifTrue:"
result = interp.evalStatements("""
  Result := true ifTrue: [ 42 ]
""")
echo "  true ifTrue: [ 42 ] = ", result[0][^1].intVal
assert(result[0][^1].intVal == 42)

echo "Test 4: Nested blocks"
result = interp.evalStatements("""
  Result := [ [ 99 ] value ] value
""")
echo "  Nested blocks = ", result[0][^1].intVal
assert(result[0][^1].intVal == 99)

echo "Test 5: on:do: without exception (ARC stress test)"
result = interp.evalStatements("""
  Result := [ "protected" ] on: Error do: [ :ex | "caught" ]
""")
echo "  on:do: result = ", result[0][^1].strVal
assert(result[0][^1].strVal == "protected")

echo ""
echo "=== All core tests passed! ==="
