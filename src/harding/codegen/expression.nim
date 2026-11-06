import std/[strutils, sequtils, strformat, tables]
import ../core/types
import ../compiler/context
import ../compiler/types
import ../compiler/symbols
import ../compiler/primitive_abi
import ./blocks
import ./numeric

# ============================================================================
# Expression Code Generation
# Generates Nim code from AST expressions
# ============================================================================

type
  VarTypeInfo* = object
    ## Type information for a variable
    name*: string          ## Variable name
    className*: string     ## Class name (e.g., "Person", "Array", etc.)
    isNativeClass*: bool   ## Whether this is a native compiled class

  GenContext* = ref object
    cls*: ClassInfo
    inBlock*: bool
    returnTarget*: string         ## Expression identifying a block's home activation
    inMethod*: bool              ## Whether we're generating code inside a method body
    cellNames*: seq[string]       ## Lexical bindings shared with compiled blocks
    locals*: seq[string]          ## Local variable names (temporaries)
    parameters*: seq[string]      ## Parameter names
    globals*: seq[string]         ## Known global variable names
    blockRegistry*: BlockRegistry ## Registry for blocks to compile
    varTypes*: Table[string, VarTypeInfo]  ## Variable name -> type info
    compiledClasses*: seq[string] ## Names of classes being compiled (for native instantiation)
    exceptionClassNames*: seq[string] ## Exception classes referenced by name, resolved to class values
    classInfo*: Table[string, ClassInfo]   ## Class name -> ClassInfo with slot info
    mixed*: bool                  ## Whether mixed mode is enabled (fallback to interpreter)
    numericBindings*: NumericBindings ## Proven lexical native representations
    suppressSlotArithmetic: bool
    ## Advisory inference results: slot name -> kind, used only to emit *guarded*
    ## native arithmetic. Storage is never narrowed, so a wrong candidate costs
    ## speed and never correctness.
    inferredNumericSlots*: Table[string, NumericRepresentation]
    directSendCandidates*: Table[string, string] ## Selector -> guarded generated helper
    integerSendCandidates*: Table[string, string] ## Selector -> guarded Integer region
    ## "Class>>selector" -> native entry for a class method whose body provably
    ## ignores its receiver; a call site guards the class object and registration.
    staticClassCalls*: Table[string, string]
    ## Set while generating a class-site fallback, so the ordinary send is
    ## emitted instead of recursing into the same specialization.
    suppressClassSite*: bool

# Forward declaration
proc genExpression*(ctx: GenContext, node: Node): string
proc genStatement*(ctx: GenContext, node: Node): string
proc asBlockNode(node: Node): BlockNode
proc isBlockWithCaptures*(ctx: GenContext, node: Node): tuple[isBlock: bool, blockInfo: BlockProcInfo]

proc exceptionNamesUnder(classInfo: Table[string, ClassInfo]): seq[string] =
  ## Names of every class in the parse tree that descends from Exception, plus the
  ## exception roots themselves. Codegen must resolve these to class values rather
  ## than to symbols, or an on:do: handler never matches the signalled instance.
  ## Deriving the set from the hierarchy keeps new exception classes working
  ## without editing a list here.
  # Builtin exception classes the runtime knows even when the script does not
  # define them (see compiledExceptionClassValue in runtime.nim). Keep this in
  # step with that registration.
  result = @["Exception", "Error", "Notification", "ArithmeticError",
             "DivisionByZero", "Overflow", "NotFound", "SubscriptOutOfBounds",
             "MessageNotUnderstood", "BlockCannotReturn", "UnhandledError",
             "LoadError"]
  for name, info in classInfo:
    var current = info
    var isException = false
    var guard = 0
    while current != nil and guard < 64:
      if current.name in ["Exception"]:
        isException = true
        break
      current = current.parent
      inc guard
    if isException and name notin result:
      result.add(name)

proc newGenContext*(cls: ClassInfo = nil, compiledClasses: seq[string] = @[],
                    classInfo: Table[string, ClassInfo] = initTable[string, ClassInfo](),
                    mixed: bool = false): GenContext =
  ## Create new generation context
  result = GenContext(
    cls: cls,
    inBlock: false,
    inMethod: false,
    locals: @[],
    parameters: @[],
    globals: @[],
    blockRegistry: newBlockRegistry(),
    varTypes: initTable[string, VarTypeInfo](),
    numericBindings: initTable[string, NumericRepresentation](),
    compiledClasses: compiledClasses,
    exceptionClassNames: exceptionNamesUnder(classInfo),
    classInfo: classInfo,
    mixed: mixed
  )

proc indentBlock*(code: string, spaces: int = 2): string =
  ## Indent each non-empty line of multi-line code by the given number of spaces
  let prefix = " ".repeat(spaces)
  for line in code.splitLines():
    if line.len > 0:
      result.add(prefix & line & "\n")

proc isLocal*(ctx: GenContext, name: string): bool =
  ## Check if name is a local variable or parameter
  return name in ctx.locals or name in ctx.parameters

proc isSlot*(ctx: GenContext, name: string): bool =
  ## Check if name is a slot in the current class
  if ctx.cls == nil:
    return false
  return ctx.cls.getSlotIndex(name) >= 0

proc directSlotPrefix(ctx: GenContext, name: string): string =
  mangleClass(ctx.cls.name) & "_direct_" & mangleSlot(name)

proc slotRead(ctx: GenContext, name: string): string =
  if not ctx.mixed and ctx.cls != nil and ctx.cls.name in ctx.compiledClasses:
    return directSlotPrefix(ctx, name) & "_read(self)"
  fmt("getSlotValue(self, \"{name}\")")

proc slotWrite(ctx: GenContext, name, value: string): string =
  if not ctx.mixed and ctx.cls != nil and ctx.cls.name in ctx.compiledClasses:
    return directSlotPrefix(ctx, name) & "_write(self, " & value & ")"
  fmt("setSlotValue(self, \"{name}\", {value})")

proc getSlotIndex*(ctx: GenContext, name: string): int =
  ## Get slot index for name, returns -1 if not a slot
  if ctx.cls == nil:
    return -1
  return ctx.cls.getSlotIndex(name)

proc setVariableType*(ctx: GenContext, varName: string, className: string, isNative = true) =
  ## Set the type of a variable to a specific class
  ctx.varTypes[varName] = VarTypeInfo(
    name: varName,
    className: className,
    isNativeClass: isNative
  )


proc inferTypeFromExpression*(ctx: GenContext, node: Node): VarTypeInfo =
  ## Infer the type of an expression
  ## Returns VarTypeInfo with isNativeClass=true only for native constructors
  if node == nil:
    return VarTypeInfo(name: "", className: "", isNativeClass: false)
  
  case node.kind
  of nkMessage:
    let msg = node.MessageNode
    # Check for "Class new" pattern where Class is a compiled class
    # In this case we generate a native constructor call
    if msg.selector == "new" and msg.receiver != nil and msg.receiver.kind == nkIdent:
      let className = msg.receiver.IdentNode.name
      # Check if this class is being compiled (will use native constructor)
      let isNative = className in ctx.compiledClasses
      return VarTypeInfo(name: "", className: className, isNativeClass: isNative)
    
    # Check for other patterns that might indicate type
    elif msg.receiver != nil:
      let receiverType = ctx.inferTypeFromExpression(msg.receiver)
      if receiverType.className.len > 0:
        # Inherit native status from receiver for cascade patterns
        return receiverType
  of nkIdent:
    let varName = node.IdentNode.name
    if varName in ctx.varTypes:
      return ctx.varTypes[varName]
  else:
    discard
  
  return VarTypeInfo(name: "", className: "", isNativeClass: false)

proc escapeNimString*(s: string): string =
  ## Escape a string for use in Nim code
  ## Handles backslashes, quotes, and other special characters
  result = s
  # Escape backslashes first (before we add new ones)
  result = result.replace("\\", "\\\\")
  # Escape double quotes
  result = result.replace("\"", "\\\"")
  # Escape newlines
  result = result.replace("\n", "\\n")
  # Escape carriage returns
  result = result.replace("\r", "\\r")
  # Escape tabs
  result = result.replace("\t", "\\t")

proc genLiteral*(node: LiteralNode): string =
  ## Generate code for literal node
  let value = node.value
  case value.kind
  of vkInt:
    return fmt("NodeValue(kind: vkInt, intVal: {value.intVal})")
  of vkFloat:
    return fmt("NodeValue(kind: vkFloat, floatVal: {value.floatVal})")
  of vkString:
    let escaped = escapeNimString(value.strVal)
    return fmt("NodeValue(kind: vkString, strVal: \"{escaped}\")")
  of vkSymbol:
    # Symbols need runtime lookup
    let escaped = escapeNimString(value.symVal)
    return fmt("NodeValue(kind: vkSymbol, symVal: \"{escaped}\")")
  of vkBool:
    return fmt("NodeValue(kind: vkBool, boolVal: {value.boolVal})")
  of vkNil:
    return "NodeValue(kind: vkNil)"
  of vkInstance:
    return "self.toValue()"
  else:
    return "NodeValue(kind: vkNil)"

proc genNodeValueLiteral*(val: NodeValue): string =
  ## Generate Nim code for a pre-computed NodeValue.
  ## Used for constant array/table literals.
  case val.kind
  of vkInt:
    return fmt("NodeValue(kind: vkInt, intVal: {val.intVal})")
  of vkFloat:
    return fmt("NodeValue(kind: vkFloat, floatVal: {val.floatVal})")
  of vkString:
    let escaped = escapeNimString(val.strVal)
    return fmt("NodeValue(kind: vkString, strVal: \"{escaped}\")")
  of vkSymbol:
    let escaped = escapeNimString(val.symVal)
    return fmt("NodeValue(kind: vkSymbol, symVal: \"{escaped}\")")
  of vkBool:
    return fmt("NodeValue(kind: vkBool, boolVal: {val.boolVal})")
  of vkNil:
    return "NodeValue(kind: vkNil)"
  of vkArray:
    var elems: seq[string] = @[]
    for elem in val.arrayVal:
      elems.add(genNodeValueLiteral(elem))
    return fmt("compiledArray(@[{elems.join(\", \")}])")
  of vkTable:
    var entries: seq[string] = @[]
    for key, v in val.tableVal.pairs:
      entries.add(fmt("({genNodeValueLiteral(key)}, {genNodeValueLiteral(v)})"))
    return fmt("nt_tableFrom([{entries.join(\", \")}])")
  else:
    return "NodeValue(kind: vkNil)"

proc captureCellNames*(registry: BlockRegistry): seq[string] =
  ## Names requiring cells in scopes that bind them.
  if registry != nil:
    for info in registry.blocks:
      for name in info.captures:
        if name != "self" and name notin result:
          result.add(name)

proc scopeCaptureCellNames*(body: seq[Node], ownerLocalNames: seq[string] = @[]): seq[string] =
  ## Analyze only blocks lexically contained in this body.
  let registry = newBlockRegistry()
  let locals = scopeLocalNames(body, ownerLocalNames)
  for node in body:
    collectBlocks(registry, node, ownerLocalNames = locals)
  return captureCellNames(registry)

proc bindingTarget(ctx: GenContext, name: string): string =
  if name in ctx.cellNames:
    return mangleIdentifier(name) & ".value"
  return mangleIdentifier(name)

proc bindingAssignmentValue(ctx: GenContext, name, value: string): string =
  case ctx.numericBindings.getOrDefault(name, nrDynamic)
  of nrInt: "(" & value & ").intVal"
  of nrFloat: "(" & value & ").floatVal"
  else: value

proc bindingDeclaration(ctx: GenContext, name, value: string): string =
  let identifier = mangleIdentifier(name)
  if name in ctx.numericBindings:
    return fmt("var {identifier} = {bindingAssignmentValue(ctx, name, value)}")
  if name in ctx.cellNames:
    return fmt("var {identifier} = MutableCell(value: {value})")
  return fmt("var {identifier} = {value}")

proc genLocalDeclarations*(ctx: GenContext, names: seq[string]): string =
  ## Declare lexical temporaries before evaluating a scope's body.
  for name in names:
    if not ctx.isLocal(name):
      ctx.locals.add(name)
      case ctx.numericBindings.getOrDefault(name, nrDynamic)
      of nrInt:
        result.add(fmt("var {mangleIdentifier(name)} = 0\n"))
      of nrFloat:
        result.add(fmt("var {mangleIdentifier(name)} = 0.0\n"))
      else:
        result.add(bindingDeclaration(ctx, name, "NodeValue(kind: vkNil)") & "\n")

proc inlineBlockContext(ctx: GenContext, blk: BlockNode): GenContext =
  result = newGenContext(ctx.cls, ctx.compiledClasses, ctx.classInfo, ctx.mixed)
  result.inMethod = ctx.inMethod
  result.directSendCandidates = ctx.directSendCandidates
  result.integerSendCandidates = ctx.integerSendCandidates
  result.staticClassCalls = ctx.staticClassCalls
  result.inBlock = ctx.inBlock
  result.returnTarget = ctx.returnTarget
  result.blockRegistry = ctx.blockRegistry
  result.varTypes = ctx.varTypes
  result.numericBindings = ctx.numericBindings
  result.globals = ctx.globals
  result.cellNames = ctx.cellNames
  for name in ctx.locals:
    if name notin blk.temporaries and name notin blk.parameters:
      result.locals.add(name)
  for name in ctx.parameters:
    if name notin blk.temporaries and name notin blk.parameters:
      result.parameters.add(name)
  for name in scopeCaptureCellNames(blk.body):
    if name notin result.cellNames:
      result.cellNames.add(name)

proc inlineBlockStatements(ctx: GenContext, blk: BlockNode): string =
  let bodyCtx = inlineBlockContext(ctx, blk)
  result = "block:\n"
  result.add(indentBlock(genLocalDeclarations(bodyCtx, blk.temporaries)))
  for statement in blk.body:
    result.add(indentBlock(genStatement(bodyCtx, statement)))
  if blk.body.len == 0 and blk.temporaries.len == 0:
    result.add("  discard\n")

proc inlineBlockExpression(ctx: GenContext, blk: BlockNode): string =
  let bodyCtx = inlineBlockContext(ctx, blk)
  result = "(block:\n"
  result.add(indentBlock(genLocalDeclarations(bodyCtx, blk.temporaries), 4))
  for i, statement in blk.body:
    if i == blk.body.high:
      result.add(indentBlock(genExpression(bodyCtx, statement), 4))
    else:
      result.add(indentBlock(genStatement(bodyCtx, statement), 4))
  if blk.body.len == 0:
    result.add("    nilValue()\n")
  result.add(")")

proc genGlobalAssignment(ctx: GenContext, name, value: string): string =
  if ctx.inMethod and not ctx.mixed and name.len > 0 and name[0] in {'A'..'Z'}:
    return fmt("(block:\n    let assignedValue = {value}\n    let binding = boundGlobalWrite(self, \"{name}\", assignedValue)\n    if binding.handled: binding.value else: setGlobal(\"{name}\", assignedValue))")
  return fmt("setGlobal(\"{name}\", {value})")

proc genUnboundSymbolAccess(ctx: GenContext, name: string): string =
  ## Generate code for symbol/variable access
  ## Priority: parameters > locals > slots > globals

  if name == "self":
    if name in ctx.cellNames:
      return "self.value"
    if ctx.inMethod:
      return "self"
    else:
      return "self.toValue()"

  if name == "nil":
    return "NodeValue(kind: vkNil)"

  if name == "true":
    return "NodeValue(kind: vkBool, boolVal: true)"

  if name == "false":
    return "NodeValue(kind: vkBool, boolVal: false)"

  # Check if it's a parameter
  if name in ctx.parameters:
    return bindingTarget(ctx, name)

  # Check if it's a local variable
  if name in ctx.locals:
    case ctx.numericBindings.getOrDefault(name, nrDynamic)
    of nrInt: return fmt("NodeValue(kind: vkInt, intVal: {mangleIdentifier(name)})")
    of nrFloat: return fmt("NodeValue(kind: vkFloat, floatVal: {mangleIdentifier(name)})")
    else: return bindingTarget(ctx, name)

  # Check if it's a slot
  if ctx.cls != nil:
    let slotIdx = ctx.cls.getSlotIndex(name)
    if slotIdx >= 0:
      if ctx.inMethod:
        return slotRead(ctx, name)
      return fmt("self.slots[{slotIdx}]")

  if not ctx.mixed and name in ctx.exceptionClassNames:
    return fmt("compiledExceptionClassValue(\"{name}\")")

  if name in ctx.compiledClasses and not ctx.mixed:
    return fmt("compiledClassValue(\"{name}\")")

  if name in ["Root", "Object", "Mixin"] and not ctx.mixed:
    return fmt("compiledBaseClassValue(\"{name}\")")

  if name == "System" and not ctx.mixed:
    return "compiledSystemClassValue()"

  if name == "Log" and not ctx.mixed:
    return "compiledLogClassValue()"

  if name == "Json" and not ctx.mixed:
    return "compiledJsonClassValue()"

  if name == "File" and not ctx.mixed:
    return "compiledFileClassValue()"

  # Check if it's a known global (class or global variable)
  if name in ctx.globals:
    # Globals are stored in a globals table
    return fmt("getGlobal(\"{name}\")")

  # Fallback: treat as symbol
  return fmt("NodeValue(kind: vkSymbol, symVal: \"{name}\")")

proc genSymbolAccess*(ctx: GenContext, name: string): string =
  ## Lexical locals/slots win; bound uppercase globals are looked up at each use.
  let fallback = genUnboundSymbolAccess(ctx, name)
  if ctx.inMethod and not ctx.mixed and name.len > 0 and name[0] in {'A'..'Z'} and
     not ctx.isLocal(name) and not ctx.isSlot(name):
    let owner = genUnboundSymbolAccess(ctx, "self")
    return fmt("(block:\n    let binding = boundGlobalValue({owner}, \"{name}\")\n    if binding.handled: binding.value else: {fallback})")
  return fallback

proc tryGenerateNamedAccess*(ctx: GenContext, node: NamedAccessNode, receiverCode: string): string =
  ## Try to generate direct access for named access on known compiled classes.
  let receiverType = ctx.inferTypeFromExpression(node.receiver)
  if receiverType.className.len == 0:
    return ""
  if ctx.mixed:
    return ""
  if not receiverType.isNativeClass:
    return ""
  if receiverType.className notin ctx.classInfo:
    return ""

  let classDef = ctx.classInfo[receiverType.className]
  var slotFound = false
  for slot in classDef.getAllSlots():
    if slot.name == node.memberName:
      slotFound = true
      break

  if not slotFound:
    return ""

  if node.isAssignment and node.valueExpr != nil:
    let valueCode = genExpression(ctx, node.valueExpr)
    return fmt("compiledNamedAccess({receiverCode}, \"{node.memberName}\", {valueCode}, true)")
  return fmt("compiledNamedAccess({receiverCode}, \"{node.memberName}\")")

proc genCapturedBlockExpression(blockInfo: BlockProcInfo, ctx: GenContext): string =
  ## Generate expression-safe block creation for captured blocks.
  var initFields: seq[string] = @[]
  if blockInfo.ownerMethodId != 0:
    initFields.add("home: hardingHome")
  for capture in blockInfo.captures:
    let cell = if ctx.isLocal(capture) and capture in ctx.cellNames:
                 mangleIdentifier(capture)
               else:
                 fmt("MutableCell(value: {genSymbolAccess(ctx, capture)})")
    initFields.add(fmt("{mangleIdentifier(capture)}: {cell}"))

  let fieldsStr = initFields.join(", ")
  return fmt("(block:\n    createBlockWithEnv({blockInfo.nimName}, {blockInfo.paramCount}, {blockInfo.envStructName}({fieldsStr})))")

proc genSend(ctx: GenContext, receiverCode, selector: string,
             arguments: seq[string]): string =
  ## Ordinary send with an already-generated receiver. Mixed mode keeps the
  ## hybrid entry point, method bodies route through the host, and top-level code
  ## uses the per-site cache.
  let args = arguments.join(", ")
  if ctx.mixed:
    return fmt("sendMessageHybrid({receiverCode}, \"{escapeNimString(selector)}\", @[{args}])")
  if ctx.inMethod:
    let owner = genSymbolAccess(ctx, "self")
    return fmt("sendMessageBound({owner}, {receiverCode}, \"{escapeNimString(selector)}\", @[{args}])")
  return fmt("cachedSend(currentRuntime[], {receiverCode}, \"{escapeNimString(selector)}\", @[{args}])")

proc isReusableOperand(code: string): bool =
  ## True when re-reading the operand has no observable effect: a plain local or
  ## parameter name, or a literal. Such an operand needs no `let` binding, which
  ## avoids a NodeValue copy at every builtin operation on the hot path.
  if code.len == 0:
    return false
  var start = 0
  if code[0] == '-':
    start = 1
  if start >= code.len:
    return false
  # Numeric literal.
  var digits = true
  for ch in code[start..^1]:
    if ch notin {'0'..'9', '.'}:
      digits = false
      break
  if digits:
    return true
  # Bare identifier (a local, parameter or global read).
  if code[0] notin {'A'..'Z', 'a'..'z', '_'}:
    return false
  for ch in code:
    if ch notin {'A'..'Z', 'a'..'z', '0'..'9', '_'}:
      return false
  return true

proc genHostedBuiltin(ctx: GenContext, receiverCode, selector, helper: string,
                      arguments: seq[string] = @[]): string =
  ## Evaluate operands once, left to right, before selecting an engine. Operands
  ## that cannot have effects (names, literals) are passed through directly rather
  ## than copied into a binding.
  if not ctx.inMethod:
    return helper & "(" & (@[receiverCode] & arguments).join(", ") & ")"
  let owner = genSymbolAccess(ctx, "self")
  var receiverRef = "hardingBuiltinReceiver"
  result = "(block:\n"
  if isReusableOperand(receiverCode):
    receiverRef = receiverCode
  else:
    result.add("    let hardingBuiltinReceiver = " & receiverCode.replace("\n", "\n    ") & "\n")
  var boundArguments: seq[string]
  for index, argument in arguments:
    if isReusableOperand(argument):
      boundArguments.add(argument)
    else:
      let temporary = "hardingBuiltinArg" & $index
      result.add("    let " & temporary & " = " & argument.replace("\n", "\n    ") & "\n")
      boundArguments.add(temporary)
  let argsCode = "@[" & boundArguments.join(", ") & "]"
  let fallback = helper & "(" & (@[receiverRef] & boundArguments).join(", ") & ")"
  result.add(fmt("    let builtin = hostedBuiltinDeferred({owner}, {receiverRef}, \"{escapeNimString(selector)}\", {argsCode})\n    if builtin.handled: builtin.value else: {fallback})"))

proc nativeNumericExpression(ctx: GenContext, node: Node): string =
  case node.kind
  of nkLiteral:
    let value = node.LiteralNode.value
    if value.kind == vkInt:
      return $value.intVal
    return $value.floatVal
  of nkIdent:
    let name = node.IdentNode.name
    if not ctx.isLocal(name) and ctx.isSlot(name):
      let clsName = mangleClass(ctx.cls.name)
      let field = mangleSlot(name)
      let slot = ctx.cls.getSlotDef(name)
      let access = fmt("{clsName}(self.instVal.compiledOwner)[].{field}")
      # A declared numeric slot already has a native field, so it is used
      # directly. Only an inferred slot is still a NodeValue and needs unboxing,
      # which the emitted kind guard has already proven safe.
      case slot.constraint
      of tcInt, tcFloat: return access
      else:
        let kind = ctx.inferredNumericSlots.getOrDefault(name, nrDynamic)
        return case kind
          of nrInt: fmt("{access}.intVal")
          of nrFloat: fmt("{access}.floatVal")
          else: access
    return mangleIdentifier(name)
  of nkMessage:
    let message = node.MessageNode
    let left = nativeNumericExpression(ctx, message.receiver)
    let right = nativeNumericExpression(ctx, message.arguments[0])
    let op = case message.selector
             of "=", "==": "=="
             of "~=": "!="
             else: message.selector
    return fmt("({left} {op} {right})")
  else:
    return ""

proc nativeBoolCondition(ctx: GenContext, node: Node): string =
  ## A raw `bool` expression when the condition is provably Boolean. Boxing a
  ## bool into a NodeValue and calling isTruthy on every loop iteration is pure
  ## overhead once the kind is known, so skip both. Returns "" when unsure, and
  ## the caller keeps the generic isTruthy path.
  if node == nil or ctx.mixed: return ""
  if numericKind(node, ctx.numericBindings) != nrBool: return ""
  let native = nativeNumericExpression(ctx, node)
  if native.len == 0 or native == "()": return ""
  native

proc conditionBody(node: Node): Node =
  ## Conditions arrive wrapped in the block that supplies them; a single-statement
  ## block is the condition expression itself.
  if node == nil: return nil
  if node.kind == nkBlock:
    if node.BlockNode.body.len == 1: return node.BlockNode.body[0]
    return nil
  if node.kind == nkLiteral and node.LiteralNode.value.kind == vkBlock:
    let literalBlock = node.LiteralNode.value.blockVal
    if literalBlock != nil and literalBlock.body.len == 1: return literalBlock.body[0]
    return nil
  node

proc conditionClause(ctx: GenContext, conditionNode: Node, fallback: string,
                      negate = false): tuple[code: string, native: bool] =
  ## Prefer an unboxed boolean condition; otherwise keep isTruthy semantics,
  ## which also preserves the "conditional requires Boolean" error.
  let nativeCond = nativeBoolCondition(ctx, conditionBody(conditionNode))
  if nativeCond.len > 0:
    return ((if negate: "not (" & nativeCond & ")" else: nativeCond), true)
  if negate:
    return ("not isTruthy(" & fallback & ")", false)
  ("isTruthy(" & fallback & ")", false)

proc nativeIntArgument*(ctx: GenContext, node: Node, guards: var seq[string]): string =
  ## Emit an unboxed Integer expression for a call-site argument, or "" when the
  ## argument is not provably an Integer. Every slot read contributes a guard for
  ## its accessor, so a redirected accessor keeps the ordinary boxed send.
  if node == nil: return ""
  case node.kind
  of nkLiteral:
    if node.LiteralNode.value.kind == vkInt: return $node.LiteralNode.value.intVal
  of nkIdent:
    let name = node.IdentNode.name
    if ctx.numericBindings.getOrDefault(name) == nrInt:
      return mangleIdentifier(name)
    # A slot named by an identifier (the pipeline sometimes leaves slot reads as
    # plain identifiers) is usable only when declared Integer on this class.
    if ctx.cls != nil and ctx.cls.name in ctx.compiledClasses and ctx.inMethod:
      for slot in ctx.cls.getAllSlots():
        if slot.name == name and slot.constraint == tcInt:
          let guard = mangleClass(ctx.cls.name) & "_direct_" & mangleSlot(name) & "_guard"
          if guard & "(self)" notin guards: guards.add(guard & "(self)")
          return "cast[" & mangleClass(ctx.cls.name) & "](self.instVal.compiledOwner)[]." &
                 mangleSlot(name)
  of nkSlotAccess:
    let slotNode = node.SlotAccessNode
    if not slotNode.isAssignment and ctx.cls != nil and
       ctx.cls.name in ctx.compiledClasses:
      var name = slotNode.slotName
      if name.len == 0:
        for slot in ctx.cls.getAllSlots():
          if slot.index == slotNode.slotIndex: name = slot.name
      if name.len > 0:
        for slot in ctx.cls.getAllSlots():
          if slot.name == name and slot.constraint == tcInt:
            let guard = mangleClass(ctx.cls.name) & "_direct_" & mangleSlot(name) & "_guard"
            if guard & "(self)" notin guards: guards.add(guard & "(self)")
            return "cast[" & mangleClass(ctx.cls.name) & "](self.instVal.compiledOwner)[]." &
                   mangleSlot(name)
  of nkMessage:
    let message = node.MessageNode
    if message.arguments.len == 1 and
       message.selector in ["+", "-", "*", "//"]:
      let left = nativeIntArgument(ctx, message.receiver, guards)
      let right = nativeIntArgument(ctx, message.arguments[0], guards)
      if left.len > 0 and right.len > 0:
        if message.selector == "//": return "compiledIntegerDiv(" & left & ", " & right & ")"
        return "(" & left & " " & message.selector & " " & right & ")"
  else: discard
  ""

proc genMessage*(ctx: GenContext, node: MessageNode): string =
  ## Generate code for message send

  # Generate receiver
  var receiverCode: string
  if node.receiver != nil:
    receiverCode = genExpression(ctx, node.receiver)
  else:
    # Implicit self - in method context use self directly, otherwise convert to value
    if ctx.inMethod:
      receiverCode = "self"
    else:
      receiverCode = "self.toValue()"

  # Check for native class instantiation: "ClassName new" where ClassName is compiled
  if node.selector == "new" and node.receiver != nil and node.receiver.kind == nkIdent:
    let className = node.receiver.IdentNode.name
    # A library class whose storage the runtime owns keeps allocation on the
    # runtime path; only classes with a generated layout get a guarded allocator.
    let hasGeneratedLayout = className in ctx.classInfo
    if className in ctx.compiledClasses and hasGeneratedLayout and
       not ctx.isLocal(className):
      # In mixed mode, use interpreter to create instances (ensures interpreter can call methods)
      if ctx.mixed:
        return fmt("sendMessageHybrid(hybridInterpreter.globals[\"{className}\"], \"new\", @[])")
      else:
        if ctx.inMethod:
          let owner = genSymbolAccess(ctx, "self")
          return fmt("guardedNew_{mangleClass(className)}({owner})")
        return fmt("guardedNew_{mangleClass(className)}()")

  # Check for inline control flow with literal blocks
  case node.selector
  of "ifTrue:ifFalse:":
    # Inline if/else when both blocks are literals
    if node.arguments.len >= 2 and
       node.arguments[0].kind == nkBlock and
       node.arguments[1].kind == nkBlock and
       not hasReturnNode(node.arguments[0]) and
       not hasReturnNode(node.arguments[1]):
      let thenBlock = node.arguments[0].BlockNode
      let elseBlock = node.arguments[1].BlockNode
      let clause = conditionClause(ctx, node.receiver, receiverCode)
      var code = "(if " & clause.code & ":\n"
      code.add(indentBlock(inlineBlockExpression(ctx, thenBlock), 6))
      code.add("    else:\n")
      code.add(indentBlock(inlineBlockExpression(ctx, elseBlock), 6))
      code.add("  )")
      return code

  of "ifTrue:":
    # Inline if when block is literal
    if node.arguments.len >= 1 and node.arguments[0].kind == nkBlock and
       not hasReturnNode(node.arguments[0]):
      let thenBlock = node.arguments[0].BlockNode
      let clause = conditionClause(ctx, node.receiver, receiverCode)
      var code = "(if " & clause.code & ":\n"
      code.add(indentBlock(inlineBlockExpression(ctx, thenBlock), 6))
      code.add("    else:\n")
      code.add("      nilValue()\n")
      code.add("  )")
      return code

  of "ifFalse:":
    # Inline ifFalse when block is literal
    if node.arguments.len >= 1 and node.arguments[0].kind == nkBlock and
       not hasReturnNode(node.arguments[0]):
      let thenBlock = node.arguments[0].BlockNode
      let clause = conditionClause(ctx, node.receiver, receiverCode, negate = true)
      var code = "(if " & clause.code & ":\n"
      code.add(indentBlock(inlineBlockExpression(ctx, thenBlock), 6))
      code.add("    else:\n")
      code.add("      nilValue()\n")
      code.add("  )")
      return code

  of "whileTrue:":
    # Inline whileTrue when body is a literal block (expression context - needs value)
    if node.arguments.len >= 1 and node.arguments[0].kind == nkBlock and
       not hasReturnNode(node.arguments[0]) and
       (node.receiver == nil or not hasReturnNode(node.receiver)):
      let bodyBlock = node.arguments[0].BlockNode
      var condCode = receiverCode
      if node.receiver != nil and node.receiver.kind == nkBlock:
        let condBlock = node.receiver.BlockNode
        if condBlock.body.len > 0:
          condCode = inlineBlockExpression(ctx, condBlock)
      let clause = conditionClause(ctx, node.receiver, condCode)
      var code = "(block:\n"
      code.add("    while " & clause.code & ":\n")
      code.add(indentBlock(inlineBlockStatements(ctx, bodyBlock), 6))
      code.add("    nilValue())")
      return code

  of "whileFalse:":
    # Inline whileFalse when body is a literal block (expression context - needs value)
    if node.arguments.len >= 1 and node.arguments[0].kind == nkBlock and
       not hasReturnNode(node.arguments[0]) and
       (node.receiver == nil or not hasReturnNode(node.receiver)):
      let bodyBlock = node.arguments[0].BlockNode
      var condCode = receiverCode
      if node.receiver != nil and node.receiver.kind == nkBlock:
        let condBlock = node.receiver.BlockNode
        if condBlock.body.len > 0:
          condCode = inlineBlockExpression(ctx, condBlock)
      let clause = conditionClause(ctx, node.receiver, condCode, negate = true)
      var code = "(block:\n"
      code.add("    while " & clause.code & ":\n")
      code.add(indentBlock(inlineBlockStatements(ctx, bodyBlock), 6))
      code.add("    nilValue())")
      return code

  else: discard

  if not ctx.mixed:
    if node.selector == "|" and node.arguments.len == 1:
      let argCode = genExpression(ctx, node.arguments[0])
      return genHostedBuiltin(ctx, receiverCode, "|", "nt_pipe", @[argCode])
    if node.selector == "not" and node.arguments.len == 0:
      return genHostedBuiltin(ctx, receiverCode, "not", "nt_not")

  case node.selector
  of "+", "-", "*", "/":
    # Binary operators - these are generated as function calls
    if node.arguments.len >= 1:
      let argCode = genExpression(ctx, node.arguments[0])
      return genHostedBuiltin(ctx, receiverCode, node.selector, mangleSelector(node.selector), @[argCode])
    return receiverCode

  of "<", "<=", ">", ">=", "=", "==", "~=", "<>":
    # Comparison operators
    if node.arguments.len >= 1:
      let argCode = genExpression(ctx, node.arguments[0])
      return genHostedBuiltin(ctx, receiverCode, node.selector, mangleSelector(node.selector), @[argCode])
    return receiverCode

  of "//", "\\", "%":
    # Integer division and modulo
    if node.arguments.len >= 1:
      let argCode = genExpression(ctx, node.arguments[0])
      return genHostedBuiltin(ctx, receiverCode, node.selector, mangleSelector(node.selector), @[argCode])
    return receiverCode

  of "at:":
    # Slot access or collection access
    if node.arguments.len >= 1:
      let argCode = genExpression(ctx, node.arguments[0])
      return genHostedBuiltin(ctx, receiverCode, "at:", mangleSelector(node.selector), @[argCode])
    return receiverCode

  of "at:put:":
    # Slot/collection assignment
    if node.arguments.len >= 2:
      let keyCode = genExpression(ctx, node.arguments[0])
      let valCode = genExpression(ctx, node.arguments[1])
      return genHostedBuiltin(ctx, receiverCode, "at:put:", mangleSelector(node.selector), @[keyCode, valCode])
    return receiverCode

  of "println", "writeLine:", "writeline:":
    # Object>>println and Object>>writeLine: are library methods; `writeline:`
    # is FileStream's own and must reach it. Printing is only the receiver's
    # own protocol here, so an explicit argument keeps the ordinary send.
    if node.arguments.len >= 1:
      return genSend(ctx, receiverCode, node.selector,
                     node.arguments.mapIt(genExpression(ctx, it)))
    return fmt("nt_println({receiverCode})")

  of "print":
    # Object>>print prints without a newline. `write:` is not an alias: it is
    # FileStream's and String's own selector and keeps ordinary dispatch.
    if node.arguments.len >= 1:
      return genSend(ctx, receiverCode, node.selector,
                     node.arguments.mapIt(genExpression(ctx, it)))
    return fmt("nt_print({receiverCode})")

  of "asString":
    return genHostedBuiltin(ctx, receiverCode, "asString", "nt_asString")

  of "&":
    # Generic concatenation via string conversion
    if node.arguments.len >= 1:
      let argCode = genExpression(ctx, node.arguments[0])
      return genHostedBuiltin(ctx, receiverCode, "&", "nt_comma", @[argCode])
    return receiverCode

  of "size":
    # Array/Table size
    return genHostedBuiltin(ctx, receiverCode, "size", "nt_size")

  of "last":
    # Array last element
    return genHostedBuiltin(ctx, receiverCode, "last", "nt_last")

  of "keys":
    # Table keys
    return genHostedBuiltin(ctx, receiverCode, "keys", "nt_table_keys")

  of "abs":
    return genHostedBuiltin(ctx, receiverCode, "abs", "nt_abs")

  of "even":
    return genHostedBuiltin(ctx, receiverCode, "even", "nt_even")

  of "odd":
    return genHostedBuiltin(ctx, receiverCode, "odd", "nt_odd")

  of "negated":
    return genHostedBuiltin(ctx, receiverCode, "negated", "nt_negated")


  of "derive:", "derive", "new", "selector:put:", "classSelector:put:":
    # Class-related messages - need runtime dispatch
    let args = node.arguments.mapIt(genExpression(ctx, it)).join(", ")
    let msgProc = if ctx.mixed: "sendMessageHybrid" else: "sendMessage"
    if ctx.mixed:
      return fmt("{msgProc}({receiverCode}, \"{escapeNimString(node.selector)}\", @[{args}])")
    else:
      if ctx.inMethod:
        let owner = genSymbolAccess(ctx, "self")
        return fmt("sendMessageBound({owner}, {receiverCode}, \"{escapeNimString(node.selector)}\", @[{args}])")
      return fmt("{msgProc}(currentRuntime[], {receiverCode}, \"{escapeNimString(node.selector)}\", @[{args}])")

  else:
    # Class-side Integer region: only a literal class receiver, and only when
    # every argument is already an Integer literal or Integer-typed local. The
    # sentinel expression re-runs the ordinary send when the guard fails, so
    # subclass overrides and replaced methods keep their semantics.
    var literalClass = ""
    if node.receiver != nil and node.receiver.kind == nkIdent:
      # Only a class constant spelling (uppercase initial) can be the receiver;
      # a local or parameter of that shape is excluded by the compiledClasses
      # test below.
      let spelled = node.receiver.IdentNode.name
      if spelled in ctx.compiledClasses:
        literalClass = spelled
    if not ctx.mixed and not ctx.suppressClassSite and literalClass.len > 0:
      let className = literalClass
      let key = className & ">>" & node.selector
      if key in ctx.staticClassCalls and
         node.arguments.len == node.selector.count(':'):
        var nativeArgs: seq[string]
        var guards: seq[string]
        var eligible = true
        for argument in node.arguments:
          let native = nativeIntArgument(ctx, argument, guards)
          if native.len == 0:
            eligible = false
            break
          nativeArgs.add(native)
        if eligible:
          let guardName = "guardStatic_" & mangleClass(className) & "_" & mangleSlot(node.selector)
          let call = ctx.staticClassCalls[key] & "(" & nativeArgs.join(", ") & ")"
          ctx.suppressClassSite = true
          let fallback = genExpression(ctx, node)
          ctx.suppressClassSite = false
          let condition = (@[guardName & "()"] & guards).join(" and ")
          # Re-run the ordinary send when any guard is cold, so overrides,
          # replaced class methods and redirected accessors keep their semantics.
          return "(block:\n    if " & condition & ": toValue(" & call & ")\n    else: " &
                 fallback & ")"
    if not ctx.mixed and node.arguments.len > 0 and
       node.arguments.len == node.selector.count(':') and
       node.selector in ctx.integerSendCandidates:
      let owner = if ctx.inMethod: genSymbolAccess(ctx, "self") else: "nilValue()"
      let operands = @[owner, receiverCode] & node.arguments.mapIt(genExpression(ctx, it))
      return ctx.integerSendCandidates[node.selector] & "(" & operands.join(", ") & ")"
    if not ctx.mixed and node.arguments.len == 0 and node.selector in ctx.directSendCandidates:
      let owner = if ctx.inMethod: genSymbolAccess(ctx, "self") else: "nilValue()"
      let helper = ctx.directSendCandidates[node.selector]
      return fmt("{helper}({owner}, {receiverCode})")
    # Mixed-mode dispatch retains its fallback; pure sends use a per-site cache.
    let args = node.arguments.mapIt(genExpression(ctx, it)).join(", ")
    if ctx.mixed:
      return fmt("sendMessageHybrid({receiverCode}, \"{escapeNimString(node.selector)}\", @[{args}])")
    if ctx.inMethod:
      let owner = genSymbolAccess(ctx, "self")
      # Method bodies are where hot sends live, so they get a per-site cache too;
      # the helper keeps the owner-based host routing for VM-owned receivers.
      return fmt("cachedSendBound({owner}, {receiverCode}, \"{escapeNimString(node.selector)}\", @[{args}])")
    return fmt("cachedSend(currentRuntime[], {receiverCode}, \"{escapeNimString(node.selector)}\", @[{args}])")

proc blockOwnerLocals*(ctx: GenContext): seq[string] =
  ## Parameters and locals declared in the enclosing method. These shadow
  ## same-named slots for nested blocks, so they must be captured as ordinary
  ## enclosing variables rather than resolved as slot accesses.
  for name in ctx.parameters:
    result.add(name)
  for name in ctx.locals:
    if name notin result:
      result.add(name)

proc blockOwnerSlots*(ctx: GenContext): seq[string] =
  ## Slot names of the class owning the enclosing method. Blocks lexically inside
  ## a method may read or write these, which requires capturing `self`.
  if ctx.cls != nil and ctx.inMethod:
    for slot in ctx.cls.getAllSlots():
      result.add(slot.name)

proc blockCaptureGlobals*(ctx: GenContext): seq[string] =
  ## Known globals to pass when registering a nested block. `self` is a
  ## pseudo-variable that block procedures receive through their captured
  ## environment, not a global, so it is deliberately excluded here: including it
  ## in knownGlobals suppresses the capture and leaves the generated block with
  ## no receiver.
  for name in ctx.globals:
    if name != "self":
      result.add(name)

proc slotNumericBindings(ctx: GenContext): NumericBindings =
  result = ctx.numericBindings
  if ctx.cls == nil or ctx.mixed or not ctx.inMethod:
    return
  for slot in ctx.cls.getAllSlots():
    if not ctx.isLocal(slot.name):
      case slot.constraint
      of tcInt: result[slot.name] = nrInt
      of tcFloat: result[slot.name] = nrFloat
      else:
        # Undeclared slot with an inferred candidate: still only a guard.
        if slot.name in ctx.inferredNumericSlots:
          result[slot.name] = ctx.inferredNumericSlots[slot.name]

proc numericSlotNode(ctx: GenContext, node: Node): Node =
  if node == nil: return nil
  if node.kind == nkSlotAccess and not node.SlotAccessNode.isAssignment:
    for slot in ctx.cls.getAllSlots():
      if slot.index == node.SlotAccessNode.slotIndex:
        return IdentNode(name: slot.name, localIndex: -1)
  if node.kind == nkMessage:
    let msg = node.MessageNode
    var args: seq[Node]
    for arg in msg.arguments: args.add(numericSlotNode(ctx, arg))
    return MessageNode(receiver: numericSlotNode(ctx, msg.receiver),
                       selector: msg.selector, arguments: args)
  return node

proc numericSlotNames(ctx: GenContext, node: Node): seq[string] =
  if node == nil: return
  if node.kind == nkIdent:
    let name = node.IdentNode.name
    if not ctx.isLocal(name) and ctx.isSlot(name): result.add(name)
  elif node.kind == nkMessage:
    result = numericSlotNames(ctx, node.MessageNode.receiver)
    for arg in node.MessageNode.arguments:
      for name in numericSlotNames(ctx, arg):
        if name notin result: result.add(name)

proc genExpression*(ctx: GenContext, node: Node): string =
  ## Dispatch to appropriate expression generator

  if node == nil:
    return "NodeValue(kind: vkNil)"

  if not ctx.suppressSlotArithmetic and ctx.cls != nil and not ctx.mixed and
     ctx.cls.name in ctx.compiledClasses:
    let numericNode = numericSlotNode(ctx, node)
    let slotNames = numericSlotNames(ctx, numericNode)
    let slotRepresentation = numericKind(numericNode, slotNumericBindings(ctx))
    if slotNames.len > 0 and slotRepresentation != nrDynamic:
      let native = nativeNumericExpression(ctx, numericNode)
      let tag = case slotRepresentation
                of nrInt: "intVal"
                of nrFloat: "floatVal"
                else: "boolVal"
      let kind = case slotRepresentation
                 of nrInt: "vkInt"
                 of nrFloat: "vkFloat"
                 else: "vkBool"
      var guards: seq[string]
      for name in slotNames:
        guards.add(directSlotPrefix(ctx, name) & "_guard(self)")
        # A declared slot already enforces its kind at write time. An inferred
        # one is still a NodeValue, so the fast path must check the tag itself.
        let slot = ctx.cls.getSlotDef(name)
        if slot.constraint notin {tcInt, tcFloat} and
           name in ctx.inferredNumericSlots:
          let field = mangleSlot(name)
          let expected = if slotRepresentation == nrFloat: "vkFloat" else: "vkInt"
          guards.add(fmt("{mangleClass(ctx.cls.name)}(self.instVal.compiledOwner)[].{field}.kind == {expected}"))
      ctx.suppressSlotArithmetic = true
      let fallback = genExpression(ctx, node)
      ctx.suppressSlotArithmetic = false
      return "(block:\n    if " & guards.join(" and ") & ":\n      NodeValue(kind: " & kind & ", " & tag & ": " & native & ")\n    else:\n" & indentBlock(fallback, 6).strip(leading = false, trailing = true) & ")"

  let representation = numericKind(node, ctx.numericBindings)
  if representation != nrDynamic:
    let native = nativeNumericExpression(ctx, node)
    case representation
    of nrInt: return fmt("NodeValue(kind: vkInt, intVal: {native})")
    of nrFloat: return fmt("NodeValue(kind: vkFloat, floatVal: {native})")
    of nrBool: return fmt("NodeValue(kind: vkBool, boolVal: {native})")
    else: discard

  case node.kind
  of nkLiteral:
    return genLiteral(node.LiteralNode)

  of nkIdent:
    return genSymbolAccess(ctx, node.IdentNode.name)

  of nkMessage:
    return genMessage(ctx, node.MessageNode)

  of nkIf:
    let conditional = node.IfNode
    let condition = genExpression(ctx, conditional.condition)
    let yes = asBlockNode(conditional.thenBranch)
    let no = asBlockNode(conditional.elseBranch)
    let yesCode = if yes != nil: inlineBlockExpression(ctx, yes) else: "nilValue()"
    let noCode = if no != nil: inlineBlockExpression(ctx, no) else: "nilValue()"
    return "(block:\n    if isTruthy(" & condition & "):\n" & indentBlock(yesCode, 8) &
           "    else:\n" & indentBlock(noCode, 8) & ")"

  of nkAssign:
    let assign = node.AssignNode
    let varName = assign.variable
    
    # Infer type from the expression being assigned
    let exprType = ctx.inferTypeFromExpression(assign.expression)
    if exprType.className.len > 0:
      ctx.setVariableType(varName, exprType.className, exprType.isNativeClass)
    
    let exprCode = genExpression(ctx, assign.expression)

    # Check if variable is a slot
    if ctx.isSlot(varName) and not ctx.isLocal(varName):
      if ctx.inMethod and ctx.cls != nil:
        return slotWrite(ctx, varName, exprCode)
      let idx = ctx.getSlotIndex(varName)
      return fmt("(proc(): NodeValue = self.slots[{idx}] = {exprCode}; return {exprCode})()")
    # Check if it's a local variable (reassignment)
    if ctx.isLocal(varName):
      return fmt("{bindingTarget(ctx, varName)} = {bindingAssignmentValue(ctx, varName, exprCode)}")

    # A Harding global (typically a top-level uppercase variable) assigns the
    # shared binding so main, methods and blocks all observe the same value.
    # Declaring a fresh local here would silently shadow it.
    if varName in ctx.globals or (ctx.inMethod and varName.len > 0 and varName[0] in {'A'..'Z'}):
      return genGlobalAssignment(ctx, varName, exprCode)

    # New local variable assignment
    ctx.locals.add(varName)
    return bindingDeclaration(ctx, varName, exprCode)

  of nkReturn:
    let ret = node.ReturnNode
    let valueCode = if ret.expression != nil: genExpression(ctx, ret.expression) else: "nilValue()"
    if ctx.inBlock and ctx.returnTarget.len > 0:
      return fmt("return raiseNonLocalReturn({ctx.returnTarget}, {valueCode})")
    return "return " & valueCode

  of nkArray:
    let arr = node.ArrayNode
    # Use pre-computed constant value if available
    if arr.isConstant and arr.elements.len > 0:
      return genNodeValueLiteral(arr.cachedValue)
    # A bare identifier inside an array literal is a symbol, never a variable
    # read: `#(name)` is `#(#name)`, matching the interpreter. A parenthesised
    # element `#((name))` is an ordinary expression.
    let elems = arr.elements.mapIt(
      if not arr.isDynamic and it != nil and it.kind == nkIdent and
         it.IdentNode.name notin ["true", "false", "nil"]:
        "NodeValue(kind: vkSymbol, symVal: \"" & escapeNimString(it.IdentNode.name) & "\")"
      else:
        genExpression(ctx, it)).join(", ")
    return fmt("compiledArray(@[{elems}])")

  of nkTable:
    let tbl = node.TableNode
    # Use pre-computed constant value if available
    if tbl.isConstant and tbl.entries.len > 0:
      return genNodeValueLiteral(tbl.cachedValue)
    # Table keys are ordinary expressions in both engines (unlike array
    # elements): `#{x -> 1}` uses the value of x as the key.
    var entries: seq[string] = @[]
    for (key, val) in tbl.entries:
      let keyCode = genExpression(ctx, key)
      let valCode = genExpression(ctx, val)
      entries.add(fmt("({keyCode}, {valCode})"))
    return fmt("nt_tableFrom([{entries.join(\", \")}])")

  of nkBlock:
    ## Look up or register the block for compilation and return creation code
    let blockNode = node.BlockNode
    let existingIdx = ctx.blockRegistry.findBlock(blockNode)
    let blockInfo = if existingIdx >= 0:
                      ctx.blockRegistry.blocks[existingIdx]
                    else:
                      registerBlock(ctx.blockRegistry, blockNode, blockCaptureGlobals(ctx), ctx.inMethod,
                                    blockOwnerSlots(ctx), blockOwnerLocals(ctx))

    if blockInfo.captures.len > 0 or blockInfo.ownerMethodId != 0:
      return genCapturedBlockExpression(blockInfo, ctx)
    else:
      return fmt("createBlock(cast[pointer]({blockInfo.nimName}), {blockInfo.paramCount})")

  of nkCascade:
    ## A cascade evaluates its receiver once, sends every collected message to
    ## that same value, and answers the last message's result. Earlier messages
    ## only run for their effects.
    let cascade = node.CascadeNode
    if cascade.receiver == nil or cascade.messages.len == 0:
      return genExpression(ctx, cascade.receiver)
    var code = "(block:\n    let hardingCascadeReceiver = " &
               genExpression(ctx, cascade.receiver).replace("\n", "\n    ") & "\n"
    for index, message in cascade.messages:
      let send = cast[MessageNode](message)
      let arguments = send.arguments.mapIt(genExpression(ctx, it))
      let sendCode = genSend(ctx, "hardingCascadeReceiver", send.selector, arguments)
      if index == cascade.messages.len - 1:
        code.add("    " & sendCode.replace("\n", "\n    ") & ")")
      else:
        code.add("    discard " & sendCode.replace("\n", "\n    ") & "\n")
    return code

  of nkPseudoVar:
    return genSymbolAccess(ctx, node.PseudoVarNode.name)

  of nkSuperSend:
    let ss = node.SuperSendNode
    let args = ss.arguments.mapIt(genExpression(ctx, it)).join(", ")
    let definingClass = if ctx.cls != nil: ctx.cls.name else: ""
    if definingClass.len > 0:
      if ss.explicitParent.len > 0:
        return fmt("sendSuperMessage(self, \"{definingClass}\", \"{escapeNimString(ss.selector)}\", @[{args}], \"{ss.explicitParent}\")")
      else:
        return fmt("sendSuperMessage(self, \"{definingClass}\", \"{escapeNimString(ss.selector)}\", @[{args}])")
    else:
      # Fallback if class context is unavailable
      return fmt("sendMessageHybrid(self, \"{escapeNimString(ss.selector)}\", @[{args}])")

  of nkPrimitive:
    # Primitives are handled separately
    return "NodeValue(kind: vkNil)"

  of nkPrimitiveCall:
    # Primitive calls need runtime support
    let primCall = node.PrimitiveCallNode
    let args = primCall.arguments.mapIt(genExpression(ctx, it)).join(", ")
    let bindings = nativePrimitiveBindings()
    if primCall.selector in bindings:
      return fmt("{bindings[primCall.selector].nimProc}(self, @[{args}])")
    return fmt("callPrimitive(\"{escapeNimString(primCall.selector)}\", @[{args}])")

  of nkSlotAccess:
    let slotNode = node.SlotAccessNode
    if ctx.inMethod and ctx.cls != nil:
      var origSlotName = if slotNode.slotName.len > 0: slotNode.slotName else: ""
      for slot in ctx.cls.getAllSlots():
        if slot.index == slotNode.slotIndex:
          origSlotName = slot.name
          break
      if origSlotName.len > 0:
        if slotNode.isAssignment and slotNode.valueExpr != nil:
          let valCode = genExpression(ctx, slotNode.valueExpr)
          return slotWrite(ctx, origSlotName, valCode)
        else:
          return slotRead(ctx, origSlotName)

    if slotNode.isAssignment and slotNode.valueExpr != nil:
      let valCode = genExpression(ctx, slotNode.valueExpr)
      return fmt("(proc(): NodeValue = self.slots[{slotNode.slotIndex}] = {valCode}; return {valCode})()")
    else:
      return fmt("self.slots[{slotNode.slotIndex}]")

  of nkNamedAccess:
    let namedNode = node.NamedAccessNode
    let recvCode = genExpression(ctx, namedNode.receiver)
    let directAccess = tryGenerateNamedAccess(ctx, namedNode, recvCode)
    if directAccess.len > 0:
      return directAccess
    if namedNode.isAssignment and namedNode.valueExpr != nil:
      let valCode = genExpression(ctx, namedNode.valueExpr)
      return fmt("compiledNamedAccess({recvCode}, \"{namedNode.memberName}\", {valCode}, true)")
    else:
      return fmt("compiledNamedAccess({recvCode}, \"{namedNode.memberName}\")")

  else:
    return "NodeValue(kind: vkNil)"

proc genStatement*(ctx: GenContext, node: Node): string =
  ## Generate code for a statement (not an expression - no result assignment)
  ## This is used for statements inside blocks/methods

  if node == nil:
    return ""


  case node.kind
  of nkAssign:
    let assign = node.AssignNode
    let varName = assign.variable
    
    
    # Infer type from the expression being assigned
    let exprType = ctx.inferTypeFromExpression(assign.expression)
    if exprType.className.len > 0:
      ctx.setVariableType(varName, exprType.className, exprType.isNativeClass)
    
    let exprCode = genExpression(ctx, assign.expression)

    # Check if variable is a slot
    if ctx.isSlot(varName) and not ctx.isLocal(varName):
      if ctx.inMethod and ctx.cls != nil:
        return "discard " & slotWrite(ctx, varName, exprCode)
      let idx = ctx.getSlotIndex(varName)
      return fmt"self.slots[{idx}] = {exprCode}"

    # Check if it's a local variable (reassignment)
    if ctx.isLocal(varName):
      return fmt("{bindingTarget(ctx, varName)} = {bindingAssignmentValue(ctx, varName, exprCode)}")

    # A Harding global assigns the shared binding; in statement position the
    # returned value is discarded.
    if varName in ctx.globals or (ctx.inMethod and varName.len > 0 and varName[0] in {'A'..'Z'}):
      return "discard " & genGlobalAssignment(ctx, varName, exprCode)

    # New local variable assignment
    ctx.locals.add(varName)
    return bindingDeclaration(ctx, varName, exprCode)

  of nkReturn:
    let ret = node.ReturnNode
    let valueCode = if ret.expression != nil: genExpression(ctx, ret.expression) else: "nilValue()"
    if ctx.inBlock and ctx.returnTarget.len > 0:
      return fmt("return raiseNonLocalReturn({ctx.returnTarget}, {valueCode})")
    return "return " & valueCode

  of nkWhile:
    let whileNode = node.WhileNode
    var condCode: string

    let condBlock = asBlockNode(whileNode.condition)
    if condBlock != nil:
      if condBlock.body.len > 0:
        condCode = inlineBlockExpression(ctx, condBlock)
      else:
        condCode = if whileNode.isWhileTrue:
                     "NodeValue(kind: vkBool, boolVal: true)"
                   else:
                     "NodeValue(kind: vkBool, boolVal: false)"
    else:
      condCode = if whileNode.condition != nil:
                   genExpression(ctx, whileNode.condition)
                 else:
                   (if whileNode.isWhileTrue:
                      "NodeValue(kind: vkBool, boolVal: true)"
                    else:
                      "NodeValue(kind: vkBool, boolVal: false)")

    let clause = conditionClause(ctx, whileNode.condition, condCode,
                                 negate = not whileNode.isWhileTrue)
    var code = "while " & clause.code & ":\n"

    let bodyBlock = asBlockNode(whileNode.body)
    if bodyBlock != nil:
      if bodyBlock.body.len == 0:
        code.add("  discard\n")
      else:
        code.add(indentBlock(inlineBlockStatements(ctx, bodyBlock)))
    elif whileNode.body != nil:
      let stmtCode = genStatement(ctx, whileNode.body)
      if stmtCode.len > 0:
        code.add(indentBlock(stmtCode))
    else:
      code.add("  discard\n")
    return code

  of nkIf:
    let ifNode = node.IfNode
    let condCode = if ifNode.condition != nil:
                     genExpression(ctx, ifNode.condition)
                   else:
                     "NodeValue(kind: vkBool, boolVal: false)"

    if ctx.inBlock and
       (hasReturnNode(ifNode.thenBranch) or hasReturnNode(ifNode.elseBranch)):
      # The if branch contains a block whose ^ performs a non-local return.
      # The block cannot be inlined; send it as a real block invocation so
      # its compiled procedure (which raises NonLocalReturnException) runs.
      var runtimeCode = "if isTruthy(" & condCode & "):\n"
      if ifNode.thenBranch != nil:
        runtimeCode.add("  discard sendMessage(currentRuntime[], " & genExpression(ctx, ifNode.thenBranch) & ", \"value\", @[])\n")
      else:
        runtimeCode.add("  discard\n")
      if ifNode.elseBranch != nil:
        runtimeCode.add("else:\n")
        runtimeCode.add("  discard sendMessage(currentRuntime[], " & genExpression(ctx, ifNode.elseBranch) & ", \"value\", @[])\n")
      return runtimeCode

    var code = "if isTruthy(" & condCode & "):\n"

    let thenBlock = asBlockNode(ifNode.thenBranch)
    if thenBlock != nil:
      if thenBlock.body.len == 0:
        code.add("  discard\n")
      else:
        code.add(indentBlock(inlineBlockStatements(ctx, thenBlock)))
    elif ifNode.thenBranch != nil:
      let stmtCode = genStatement(ctx, ifNode.thenBranch)
      if stmtCode.len > 0:
        code.add(indentBlock(stmtCode))
    else:
      code.add("  discard\n")

    if ifNode.elseBranch != nil:
      code.add("else:\n")
      let elseBlock = asBlockNode(ifNode.elseBranch)
      if elseBlock != nil:
        if elseBlock.body.len == 0:
          code.add("  discard\n")
        else:
          code.add(indentBlock(inlineBlockStatements(ctx, elseBlock)))
      else:
        let stmtCode = genStatement(ctx, ifNode.elseBranch)
        if stmtCode.len > 0:
          code.add(indentBlock(stmtCode))
        else:
          code.add("  discard\n")

    return code

  of nkMessage:
    let msg = node.MessageNode
    # Inline control flow in statement context (no value needed)
    case msg.selector
    of "whileTrue:":
      if msg.arguments.len >= 1 and
         not hasReturnNode(msg.arguments[0]) and
         (msg.receiver == nil or not hasReturnNode(msg.receiver)):
        let bodyBlock = asBlockNode(msg.arguments[0])
        if bodyBlock != nil:
          var condCode: string
          let condBlock = asBlockNode(msg.receiver)
          if condBlock != nil:
            if condBlock.body.len > 0:
              condCode = inlineBlockExpression(ctx, condBlock)
            else:
              condCode = "NodeValue(kind: vkBool, boolVal: true)"
          else:
            condCode = if msg.receiver != nil: genExpression(ctx, msg.receiver)
                       else: "NodeValue(kind: vkBool, boolVal: true)"
          var code = "while isTruthy(" & condCode & "):\n"
          code.add(indentBlock(inlineBlockStatements(ctx, bodyBlock)))
          return code

    of "whileFalse:":
      if msg.arguments.len >= 1 and
         not hasReturnNode(msg.arguments[0]) and
         (msg.receiver == nil or not hasReturnNode(msg.receiver)):
        let bodyBlock = asBlockNode(msg.arguments[0])
        if bodyBlock != nil:
          var condCode: string
          let condBlock = asBlockNode(msg.receiver)
          if condBlock != nil:
            if condBlock.body.len > 0:
              condCode = inlineBlockExpression(ctx, condBlock)
            else:
              condCode = "NodeValue(kind: vkBool, boolVal: false)"
          else:
            condCode = if msg.receiver != nil: genExpression(ctx, msg.receiver)
                       else: "NodeValue(kind: vkBool, boolVal: false)"
          var code = "while not isTruthy(" & condCode & "):\n"
          code.add(indentBlock(inlineBlockStatements(ctx, bodyBlock)))
          return code

    of "ifTrue:":
      if msg.arguments.len >= 1 and not hasReturnNode(msg.arguments[0]):
        let thenBlock = asBlockNode(msg.arguments[0])
        if thenBlock != nil:
          let condCode = if msg.receiver != nil: genExpression(ctx, msg.receiver)
                         else: "NodeValue(kind: vkBool, boolVal: true)"
          var code = "if isTruthy(" & condCode & "):\n"
          if thenBlock.body.len == 0:
            code.add("  discard\n")
          else:
            code.add(indentBlock(inlineBlockStatements(ctx, thenBlock)))
          return code

    of "ifFalse:":
      if msg.arguments.len >= 1 and not hasReturnNode(msg.arguments[0]):
        let thenBlock = asBlockNode(msg.arguments[0])
        if thenBlock != nil:
          let condCode = if msg.receiver != nil: genExpression(ctx, msg.receiver)
                         else: "NodeValue(kind: vkBool, boolVal: false)"
          var code = "if not isTruthy(" & condCode & "):\n"
          if thenBlock.body.len == 0:
            code.add("  discard\n")
          else:
            code.add(indentBlock(inlineBlockStatements(ctx, thenBlock)))
          return code

    of "ifTrue:ifFalse:":
      if msg.arguments.len >= 2 and
         not hasReturnNode(msg.arguments[0]) and
         not hasReturnNode(msg.arguments[1]):
        let thenBlock = asBlockNode(msg.arguments[0])
        let elseBlock = asBlockNode(msg.arguments[1])
        if thenBlock != nil and elseBlock != nil:
          let condCode = if msg.receiver != nil: genExpression(ctx, msg.receiver)
                         else: "NodeValue(kind: vkBool, boolVal: true)"
          var code = "if isTruthy(" & condCode & "):\n"
          if thenBlock.body.len == 0:
            code.add("  discard\n")
          else:
            for stmt in thenBlock.body:
              let stmtCode = genStatement(ctx, stmt)
              if stmtCode.len > 0:
                code.add(indentBlock(stmtCode))
          code.add("else:\n")
          if elseBlock.body.len == 0:
            code.add("  discard\n")
          else:
            for stmt in elseBlock.body:
              let stmtCode = genStatement(ctx, stmt)
              if stmtCode.len > 0:
                code.add(indentBlock(stmtCode))
          return code

    of "timesRepeat:":
      if msg.arguments.len >= 1 and not hasReturnNode(msg.arguments[0]):
        let bodyBlock = asBlockNode(msg.arguments[0])
        if bodyBlock != nil:
          let countCode = if msg.receiver != nil: genExpression(ctx, msg.receiver)
                          else: "NodeValue(kind: vkInt, intVal: 0)"
          var code = "for timesRepeatI in 0..<compiledLoopInt(" & countCode & "):\n"
          if bodyBlock.body.len == 0:
            code.add("  discard\n")
          else:
            code.add(indentBlock(inlineBlockStatements(ctx, bodyBlock)))
          return code

    else:
      discard

    # Default: message send as statement
    let msgCode = genMessage(ctx, node.MessageNode)
    return "discard " & msgCode

  of nkCascade:
    ## Statement position discards the cascade's answer, so the last message is
    ## discarded too.
    let cascade = node.CascadeNode
    if cascade.receiver == nil or cascade.messages.len == 0:
      return genStatement(ctx, cascade.receiver)
    var code = "block:\n    let hardingCascadeReceiver = " &
               genExpression(ctx, cascade.receiver).replace("\n", "\n    ") & "\n"
    for message in cascade.messages:
      let send = cast[MessageNode](message)
      let arguments = send.arguments.mapIt(genExpression(ctx, it))
      let sendCode = genSend(ctx, "hardingCascadeReceiver", send.selector, arguments)
      code.add("    discard " & sendCode.replace("\n", "\n    ") & "\n")
    return code

  of nkPrimitiveCall:
    # Primitive call as statement
    let primCall = node.PrimitiveCallNode
    let args = primCall.arguments.mapIt(genExpression(ctx, it)).join(", ")
    let bindings = nativePrimitiveBindings()
    if primCall.selector in bindings:
      return "discard " & bindings[primCall.selector].nimProc & "(self, @[" & args & "])"
    return "discard callPrimitive(\"" & escapeNimString(primCall.selector) & "\", @[" & args & "])"

  else:
    # For other nodes, just generate the expression
    let exprCode = genExpression(ctx, node)
    if exprCode.len > 0:
      return "discard " & exprCode
    return ""

proc hasBranchValue(ifNode: IfNode): bool

proc genBlockBody*(ctx: GenContext, blkNode: BlockNode, captures: seq[string] = @[],
                   hasNonLocalReturn: bool = false, envStructName: string = "",
                   targetMethodId: int = 0): string =
  ## Generate code for block body (sequence of statements)
  ## captures: list of captured variable names (from BlockProcInfo)
  ## hasNonLocalReturn: if true, ^ generates NonLocalReturnException
  ## targetMethodId: lexical owner metadata; nonzero environments carry the invocation target
  var output = ""

  # Create new context for block body with its parameters
  # Share the blockRegistry so nested blocks can be looked up
  var bodyCtx = GenContext(
    cls: ctx.cls,
    inBlock: true,
    returnTarget: (if not hasNonLocalReturn: ""
                   elif targetMethodId != 0: "hardingHome" else: "nil"),
    inMethod: ctx.inMethod,
    mixed: ctx.mixed,
    locals: @[],
    parameters: @[],
    globals: ctx.globals,
    blockRegistry: ctx.blockRegistry,
    varTypes: ctx.varTypes,
    compiledClasses: ctx.compiledClasses,
    classInfo: ctx.classInfo,
    directSendCandidates: ctx.directSendCandidates,
    integerSendCandidates: ctx.integerSendCandidates,
    cellNames: scopeCaptureCellNames(blkNode.body, blkNode.parameters & blkNode.temporaries)
  )
  for param in blkNode.parameters:
    bodyCtx.parameters.add(param)
    output.add("  " & bindingDeclaration(bodyCtx, param, "hardingArg_" & mangleIdentifier(param)) & "\n")

  # Extract captured variables from environment struct
  if captures.len > 0 or targetMethodId != 0:
    if envStructName.len > 0:
      output.add(fmt("  let envTyped = cast[{envStructName}](env)\n"))
      if targetMethodId != 0:
        output.add("  let hardingHome = envTyped.home\n")
    for capture in captures:
      if envStructName.len > 0:
        if capture == "self":
          output.add("  let self = envTyped[].self.value\n")
        else:
          let identifier = mangleIdentifier(capture)
          output.add(fmt("  let {identifier} = envTyped[].{identifier}\n"))
          if capture notin bodyCtx.cellNames:
            bodyCtx.cellNames.add(capture)
      else:
        output.add("  " & bindingDeclaration(bodyCtx, capture, "NodeValue(kind: vkNil)") & "\n")
      bodyCtx.locals.add(capture)

  output.add(indentBlock(genLocalDeclarations(bodyCtx, blkNode.temporaries)))

  # Handle empty block body
  if blkNode.body.len == 0:
    output.add("  return NodeValue(kind: vkNil)\n")
    return output

  for i, stmt in blkNode.body:
    if stmt.kind == nkReturn and hasNonLocalReturn:
      # Non-local return from block: raise exception to return from enclosing method
      let ret = stmt.ReturnNode
      let exprCode = if ret.expression != nil:
                       genExpression(bodyCtx, ret.expression)
                     else:
                       "NodeValue(kind: vkNil)"
      let target = if targetMethodId != 0: "hardingHome" else: "nil"
      output.add(fmt("  return raiseNonLocalReturn({target}, {exprCode})\n"))
    elif i == blkNode.body.len - 1 and stmt.kind == nkIf and
         not (hasReturnNode(stmt.IfNode.thenBranch) or hasReturnNode(stmt.IfNode.elseBranch)) and
         not hasBranchValue(stmt.IfNode):
      # An if-expression whose branches are plain statements is the block's
      # answer: emit its branches as values, not as discarded statements (which
      # made every such block answer nil). A branch that assigns answers the
      # assigned value under `ifTrue:`, whose value the block must return, so
      # those take the statement path below and answer nil.
      output.add("  return " & indentBlock(genExpression(bodyCtx, stmt), 2) & "\n")
    elif i == blkNode.body.len - 1 and stmt.kind in {nkIf, nkWhile}:
      let stmtCode = genStatement(bodyCtx, stmt)
      if stmtCode.len > 0:
        output.add(indentBlock(stmtCode))
      output.add("  return NodeValue(kind: vkNil)\n")
    elif i == blkNode.body.len - 1 and stmt.kind == nkAssign:
      # Preserve the value before assignment (including global/class naming)
      # without re-evaluating an RHS that may have side effects.
      let assignment = stmt.AssignNode
      let temporary = "\x00blockAssignmentValue"
      let temporaryName = mangleIdentifier(temporary)
      let rhs = genExpression(bodyCtx, assignment.expression)
      output.add(fmt("  let {temporaryName} = {rhs}\n"))
      bodyCtx.locals.add(temporary)
      let stored = AssignNode(variable: assignment.variable,
        expression: IdentNode(name: temporary))
      output.add(indentBlock(genStatement(bodyCtx, stored)))
      output.add(fmt("  return {temporaryName}\n"))
    elif i == blkNode.body.len - 1 and stmt.kind != nkReturn:
      # Last statement is the return value
      let exprCode = genExpression(bodyCtx, stmt)
      output.add("  return " & exprCode & "\n")
    else:
      let stmtCode = genStatement(bodyCtx, stmt)
      if stmtCode.len > 0:
        output.add(indentBlock(stmtCode))


  return output


proc hasBranchValue(ifNode: IfNode): bool =
  ## True when either branch is a bare assignment, which `ifTrue:` answers with
  ## the assigned value instead of the expression.
  for branch in [ifNode.thenBranch, ifNode.elseBranch]:
    var statements: seq[Node] = @[]
    if branch != nil:
      if branch.kind == nkBlock: statements = branch.BlockNode.body
      else: statements = @[branch]
    for stmt in statements:
      if stmt != nil and stmt.kind == nkAssign:
        return true
  return false

proc asBlockNode(node: Node): BlockNode =
  ## Get BlockNode from either nkBlock or nkLiteral(vkBlock)
  if node == nil:
    return nil
  case node.kind
  of nkBlock:
    return node.BlockNode
  of nkLiteral:
    let lit = node.LiteralNode.value
    if lit.kind == vkBlock:
      return lit.blockVal
    return nil
  else:
    return nil

proc isBlockWithCaptures*(ctx: GenContext, node: Node): tuple[isBlock: bool, blockInfo: BlockProcInfo] =
  ## Check if a node is a block literal that requires captures
  ## Returns (true, blockInfo) if it's a block with captures, (false, default) otherwise
  let blockNode = asBlockNode(node)
  if blockNode == nil:
    return (false, default(BlockProcInfo))
  
  # Look up or register the block
  let existingIdx = ctx.blockRegistry.findBlock(blockNode)
  let blockInfo = if existingIdx >= 0:
                    ctx.blockRegistry.blocks[existingIdx]
                  else:
                    registerBlock(ctx.blockRegistry, blockNode, blockCaptureGlobals(ctx), ctx.inMethod,
                                  blockOwnerSlots(ctx), blockOwnerLocals(ctx))
  
  if blockInfo.captures.len > 0:
    return (true, blockInfo)
  else:
    return (false, default(BlockProcInfo))


proc genTopLevelStatement*(ctx: GenContext, node: Node): string =
  ## Generate code for a top-level statement (for main proc)
  ## Returns code that can be executed in a main() procedure

  if node == nil:
    return ""

  
  case node.kind
  of nkAssign:
    let assign = node.AssignNode
    let varName = assign.variable
    
    
    # Infer type from the expression being assigned
    let exprType = ctx.inferTypeFromExpression(assign.expression)
    if exprType.className.len > 0:
      ctx.setVariableType(varName, exprType.className, exprType.isNativeClass)
    
    let exprCode = genExpression(ctx, assign.expression)

    # A top-level uppercase name is a Harding global: assign the shared binding
    # instead of declaring a local, so methods and blocks observe it too.
    if varName in ctx.globals:
      return fmt("discard setGlobal(\"{varName}\", {exprCode})")

    # Reassignment of an existing script-local variable
    if varName in ctx.locals:
      return fmt("{bindingTarget(ctx, varName)} = {bindingAssignmentValue(ctx, varName, exprCode)}")

    # New top-level variable: a local of main, visible to blocks nested in main.
    ctx.locals.add(varName)
    return bindingDeclaration(ctx, varName, exprCode)

  of nkMessage:
    # Top-level message send - delegate to genStatement for inline control flow
    return genStatement(ctx, node)

  of nkWhile, nkIf:
    # Top-level specialized control-flow nodes
    return genStatement(ctx, node)

  of nkReturn:
    # Return at top level becomes exit code
    let ret = node.ReturnNode
    if ret.expression != nil:
      return "return " & genExpression(ctx, ret.expression) & ".intVal"
    return "return 0"

  else:
    # Other expressions
    let exprCode = genExpression(ctx, node)
    if exprCode.len > 0:
      return "discard " & exprCode
    return ""
