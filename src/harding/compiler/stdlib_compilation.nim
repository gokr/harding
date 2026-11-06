import std/[algorithm, sets, strutils, tables]
import ../core/types
import ../interpreter/vm
import ../codegen/module
import ../parser/parser
import ./primitive_abi

const libraryRoots* = ["lib/core/", "lib/standard/"]
## Classes whose representation the runtime owns. They keep their native storage
## and allocator; their source methods are compiled like any other class's.
const nativeRepresentedClasses* = ["Root", "Object", "Mixin", "Integer", "Float",
  "Boolean", "True", "False", "UndefinedObject", "String", "Symbol", "Array",
  "Table", "Set", "Block"]

proc stripSide(ownerClass: string): string =
  result = ownerClass
  for suffix in [" class", " instance"]:
    if result.endsWith(suffix):
      result = result[0 ..< result.len - suffix.len]

proc isLibraryPath(path: string): bool =
  let normalized = path.replace('\\', '/')
  for root in libraryRoots:
    if normalized.contains(root): return true

proc libraryOwners*(interp: Interpreter): seq[tuple[owner, side, filePath: string]] =
  ## Every class-side and instance-side owner that a library source file defines,
  ## read from the interpreter's own source index.
  var seen = initHashSet[string]()
  if interp.sourceIndex != nil:
    for entry in interp.sourceIndex[].values:
      if not isLibraryPath(entry.filePath): continue
      let owner = stripSide(entry.ownerClass)
      if owner.len == 0: continue
      let side = if entry.side == "class": "class" else: "instance"
      let key = owner & "|" & side
      if key in seen: continue
      seen.incl(key)
      result.add((owner, side, entry.filePath))
  result.sort(proc (a, b: tuple[owner, side, filePath: string]): int =
    result = cmp(a.owner, b.owner)
    if result == 0: result = cmp(a.side, b.side))

proc libraryClasses*(interp: Interpreter): seq[string] =
  ## Distinct class names the library sources extend.
  var found = initHashSet[string]()
  for (owner, _, _) in libraryOwners(interp): found.incl(owner)
  for name in found: result.add(name)
  result.sort()

proc stdlibStorageDefinitions*(interp: Interpreter, classNames: openArray[string]): seq[Node] =
  ## Emit ordinary layouts for library classes that the runtime does not
  ## represent natively, so their source methods can address slots.
  for name in classNames:
    if name in nativeRepresentedClasses: continue
    var host = interp
    let value = evalWithVM(host, IdentNode(name: name))
    if value.kind != vkClass or value.classVal == nil: continue
    let cls = value.classVal
    if cls.allSlotNames.len == 0: continue
    var source = name & " := Object derive: #("
    for index, slot in cls.allSlotNames:
      if index > 0: source.add(", ")
      source.add(slot)
    source.add(")")
    let (nodes, syntax) = parse(source)
    if syntax.hasError:
      raise newException(ValueError, syntax.errorMsg)
    result.add(nodes)

proc librarySelectors*(interp: Interpreter, owner, side: string,
                      methods: Table[string, BlockNode]): seq[string] =
  ## Selectors the library files define for this owner and side, in order.
  var names = initHashSet[string]()
  if interp.sourceIndex != nil:
    for entry in interp.sourceIndex[].values:
      if not isLibraryPath(entry.filePath): continue
      if stripSide(entry.ownerClass) != owner: continue
      if entry.selector == "<classDefinition>": continue
      let entrySide = if entry.side == "class": "class" else: "instance"
      if entrySide != side: continue
      # A selectors entry may be recorded with the raw source spelling (`\\`)
      # while the class registered the single-character selector the lexer
      # produced; normalize to the registered one.
      var selector = entry.selector
      if selector notin methods and selector.replace("\\\\", "\\") in methods:
        selector = selector.replace("\\\\", "\\")
      names.incl(selector)
  for name in names: result.add(name)
  result.sort()

proc stdlibMethodDefinitions*(interp: Interpreter, classNames: openArray[string],
                              gaps: var seq[string]): seq[Node] =
  ## Lift every library-defined method into the ordinary method pipeline. A
  ## declarative primitive becomes a call to its Nim implementation, so the
  ## library stays the source of truth for what a method does; a method the
  ## compiled backend cannot reach is reported as a gap rather than dropped.
  ##
  ## The VM also publishes some instance methods on a class's metaclass so a
  ## class object answers them. That is a host registration, not a second
  ## definition, so the instance declaration supplies the class-side body too.
  for name in classNames:
    var host = interp
    let value = evalWithVM(host, IdentNode(name: name))
    if value.kind != vkClass or value.classVal == nil: continue
    let cls = value.classVal
    let bindings = nativePrimitiveBindings()
    let instanceSource = librarySelectors(interp, name, "instance", cls.methods)
    for classSide in [false, true]:
      let side = if classSide: "class" else: "instance"
      var declared = librarySelectors(interp, name, side,
        if classSide: cls.classMethods else: cls.methods)
      if classSide:
        for selector in instanceSource:
          if selector notin declared and selector in cls.classMethods:
            declared.add(selector)
        declared.sort()
      for selector in declared:
        if selector notin (if classSide: cls.classMethods else: cls.methods):
          gaps.add(name & ">>" & selector & " (not registered)")
          continue
        var implementation: BlockNode = nil
        if classSide:
          implementation = cls.classMethods[selector]
          # A host alias on the metaclass carries the host block; the compiled
          # body must come from the library declaration that defines it.
          if selector in instanceSource and cls.methods[selector].primitiveSelector.len > 0:
            implementation = cls.methods[selector]
        else:
          implementation = cls.methods[selector]
        if implementation.primitiveSelector.len > 0:
          if implementation.primitiveSelector notin bindings:
            gaps.add(name & ">>" & selector & " (" & implementation.primitiveSelector & ")")
            continue
          let primitive = PrimitiveCallNode(selector: implementation.primitiveSelector,
            arguments: @[])
          for parameter in implementation.parameters:
            primitive.arguments.add(IdentNode(name: parameter))
          implementation = BlockNode(parameters: implementation.parameters,
            body: @[Node(ReturnNode(expression: primitive))], isMethod: true)
        elif implementation.nativeImpl != nil or implementation.nativeValueImpl != nil:
          gaps.add(name & ">>" & selector & " (native method)")
          continue
        let definition = MessageNode(receiver: IdentNode(name: name),
          selector: (if classSide: "classSelector:put:" else: "selector:put:"),
          arguments: @[Node(LiteralNode(value: NodeValue(kind: vkSymbol, symVal: selector))),
                       Node(implementation)])
        var primitives: seq[string]
        collectDeclarativePrimitives(@[Node(definition)], primitives)
        if primitives.len == 0:
          result.add(definition)

proc stdlibSuperclassEdges*(interp: Interpreter,
                            classNames: openArray[string]): seq[(string, string)] =
  ## Preserve live parent order without generating replacement native allocators.
  for name in classNames:
    var host = interp
    let value = evalWithVM(host, IdentNode(name: name))
    if value.kind != vkClass or value.classVal == nil: continue
    for parent in value.classVal.superclasses:
      result.add((name, parent.name))
