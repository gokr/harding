import std/[unittest, strutils, tables]
import ../src/harding/interpreter/objects
import ../src/harding/core/types
import ../src/harding/parser/parser
import ../src/harding/interpreter/scope_validation

let parent = newClass(name = "BindingParent", slotNames = @["payload"])
let child = newClass(name = "BindingChild", superclasses = @[parent], slotNames = @["other"])

proc blockFrom(source: string): BlockNode =
  let (nodes, syntax) = parse(source)
  doAssert not syntax.hasError, syntax.errorMsg
  doAssert nodes.len == 1 and nodes[0] of BlockNode
  BlockNode(nodes[0])

suite "Slot binding declarations":
  test "method arguments and temporaries cannot hide inherited or private slots":
    for source in ["[:payload | payload]", "[| payload | payload := 1]", "[| other | other]"]:
      expect ValueError:
        validateSlotBindings(blockFrom(source), child, "probe")

  test "declarations in control-flow branches and nested callbacks are checked":
    for source in ["[true ifTrue: [| payload | payload := 1]]",
                   "[[false] whileTrue: [| payload | payload := 1]]",
                   "[[[:payload | payload]]]",
                   "[self accept: [:payload | payload]]",
                   "[self accept: [| other | other := 2]; yourself]"]:
      expect ValueError:
        validateSlotBindings(blockFrom(source), child, "probe")

  test "reads and assignments to slots and unrelated local shadows remain legal":
    for source in ["[payload := 3. ^payload]", "[| local | local := 2. ^[local]]",
                   "[| local | local := 2. ^[:local | local]]"]:
      validateSlotBindings(blockFrom(source), child, "probe")

  test "failed replacement leaves registration and caches unchanged":
    let original = blockFrom("[^payload]")
    addMethodToClass(child, "probe", original)
    let version = child.version
    let rejected = blockFrom("[| payload | payload]")
    expect ValueError:
      addMethodToClass(child, "probe", rejected)
    check child.methods["probe"] == original
    check child.allMethods["probe"] == original
    check child.version == version
    check not rejected.isMethod

  test "class-side factory parameters do not shadow instance slots":
    let factory = blockFrom("[:payload | payload]")
    addMethodToClass(child, "withPayload:", factory, isClassMethod = true)
    check child.classMethods["withPayload:"] == factory

  test "generated accessor chooses a nonconflicting parameter":
    let cls = newClass(name = "AccessorBindings", slotNames = @["aValue", "aValue_"])
    let setter = createSetterMethod(cls, "aValue")
    addMethodToClass(cls, "aValue:", setter)
    check setter.parameters == @["aValue__"]

  test "diagnostic identifies the owner selector and binding":
    try:
      validateSlotBindings(blockFrom("[| payload | payload]"), child, "replace:")
      check false
    except ValueError as failure:
      check failure.msg.contains("Local binding 'payload' shadows slot")
      check failure.msg.contains("BindingChild>>replace:")
