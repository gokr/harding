import ../core/types

proc hasBlocksWithNonLocalReturn*(node: Node): bool =
  ## Check if an AST node contains blocks with ^ (non-local return)
  if node == nil:
    return false
  case node.kind
  of nkBlock:
    let blk = node.BlockNode
    for stmt in blk.body:
      if stmt of ReturnNode:
        return true
    # Also check nested blocks
    for stmt in blk.body:
      if hasBlocksWithNonLocalReturn(stmt):
        return true
  of nkMessage:
    let msg = node.MessageNode
    if msg.receiver != nil and hasBlocksWithNonLocalReturn(msg.receiver):
      return true
    for arg in msg.arguments:
      if hasBlocksWithNonLocalReturn(arg):
        return true
  of nkAssign:
    return hasBlocksWithNonLocalReturn(node.AssignNode.expression)
  of nkReturn:
    if node.ReturnNode.expression != nil:
      return hasBlocksWithNonLocalReturn(node.ReturnNode.expression)
  of nkIf:
    let ifNode = node.IfNode
    if ifNode.thenBranch != nil and hasBlocksWithNonLocalReturn(ifNode.thenBranch):
      return true
    if ifNode.elseBranch != nil and hasBlocksWithNonLocalReturn(ifNode.elseBranch):
      return true
  of nkWhile:
    let whileNode = node.WhileNode
    if whileNode.condition != nil and hasBlocksWithNonLocalReturn(whileNode.condition):
      return true
    if whileNode.body != nil and hasBlocksWithNonLocalReturn(whileNode.body):
      return true
  of nkSlotAccess, nkNamedAccess:
    # A returning block may be stored through a slot or named member, e.g.
    # `handler := [:x | ^x]`. The block literal lives in valueExpr, so omitting
    # it left the method without a NonLocalReturn boundary and the escape
    # exception left the method instead of being caught here.
    let valueExpr = if node.kind == nkSlotAccess: node.SlotAccessNode.valueExpr
                    else: node.NamedAccessNode.valueExpr
    if valueExpr != nil and hasBlocksWithNonLocalReturn(valueExpr):
      return true
  of nkCascade:
    let cascade = node.CascadeNode
    if cascade.receiver != nil and hasBlocksWithNonLocalReturn(cascade.receiver):
      return true
    for message in cascade.messages:
      if hasBlocksWithNonLocalReturn(message):
        return true
  of nkSuperSend:
    for argument in node.SuperSendNode.arguments:
      if hasBlocksWithNonLocalReturn(argument):
        return true
  of nkPrimitiveCall:
    for argument in node.PrimitiveCallNode.arguments:
      if hasBlocksWithNonLocalReturn(argument):
        return true
  else:
    discard
  return false
