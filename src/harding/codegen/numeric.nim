import std/[tables, sets]
import ../core/types
import ./blocks

type
  NumericRepresentation* = enum
    nrDynamic, nrInt, nrFloat, nrBool
  NumericBindings* = Table[string, NumericRepresentation]

proc numericKind*(node: Node, bindings: NumericBindings): NumericRepresentation =
  ## Result representation for operations with proven, same-kind operands.
  if node == nil:
    return nrDynamic
  case node.kind
  of nkLiteral:
    case node.LiteralNode.value.kind
    of vkInt: return nrInt
    of vkFloat: return nrFloat
    else: discard
  of nkIdent:
    return bindings.getOrDefault(node.IdentNode.name, nrDynamic)
  of nkMessage:
    let message = node.MessageNode
    if message.arguments.len == 1:
      # Leave literal-only operations on the runtime path: Nim constant folding
      # must not turn a runtime overflow into a generated-source compile error.
      if message.receiver != nil and message.receiver.kind == nkLiteral and
         message.arguments[0].kind == nkLiteral:
        return nrDynamic
      let left = numericKind(message.receiver, bindings)
      let right = numericKind(message.arguments[0], bindings)
      if left in {nrInt, nrFloat} and left == right:
        if message.selector in ["+", "-", "*"]:
          return left
        if message.selector in ["<", "<=", ">", ">=", "=", "==", "~="]:
          return nrBool
  else:
    discard
  return nrDynamic

proc analyzeNumericBindings*(body: seq[Node], captured: seq[string],
                             localNames: seq[string] = @[]): NumericBindings =
  ## Find directly initialized lexical numeric candidates. Every assignment must
  ## retain its numeric kind and every read must follow definite initialization.
  ## Any lexical shadowing excludes the name throughout this conservative pass.
  ## A nonempty localNames list restricts candidates before dependency analysis.
  var candidates = initTable[string, NumericRepresentation]()
  for node in body:
    if node != nil and node.kind == nkAssign:
      let assignment = node.AssignNode
      let name = assignment.variable
      if name.len > 0 and name[0] in {'a'..'z'} and name notin captured and
         name notin candidates and (localNames.len == 0 or name in localNames):
        let kind = numericKind(assignment.expression, initTable[string, NumericRepresentation]())
        if kind in {nrInt, nrFloat}:
          candidates[name] = kind

  var rejected = initHashSet[string]()
  proc inspect(node: Node, initialized: var HashSet[string], inlineBlock = false) =
    if node == nil:
      return
    case node.kind
    of nkIdent:
      let name = node.IdentNode.name
      if name in candidates and name notin initialized:
        rejected.incl(name)
    of nkAssign:
      let assignment = node.AssignNode
      inspect(assignment.expression, initialized)
      let name = assignment.variable
      if name in candidates:
        if numericKind(assignment.expression, candidates) != candidates[name]:
          rejected.incl(name)
        initialized.incl(name)
    of nkBlock:
      let blockNode = node.BlockNode
      if not inlineBlock:
        for name in candidates.keys:
          rejected.incl(name)
      for name in blockNode.parameters & blockNode.temporaries:
        rejected.incl(name)
      var blockInitialized = initialized
      for statement in blockNode.body:
        inspect(statement, blockInitialized)
    of nkIf:
      let conditional = node.IfNode
      inspect(conditional.condition, initialized)
      var branchInitialized = initialized
      inspect(conditional.thenBranch, branchInitialized, not hasReturnNode(conditional.thenBranch))
      branchInitialized = initialized
      inspect(conditional.elseBranch, branchInitialized, not hasReturnNode(conditional.elseBranch))
    of nkWhile:
      let loop = node.WhileNode
      inspect(loop.condition, initialized, not hasReturnNode(loop.condition))
      var loopInitialized = initialized
      inspect(loop.body, loopInitialized, not hasReturnNode(loop.body))
    of nkMessage:
      let message = node.MessageNode
      let inlineControl = message.selector in ["ifTrue:", "ifFalse:", "ifTrue:ifFalse:",
        "whileTrue:", "whileFalse:", "timesRepeat:", "to:by:do:", "do:", "collect:", "select:"]
      inspect(message.receiver, initialized, inlineControl and not hasReturnNode(message.receiver))
      for argument in message.arguments:
        inspect(argument, initialized, inlineControl and not hasReturnNode(argument))
    of nkReturn:
      inspect(node.ReturnNode.expression, initialized)
    of nkArray:
      for element in node.ArrayNode.elements:
        inspect(element, initialized)
    of nkTable:
      for entry in node.TableNode.entries:
        inspect(entry[0], initialized)
        inspect(entry[1], initialized)
    of nkNamedAccess:
      inspect(node.NamedAccessNode.receiver, initialized)
      inspect(node.NamedAccessNode.valueExpr, initialized)
    of nkSlotAccess:
      inspect(node.SlotAccessNode.valueExpr, initialized)
    of nkCascade:
      inspect(node.CascadeNode.receiver, initialized)
      for message in node.CascadeNode.messages:
        inspect(message, initialized)
    of nkSuperSend:
      for argument in node.SuperSendNode.arguments:
        inspect(argument, initialized)
    of nkPrimitiveCall:
      for argument in node.PrimitiveCallNode.arguments:
        inspect(argument, initialized)
    of nkLiteral:
      if node.LiteralNode.value.kind == vkBlock:
        for name in candidates.keys:
          rejected.incl(name)
    else:
      discard

  # Removing a candidate can invalidate assignments depending on it.
  while true:
    rejected.clear()
    var initialized = initHashSet[string]()
    for node in body:
      inspect(node, initialized)
    var removed = false
    for name in rejected:
      if name in candidates:
        candidates.del(name)
        removed = true
    if not removed:
      break
  return candidates
