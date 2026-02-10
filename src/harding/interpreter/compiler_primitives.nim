## Compiler Primitives for Granite
## Exposes compilation functionality as Harding primitives

when defined(granite):
  import std/[os, strutils, strformat, tables, sets, hashes]
  import ../core/types
  import ../parser/parser
  import ../parser/lexer
  import ../codegen/module
  import ../compiler/context
  import ../compiler/codegen
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

    ClassInfoEx* = ref object
      class*: Class
      name*: string
      superClass*: string
      classMethods*: seq[tuple[selector: string, meth: BlockNode]]

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

  proc generateClassType*(cls: Class): string =
    ## Generate Nim type definition for a Harding class
    var output = "# " & cls.name & " class type\n"
    output.add("type\n")
    output.add("  " & cls.name & "Obj* = object\n")

    # Add slots as fields (using allSlotNames for complete instance layout)
    if cls.allSlotNames.len > 0:
      for slot in cls.allSlotNames:
        output.add("    " & slot & "*: NodeValue\n")
    else:
      output.add("    # No slots defined\n")

    output.add("\n")
    output.add("  " & cls.name & "* = ref " & cls.name & "Obj\n\n")
    return output

  proc generateMethodImpl*(cls: Class, selector: string, meth: BlockNode): string =
    ## Generate Nim method implementation from Harding AST
    var output = ""

    # Generate method signature
    let safeSelector = selector.replace(":", "_")
    output.add("proc " & cls.name & "_" & safeSelector & "*(self: " & cls.name)

    # Add parameters
    for param in meth.parameters:
      output.add(", " & param & ": NodeValue")
    output.add("): NodeValue =\n")

    output.add("  ## Compiled method: " & selector & "\n")

    # Generate temporaries
    if meth.temporaries.len > 0:
      output.add("  # Temporaries\n")
      for temp in meth.temporaries:
        output.add("  var " & temp & " = NodeValue(kind: vkNil)\n")
      output.add("\n")

    # Generate body (simplified for now)
    if meth.body.len == 0:
      output.add("  return NodeValue(kind: vkNil)\n")
    else:
      # For now, generate a placeholder that uses runtime dispatch
      output.add("  # Method body (runtime dispatch for now)\n")
      output.add("  echo \"Calling " & selector & " on \" & $(self[])\n")
      output.add("  return NodeValue(kind: vkNil)\n")

    output.add("\n")
    return output

  proc generateApplicationCode*(app: Instance, classes: seq[Class], interp: Interpreter): string =
    ## Generate Nim code for the application
    let appName = getSlotValue(app, 0).strVal
    let appClass = app.class

    var output = "## Generated by Granite Compiler\n"
    output.add("## Application: " & appName & "\n\n")

    output.add("import std/[os, tables, sequtils]\n")
    output.add("import ../src/harding/core/[types]\n")
    output.add("import ../src/harding/interpreter/[objects]\n\n")

    # Generate type definitions for each class
    output.add("# Class Type Definitions\n")
    output.add("# =====================\n\n")
    for cls in classes:
      output.add(generateClassType(cls))

    # Generate method implementations
    output.add("# Method Implementations\n")
    output.add("# =====================\n\n")

    # Generate methods for Application class
    if appClass != nil:
      for selector, meth in appClass.methods:
        output.add(generateMethodImpl(appClass, selector, meth))

      # Also generate inherited methods from allMethods
      for selector, meth in appClass.allMethods:
        if selector notin appClass.methods:
          output.add(generateMethodImpl(appClass, selector, meth))

    # Generate main entry point
    output.add("# Main Entry Point\n")
    output.add("# ================\n\n")
    output.add("proc main() =\n")
    output.add("  echo \"Application: " & appName & "\"\n")

    # Create Application instance
    if appClass != nil:
      output.add("\n  # Create Application instance\n")
      output.add("  var app = " & appClass.name & "()\n")

      # Set slots from the app instance
      if app.slots.len > 0 and appClass.allSlotNames.len > 0:
        output.add("\n  # Initialize slots\n")
        for i, slotVal in app.slots:
          if i < appClass.allSlotNames.len:
            let slotName = appClass.allSlotNames[i]
            case slotVal.kind
            of vkInt:
              output.add("  app." & slotName & " = NodeValue(kind: vkInt, intVal: " & $slotVal.intVal & ")\n")
            of vkString:
              let escaped = slotVal.strVal.replace("\"", "\\\"")
              output.add("  app." & slotName & " = NodeValue(kind: vkString, strVal: \"" & escaped & "\")\n")
            else:
              output.add("  app." & slotName & " = NodeValue(kind: vkNil)\n")

      # Call main: method with args
      output.add("\n  # Call main: method\n")
      output.add("  let args = NodeValue(kind: vkArray, arrayVal: @[])\n")
      output.add("  discard " & appClass.name & "_main_(app, args)\n")

    output.add("\nwhen isMainModule:\n")
    output.add("  main()\n")

    return output

  # Primitive: Granite class>>build: application
  proc graniteBuildImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
    ## Build an Application to binary
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

    # Generate code
    let nimCode = generateApplicationCode(app, classes, currentInterpreter)

    # Write to file
    let outputDir = "./build"
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
