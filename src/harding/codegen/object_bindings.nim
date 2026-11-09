import std/[tables, sets]
import ../core/types
import ../compiler/[context, types, slot_inference]

proc objectParameterCandidates*(body: seq[Node], parameters, temporaries,
                                excluded: seq[string], cls: ClassInfo,
                                receiverHints: Table[string, string] = default(Table[string, string])): Table[string, string] =
  ## Declared object-slot writes and unique getter receivers suggest parameter
  ## representations, not proofs.
  ## Entry guards must establish the argument's class (or nil). Mutation,
  ## captures, lexical shadowing and conflicting slot contracts exclude a name.
  var candidates: Table[string, string]
  var rejected = excluded.toHashSet()
  proc visit(node: Node) =
    if node == nil: return
    var slotName: string
    var value: Node
    case node.kind
    of nkAssign:
      let assignment = node.AssignNode
      if assignment.variable notin parameters and assignment.variable notin temporaries:
        slotName = assignment.variable
        value = assignment.expression
      if assignment.variable in parameters: rejected.incl(assignment.variable)
    of nkSlotAccess:
      let access = node.SlotAccessNode
      if access.isAssignment:
        slotName = access.slotName
        if slotName.len == 0 and cls != nil:
          for slot in cls.getAllSlots():
            if slot.index == access.slotIndex: slotName = slot.name
        value = access.valueExpr
    of nkMessage:
      let message = node.MessageNode
      if message.arguments.len == 0 and message.selector in receiverHints and
         message.receiver != nil and message.receiver.kind == nkIdent:
        let name = message.receiver.IdentNode.name
        let expected = receiverHints[message.selector]
        if name in parameters:
          if name in candidates and candidates[name] != expected:
            rejected.incl(name)
          else:
            candidates[name] = expected
    of nkBlock:
      for name in node.BlockNode.parameters & node.BlockNode.temporaries:
        rejected.incl(name)
    of nkLiteral:
      let literal = node.LiteralNode.value
      if literal.kind == vkBlock and literal.blockVal != nil:
        for name in literal.blockVal.parameters & literal.blockVal.temporaries:
          rejected.incl(name)
    else: discard
    if cls != nil and slotName.len > 0 and value != nil and value.kind == nkIdent:
      let name = value.IdentNode.name
      let slot = cls.getSlotDef(slotName)
      if name in parameters and slot.constraint == tcObject and slot.objectClass.len > 0:
        if name in candidates and candidates[name] != slot.objectClass:
          rejected.incl(name)
        else:
          candidates[name] = slot.objectClass
    for child in nodeChildren(node): visit(child)
  for node in body: visit(node)
  for name, className in candidates:
    if name notin rejected: result[name] = className

proc referenceGetterUses*(body: seq[Node], parameters: Table[string, string],
                          receiverHints: Table[string, string]): HashSet[string] =
  ## Emit reference helpers only where a specialized binding can reach them.
  proc visit(node: Node, uses: var HashSet[string]) =
    if node == nil: return
    if node.kind == nkMessage:
      let message = node.MessageNode
      if message.arguments.len == 0 and message.selector in receiverHints and
         message.receiver != nil and message.receiver.kind == nkIdent and
         message.receiver.IdentNode.name in parameters:
        uses.incl(message.selector)
    for child in nodeChildren(node): visit(child, uses)
  for node in body: visit(node, result)
