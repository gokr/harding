## Compile-time diagnostics for declared slot stores.
##
## The interpreter stays permissive: dynamic storage and Float slots that accept
## Integer writes keep working. Granite is where a production build should make a
## decision, so a provably-wrong numeric store is reported here.
##
## Only provable cases are reported. Anything uncertain stays silent rather than
## producing noise a developer would learn to ignore.

import std/[tables, strformat]
import ../core/types
import ./context
import ./types
import ./slot_inference

type
  DiagnosticSeverity* = enum
    dsWarning, dsError

  SlotDiagnostic* = object
    file*: string
    line*, col*: int
    severity*: DiagnosticSeverity
    rule*: string
    className*, slotName*: string
    message*: string

proc format*(diagnostic: SlotDiagnostic): string =
  let severity = if diagnostic.severity == dsError: "error" else: "warning"
  fmt("{diagnostic.file}:{diagnostic.line}:{diagnostic.col}: {severity}: {diagnostic.message} [{diagnostic.rule}]")

proc provablyInteger(node: Node): bool =
  ## Integer arithmetic on literal/known-integer operands only.
  if node == nil: return false
  case node.kind
  of nkLiteral: node.LiteralNode.value.kind == vkInt
  of nkMessage:
    let msg = node.MessageNode
    msg.selector in ["+", "-", "*"] and
      provablyInteger(msg.receiver) and
      msg.arguments.len == 1 and provablyInteger(msg.arguments[0])
  else: false

proc provablyFloat(node: Node): bool =
  if node == nil: return false
  case node.kind
  of nkLiteral: node.LiteralNode.value.kind == vkFloat
  of nkMessage:
    let msg = node.MessageNode
    msg.selector in ["+", "-", "*", "/"] and
      ((msg.receiver != nil and msg.receiver.kind == nkLiteral and
        msg.receiver.LiteralNode.value.kind == vkFloat) or
       (msg.arguments.len == 1 and msg.arguments[0].kind == nkLiteral and
        msg.arguments[0].LiteralNode.value.kind == vkFloat))
  else: false

proc methodBody(node: Node): BlockNode =
  if node == nil: return nil
  if node.kind == nkLiteral and node.LiteralNode.value.kind == vkBlock:
    return node.LiteralNode.value.blockVal
  nil

proc resolveSlot(classes: Table[string, ClassInfo], owner, name: string): tuple[found: bool, def: SlotDef] =
  var current = if owner in classes: classes[owner] else: nil
  var seen = 0
  while current != nil and seen < 64:
    inc seen
    let found = current.getSlotDef(name)
    if found.index >= 0 or (found.name == name and found.constraint != tcNone):
      return (true, found)
    for slot in current.slots:
      if slot.name == name: return (true, slot)
    current = current.parent
  (false, SlotDef())

proc diagnoseSlotStores*(nodes: seq[Node], classes: Table[string, ClassInfo],
                         file: string): seq[SlotDiagnostic] =
  ## Report stores whose numeric kind contradicts the declared slot type.
  var found: seq[SlotDiagnostic]
  proc scan(node: Node, owner: string, locals: seq[string]) =
    if node == nil: return
    let body = methodBody(node)
    if body != nil:
      for statement in body.body: scan(statement, owner, locals & body.parameters & body.temporaries)
      return
    if node.kind == nkAssign:
      let assignment = node.AssignNode
      if assignment.variable.len > 0 and assignment.variable notin locals:
        let slot = resolveSlot(classes, owner, assignment.variable)
        if slot.found:
          if slot.def.constraint == tcFloat and provablyInteger(assignment.expression):
            found.add(SlotDiagnostic(file: file, line: node.line, col: node.col,
              severity: dsWarning, rule: "int-to-float",
              className: owner, slotName: assignment.variable,
              message: "Integer stored into Float slot '" & assignment.variable &
                "' of " & owner & "; converted at runtime and exact only to 2^53"))
          elif slot.def.constraint == tcInt and provablyFloat(assignment.expression):
            found.add(SlotDiagnostic(file: file, line: node.line, col: node.col,
              severity: dsError, rule: "float-to-int",
              className: owner, slotName: assignment.variable,
              message: "Float stored into Integer slot '" & assignment.variable &
                "' of " & owner & "; declared Integer slots reject Float"))
    for child in nodeChildren(node):
      scan(child, owner, locals)
  for node in nodes:
    if node.kind != nkMessage: continue
    let msg = node.MessageNode
    if msg.selector notin ["selector:put:", "classSelector:put:"]: continue
    if msg.receiver == nil or msg.receiver.kind != nkIdent: continue
    if msg.selector == "classSelector:put:": continue
    scan(msg.arguments[1], msg.receiver.IdentNode.name, @[])
  # Class-side and top-level statements can still reach a slot through `::`, but
  # the receiver's class is unresolved there, so they are deliberately skipped.
  result = found
