import std/[tables, sets, strutils, algorithm, json]
import ../core/types
import ./context

type
  SlotKind* = enum
    skDynamic, skInt, skFloat, skBool, skString, skSymbol, skObject

  SlotInference* = object
    kind*: SlotKind
    className*: string
    conclusive*: bool  # consistent module evidence, NOT a closed-world proof
    nilSeen*: bool
    writes*: int
    reason*: string

  InferenceResult* = object
    slots*: Table[string, SlotInference]
    unresolved*: seq[string]

  MethodEvidence = object
    owner, selector: string
    body: BlockNode
    classSide: bool

proc unknown(reason = "no evidence"): SlotInference =
  SlotInference(kind: skDynamic, reason: reason)

proc isUnknown(evidence: SlotInference): bool =
  ## "Nothing known yet", as opposed to a known write we could not type. During
  ## propagation an unresolved operand must not poison a parameter that another
  ## call site proves, or the fixed point could never converge on anything.
  not evidence.conclusive and not evidence.nilSeen and evidence.reason == "no evidence"

proc combine(slot: var SlotInference, evidence: SlotInference) =
  slot.nilSeen = slot.nilSeen or evidence.nilSeen
  if isUnknown(evidence): return
  inc slot.writes
  if slot.reason.len > 0: return
  if not evidence.conclusive:
    slot.kind = skDynamic
    slot.conclusive = false
    slot.reason = evidence.reason
  elif not slot.conclusive:
    slot.kind = evidence.kind
    slot.className = evidence.className
    slot.conclusive = true
  elif slot.kind != evidence.kind or slot.className != evidence.className:
    slot.kind = skDynamic
    slot.conclusive = false
    slot.reason = if evidence.kind == skObject: "conflicting classes" else: "conflicting kinds"

proc nodeChildren*(node: Node): seq[Node] =
  ## Structural child nodes, shared with the diagnostics pass.
  if node == nil: return
  case node.kind
  of nkAssign: result.add(node.AssignNode.expression)
  of nkReturn: result.add(node.ReturnNode.expression)
  of nkMessage:
    result.add(node.MessageNode.receiver)
    result.add(node.MessageNode.arguments)
  of nkSuperSend: result.add(node.SuperSendNode.arguments)
  of nkLiteral:
    if node.LiteralNode.value.kind == vkBlock and node.LiteralNode.value.blockVal != nil:
      result.add(node.LiteralNode.value.blockVal.body)
  of nkBlock: result.add(node.BlockNode.body)
  of nkIf:
    result.add(@[node.IfNode.condition, node.IfNode.thenBranch, node.IfNode.elseBranch])
  of nkWhile: result.add(@[node.WhileNode.condition, node.WhileNode.body])
  of nkNamedAccess: result.add(@[node.NamedAccessNode.receiver, node.NamedAccessNode.valueExpr])
  of nkSlotAccess: result.add(node.SlotAccessNode.valueExpr)
  of nkArray: result.add(node.ArrayNode.elements)
  of nkTable:
    for entry in node.TableNode.entries: result.add(@[entry.key, entry.value])
  of nkCascade:
    result.add(node.CascadeNode.receiver)
    for message in node.CascadeNode.messages: result.add(message)
  of nkPrimitiveCall: result.add(node.PrimitiveCallNode.arguments)
  else: discard

proc methodBody(node: Node): BlockNode =
  if node == nil: return nil
  if node.kind == nkBlock: return node.BlockNode
  if node.kind == nkLiteral and node.LiteralNode.value.kind == vkBlock:
    return node.LiteralNode.value.blockVal

proc inferSlots*(nodes: seq[Node], classes: Table[string, ClassInfo]): InferenceResult =
  ## Advisory module evidence. No storage narrowing or source rewriting. Calls
  ## outside this source, dynamic selectors and method replacement remain open.
  var methods: seq[MethodEvidence]
  proc collect(node: Node) =
    if node == nil: return
    if node.kind == nkMessage:
      let msg = node.MessageNode
      if msg.selector in ["selector:put:", "classSelector:put:"] and
         msg.receiver != nil and msg.receiver.kind == nkIdent and msg.arguments.len == 2:
        let body = methodBody(msg.arguments[1])
        if body != nil and msg.arguments[0].kind == nkLiteral:
          let selector = msg.arguments[0].LiteralNode.value
          if selector.kind in {vkSymbol, vkString}:
            methods.add(MethodEvidence(owner: msg.receiver.IdentNode.name,
              selector: if selector.kind == vkSymbol: selector.symVal else: selector.strVal,
              body: body, classSide: msg.selector == "classSelector:put:"))
        return
    for child in nodeChildren(node): collect(child)
  for node in nodes: collect(node)

  var parameters: Table[string, SlotInference]
  var returns: Table[string, SlotInference]
  proc methodKey(index: int): string = $index
  proc target(selector, owner: string, classSide: bool): int =
    result = -1
    # Resolve lexical self/super owners first. Unknown receivers use only a
    # unique module selector as candidate evidence, never as a proof.
    var candidateOwner = owner
    var seen: HashSet[string]
    while candidateOwner.len > 0 and candidateOwner notin seen:
      seen.incl(candidateOwner)
      for index, methodInfo in methods:
        if methodInfo.owner == candidateOwner and methodInfo.classSide == classSide and methodInfo.selector == selector:
          return index
      if candidateOwner in classes and classes[candidateOwner].parent != nil:
        candidateOwner = classes[candidateOwner].parent.name
      else: candidateOwner = ""
    if owner.len > 0: return -1
    for index, methodInfo in methods:
      if methodInfo.selector == selector and not methodInfo.classSide:
        if result >= 0: return -1
        result = index

  proc kind(node: Node, locals: Table[string, SlotInference], owner: string,
            classSide: bool): SlotInference =
    if node == nil: return unknown()
    if node.kind == nkIdent:
      return locals.getOrDefault(node.IdentNode.name, unknown())
    if node.kind == nkPseudoVar:
      case node.PseudoVarNode.name
      of "nil": return SlotInference(nilSeen: true, reason: "nil literal")
      of "true", "false": return SlotInference(kind: skBool, conclusive: true)
      of "self": return SlotInference(kind: skObject, className: owner, conclusive: owner.len > 0)
      else: return unknown()
    if node.kind == nkLiteral:
      case node.LiteralNode.value.kind
      of vkInt: return SlotInference(kind: skInt, conclusive: true)
      of vkFloat: return SlotInference(kind: skFloat, conclusive: true)
      of vkBool: return SlotInference(kind: skBool, conclusive: true)
      of vkString: return SlotInference(kind: skString, conclusive: true)
      of vkSymbol: return SlotInference(kind: skSymbol, conclusive: true)
      of vkNil: return SlotInference(nilSeen: true, reason: "nil literal")
      else: return unknown()
    if node.kind == nkSuperSend:
      let parent = if owner in classes and classes[owner].parent != nil: classes[owner].parent.name else: ""
      if parent.len > 0:
        let index = target(node.SuperSendNode.selector, parent, classSide)
        return returns.getOrDefault(methodKey(index), unknown())
      return unknown()
    if node.kind != nkMessage: return unknown()
    let msg = node.MessageNode
    if msg.receiver != nil and msg.receiver.kind == nkIdent and msg.selector in ["new", "basicNew"]:
      let cls = msg.receiver.IdentNode.name
      if cls in classes: return SlotInference(kind: skObject, className: cls, conclusive: true)
    let left = kind(msg.receiver, locals, owner, classSide)
    if msg.arguments.len == 1:
      let right = kind(msg.arguments[0], locals, owner, classSide)
      if left.kind in {skInt, skFloat} and left.kind == right.kind and left.conclusive and right.conclusive:
        if msg.selector in ["+", "-", "*"]: return left
        if msg.selector in ["=", "<", ">", "<=", ">="]: return SlotInference(kind: skBool, conclusive: true)
    let selfSend = msg.receiver != nil and msg.receiver.kind == nkPseudoVar and msg.receiver.PseudoVarNode.name == "self"
    let index = target(msg.selector, if selfSend: owner elif left.kind == skObject: left.className else: "", classSide and selfSend)
    returns.getOrDefault(methodKey(index), unknown())

  # Bounded fixed point of call-site argument and method-return candidate facts.
  for iteration in 0..<8:
    var nextParameters: Table[string, SlotInference]
    var nextReturns: Table[string, SlotInference]
    proc scan(node: Node, locals: var Table[string, SlotInference], owner: string, classSide: bool) =
      if node == nil: return
      let blockNode = methodBody(node)
      if blockNode != nil:
        var nested = locals
        for name in blockNode.parameters & blockNode.temporaries: nested[name] = unknown()
        for statement in blockNode.body: scan(statement, nested, owner, classSide)
        return
      if node.kind == nkAssign:
        scan(node.AssignNode.expression, locals, owner, classSide)
        locals[node.AssignNode.variable] = kind(node.AssignNode.expression, locals, owner, classSide)
        return
      if node.kind == nkMessage:
        let msg = node.MessageNode
        if msg.selector in ["selector:put:", "classSelector:put:"]: return
        let receiver = kind(msg.receiver, locals, owner, classSide)
        let selfSend = msg.receiver != nil and msg.receiver.kind == nkPseudoVar and msg.receiver.PseudoVarNode.name == "self"
        let index = target(msg.selector, if selfSend: owner elif receiver.kind == skObject: receiver.className else: "", classSide and selfSend)
        if index >= 0:
          for i, arg in msg.arguments:
            let key = methodKey(index) & ":" & $i
            var evidence = nextParameters.getOrDefault(key)
            combine(evidence, kind(arg, locals, owner, classSide))
            nextParameters[key] = evidence
      for child in nodeChildren(node): scan(child, locals, owner, classSide)
    for index, methodInfo in methods:
      var locals: Table[string, SlotInference]
      for i, name in methodInfo.body.parameters:
        locals[name] = parameters.getOrDefault(methodKey(index) & ":" & $i, unknown())
      for name in methodInfo.body.temporaries: locals[name] = unknown()
      var answer: SlotInference
      for statement in methodInfo.body.body:
        scan(statement, locals, methodInfo.owner, methodInfo.classSide)
        if statement.kind == nkReturn:
          combine(answer, kind(statement.ReturnNode.expression, locals, methodInfo.owner, methodInfo.classSide))
      if answer.writes > 0: nextReturns[methodKey(index)] = answer
    var mainLocals: Table[string, SlotInference]
    for node in nodes: scan(node, mainLocals, "", false)
    parameters = nextParameters
    returns = nextReturns

  result.slots = initTable[string, SlotInference]()
  for name, cls in classes:
    for slot in cls.getAllSlots(): result.slots[name & "#" & slot.name] = SlotInference()
  var collected = result.slots
  var outside: HashSet[string]
  proc assignments(node: Node, locals: var Table[string, SlotInference], owner: string,
                   classSide: bool) =
    if node == nil: return
    let blockNode = methodBody(node)
    if blockNode != nil:
      var nested = locals
      for name in blockNode.parameters & blockNode.temporaries: nested[name] = unknown()
      for statement in blockNode.body: assignments(statement, nested, owner, classSide)
      return
    if node.kind == nkAssign:
      let assignment = node.AssignNode
      let evidence = kind(assignment.expression, locals, owner, classSide)
      let key = owner & "#" & assignment.variable
      if not classSide and assignment.variable notin locals and key in collected:
        var slot = collected[key]
        combine(slot, evidence)
        collected[key] = slot
      else: locals[assignment.variable] = evidence
    elif node.kind == nkNamedAccess and node.NamedAccessNode.isAssignment:
      outside.incl(node.NamedAccessNode.memberName)
    elif node.kind == nkSlotAccess and node.SlotAccessNode.isAssignment:
      outside.incl(node.SlotAccessNode.slotName)
    for child in nodeChildren(node): assignments(child, locals, owner, classSide)
  for index, methodInfo in methods:
    var locals: Table[string, SlotInference]
    for i, name in methodInfo.body.parameters:
      locals[name] = parameters.getOrDefault(methodKey(index) & ":" & $i, unknown())
    for name in methodInfo.body.temporaries: locals[name] = unknown()
    for statement in methodInfo.body.body:
      assignments(statement, locals, methodInfo.owner, methodInfo.classSide)
  var mainLocals: Table[string, SlotInference]
  for node in nodes:
    if node.kind != nkMessage or node.MessageNode.selector notin ["selector:put:", "classSelector:put:"]:
      assignments(node, mainLocals, "", false)
  for key, evidence in collected.mpairs:
    let name = key.split('#')[^1]
    if name in outside:
      combine(evidence, unknown("written from outside the class"))
    if evidence.writes == 0: result.unresolved.add(key)
  result.slots = collected

proc summarise*(inference: InferenceResult): string =
  var counts: array[SlotKind, int]
  for slot in inference.slots.values: inc counts[slot.kind]
  "slots=" & $inference.slots.len & " int=" & $counts[skInt] &
    " float=" & $counts[skFloat] & " bool=" & $counts[skBool] &
    " string=" & $counts[skString] & " symbol=" & $counts[skSymbol] &
    " object=" & $counts[skObject] & " dynamic=" & $counts[skDynamic] &
    " unresolved=" & $inference.unresolved.len

proc observedKind(tag: string): string =
  ## Map an observation tag to the static candidate vocabulary.
  let colon = tag.find(':')
  if colon < 0: return ""
  let kind = tag[colon + 1 .. ^1]
  case kind
  of "Integer": "skInt"
  of "Float": "skFloat"
  of "Boolean": "skBool"
  of "String": "skString"
  of "Symbol": "skSymbol"
  of "Nil": "Nil"
  else:
    if kind.startsWith("Object:"): "skObject" else: ""

proc reconcile(staticCandidate: SlotInference, counts: JsonNode): tuple[effective: string,
                                                                      source, reason: string] =
  ## Observations can only ever *reject* a static candidate here, or propose one
  ## when the module was silent. A dynamic slot is never narrowed as a result of
  ## a partial run, and any disagreement keeps it dynamic.
  var writes: seq[string]
  var nilWritten = false
  if counts != nil:
    for tag, count in counts:
      if not tag.startsWith("write:") or count.getInt == 0: continue
      let kind = observedKind(tag)
      if kind == "Nil": nilWritten = true
      elif kind.len > 0 and kind notin writes: writes.add(kind)

  # Smalltalk's numeric tower lets an Integer flow into a Float slot, but a
  # float64 cannot represent every 64-bit Integer. Rather than silently picking
  # a representation, report the conflict so the developer decides. Granite also
  # warns at compile time when an Integer is stored into a declared Float slot.
  var numericOnly = writes.len > 0
  for kind in writes:
    if kind notin ["skInt", "skFloat"]: numericOnly = false
  if numericOnly and "skFloat" in writes and "skInt" in writes:
    if nilWritten:
      return ("skDynamic", "observations", "nil observed at runtime")
    return ("skDynamic", "numeric-conflict",
            "Integer and Float both observed; declare Float or Integer")

  if nilWritten and staticCandidate.kind != skDynamic:
    return ("skDynamic", "observations", "nil observed at runtime")
  if staticCandidate.kind != skDynamic:
    for kind in writes:
      if kind != $staticCandidate.kind:
        return ("skDynamic", "observations", "contradicted by observations")
    return ($staticCandidate.kind, "static+observations", staticCandidate.reason)
  if writes.len == 1 and not nilWritten:
    return (writes[0], "observed-proposal", "single observed write kind, still unproven")
  return ($staticCandidate.kind, "static", staticCandidate.reason)

proc inferenceReport*(inference: InferenceResult, feedback: JsonNode = nil): JsonNode =
  ## Static and observed facts stay separate; the merged field names its evidence.
  result = %*{"schema": 1, "semantics": "advisory-no-storage-narrowing", "slots": {}}
  var keys: seq[string]
  for key in inference.slots.keys: keys.add(key)
  if feedback != nil and feedback["slots"].kind == JObject:
    for key in feedback["slots"].keys:
      if key notin keys: keys.add(key)
  keys.sort()
  for key in keys:
    let slot = inference.slots.getOrDefault(key, unknown("not declared in module"))
    let counts = if feedback != nil and feedback["slots"].hasKey(key): feedback["slots"][key] else: nil
    let merged = reconcile(slot, counts)
    result["slots"][key] = %*{"staticCandidate": $slot.kind, "objectClass": slot.className,
      "nilSeen": slot.nilSeen, "writes": slot.writes, "reason": slot.reason,
      "effectiveCandidate": merged.effective, "evidence": merged.source,
      "effectiveReason": merged.reason,
      "requiresGuard": true,
      "storageNarrowed": false}
    if counts != nil:
      result["slots"][key]["observations"] = counts
