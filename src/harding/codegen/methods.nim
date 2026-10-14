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
  else:
    discard
  return false
