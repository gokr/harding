## Conservative static slot-kind inference for Granite.
##
## Classifies each slot as primitive, object or dynamic from what the compiled
## module actually does. The result is advisory: it changes no behaviour, and any
## doubt resolves to `skDynamic`. Inferred kinds may later pick a native
## representation, so inference must never change an answer.
##
## Deliberately simple, in the spirit of `analyzeNumericBindings`: literal
## initialisers and agreement across all writes. Anything a conservative reading
## cannot prove stays dynamic.

import std/[tables, sets, sequtils, strutils]
import ../core/types
import ./context

type
  SlotKind* = enum
    skDynamic   ## unresolved, mixed, or nil-bearing: keep NodeValue
    skInt
    skFloat
    skBool
    skString    ## String only; Symbol is not modelled (interning)
    skObject    ## non-nil instance of one class

  SlotInference* = object
    kind*: SlotKind
    className*: string    ## for skObject: the observed class
    conclusive*: bool     ## at least one provable write was recorded
    nilSeen*: bool        ## any nil literal write (poisons the slot)
    writes*: int
    reason*: string       ## why it is dynamic, for auditing

  InferenceResult* = object
    slots*: Table[string, SlotInference]  ## key: "Class#slot"
    unresolved*: seq[string]              ## declared slots with no observed write

const primitiveClasses* = ["Integer", "Float", "Boolean", "String", "Symbol",
                           "True", "False", "Number"]

proc isCapitalised(name: string): bool =
  name.len > 0 and name[0] in {'A'..'Z'}

proc classifyWrite(expr: Node): SlotInference =
  ## Conservative single-write classification. Only literal evidence is trusted.
  result = SlotInference(kind: skDynamic, writes: 1)
  if expr == nil:
    result.reason = "no evidence"
    return
  # `nil`, `true` and `false` parse as pseudo-vars, not literals.
  if expr.kind == nkPseudoVar:
    case expr.PseudoVarNode.name
    of "nil":
      result.nilSeen = true
      result.reason = "nil literal"
    of "true", "false":
      result.kind = skBool
      result.conclusive = true
    else:
      result.reason = "unrecognised pseudo-var"
    return
  if expr.kind == nkLiteral:
    let value = expr.LiteralNode.value
    case value.kind
    of vkNil:
      result.nilSeen = true
      result.reason = "nil literal"
    of vkInt:
      result.kind = skInt
      result.conclusive = true
    of vkFloat:
      result.kind = skFloat
      result.conclusive = true
    of vkBool:
      result.kind = skBool
      result.conclusive = true
    of vkString:
      result.kind = skString
      result.conclusive = true
    else:
      result.reason = "non-literal value"
    return
  # `Class new` / `Class basicNew` is object evidence for that class.
  if expr.kind == nkMessage:
    let msg = expr.MessageNode
    if msg.selector in ["new", "basicNew"] and msg.receiver != nil and
       msg.receiver.kind == nkIdent:
      let name = msg.receiver.IdentNode.name
      if isCapitalised(name) and name notin primitiveClasses:
        result.kind = skObject
        result.className = name
        result.conclusive = true
        return
  result.reason = "no evidence"

proc mergeInference(slot: var SlotInference, write: SlotInference) =
  ## Fold one write in. Any nil, any unproven write, or any disagreement settles
  ## the slot as dynamic and it never recovers.
  slot.writes = slot.writes + write.writes
  if write.nilSeen:
    slot.nilSeen = true
  if slot.kind == skDynamic and slot.reason.len > 0:
    return  # already poisoned
  if not write.conclusive:
    slot.kind = skDynamic
    slot.conclusive = false
    slot.reason = write.reason
    return
  if write.nilSeen:
    slot.kind = skDynamic
    slot.conclusive = false
    slot.reason = "nil literal"
    return
  if not slot.conclusive:
    slot.kind = write.kind
    slot.className = write.className
    slot.conclusive = true
    slot.reason = ""
    return
  if slot.kind != write.kind:
    slot.kind = skDynamic
    slot.conclusive = false
    slot.reason = "conflicting kinds"
    return
  if slot.kind == skObject and slot.className != write.className:
    slot.kind = skDynamic
    slot.conclusive = false
    slot.reason = "conflicting classes"

proc collectAssignments(nodes: seq[Node], className: string,
                        into: var Table[string, SlotInference],
                        classSide: bool = false,
                        outsideWrites: var seq[string] = @[]) =
  ## `outsideWrites` collects slot names written through a receiver whose class
  ## cannot be resolved; those poison every slot of that name globally.
  ## Record every assignment in a body, descending into nested blocks.
  for node in nodes:
    if node == nil:
      continue
    case node.kind
    of nkAssign:
      let assignment = node.AssignNode
      # In a class-side method a bare name is a local or a global, never an
      # instance slot; only `obj::slot := ...` can reach instance storage.
      if not classSide and assignment.variable.len > 0:
        let key = className & "#" & assignment.variable
        var slot = into.getOrDefault(key, SlotInference(kind: skDynamic))
        mergeInference(slot, classifyWrite(assignment.expression))
        into[key] = slot
      collectAssignments(@[assignment.expression], className, into, classSide, outsideWrites)
    of nkBlock:
      collectAssignments(node.BlockNode.body, className, into, classSide, outsideWrites)
    of nkReturn:
      collectAssignments(@[node.ReturnNode.expression], className, into, classSide, outsideWrites)
    of nkWhile:
      collectAssignments(@[node.WhileNode.condition, node.WhileNode.body], className, into, classSide, outsideWrites)
    of nkIf:
      collectAssignments(@[node.IfNode.condition, node.IfNode.thenBranch,
                           node.IfNode.elseBranch], className, into, classSide, outsideWrites)
    of nkNamedAccess:
      # `obj::slot := value` -- an outside write through the named-access form.
      # It is evidence about that slot, and the class it names is not necessarily
      # this method's class, so record it under the receiver when it is a class.
      let access = node.NamedAccessNode
      collectAssignments(@[access.receiver], className, into, classSide, outsideWrites)
      if access.isAssignment:
        collectAssignments(@[access.valueExpr], className, into, classSide, outsideWrites)
        if access.receiver != nil and access.receiver.kind == nkIdent and
           isCapitalised(access.receiver.IdentNode.name):
          let owner = access.receiver.IdentNode.name
          let key = owner & "#" & access.memberName
          var slot = into.getOrDefault(key, SlotInference(kind: skDynamic))
          mergeInference(slot, classifyWrite(access.valueExpr))
          into[key] = slot
        elif access.memberName.len > 0:
          # The receiver's class cannot be resolved here, so this write could
          # reach ANY class owning a slot of that name. Poison them all rather
          # than type a slot that an unresolvable write might violate.
          outsideWrites.add(access.memberName)
    of nkArray:
      collectAssignments(node.ArrayNode.elements, className, into, classSide, outsideWrites)
    of nkMessage:
      let msg = node.MessageNode
      var parts: seq[Node] = @[]
      if msg.receiver != nil:
        parts.add(msg.receiver)
      for argument in msg.arguments:
        parts.add(argument)
      collectAssignments(parts, className, into, classSide, outsideWrites)
    else:
      discard

proc methodBody(msg: MessageNode): BlockNode =
  ## Body block of a `Class>>selector [ ... ]` definition, or nil.
  if msg.arguments.len < 2 or msg.arguments[1].kind != nkLiteral:
    return nil
  let value = msg.arguments[1].LiteralNode.value
  if value.kind != vkBlock:
    return nil
  value.blockVal

proc inferSlots*(nodes: seq[Node], classes: Table[string, ClassInfo]): InferenceResult =
  ## Seed every declared slot, then fold in writes observed in the same module.
  ## A declared slot with no observed write is reported unresolved, not assumed.
  result.slots = initTable[string, SlotInference]()
  for className, cls in classes.pairs:
    if cls == nil:
      continue
    for slot in cls.getAllSlots():
      let key = className & "#" & slot.name
      if key notin result.slots:
        # Seeded but unproven: empty reason distinguishes this from a poisoned slot.
        result.slots[key] = SlotInference(kind: skDynamic)

  for node in nodes:
    if node.kind != nkMessage:
      continue
    let msg = node.MessageNode
    if msg.selector notin ["selector:put:", "classSelector:put:"]:
      continue
    let classSide = msg.selector == "classSelector:put:"
    if msg.receiver == nil or msg.receiver.kind != nkIdent:
      continue
    let className = msg.receiver.IdentNode.name
    let body = methodBody(msg)
    if body == nil:
      continue
    # Method arguments and temporaries are locals, never slot writes.
    var localNames = initHashSet[string]()
    for name in body.temporaries:
      localNames.incl(name)
    for name in body.parameters:
      localNames.incl(name)
    var found = initTable[string, SlotInference]()
    var outsideWrites: seq[string] = @[]
    collectAssignments(body.body, className, found, classSide, outsideWrites)
    for slotName in outsideWrites:
      for key in result.slots.keys.toSeq():
        if key.endsWith("#" & slotName):
          var slot = result.slots[key]
          mergeInference(slot, SlotInference(kind: skDynamic, writes: 1,
                                             reason: "written from outside the class"))
          result.slots[key] = slot
    for key, write in found.pairs:
      let slotName = key.split('#', maxsplit = 1)[^1]
      if slotName in localNames:
        continue
      var slot = result.slots.getOrDefault(key, SlotInference(kind: skDynamic))
      mergeInference(slot, write)
      result.slots[key] = slot

  for key, inference in result.slots.pairs:
    if inference.writes == 0:
      result.unresolved.add(key)

proc summarise*(inference: InferenceResult): string =
  ## Auditable one-line summary; used by tests and the optional report flag.
  var counts: array[SlotKind, int]
  for _, slot in inference.slots.pairs:
    inc counts[slot.kind]
  result = "slots=" & $inference.slots.len &
           " int=" & $counts[skInt] &
           " float=" & $counts[skFloat] &
           " bool=" & $counts[skBool] &
           " string=" & $counts[skString] &
           " object=" & $counts[skObject] &
           " dynamic=" & $counts[skDynamic] &
           " unresolved=" & $inference.unresolved.len
