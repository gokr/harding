## Compiler Primitives for Granite
## Exposes compilation functionality as Harding primitives

when defined(granite):
  import std/[os, strutils, strformat, tables, sets, hashes]
  import ../core/types
  import ../parser/parser
  import ../parser/lexer
  import ../codegen/module
  import ../compiler/context
  import ../compiler/symbols
  import ../interpreter/vm

  # Global reference to current interpreter (set during primitive calls)
  var currentInterpreter*: Interpreter = nil

  # Forward declarations for primitive implementations
  proc graniteCompileImpl*(self: Instance, args: seq[NodeValue]): NodeValue
  proc graniteBuildImpl*(self: Instance, args: seq[NodeValue]): NodeValue

  type
    CompileResult* = object
      nimCode*: string
      errors*: seq[string]

  proc compileHrdToNim*(source: string, sourcePath: string = ""): CompileResult =
    ## Compile Harding source to Nim code
    result.errors = @[]

    try:
      let tokens = lex(source)
      var parser = initParser(tokens)
      parser.lastLine = 1
      let nodes = parser.parseStatements()

      if parser.hasError:
        result.errors.add(parser.errorMsg)
        return

      let moduleName = if sourcePath.len > 0:
                         changeFileExt(extractFilename(sourcePath), "")
                       else:
                         "generated"

      var ctx = newCompiler("./build", moduleName)
      result.nimCode = genModule(ctx, nodes, moduleName)

    except CatchableError as e:
      result.errors.add("Compilation error: " & e.msg)

  # Primitive: Granite class>>compile: source
  proc graniteCompileImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
    if args.len < 1 or args[0].kind != vkString:
      return NodeValue(kind: vkNil)

    let source = args[0].strVal
    let compResult = compileHrdToNim(source, "")

    if compResult.errors.len > 0:
      return NodeValue(kind: vkString, strVal: compResult.errors.join("\n"))

    return NodeValue(kind: vkString, strVal: compResult.nimCode)

  proc getSlotValue*(inst: Instance, slotIdx: int): NodeValue =
    ## Get slot value at index
    if inst.kind == ikObject and slotIdx >= 0 and slotIdx < inst.slots.len:
      return inst.slots[slotIdx]
    return NodeValue(kind: vkNil)

  proc findClassInGlobals*(interp: Interpreter, className: string): Class =
    ## Find a class by name in globals
    if className in interp.globals[]:
      let val = interp.globals[][className]
      if val.kind == vkClass:
        return val.classVal
    return nil

  proc collectTransitiveClasses*(app: Instance, interp: Interpreter): seq[Class] =
    ## Collect all classes transitively referenced from Application
    result = @[]
    var visited = initHashSet[string]()
    var toProcess: seq[Class] = @[]

    # Start with Application's class
    if app.class != nil:
      toProcess.add(app.class)

    while toProcess.len > 0:
      let cls = toProcess.pop()
      if cls.name in visited:
        continue
      visited.incl(cls.name)
      result.add(cls)

      # Add superclasses if not Object/Root
      for superCls in cls.superclasses:
        if superCls.name != "Root" and superCls.name != "Object":
          if not (superCls.name in visited):
            toProcess.add(superCls)

      # Look for class references in method bodies
      # For now, we include all classes in globals that might be used
      # A more sophisticated analysis would parse method bodies

    # Also include any classes referenced in Application's libraries slot
    let librariesVal = getSlotValue(app, 1)  # libraries is slot 1
    if librariesVal.kind == vkArray:
      for libEntry in librariesVal.arrayVal:
        if libEntry.kind == vkString:
          let libName = libEntry.strVal
          # Find classes from this library
          # For now, we include common collection classes
          case libName
          of "Core":
            discard  # Core classes already included
          of "Collections":
            let arrayCls = findClassInGlobals(interp, "Array")
            if arrayCls != nil and not (arrayCls.name in visited):
              result.add(arrayCls)
            let tableCls = findClassInGlobals(interp, "Table")
            if tableCls != nil and not (tableCls.name in visited):
              result.add(tableCls)
            let setCls = findClassInGlobals(interp, "Set")
            if setCls != nil and not (setCls.name in visited):
              result.add(setCls)

  proc synthesizeClassAndMethodNodes*(app: Instance, classes: seq[Class],
                                       interp: Interpreter): seq[Node] =
    ## Synthesize AST nodes from live VM class model for the genModule pipeline.
    ## Creates class definition and method definition nodes that genModule can process.
    ## Also creates top-level main entry point code.
    let appName = getSlotValue(app, 0).strVal
    let appClass = app.class
    var nodes: seq[Node] = @[]

    # For each method on the Application class, generate a method body call in main
    # We synthesize top-level statements that genModule will put into main()

    if appClass != nil:
      # Synthesize: appInstance := ClassName new
      # For now, just echo the app name and call main:
      let echoNode = MessageNode(
        receiver: LiteralNode(value: NodeValue(kind: vkString, strVal: "Application: " & appName)),
        selector: "println",
        arguments: @[]
      )
      nodes.add(echoNode)

      # Generate method calls by inlining the main: method body
      if "main:" in appClass.allMethods:
        let mainMethod = appClass.allMethods["main:"]
        for stmt in mainMethod.body:
          nodes.add(stmt)

    return nodes

  # Primitive: Granite class>>build: application
  proc graniteBuildImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
    ## Build an Application to binary using the shared genModule pipeline
    if args.len < 1 or args[0].kind != vkInstance:
      return NodeValue(kind: vkString, strVal: "Error: Expected Application instance")

    let app = args[0].instVal

    # Get application name from slot 0
    let nameVal = getSlotValue(app, 0)
    if nameVal.kind != vkString:
      return NodeValue(kind: vkString, strVal: "Error: Application name not set")
    let appName = nameVal.strVal

    if currentInterpreter == nil:
      return NodeValue(kind: vkString, strVal: "Error: No interpreter context")

    # Collect transitive classes
    let classes = collectTransitiveClasses(app, currentInterpreter)

    # Synthesize AST nodes from live VM and use shared genModule pipeline
    let nodes = synthesizeClassAndMethodNodes(app, classes, currentInterpreter)

    let outputDir = "./build"
    var ctx = newCompiler(outputDir, appName)
    let nimCode = genModule(ctx, nodes, appName, injectMainArgsVar = true)

    # Write to file
    let nimPath = outputDir / appName & ".nim"

    try:
      createDir(outputDir)
      writeFile(nimPath, nimCode)
    except CatchableError as e:
      return NodeValue(kind: vkString, strVal: "Error writing file: " & e.msg)

    # Compile with Nim
    let binaryPath = outputDir / appName
    let cmd = fmt("nim c -o:{binaryPath} {nimPath}")

    let exitCode = execShellCmd(cmd)

    if exitCode == 0:
      return NodeValue(kind: vkString, strVal: "Build successful: " & binaryPath)
    else:
      return NodeValue(kind: vkString, strVal: "Build failed with exit code: " & $exitCode)
