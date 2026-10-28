import ../core/types

proc validateSlotBindings*(node: Node, cls: Class, selector: string) =
  ## Reject lexical declarations hiding receiver slots, including inherited slots.
  if node == nil:
    return
  case node.kind
  of nkBlock:
    let blk = BlockNode(node)
    for name in blk.parameters & blk.temporaries:
      if name in cls.allSlotNames:
        raise newException(ValueError, "Local binding '" & name & "' shadows slot in " & cls.name & ">>" & selector)
    for statement in blk.body:
      validateSlotBindings(statement, cls, selector)
  of nkMessage:
    let message = MessageNode(node)
    validateSlotBindings(message.receiver, cls, selector)
    for argument in message.arguments:
      validateSlotBindings(argument, cls, selector)
  of nkCascade:
    let cascade = CascadeNode(node)
    validateSlotBindings(cascade.receiver, cls, selector)
    for message in cascade.messages:
      validateSlotBindings(message, cls, selector)
  of nkAssign:
    validateSlotBindings(AssignNode(node).expression, cls, selector)
  of nkReturn:
    validateSlotBindings(ReturnNode(node).expression, cls, selector)
  of nkIf:
    let conditional = IfNode(node)
    validateSlotBindings(conditional.condition, cls, selector)
    validateSlotBindings(conditional.thenBranch, cls, selector)
    validateSlotBindings(conditional.elseBranch, cls, selector)
  of nkWhile:
    let loop = WhileNode(node)
    validateSlotBindings(loop.condition, cls, selector)
    validateSlotBindings(loop.body, cls, selector)
  of nkArray:
    for element in ArrayNode(node).elements:
      validateSlotBindings(element, cls, selector)
  of nkTable:
    for entry in TableNode(node).entries:
      validateSlotBindings(entry.key, cls, selector)
      validateSlotBindings(entry.value, cls, selector)
  of nkSuperSend:
    for argument in SuperSendNode(node).arguments:
      validateSlotBindings(argument, cls, selector)
  of nkPrimitiveCall:
    for argument in PrimitiveCallNode(node).arguments:
      validateSlotBindings(argument, cls, selector)
  of nkPrimitive:
    for statement in PrimitiveNode(node).fallback:
      validateSlotBindings(statement, cls, selector)
  of nkSlotAccess:
    validateSlotBindings(SlotAccessNode(node).valueExpr, cls, selector)
  of nkNamedAccess:
    let access = NamedAccessNode(node)
    validateSlotBindings(access.receiver, cls, selector)
    validateSlotBindings(access.valueExpr, cls, selector)
  else:
    discard
