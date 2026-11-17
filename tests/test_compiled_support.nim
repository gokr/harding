import std/[tables, unittest]
import ../src/harding/runtime/compiled_support

proc answer(): NodeValue {.cdecl.} =
  NodeValue(kind: vkInt, intVal: 42)

type TestEnvironment = ref object of RootObj
  counter: MutableCell

proc increment(env: pointer): NodeValue {.cdecl.} =
  let captured = cast[TestEnvironment](env)
  captured.counter.value.intVal += 1
  captured.counter.value

proc identityArg(a: NodeValue): NodeValue {.cdecl.} =
  a

proc sumPair(a, b: NodeValue): NodeValue {.cdecl.} =
  toValue(a.intVal + b.intVal)

proc sumTriple(a, b, c: NodeValue): NodeValue {.cdecl.} =
  toValue(a.intVal + b.intVal + c.intVal)

var indexedElements: seq[NodeValue]
var indexedIndices: seq[int]

proc recordIndexed(element, index: NodeValue): NodeValue {.cdecl.} =
  indexedElements.add(element)
  indexedIndices.add(index.intVal)
  nilValue()

proc helperOverride(self: NodeValue, args: openArray[NodeValue]): NodeValue =
  toValue("override")

proc nilHelperOverride(self: NodeValue, args: openArray[NodeValue]): NodeValue =
  nilValue()

# The helpers are ordinary dispatch, not inline fast paths: since the stdlib is
# compiled through the normal pipeline, `True>>not` and friends come from
# `lib/core/` and a user override must be able to win. A generated module
# registers them, so these tests register them too. Special-casing Booleans in
# the helper instead would shadow the library method, which is the bug that made
# `&` unoverridable.
proc trueNot(self: NodeValue, args: seq[NodeValue]): NodeValue =
  NodeValue(kind: vkBool, boolVal: false)

proc falseNot(self: NodeValue, args: seq[NodeValue]): NodeValue =
  NodeValue(kind: vkBool, boolVal: true)

proc truePipe(self: NodeValue, args: seq[NodeValue]): NodeValue =
  NodeValue(kind: vkBool, boolVal: true)

proc falsePipe(self: NodeValue, args: seq[NodeValue]): NodeValue =
  ## False>>| answers the argument, which is already evaluated.
  if args.len > 0: args[0] else: NodeValue(kind: vkBool, boolVal: false)

proc registerBooleanLibrary =
  registerCompiledMethod("True", "not", trueNot)
  registerCompiledMethod("False", "not", falseNot)
  registerCompiledMethod("True", "|", truePipe)
  registerCompiledMethod("False", "|", falsePipe)

proc arrayWithIndexDo(self: NodeValue, args: seq[NodeValue]): NodeValue =
  ## Mirrors `lib/core/Array.hrd`: zero-based index, answers the receiver.
  if args.len == 0:
    return self
  let callback = args[0]
  let elements = if self.kind == vkArray: self.arrayVal
                 elif self.kind == vkInstance and self.instVal != nil and self.instVal.kind == ikArray:
                   self.instVal.elements
                 else: @[]
  for index, element in elements:
    discard invokeCompiledBlock(callback.blockVal, @[element, toValue(index)])
  self

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

  test "Boolean helpers preserve truth tables and dynamic overrides":
    registerBooleanLibrary()
    for left in [false, true]:
      check nt_not(toValue(left)).boolVal == not left
      for right in [false, true]:
        check nt_pipe(toValue(left), toValue(right)).boolVal == (left or right)
    let instance = newInstance(newClass(name = "BooleanHelperOverride"))
    instance.isNimProxy = true
    let receiver = NodeValue(kind: vkInstance, instVal: instance)
    registerCompiledMethod(instance.class.name, "|", helperOverride)
    registerCompiledMethod(instance.class.name, "not", helperOverride)
    check nt_pipe(receiver, toValue(false)).strVal == "override"
    check nt_not(receiver).strVal == "override"
    registerCompiledMethod(instance.class.name, "not", nilHelperOverride)
    check isNilValue(nt_not(receiver))
    # These are ordinary sends, so a non-Boolean answers from the library exactly
    # as the interpreter does: `true | 1` is true, `false | 5` is 5, and a
    # selector no class implements is MessageNotUnderstood rather than nil.
    check nt_pipe(toValue(true), toValue(1)).boolVal
    check nt_pipe(toValue(false), toValue(5)).intVal == 5
    expect CompiledHardingError:
      discard nt_pipe(toValue(1), toValue(2))
    expect CompiledHardingError:
      discard nt_not(toValue(1))

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
    check rt.evalBlock(plain.blockVal).intVal == 42
    let captured = block:
      let env = TestEnvironment(counter: MutableCell(value: NodeValue(kind: vkInt, intVal: 0)))
      createBlockWithEnv(cast[pointer](increment), 0, env)
    check sendMessage(rt, captured, "value", @[]).intVal == 1
    check sendMessage(rt, captured, "value", @[]).intVal == 2
    check rt.evalBlock(captured.blockVal).intVal == 3
    # The environment pointer is a plain field, not smuggled through the captured
    # variable table: that table is only for interpreter-visible captures.
    check captured.blockVal.nativeEnvPtr != nil
    check getBlockEnvPtr(captured.blockVal) == captured.blockVal.nativeEnvPtr
    check not captured.blockVal.capturedEnvInitialized
    check captured.blockVal.capturedEnv.len == 0
    check plain.blockVal.nativeEnvPtr == nil
    check getBlockEnvPtr(plain.blockVal) == nil

  test "environment-free block ABI supports one to three arguments":
    let one = createBlock1(identityArg, 1)
    let two = createBlock2(sumPair, 2)
    let three = createBlock3(sumTriple, 3)
    check invokeCompiledBlock(one.blockVal, @[toValue(7)]).intVal == 7
    check invokeCompiledBlock(two.blockVal, @[toValue(7), toValue(8)]).intVal == 15
    check invokeCompiledBlock(three.blockVal, @[toValue(7), toValue(8), toValue(9)]).intVal == 24
    check invokeBlockValue(one, [toValue(7)]).intVal == 7
    check invokeBlockValue(two, [toValue(7), toValue(8)]).intVal == 15
    check invokeBlockValue(three, [toValue(7), toValue(8), toValue(9)]).intVal == 24
    check two.blockVal.compiledInvoker(two.blockVal, @[toValue(7), toValue(8)]).intVal == 15

  test "compiled block invocation rejects mismatched and unsupported arities before casting":
    let plain = createBlock0(answer, 0)
    check plain.blockVal.compiledInvoker != nil
    check plain.blockVal.compiledInvoker(plain.blockVal, @[]).intVal == 42
    expect ValueError:
      discard invokeCompiledBlock(plain.blockVal, @[toValue(1)])
    expect ValueError:
      discard invokeBlockValue(plain, [toValue(1)])
    expect ValueError:
      discard sendMessage(nil, plain, "value:", @[toValue(1)])
    let unsupported = createBlock(cast[pointer](answer), 4)
    expect ValueError:
      discard invokeCompiledBlock(unsupported.blockVal, @[toValue(1), toValue(2), toValue(3), toValue(4)])

  test "indexed iteration passes element and zero-based index and answers receiver":
    registerCompiledMethod("Array", "withIndexDo:", arrayWithIndexDo)
    indexedElements = @[]
    indexedIndices = @[]
    let callback = createBlock2(recordIndexed, 2)
    # Compiled code represents an Array as an instance-backed value, which is what
    # carries a class name and therefore reaches the registered method. Raw
    # vkArray values are an intermediate form and have no class name at all.
    let array = compiledArray(@[toValue("first"), toValue("second")])
    check sendMessage(newRuntime(), array, "withIndexDo:", @[callback]) == array
    check indexedElements == array.instVal.elements
    check indexedIndices == @[0, 1]
    indexedElements = @[]
    indexedIndices = @[]
    discard sendMessage(newRuntime(), compiledArray(@[]), "withIndexDo:", @[callback])
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

type
  SlotNodeObj {.inheritable.} = object of HardingObject
    number: int
  SlotNode = ref SlotNodeObj
  SlotNodeChildObj {.inheritable.} = object of SlotNodeObj
    extra: int
  SlotNodeChild = ref SlotNodeChildObj

proc newSlotNode(number: int): SlotNode =
  result = SlotNode(new(SlotNodeObj))
  result.number = number

suite "Native object slot views":
  test "a matching native layout exposes a typed view and keeps the wrapper":
    let node = newSlotNode(42)
    let instance = Instance(kind: ikObject, class: nil, isNimProxy: true,
                            compiledOwner: node)
    instance.nimValue = cast[pointer](node)
    let view = nativeObjectSlot(instance, SlotNode)
    check view.native == node
    check view.native.number == 42
    check view.instance == instance
    # The wrapper is still what identity is checked against.
    check compiledObjectSlotValue(view).instVal == instance

  test "subclass storage keeps the same typed view":
    let child = SlotNodeChild(new(SlotNodeChildObj))
    child.number = 7
    let instance = Instance(kind: ikObject, class: nil, isNimProxy: true,
                            compiledOwner: child)
    instance.nimValue = cast[pointer](child)
    let view = nativeObjectSlot(instance, SlotNode)
    check view.native.number == 7
    check view.native of SlotNodeChild

  test "a VM-owned or differently laid out value keeps only the wrapper":
    let plain = Instance(kind: ikObject, class: nil, isNimProxy: true)
    check nativeObjectSlot(plain, SlotNode).native == nil
    # A compiled owner of the wrong type must not be viewed as SlotNode.
    let other = newSlotNode(1)
    let mismatched = Instance(kind: ikObject, class: nil, isNimProxy: true,
                              compiledOwner: other)
    mismatched.nimValue = cast[pointer](other)
    check nativeObjectSlot(mismatched, SlotNodeChild).native == nil
    # Storage already bridged to a VM layout is not a private native layout.
    let bridged = Instance(kind: ikObject, class: nil, isNimProxy: true,
                           compiledOwner: other)
    bridged.nimValue = cast[pointer](other)
    bridged.nativeSlots = NativeSlotStorage()
    check nativeObjectSlot(bridged, SlotNode).native == nil
