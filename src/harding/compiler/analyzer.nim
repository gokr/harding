import std/[strutils, tables]
import ../core/types
import ./context
import ./types

# ============================================================================
# Type Analyzer
# Parses type hints from derive: syntax and builds class type info
# ============================================================================

type
  AnalysisResult* = ref object
    classes*: Table[string, ClassInfo]
    errors*: seq[string]

proc newAnalysisResult*(): AnalysisResult =
  ## Create new analysis result
  result = AnalysisResult(
    classes: initTable[string, ClassInfo](),
    errors: @[]
  )

proc hintConstraint(hint: string): tuple[constraint: TypeConstraint, objectClass, defaultText: string] =
  ## `nil`/empty means explicitly dynamic; a literal declares the primitive type
  ## and its default value; a primitive keyword names only the type; any other
  ## capitalised word names an object class.
  if hint.len == 0 or hint == "nil":
    return (tcNone, "", "")
  # Literal defaults: `0`, `5.0`, `"text"`, `true`, `false`.
  if hint == "true" or hint == "false":
    return (tcBool, "", hint)
  if hint.len > 1 and hint[0] == '"' and hint[^1] == '"':
    return (tcString, "", hint)
  try:
    discard parseInt(hint)
    return (tcInt, "", hint)
  except ValueError:
    discard
  try:
    discard parseFloat(hint)
    return (tcFloat, "", hint)
  except ValueError:
    discard
  let primitive = parseTypeHint(hint)
  if primitive != tcNone:
    return (primitive, "", "")
  if hint[0] in {'A'..'Z'}:
    return (tcObject, hint, "")
  return (tcNone, "", "")

proc parseTypeList*(typeList: string): seq[tuple[name: string, constraint: TypeConstraint, objectClass, defaultText: string]] =
  ## Parse type list from derive: slot lists. Supported forms:
  ## #(name age), #(name, age), #(name: Type age: Int)
  ## A capitalised hint that is not a primitive names an object class, so
  ## `#(q: Banana)` constrains that slot to `Banana`. `nil` means explicitly
  ## dynamic. A literal hint (`0`, `5.0`, `""`, `false`) declares both the
  ## primitive type and the slot's default value.
  result = @[]

  var remaining = typeList.strip()
  if remaining.startsWith("#(") and remaining.endsWith(")"):
    remaining = remaining[2..^2].strip()

  # Tokenize on whitespace and commas. A token ending in ':' is a slot name
  # whose (optional) type hint is the following token.
  var pendingName = ""
  for rawToken in remaining.split({',', ' ', '\t', '\n'}):
    let token = rawToken.strip()
    if token.len == 0:
      continue

    if token.endsWith(":"):
      if pendingName.len > 0:
        result.add((pendingName, tcNone, "", ""))
      pendingName = token[0..^2]
    elif ':' in token:
      # Combined "name:Type" form emitted by the parser for `#(name: Type)`.
      let colon = token.find(':')
      let name = token[0 ..< colon].strip()
      let hint = token[colon + 1 .. ^1].strip()
      if pendingName.len > 0:
        result.add((pendingName, tcNone, "", ""))
        pendingName = ""
      if name.len > 0:
        let resolved = hintConstraint(hint)
        result.add((name, resolved.constraint, resolved.objectClass, resolved.defaultText))
    elif pendingName.len > 0:
      let resolved = hintConstraint(token)
      result.add((pendingName, resolved.constraint, resolved.objectClass, resolved.defaultText))
      pendingName = ""
    else:
      let resolved = hintConstraint(token)
      result.add((token, resolved.constraint, resolved.objectClass, resolved.defaultText))

  if pendingName.len > 0:
    result.add((pendingName, tcNone, "", ""))

  return result

proc extractDeriveChain*(node: Node): (string, string, string) =
  ## Extract (name, parent, typeList) from derive: message
  ## Handles: ClassName := ParentName derive: #(name: Type ...)
  ## Returns ("", "", "") if not a derive: chain
  result = ("", "", "")

  var className = ""
  var deriveMsg: MessageNode = nil
  
  # Check for assignment syntax: ClassName := Parent derive: ...
  if node.kind == nkAssign:
    let assign = node.AssignNode
    className = assign.variable
    if assign.expression != nil and assign.expression.kind == nkMessage:
      deriveMsg = assign.expression.MessageNode
  # Check for message syntax (at:put:)
  elif node.kind == nkMessage:
    let msg = node.MessageNode
    if msg.selector == "at:put:":
      if msg.arguments.len >= 2:
        # Check for derive: inside the value
        if msg.arguments[1].kind == nkMessage:
          deriveMsg = msg.arguments[1].MessageNode
          if msg.receiver.kind == nkLiteral:
            className = msg.receiver.LiteralNode.value.symVal
  
  if deriveMsg == nil:
    return
  
  # Handle canonical class derivation selectors.
  if deriveMsg.selector notin ["derive:", "derive", "derivePublic:", "derivePublic", "derive:read:write:", "derive:read:write:superclasses:", "deriveWithAccessors:", "deriveWithAccessors"]:
    return
  
  # Extract parent from receiver of derive message
  let parent =
    if deriveMsg.receiver.kind == nkIdent:
      deriveMsg.receiver.IdentNode.name
    elif deriveMsg.receiver.kind == nkLiteral and
         deriveMsg.receiver.LiteralNode.value.kind == vkSymbol:
      deriveMsg.receiver.LiteralNode.value.symVal
    elif deriveMsg.receiver.kind == nkLiteral and
         deriveMsg.receiver.LiteralNode.value.kind == vkString:
      deriveMsg.receiver.LiteralNode.value.strVal
    else:
      "Object"
  
  # Extract type list from arguments
  let typeArg = if deriveMsg.arguments.len > 0:
                   deriveMsg.arguments[0]
                 else:
                   nil
  
  if typeArg != nil and typeArg.kind == nkTable:
    var names: seq[string]
    for entry in typeArg.TableNode.entries:
      if entry.key.kind == nkLiteral:
        let key = entry.key.LiteralNode.value
        if key.kind == vkString: names.add(key.strVal)
        elif key.kind == vkSymbol: names.add(key.symVal)
    return (className, parent, "#(" & names.join(" ") & ")")

  var typeList = ""
  if typeArg != nil:
    if typeArg.kind == nkLiteral:
      let val = typeArg.LiteralNode.value
      if val.kind == vkString:
        typeList = val.strVal
      elif val.kind == vkArray:
        # Handle #(name: Type) array syntax
        var parts: seq[string] = @[]
        for elem in typeArg.LiteralNode.value.arrayVal:
          if elem.kind == vkString:
            parts.add(elem.strVal)
          elif elem.kind == vkSymbol:
            parts.add(elem.symVal)
        typeList = "#(" & parts.join(" ") & ")"
    elif typeArg.kind == nkArray:
      # Handle direct array literal like #(name age)
      var parts: seq[string] = @[]
      for elem in typeArg.ArrayNode.elements:
        if elem.kind == nkLiteral:
          let val = elem.LiteralNode.value
          if val.kind == vkSymbol:
            parts.add(val.symVal)
          elif val.kind == vkString:
            parts.add(val.strVal)
        elif elem.kind == nkIdent:
          # Handle identifiers like 'name' in #(name age)
          parts.add(elem.IdentNode.name)
      typeList = "#(" & parts.join(" ") & ")"

  return (className, parent, typeList)

proc slotNames(node: Node): seq[string] =
  if node == nil:
    return @[]
  if node.kind == nkLiteral and node.LiteralNode.value.kind == vkArray:
    for value in node.LiteralNode.value.arrayVal:
      if value.kind == vkSymbol:
        result.add(value.symVal)
      elif value.kind == vkString:
        result.add(value.strVal)
  elif node.kind == nkArray:
    for element in node.ArrayNode.elements:
      if element.kind == nkIdent:
        result.add(element.IdentNode.name)
      elif element.kind == nkLiteral:
        let value = element.LiteralNode.value
        if value.kind == vkSymbol:
          result.add(value.symVal)
        elif value.kind == vkString:
          result.add(value.strVal)

proc extractAccessorInfo(node: Node, cls: ClassInfo) =
  let expression = if node.kind == nkAssign: node.AssignNode.expression else: node
  if expression == nil or expression.kind != nkMessage:
    return
  let msg = expression.MessageNode
  if msg.selector in ["derivePublic", "derivePublic:", "deriveWithAccessors", "deriveWithAccessors:"]:
    for slot in cls.slots:
      cls.getterSlots.add(slot.name)
      cls.setterSlots.add(slot.name)
  elif msg.selector in ["derive:read:write:", "derive:read:write:superclasses:"] and msg.arguments.len >= 3:
    cls.getterSlots = slotNames(msg.arguments[1])
    cls.setterSlots = slotNames(msg.arguments[2])

proc applySlotDeclarations(node: Node, cls: ClassInfo) =
  let expression = if node.kind == nkAssign: node.AssignNode.expression else: node
  if expression == nil or expression.kind != nkMessage: return
  let msg = expression.MessageNode
  if msg.arguments.len == 0 or msg.arguments[0].kind != nkTable: return
  for entry in msg.arguments[0].TableNode.entries:
    if entry.key.kind != nkLiteral: continue
    let key = entry.key.LiteralNode.value
    let name = if key.kind == vkSymbol: key.symVal
               elif key.kind == vkString: key.strVal else: ""
    for slot in cls.slots.mitems:
      if slot.name != name: continue
      slot.constraint = tcNone
      slot.objectClass = ""
      slot.defaultValue = ""
      if entry.value.kind == nkIdent:
        let declared = entry.value.IdentNode.name
        slot.constraint = parseTypeHint(declared)
        if slot.constraint == tcNone or slot.constraint in {tcObject, tcBlock, tcArray, tcTable}:
          slot.constraint = tcObject
          slot.objectClass = declared
      elif entry.value.kind == nkPseudoVar:
        case entry.value.PseudoVarNode.name
        of "true", "false":
          slot.constraint = tcBool
          slot.defaultValue = entry.value.PseudoVarNode.name
        else: discard
      elif entry.value.kind == nkLiteral:
        let value = entry.value.LiteralNode.value
        slot.constraint = constraintForNode(value.kind)
        case value.kind
        of vkInt: slot.defaultValue = $value.intVal
        of vkFloat: slot.defaultValue = $value.floatVal
        of vkBool: slot.defaultValue = $value.boolVal
        of vkString: slot.defaultValue = value.strVal.escape()
        of vkSymbol: slot.defaultValue = value.symVal.escape()
        else: discard

proc analyzeClassDef*(node: Node, ctx: var CompilerContext,
                      parentClass: ClassInfo): ClassInfo =
  ## Analyze a class definition and create ClassInfo
  let (className, _, typeList) = extractDeriveChain(node)

  if className.len == 0:
    return nil

  result = newClassInfo(className, parentClass)
  ctx.classes[className] = result

  if typeList.len > 0:
    let slots = parseTypeList(typeList)
    for (name, constraint, objectClass, defaultText) in slots:
      discard result.addSlot(name, constraint, objectClass, defaultText)
  applySlotDeclarations(node, result)
  extractAccessorInfo(node, result)

proc buildClassGraph*(nodes: seq[Node]): AnalysisResult =
  ## Build class graph from parsed nodes
  result = newAnalysisResult()
  var ctx = newCompiler()
  var classMap = initTable[string, ClassInfo]()
  var parentNames = initTable[string, string]()

  # First pass: collect all class declarations
  for node in nodes:
    if node.kind in [nkMessage, nkAssign]:
      let chain = extractDeriveChain(node)
      let className = chain[0]
      if className.len > 0 and className notin classMap:
        classMap[className] = nil  # Placeholder

  # Second pass: create ClassInfo and record parent names
  for node in nodes:
    if node.kind in [nkMessage, nkAssign]:
      let chain = extractDeriveChain(node)
      let className = chain[0]
      let parentName = chain[1]
      let typeList = chain[2]

      if className.len > 0:
        if className in ctx.classes:
          result.errors.add("Duplicate class definition: " & className)
          continue

        let cls = newClassInfo(className, nil)
        ctx.classes[className] = cls
        classMap[className] = cls
        parentNames[className] = parentName

        if typeList.len > 0:
          let slots = parseTypeList(typeList)
          for (name, constraint, objectClass, defaultText) in slots:
            discard cls.addSlot(name, constraint, objectClass, defaultText)

        applySlotDeclarations(node, cls)
        extractAccessorInfo(node, cls)

  for node in nodes:
    if node.kind == nkMessage:
      let msg = node.MessageNode
      if msg.selector == "selector:put:" and msg.receiver != nil and msg.receiver.kind == nkIdent and
         msg.receiver.IdentNode.name in classMap and msg.arguments.len > 0 and
         msg.arguments[0].kind == nkLiteral:
        let value = msg.arguments[0].LiteralNode.value
        if value.kind == vkSymbol:
          classMap[msg.receiver.IdentNode.name].instanceSelectors.add(value.symVal)
        elif value.kind == vkString:
          classMap[msg.receiver.IdentNode.name].instanceSelectors.add(value.strVal)

  # Built-in exception storage is inherited even without stdlib source in the module.
  let exceptionBase = newClassInfo("Exception")
  for name in ["message", "stackTrace", "signaler"]:
    discard exceptionBase.addSlot(name)
  var exceptionParents = initTable[string, ClassInfo]()
  exceptionParents["Exception"] = exceptionBase
  for name in ["Error", "Notification"]:
    exceptionParents[name] = newClassInfo(name, exceptionBase)
  for name in ["DivisionByZero", "MessageNotUnderstood", "SubscriptOutOfBounds", "BlockCannotReturn"]:
    exceptionParents[name] = newClassInfo(name, exceptionParents["Error"])

  # Third pass: wire parent links now that all classes exist
  for className, parentName in parentNames.pairs:
    if className in classMap and parentName in classMap:
      classMap[className].parent = classMap[parentName]
    elif className in classMap and parentName in exceptionParents:
      classMap[className].parent = exceptionParents[parentName]

  result.classes = ctx.classes

  # Resolve slot indices
  for cls in ctx.classes.mvalues:
    cls.slotIndex.clear()
    var idx = cls.parent.getAllSlots().len
    for slot in cls.slots.mitems:
      if not slot.isInherited:
        slot.index = idx
        cls.slotIndex[slot.name] = idx
        inc idx

  return result
