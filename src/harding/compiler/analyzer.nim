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

proc parseTypeList*(typeList: string): seq[tuple[name: string, constraint: TypeConstraint]] =
  ## Parse type list from derive: #(name: Type age: Int name2:) or #(name age)
  ## Returns (name, constraint) tuples, constraint = tcNone for untyped
  result = @[]

  var remaining = typeList
  remaining = remaining.strip()
  if remaining.startsWith("#(") and remaining.endsWith(")"):
    remaining = remaining[2..^2].strip()

  var pos = 0
  while pos < remaining.len:
    # Skip whitespace and commas
    while pos < remaining.len and remaining[pos] in {' ', '\t', ','}:
      inc pos
    if pos >= remaining.len or remaining[pos] == ')':
      break

    # Extract slot name up to colon, whitespace, comma, or end
    var nameStart = pos
    while pos < remaining.len and remaining[pos] notin {':', ',', ')', ' ', '\t'}:
      inc pos
    let slotName = remaining[nameStart..<pos].strip()
    
    if slotName.len == 0:
      # Skip past any separator and continue
      while pos < remaining.len and remaining[pos] in {':', ',', ' ', '\t'}:
        inc pos
      continue

    # Check for type hint after colon
    var constraint = tcNone
    if pos < remaining.len and remaining[pos] == ':':
      inc pos  # Skip colon
      while pos < remaining.len and remaining[pos].isSpaceAscii():
        inc pos
      var typeStart = pos
      var typeEnd = pos
      while pos < remaining.len and not remaining[pos].isSpaceAscii() and remaining[pos] notin {',', ')'}:
        inc pos
        typeEnd = pos
      let typeHint = if typeStart < typeEnd: remaining[typeStart..<typeEnd].strip() else: ""
      if typeHint.len > 0:
        constraint = parseTypeHint(typeHint)

    result.add((slotName, constraint))

    # Skip past any trailing characters to next slot
    while pos < remaining.len and remaining[pos] notin {',', ')'}:
      inc pos
    if pos < remaining.len and remaining[pos] == ',':
      inc pos

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
  
  # Handle derive: and deriveWithAccessors:
  if deriveMsg.selector notin ["derive:", "derive", "deriveWithAccessors:", "deriveWithAccessors"]:
    return
  
  # Extract parent from receiver of derive message
  let parent = if deriveMsg.receiver.kind == nkLiteral and
                  deriveMsg.receiver.LiteralNode.value.kind == vkSymbol:
                  deriveMsg.receiver.LiteralNode.value.symVal
                else:
                  "Object"
  
  # Extract type list from arguments
  let typeArg = if deriveMsg.arguments.len > 0:
                   deriveMsg.arguments[0]
                 else:
                   nil
  
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

proc analyzeClassDef*(node: Node, ctx: var CompilerContext,
                      parentClass: ClassInfo): ClassInfo =
  ## Analyze a class definition and create ClassInfo
  let (className, parentName, typeList) = extractDeriveChain(node)

  if className.len == 0:
    return nil

  result = newClassInfo(className, parentClass)
  ctx.classes[className] = result

  if typeList.len > 0:
    let slots = parseTypeList(typeList)
    for (name, constraint) in slots:
      discard result.addSlot(name, constraint)

proc buildClassGraph*(nodes: seq[Node]): AnalysisResult =
  ## Build class graph from parsed nodes
  result = newAnalysisResult()
  var ctx = newCompiler()
  var classMap: Table[string, ClassInfo]

  # First pass: collect all class declarations
  for node in nodes:
    if node.kind in [nkMessage, nkAssign]:
      let chain = extractDeriveChain(node)
      let className = chain[0]
      if className.len > 0 and className notin classMap:
        classMap[className] = nil  # Placeholder

  # Second pass: create ClassInfo with parent links
  for node in nodes:
    if node.kind in [nkMessage, nkAssign]:
      let chain = extractDeriveChain(node)
      let className = chain[0]
      let parentName = chain[1]
      let typeList = chain[2]

      if className.len > 0:
        let parent = if parentName in classMap: classMap[parentName] else: nil

        if className in ctx.classes:
          result.errors.add("Duplicate class definition: " & className)
          continue

        let cls = newClassInfo(className, parent)
        ctx.classes[className] = cls

        if typeList.len > 0:
          let slots = parseTypeList(typeList)
          for (name, constraint) in slots:
            discard cls.addSlot(name, constraint)

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
