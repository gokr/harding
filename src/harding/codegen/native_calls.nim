import std/[tables, strutils, sequtils, sets]
import ../core/types
import ../compiler/symbols
import ../compiler/context
import ../compiler/types

type
  IntegerCallPlan* = object
    ## Pure Integer region. Every transitive method dependency must be guarded
    ## before entry; no callbacks or heap mutation can invalidate it inside.
    eligible*: bool
    arity*: int
    expression*: string
    statements*: string
    dependencies*: seq[string]
    slotWrites*: seq[string]
    slotReads*: seq[string]
    touchedSlots*: seq[string]  ## deduplicated reads + writes, for entry guards
  IntegerPlans* = Table[string, IntegerCallPlan]

proc integerStem*(owner, selector: string): string =
  "integerCall_" & mangleClass(owner) & "_" & mangleSlot(selector)

proc nativeIntegerSlot(cls: ClassInfo, name: string): bool =
  ## A slot this region may touch as a Nim int field: declared Integer, so
  ## storage is native and writes are contract-checked at every other boundary.
  if cls == nil: return false
  for slot in cls.getAllSlots():
    if slot.name == name:
      return slot.constraint == tcInt
  return false

proc planIntegerCall*(owner: string, parameters: seq[string], body: seq[Node],
                      known: IntegerPlans, temporaries: seq[string] = @[],
                      cls: ClassInfo = nil): IntegerCallPlan =
  ## Integer arguments, definitely initialized Integer locals, structured
  ## branches/loops with an explicit final return, and direct access to declared
  ## Integer slots of the receiver class. No escaping blocks, recursion,
  ## parameter assignment, division, non-local returns or dynamic slots.
  if parameters.len == 0 or body.len == 0 or body[^1].kind != nkReturn: return
  proc slotNameOf(node: Node): string =
    let slotNode = node.SlotAccessNode
    if slotNode.slotName.len > 0: return slotNode.slotName
    if cls != nil:
      for slot in cls.getAllSlots():
        if slot.index == slotNode.slotIndex: return slot.name
    return ""

  var dependencies: seq[string]
  var initialized = initHashSet[string]()
  var written = initHashSet[string]()
  var read = initHashSet[string]()
  for name in parameters: initialized.incl(name)

  proc expression(node: Node, available: HashSet[string], boolean = false): string =
    if node == nil: return ""
    case node.kind
    of nkIdent:
      let name = node.IdentNode.name
      if not boolean and name in available:
        return mangleIdentifier(name)
      # A receiver slot reads as a plain field. The entry guard already proved
      # the receiver is this exact compiled class with native storage, so no
      # per-access accessor round trip is needed inside the region.
      if not boolean and name notin parameters and name notin temporaries:
        if nativeIntegerSlot(cls, name):
          read.incl(name)
          return "self[]." & mangleSlot(name)
    of nkLiteral:
      let value = node.LiteralNode.value
      if not boolean and value.kind == vkInt: return $value.intVal
      if boolean and value.kind == vkBool: return $value.boolVal
    of nkSlotAccess:
      if not boolean and not node.SlotAccessNode.isAssignment:
        let name = slotNameOf(node)
        if name.len > 0 and nativeIntegerSlot(cls, name):
          read.incl(name)
          return "self[]." & mangleSlot(name)
    of nkPseudoVar:
      if boolean and node.PseudoVarNode.name in ["true", "false"]:
        return node.PseudoVarNode.name
    of nkMessage:
      let message = node.MessageNode
      if not boolean and message.receiver != nil and message.receiver.kind == nkPseudoVar and
         message.receiver.PseudoVarNode.name == "self" and message.selector in known:
        var arguments: seq[string]
        for argument in message.arguments:
          let value = expression(argument, available)
          if value.len == 0: return ""
          arguments.add(value)
        if arguments.len != known[message.selector].arity: return ""
        for dependency in @[message.selector] & known[message.selector].dependencies:
          if dependency notin dependencies: dependencies.add(dependency)
        return integerStem(owner, message.selector) & "_native(" & arguments.join(", ") & ")"
      let supported = if boolean: message.selector in ["<", "<=", ">", ">=", "=", "<>"]
                      else: message.selector in ["+", "-", "*"]
      if message.arguments.len == 1 and supported:
        # Do not move literal-only operations into Nim's constant evaluator.
        if message.receiver.kind == nkLiteral and message.arguments[0].kind == nkLiteral: return ""
        let left = expression(message.receiver, available)
        let right = expression(message.arguments[0], available)
        let op = case message.selector
                 of "=": "=="
                 of "<>": "!="
                 else: message.selector
        if left.len > 0 and right.len > 0:
          return "(" & left & " " & op & " " & right & ")"
    else: discard
    return ""

  proc blockBody(node: Node): seq[Node] =
    if node == nil: return @[]
    let blk = if node.kind == nkBlock: node.BlockNode
              elif node.kind == nkLiteral and node.LiteralNode.value.kind == vkBlock:
                node.LiteralNode.value.blockVal
              else: nil
    # Block-local shadowing and parameters require a separate scope analysis.
    if blk != nil and blk.parameters.len == 0 and blk.temporaries.len == 0:
      return blk.body
    return @[]

  proc condition(node: Node, available: HashSet[string]): string =
    let statements = blockBody(node)
    if statements.len == 1: return expression(statements[0], available, true)
    return expression(node, available, true)

  proc statements(nodes: seq[Node], available: var HashSet[string], depth: int,
                  code: var string): bool =
    let indent = " ".repeat(depth)
    for node in nodes:
      if node == nil:
        return false
      case node.kind
      of nkAssign:
        let assignment = node.AssignNode
        let value = expression(assignment.expression, available)
        if value.len == 0:
          return false
        if assignment.variable in temporaries:
          code.add(indent & mangleIdentifier(assignment.variable) & " = " & value & "\n")
          available.incl(assignment.variable)
        elif nativeIntegerSlot(cls, assignment.variable):
          # Declared Integer storage is already an int field and every write is
          # contract-checked here: the value came from int arithmetic or an int
          # field, so it cannot violate the slot contract.
          code.add(indent & "self[]." & mangleSlot(assignment.variable) &
                   " = " & value & "\n")
          written.incl(assignment.variable)
        else:
          return false
      of nkSlotAccess:
        let slotNode = node.SlotAccessNode
        let name = slotNameOf(node)
        if not slotNode.isAssignment or name.len == 0 or
           not nativeIntegerSlot(cls, name): return false
        let value = expression(slotNode.valueExpr, available)
        if value.len == 0: return false
        # Declared Integer storage is already an int field and every other
        # boundary contract-checks it; inside the region the value is an int.
        code.add(indent & "self[]." & mangleSlot(name) & " = " & value & "\n")
        written.incl(name)
      of nkIf:
        let branch = node.IfNode
        let test = condition(branch.condition, available)
        let yes = blockBody(branch.thenBranch)
        if test.len == 0 or yes.len == 0:
          return false
        var yesAvailable = available
        code.add(indent & "if " & test & ":\n")
        if not statements(yes, yesAvailable, depth + 2, code): return false
        if branch.elseBranch != nil:
          let no = blockBody(branch.elseBranch)
          if no.len == 0:
            return false
          var noAvailable = available
          code.add(indent & "else:\n")
          if not statements(no, noAvailable, depth + 2, code): return false
          # Only assignments executed on both paths establish initialization.
          for name in yesAvailable:
            if name in noAvailable: available.incl(name)
      of nkWhile:
        let loop = node.WhileNode
        let test = condition(loop.condition, available)
        let loopBody = blockBody(loop.body)
        if test.len == 0 or loopBody.len == 0:
          return false
        var loopAvailable = available
        code.add(indent & "while " & (if loop.isWhileTrue: test else: "not (" & test & ")") & ":\n")
        if not statements(loopBody, loopAvailable, depth + 2, code): return false
        # A zero-iteration loop cannot establish a local's initialization.
      else:
        return false
    return true

  var code: string
  if not statements(body[0 ..< body.len - 1], initialized, 2, code):
    return
  let answer = expression(body[^1].ReturnNode.expression, initialized)
  if answer.len == 0:
    return
  result.expression = answer
  if body.len > 1:
    for name in temporaries:
      code = "  var " & mangleIdentifier(name) & ": int\n" & code
    result.statements = code & "  return " & answer & "\n"
  result.eligible = true
  result.arity = parameters.len
  result.dependencies = dependencies
  result.slotWrites = written.toSeq
  result.slotReads = read.toSeq
  var touched = initHashSet[string]()
  for name in written.toSeq & read.toSeq:
    if name notin touched:
      touched.incl(name)
      result.touchedSlots.add(name)

proc emitIntegerCall*(owner, selector: string, parameters: seq[string],
                      plan: IntegerCallPlan): tuple[code, helper: string] =
  ## Arguments arrive evaluated before any guard. The entire pure call chain
  ## stays in int signatures; boxing happens only at this dynamic boundary.
  let stem = integerStem(owner, selector)
  let args = parameters.mapIt(mangleIdentifier(it))
  let boundary = parameters.mapIt("argument_" & mangleIdentifier(it))
  let usesSelf = plan.slotReads.len > 0 or plan.slotWrites.len > 0
  result.helper = stem
  # A region that touches slots takes the typed receiver, so field access is a
  # plain load/store instead of an accessor call per read and write.
  result.code = "proc " & stem & "_native*(" &
                (if usesSelf: "self: " & mangleClass(owner) & ", " else: "") &
                args.join(", ") & ": int): int =\n"
  if plan.statements.len > 0: result.code.add(plan.statements)
  else: result.code.add("  " & plan.expression & "\n")
  for dependency in @[selector] & plan.dependencies:
    result.code.add("var " & stem & "_guard_" & mangleSlot(dependency) & " {.threadvar.}: CompiledDirectGuard\n")
  for slot in plan.touchedSlots:
    # Reuses the generated per-slot accessor guard, which tracks
    # compiledSlotAccessorVersion and compares the registered getter/setter, so a
    # replaced accessor disables the region instead of being bypassed.
    result.code.add("proc nativeSlotAccessorGuard_" & mangleClass(owner) & "_" & mangleSlot(slot) &
                    "(receiver: NodeValue): bool {.inline.} =\n" &
                    "  " & mangleClass(owner) & "_direct_" & mangleSlot(slot) & "_guard(receiver)\n")
  result.code.add("proc " & stem & "(owner, receiver: NodeValue, " & boundary.join(", ") & ": NodeValue): NodeValue =\n")
  var checks = boundary.mapIt(it & ".kind == vkInt")
  # A region that reads or writes slots touches storage the accessor table can
  # redirect (registerSlotAccessor / a redefined getter). The per-access guards
  # in ordinary code exist for that; here the same check runs once at entry, so
  # a replaced accessor falls back to normal dispatch instead of being bypassed.
  for slot in plan.touchedSlots:
    checks.add("nativeSlotAccessorGuard_" & mangleClass(owner) & "_" & mangleSlot(slot) & "(receiver)")
  for dependency in @[selector] & plan.dependencies:
    checks.add("canDirectCompiledSend(receiver, compiledClassValue(\"" & owner & "\").classVal, \"" & dependency & "\", " & mangleClass(owner) & "_" & mangleSelector(dependency) & ", " & stem & "_guard_" & mangleSlot(dependency) & ")")
  result.code.add("  if " & checks.join(" and ") & ":\n")
  let nativeCall = stem & "_native(" &
                   (if usesSelf: "cast[" & mangleClass(owner) & "](receiver.instVal.compiledOwner)" & (if boundary.len > 0: ", " else: "") else: "") &
                   boundary.mapIt(it & ".intVal").join(", ") & ")"
  result.code.add("    return toValue(" & nativeCall & ")\n")
  result.code.add("  sendMessageBound(owner, receiver, \"" & selector & "\", @[" & boundary.join(", ") & "])\n\n")
