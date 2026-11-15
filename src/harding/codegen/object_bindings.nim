import std/[tables, sets, os]
import ../core/types
import ../compiler/[context, types, slot_inference]

proc objectParameterCandidates*(body: seq[Node], parameters, temporaries,
                                excluded: seq[string], cls: ClassInfo,
                                receiverHints: Table[string, string] = default(Table[string, string]),
                                allClassInfos: seq[ClassInfo] = @[]): Table[string, string] =
  ## Declared object-slot writes and unique getter receivers suggest parameter
  ## representations, not proofs.
  ## Entry guards must establish the argument's class (or nil). Mutation,
  ## captures, lexical shadowing and conflicting slot contracts exclude a name.
  # The nearest class on cls's inheritance chain that declares `selector`.
  proc slotOwner(name: string, start: ClassInfo): SlotDef =
    var current = start
    while current != nil:
      for slot in current.slots:
        if slot.name == name: return slot
      current = current.parent
    SlotDef(name: name, constraint: tcNone, index: -1)

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
      # A slot read through the parameter (`node left`) whose declared class is the
      # class owning that slot tells us the parameter's class is that owner.
      # maxDepth:/leaves: have no other evidence: the parameter is only nil-tested
      # and indexed, so without this they never become typed.
      #
      # The slot may be declared on the parameter's class rather than the reader's,
      # so consult every analysed class for the selector before giving up.
      if message.arguments.len == 0 and message.receiver != nil and
         message.receiver.kind == nkIdent and cls != nil:
        let name = message.receiver.IdentNode.name
        if name in parameters:
          var slot = slotOwner(message.selector, cls)
          if slot.constraint != tcObject:
            # `node left` where `left` is declared on Node, not on the reader.
            # A selector declared on exactly one analysed class names it.
            var owner: SlotDef
            var owners = 0
            for info in allClassInfos:
              for candidate in info.slots:
                if candidate.name == message.selector and candidate.constraint == tcObject:
                  owner = candidate
                  inc owners
            if owners == 1: slot = owner
          if slot.constraint == tcObject and slot.objectClass.len > 0:
            if name in candidates and candidates[name] != slot.objectClass:
              rejected.incl(name)
            else:
              candidates[name] = slot.objectClass
    of nkPseudoVar: discard
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
