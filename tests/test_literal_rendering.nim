import std/[unittest, tables]
import ../src/harding/core/types
import ../src/harding/interpreter/vm
import ./stdlib_test_support

var interp = newSharedStdlibInterpreter()

suite "Literal rendering separators":
  test "raw arrays and tables use comma separators":
    let array = NodeValue(kind: vkArray, arrayVal: @[toValue(1), toValue(2)])
    check array.toString() == "#(1, 2)"
    check array.formatLiteral() == "#(1, 2)"
    let nested = NodeValue(kind: vkArray, arrayVal: @[array, toValue(3)])
    check nested.toString() == "#(#(1, 2), 3)"
    var entries = initTable[NodeValue, NodeValue]()
    entries[toValue("a")] = toValue(1)
    entries[toValue("b")] = toValue(2)
    let table = NodeValue(kind: vkTable, tableVal: entries)
    check table.formatLiteral() in ["#{\"a\" -> 1, \"b\" -> 2}", "#{\"b\" -> 2, \"a\" -> 1}"]

  test "library printString is readable for nested numeric collections":
    let (printed, error) = interp.doit("#(#(1, 2), 3) printString")
    require error.len == 0
    let source = if printed.kind == vkString: printed.strVal else: printed.instVal.strVal
    let (value, parseError) = interp.doit(source)
    require parseError.len == 0
    check value.toString() == "#(#(1, 2), 3)"
