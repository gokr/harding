import std/unittest
import ../src/harding/runtime/compiled_support

proc answer(): NodeValue {.cdecl.} =
  NodeValue(kind: vkInt, intVal: 42)

type TestEnvironment = ref object of RootObj
  counter: MutableCell

proc increment(env: pointer): NodeValue {.cdecl.} =
  let captured = cast[TestEnvironment](env)
  captured.counter.value.intVal += 1
  captured.counter.value

var indexedElements: seq[NodeValue]
var indexedIndices: seq[int]

proc recordIndexed(element, index: NodeValue): NodeValue {.cdecl.} =
  indexedElements.add(element)
  indexedIndices.add(index.intVal)
  nilValue()

proc helperOverride(self: NodeValue, args: seq[NodeValue]): NodeValue =
  toValue("override")

proc nilHelperOverride(self: NodeValue, args: seq[NodeValue]): NodeValue =
  nilValue()

suite "Compiled shared support":
  test "builtin helpers honor dynamic instance methods and replacement":
    let cls = newClass(name = "DynamicHelperOverrides")
    let instance = newInstance(cls)
    instance.isNimProxy = true
    let receiver = NodeValue(kind: vkInstance, instVal: instance)
    for selector in ["size", "last", "keys", "abs", "even", "odd", "negated", "asString", "&"]:
      registerCompiledMethod(cls.name, selector, helperOverride)
    check nt_size(receiver).strVal == "override"
    check nt_last(receiver).strVal == "override"
    check nt_table_keys(receiver).strVal == "override"
    check nt_table_size(receiver).strVal == "override"
    check nt_abs(receiver).strVal == "override"
    check nt_even(receiver).strVal == "override"
    check nt_odd(receiver).strVal == "override"
    check nt_negated(receiver).strVal == "override"
    check nt_asString(receiver).strVal == "override"
    check nt_comma(receiver, toValue("suffix")).strVal == "override"
    registerCompiledMethod(cls.name, "last", nilHelperOverride)
    check isNilValue(nt_last(receiver))

  test "base storage is retainable by instance wrappers":
    let owner = HardingObjectRef(className: "OwnedTest")
    let wrapper = Instance(kind: ikObject, compiledOwner: owner)
    check wrapper.compiledOwner == owner

  test "loop conversion keeps generated helper behavior":
    check compiledLoopInt(NodeValue(kind: vkInt, intVal: 3)) == 3
    check compiledLoopInt(NodeValue(kind: vkFloat, floatVal: 3.9)) == 3
    check compiledLoopInt(nilValue()) == 0
    expect ValueError:
      discard toInt(nilValue())

  test "globals and arithmetic use imported helpers":
    let value = NodeValue(kind: vkInt, intVal: 17)
    check setGlobal("SharedSupportTest", value) == value
    check getGlobal("SharedSupportTest") == value
    check nt_plus(value, NodeValue(kind: vkFloat, floatVal: 0.5)).floatVal == 17.5
    check nt_lt(value, NodeValue(kind: vkInt, intVal: 18)).boolVal

  test "compiled blocks and managed captures survive module boundaries":
    let rt = newRuntime()
    let plain = createBlock0(answer, 0)
    check sendMessage(rt, plain, "value", @[]).intVal == 42
    let captured = block:
      let env = TestEnvironment(counter: MutableCell(value: NodeValue(kind: vkInt, intVal: 0)))
      createBlockWithEnv(cast[pointer](increment), 0, env)
    check sendMessage(rt, captured, "value", @[]).intVal == 1
    check sendMessage(rt, captured, "value", @[]).intVal == 2

  test "indexed iteration passes element and zero-based index and answers receiver":
    indexedElements = @[]
    indexedIndices = @[]
    let callback = createBlock2(recordIndexed, 2)
    let array = NodeValue(kind: vkArray, arrayVal: @[toValue("first"), toValue("second")])
    check sendMessage(newRuntime(), array, "withIndexDo:", @[callback]) == array
    check indexedElements == array.arrayVal
    check indexedIndices == @[0, 1]
    indexedElements = @[]
    indexedIndices = @[]
    discard sendMessage(newRuntime(), NodeValue(kind: vkArray, arrayVal: @[]),
                        "withIndexDo:", @[callback])
    check indexedElements.len == 0
    check indexedIndices.len == 0

  test "identity helpers work without a current runtime":
    let cls = newClass(name = "SupportIdentityTest")
    let first = NodeValue(kind: vkInstance, instVal: newInstance(cls))
    let second = NodeValue(kind: vkInstance, instVal: newInstance(cls))
    check nt_eqeq(first, first).boolVal
    check not nt_eqeq(first, second).boolVal
    check nt_tildeeq(first, second).boolVal
    check not nt_tildeeq(first, first).boolVal
    let blk = createBlock0(answer, 0)
    check nt_eqeq(blk, blk).boolVal
    check not nt_eqeq(blk, createBlock0(answer, 0)).boolVal
    check nt_eqeq(NodeValue(kind: vkNil), NodeValue(kind: vkNil)).boolVal
    check not nt_eqeq(NodeValue(kind: vkInt, intVal: 1),
                     NodeValue(kind: vkFloat, floatVal: 1.0)).boolVal
    check nt_eqeq(NodeValue(kind: vkSymbol, symVal: "tag"),
                 NodeValue(kind: vkSymbol, symVal: "tag")).boolVal

  test "return transfer preserves activation identity":
    let home = CompiledReturnTarget(active: true)
    try:
      discard raiseNonLocalReturn(home, NodeValue(kind: vkInt, intVal: 9))
      check false
    except NonLocalReturnException as transfer:
      check transfer.target == home
      check transfer.value.intVal == 9
    home.active = false
    expect CompiledHardingError:
      discard raiseNonLocalReturn(home, nilValue())
