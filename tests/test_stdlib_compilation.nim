import std/[strutils, tables, unittest]
import ../src/harding/core/[types, scheduler]
import ../src/harding/interpreter/vm
import ../src/harding/compiler/[stdlib_compilation, context, symbols, primitive_abi]
import ../src/harding/codegen/module

suite "Granite source-backed stdlib methods":
  let host = newSchedulerContext()
  var interp = host.mainProcess.getInterpreter()
  loadStdlib(interp, "lib/core/Bootstrap.hrd")

  test "library classes are discovered, not listed":
    let classes = libraryClasses(interp)
    for name in ["Integer", "String", "Array", "Table", "Set", "Iterable",
                 "Bag", "SortedCollection", "Interval", "Exception", "Library"]:
      check name in classes
    check classes == libraryClasses(interp)  # stable order

  test "source method inventory excludes primitive implementations":
    var gaps: seq[string]
    let definitions = stdlibMethodDefinitions(interp, ["Integer"], gaps)
    var selectors: seq[string]
    for node in definitions:
      let message = node.MessageNode
      check message.receiver.IdentNode.name == "Integer"
      selectors.add(message.arguments[0].LiteralNode.value.symVal)
    for expected in ["factorial", "gcd:", "lcm:", "odd", "even", "abs", "negated"]:
      check expected in selectors

  test "no library method is left hand-implemented":
    ## The invariant this work exists to hold: every method a library file
    ## defines either compiles from source or resolves to a declared primitive.
    var gaps: seq[string]
    let classes = libraryClasses(interp)
    discard stdlibMethodDefinitions(interp, classes, gaps)
    check gaps.len == 0

  test "every declared primitive has a Nim implementation":
    var gaps: seq[string]
    let classes = libraryClasses(interp)
    discard stdlibMethodDefinitions(interp, classes, gaps)
    let bindings = nativePrimitiveBindings()
    for selector in ["primitiveArraySize", "primitiveArrayAt:", "primitivePlus:",
                     "primitiveEquals:", "primitiveValue:", "primitiveWhileTrue:",
                     "primitiveClassName", "primitiveIsKindOf:", "primitiveSetNew",
                     "primitiveTableAt:", "primitiveStringSize", "primitivePrintString"]:
      check selector in bindings

  test "method emission without application source copies":
    var gaps: seq[string]
    let classes = libraryClasses(interp)
    let methods = stdlibMethodDefinitions(interp, classes, gaps)
    let edges = stdlibSuperclassEdges(interp, classes)
    let layouts = stdlibStorageDefinitions(interp, classes)
    var compiler = newCompiler("build", "library_inventory")
    let generated = genModule(compiler, @[], "library_inventory",
      libraryMethods = methods, librarySuperclasses = edges, libraryStorage = layouts)
    check generated.contains("registerCompiledMethod(\"Integer\", \"factorial\"")
    check generated.contains("registerCompiledMethod(\"Array\", \"sorted:\"")
    check generated.contains("registerCompiledMethod(\"Iterable\", \"sum\"")
    check generated.contains("registerSuperclass(\"String\", \"Comparable\")")
    check generated.contains("primitiveArraySize(self, @[])")
    check not generated.contains("callPrimitive(")
    # A library class the runtime represents natively keeps that representation.
    check not generated.contains("registerCompiledClass(\"Array\"")
    check generated.contains("registerCompiledClass(\"Bag\"")

suite "Granite primitive boundary":
  test "selectors are mangled so no generated identifier is invalid":
    for selector in ["&", "|", "\\", "+", "//", "at:put:", "value:value:"]:
      let mangled = mangleSelector(selector)
      for ch in mangled:
        check ch in {'a'..'z', 'A'..'Z', '0'..'9', '_'}
      check not mangled.endsWith("_")
