import std/[tables, strutils, sequtils, sets, os]
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
    ## True when any touched callee also reads the receiver, so this region must
    ## take the typed receiver itself and forward it.
    needsReceiver*: bool
    expression*: string
    statements*: string
    dependencies*: seq[string]
    slotWrites*: seq[string]
    slotReads*: seq[string]
    touchedSlots*: seq[string]  ## deduplicated reads + writes, for entry guards
    objectParameters*: Table[string, string]  ## typed reference parameters
    fieldReadObjects*: seq[string]  ## object params whose typed fields are read
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
                      cls: ClassInfo = nil, returnBoolean = false,
                      objects: Table[string, string] = default(Table[string, string]),
                      allClasses: Table[string, ClassInfo] = default(Table[string, ClassInfo]),
                      selfSelector: string = ""): IntegerCallPlan =
  ## Integer arguments, definitely initialized Integer locals, structured
  ## branches/loops with an explicit final return, and direct access to declared
  ## Integer slots of the receiver class. No escaping blocks, recursion,
  ## division, non-local returns or dynamic slots.
  # A body may end either in `^expr` or in a conditional that returns from every
  # branch; both leave the region exactly once.
  # Boolean regions answer from an explicit `^boolExpr` only. A conditional tail
  # is accepted for Integer regions, where a branch returning an int is the
  # answer; inferring that as a bool would be a silent miscompile.
  let endsWithConditional = not returnBoolean and body.len > 0 and
                             body[^1].kind == nkIf and body[^1].IfNode.elseBranch != nil
  if parameters.len == 0 or body.len == 0 or
     (body[^1].kind != nkReturn and not endsWithConditional): return
  proc slotNameOf(node: Node): string =
    let slotNode = node.SlotAccessNode
    if slotNode.slotName.len > 0: return slotNode.slotName
    if cls != nil:
      for slot in cls.getAllSlots():
        if slot.index == slotNode.slotIndex: return slot.name
    return ""

  var dependencies: seq[string]
  var needsReceiver = false
  var fieldReadObjects = initHashSet[string]()
  var initialized = initHashSet[string]()
  var written = initHashSet[string]()
  var read = initHashSet[string]()
  for name in parameters: initialized.incl(name)

  proc conditionalBranchValue(branch: Node, available: HashSet[string]): string {.used.}

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

  proc expression(node: Node, available: HashSet[string], boolean = false): string =
    if node == nil: return ""
    case node.kind
    of nkIdent:
      let name = node.IdentNode.name
      # An object parameter is a typed reference; reading it needs no boxing.
      if not boolean and name in objects and name in available:
        return mangleIdentifier(name)
      if not boolean and name in available:
        return mangleIdentifier(name)
      # A receiver slot reads as a plain field. The entry guard already proved
      # the receiver is this exact compiled class with native storage, so no
      # per-access accessor round trip is needed inside the region.
      if not boolean and name notin parameters and name notin temporaries:
        if nativeIntegerSlot(cls, name):
          read.incl(name)
          return "self[]." & mangleSlot(name)
    of nkIf:
      # `c ifTrue: [a] ifFalse: [b]` used as a value. The parser lowered the send
      # form already, so the conditional arrives as nkIf here. Each branch must be
      # a single native expression. Boolean regions answer from an explicit
      # `^boolExpr`, so a value conditional must not be inferred there: its branch
      # values need not be Boolean.
      if boolean: return ""
      let branch = node.IfNode
      let test = expression(branch.condition, available, true)
      if test.len > 0 and branch.thenBranch != nil and branch.elseBranch != nil:
        let yes = conditionalBranchValue(branch.thenBranch, available)
        let no = conditionalBranchValue(branch.elseBranch, available)
        if yes.len > 0 and no.len > 0:
          return "(if " & test & ": " & yes & " else: " & no & ")"
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
      # Short-circuit `and:`/`or:` between two native conditions. The argument is
      # a block literal whose single statement is the second condition.
      if boolean and message.selector in ["and:", "or:"] and
         message.arguments.len == 1:
        let left = expression(message.receiver, available, true)
        var right = ""
        let body = blockBody(message.arguments[0])
        if body.len == 1: right = expression(body[0], available, true)
        if left.len > 0 and right.len > 0:
          let op = if message.selector == "and:": "and" else: "or"
          return "((" & left & ") " & op & " (" & right & "))"
      # `x isNil` on a typed reference is a pointer compare, not a send.
      if boolean and message.arguments.len == 0 and
         message.selector in ["isNil", "notNil"] and message.receiver != nil and
         message.receiver.kind == nkIdent:
        let name = message.receiver.IdentNode.name
        if name in objects and name in available:
          let op = if message.selector == "isNil": "== " else: "!= "
          return "(" & mangleIdentifier(name) & " " & op & "nil)"
      # `node left isNil`: a nil test on an object-typed slot of a typed reference.
      if boolean and message.arguments.len == 0 and
         message.selector in ["isNil", "notNil"] and message.receiver != nil and
         message.receiver.kind == nkMessage:
        let inner = message.receiver.MessageNode
        if inner.arguments.len == 0 and inner.receiver != nil and
           inner.receiver.kind == nkIdent:
          let refName = inner.receiver.IdentNode.name
          if refName in objects and refName in available:
            let target = objects[refName]
            if target in allClasses and
               allClasses[target].getSlotDef(inner.selector).constraint == tcObject:
              fieldReadObjects.incl(refName)
              let slotDef = allClasses[target].getSlotDef(inner.selector)
              let field = "cast[" & mangleClass(target) & "](" & mangleIdentifier(refName) &
                          ".compiledOwner)[]. " & mangleSlot(inner.selector)
              let nilTest = if slotDef.nativeObject: field & ".instance == nil"
                            else: "isNilValue(" & field & ")"
              return (if message.selector == "isNil": "(" & nilTest & ")"
                      else: "(not (" & nilTest & "))")
      # `o amount` where o is a typed reference: an Integer slot of the declared
      # class reads as a plain field through the reference, with no send.
      if not boolean and message.arguments.len == 0 and message.receiver != nil and
         message.receiver.kind == nkIdent:
        let refName = message.receiver.IdentNode.name
        if refName in objects and refName in available:
          let target = objects[refName]
          if target in allClasses and nativeIntegerSlot(name = message.selector,
                                                        cls = allClasses[target]):
            # Do NOT record this as a touched slot of the region's own receiver:
            # the guard table belongs to the parameter's class, and a plain field
            # read through an already class-checked reference has no accessor to
            # redirect.
            # The typed view lives in compiledOwner, exactly as the direct field
            # helpers read it. A nil argument must not reach this read, so the
            # entry guard requires non-nil (see fieldReadObjects below).
            fieldReadObjects.incl(refName)
            return "cast[" & mangleClass(target) & "](" & mangleIdentifier(refName) &
                   ".compiledOwner)[]. " & mangleSlot(message.selector)
          # An object-typed slot read yields the stored Instance, so it flows into
          # a recursive call with no NodeValue hop. A typed wrapper carries both
          # the native view and the original Instance.
          if target in allClasses:
            let slot = allClasses[target].getSlotDef(message.selector)
            if slot.constraint == tcObject:
              fieldReadObjects.incl(refName)
              let field = "cast[" & mangleClass(target) & "](" & mangleIdentifier(refName) &
                          ".compiledOwner)[]. " & mangleSlot(message.selector)
              return "(if " & (if slot.nativeObject: field & ".instance == nil"
                               else: "isNilValue(" & field & ")") & ": nil else: " &
                     (if slot.nativeObject: field & ".instance" else: field & ".instVal") & ")"
      # Recursion: a self-send of this very selector has this region's own
      # signature, so it needs no separate plan and its result is this region's
      # Integer result. That is what lets `f x + f y` type without a declared
      # return contract on the method.
      if not boolean and selfSelector.len > 0 and message.receiver != nil and
         message.receiver.kind == nkPseudoVar and
         message.receiver.PseudoVarNode.name == "self" and
         message.selector == selfSelector:
        var arguments: seq[string]
        for argument in message.arguments:
          let value = expression(argument, available)
          if value.len == 0: return ""
          arguments.add(value)
        if arguments.len != parameters.len: return ""
        # The recursive call is this region, so it needs the receiver exactly when
        # this region does. Request it now: `read`/`written` may be filled later.
        # This region needs the receiver because the recursive call passes it.
        needsReceiver = true
        return integerStem(owner, message.selector) & "_native(self, " &
               arguments.join(", ") & ")"
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
        # A callee region that touches its receiver takes it as a typed first
        # parameter; omitting it makes the generated call arity-mismatched.
        let callee = known[message.selector]
        let calleeNeedsReceiver = callee.touchedSlots.len > 0 or callee.needsReceiver
        if calleeNeedsReceiver: needsReceiver = true
        let receiverArg = if calleeNeedsReceiver: "self, " else: ""
        return integerStem(owner, message.selector) & "_native(" & receiverArg &
               arguments.join(", ") & ")"
      # A conditional used as a value: `c ifTrue: [a] ifFalse: [b]` answers one of
      # two native expressions. Only the value form fits here; a branch that
      # returns is handled by the statement walker instead.
      if not boolean and message.selector in ["ifTrue:ifFalse:", "ifFalse:ifTrue:"] and
         message.arguments.len == 2:
        let test = expression(message.receiver, available, true)
        if test.len > 0:
          let positive = message.selector == "ifTrue:ifFalse:"
          let firstArg = if positive: message.arguments[0] else: message.arguments[1]
          let secondArg = if positive: message.arguments[1] else: message.arguments[0]
          let yes = conditionalBranchValue(firstArg, available)
          let no = conditionalBranchValue(secondArg, available)
          if yes.len > 0 and no.len > 0:
            return "(if " & test & ": " & yes & " else: " & no & ")"
      # `c ifTrue: [a]` used as a value answers nil when the test fails.
      if not boolean and message.selector in ["ifTrue:", "ifFalse:"] and
         message.arguments.len == 1:
        let test = expression(message.receiver, available, true)
        if test.len > 0:
          let positive = message.selector == "ifTrue:"
          let yes = conditionalBranchValue(message.arguments[0], available)
          if yes.len > 0:
            return "(if " & (if positive: test else: "not (" & test & ")") & ": " &
                   yes & " else: 0)"
      let supported = if boolean: message.selector in ["<", "<=", ">", ">=", "=", "<>"]
                      else: message.selector in ["+", "-", "*", "//"]
      if not boolean and message.arguments.len == 1 and message.selector == "//":
        # Integer division must keep Harding's division-by-zero error rather
        # than turning a zero divisor into a Nim DivisionByZeroDefect. The
        # runtime helper answers exactly this, so reuse its contract.
        let left = expression(message.receiver, available)
        let right = expression(message.arguments[0], available)
        if left.len > 0 and right.len > 0:
          return "compiledIntegerDiv(" & left & ", " & right & ")"
        return ""
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

  proc condition(node: Node, available: HashSet[string]): string =
    let statements = blockBody(node)
    if statements.len == 1: return expression(statements[0], available, true)
    return expression(node, available, true)

  proc earlyReturnValue(branch: Node, available: HashSet[string]): string =
    ## A branch whose body is exactly one `^expr` becomes a native early return.
    ## `(c) ifTrue: [^x]` is the most common Smalltalk method shape, and without
    ## this every method that used one was rejected as a region.
    let body = blockBody(branch)
    if body.len != 1 or body[0].kind != nkReturn: return ""
    expression(body[0].ReturnNode.expression, available)

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
        if assignment.variable in temporaries or assignment.variable in parameters:
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
        if test.len == 0:
          return false
        let yesReturn = earlyReturnValue(branch.thenBranch, available)
        let noReturn = if branch.elseBranch != nil:
                         earlyReturnValue(branch.elseBranch, available) else: ""
        if yesReturn.len > 0 and (branch.elseBranch == nil or noReturn.len > 0):
          # Both paths leave the region: `if c: return a` / `else: return b`.
          code.add(indent & "if " & test & ":\n")
          code.add(indent & "  return " & yesReturn & "\n")
          if branch.elseBranch != nil:
            code.add(indent & "else:\n" & indent & "  return " & noReturn & "\n")
        elif noReturn.len > 0 and yesReturn.len == 0:
          # Only the else path leaves: `if not c: return b`, then fall through.
          code.add(indent & "if not (" & test & "):\n")
          code.add(indent & "  return " & noReturn & "\n")
        elif yesReturn.len > 0:
          # Only the then path leaves; the rest of the body continues.
          code.add(indent & "if " & test & ":\n")
          code.add(indent & "  return " & yesReturn & "\n")
        else:
          let yes = blockBody(branch.thenBranch)
          if yes.len == 0:
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
  # A body that ends in a conditional returning on every branch needs no separate
  # tail expression: the region already answers from inside the branches.
  let tailIsConditional = endsWithConditional
  proc conditionalBranchValue(branch: Node, available: HashSet[string]): string =
    ## A branch usable as a value: one expression, or one explicit return.
    let body = blockBody(branch)
    if body.len != 1: return ""
    if body[0].kind == nkReturn:
      return expression(body[0].ReturnNode.expression, available)
    expression(body[0], available)

  var answer = ""
  if tailIsConditional:
    if not statements(body, initialized, 2, code): return
  else:
    if not statements(body[0 ..< body.len - 1], initialized, 2, code):
      return
    answer = expression(body[^1].ReturnNode.expression, initialized, returnBoolean)
    if answer.len == 0:
      return
  result.expression = answer
  # Emit statements only when the body needs them: a single-expression region
  # is a bare `return expr` and its parameters are read directly. A conditional
  # tail always needs the statements, including for a one-statement body.
  if tailIsConditional or body.len > 1 or temporaries.len > 0:
    for name in temporaries:
      code = "  var " & mangleIdentifier(name) & ": int\n" & code
    for name in parameters:
      code = "  var " & mangleIdentifier(name) & " = hardingNativeArg_" & mangleIdentifier(name) & "\n" & code
    result.statements = code & (if tailIsConditional: "" else: "  return " & answer & "\n")
  result.eligible = true
  result.arity = parameters.len
  result.dependencies = dependencies
  result.slotWrites = written.toSeq
  result.slotReads = read.toSeq
  result.needsReceiver = needsReceiver
  result.objectParameters = objects
  result.fieldReadObjects = fieldReadObjects.toSeq
  var touched = initHashSet[string]()
  for name in written.toSeq & read.toSeq:
    if name notin touched:
      touched.incl(name)
      result.touchedSlots.add(name)

proc planBooleanCall*(owner: string, parameters: seq[string], body: seq[Node],
                      temporaries: seq[string] = @[], cls: ClassInfo = nil): IntegerCallPlan =
  ## Reuse definite initialization and Integer expression inference, but require
  ## an explicitly Boolean final expression. Native int parameters/locals stay
  ## unboxed through a bool return. Method and slot guards belong at the caller.
  planIntegerCall(owner, parameters, body, initTable[string, IntegerCallPlan](),
                  temporaries, cls, returnBoolean = true)

proc emitBooleanCall*(owner, selector: string, parameters: seq[string],
                      plan: IntegerCallPlan): tuple[code, helper: string] =
  ## A checked bool-return boundary for already-native Integer arguments. A
  ## replaced method can return anything: only isTruthy on the fallback applies
  ## the ordinary condition contract, never an unchecked boolVal projection.
  let stem = "booleanCall_" & mangleClass(owner) & "_" & mangleSlot(selector)
  let usesSelf = plan.touchedSlots.len > 0
  let receiverType = mangleClass(owner)
  let names = parameters.mapIt(mangleIdentifier(it))
  let nativeNames = parameters.mapIt((if plan.statements.len > 0: "hardingNativeArg_" else: "") & mangleIdentifier(it))
  let target = receiverType & "_" & mangleSelector(selector)
  result.helper = stem
  result.code = "proc " & target & "*(self: NodeValue, args: openArray[NodeValue]): NodeValue\n"
  result.code.add("proc " & stem & "_native*(" &
    (if usesSelf: "self: " & receiverType & ", " else: "") & nativeNames.join(", ") & ": int): bool =\n")
  if plan.statements.len > 0: result.code.add(plan.statements)
  else: result.code.add("  " & plan.expression & "\n")
  result.code.add("var " & stem & "_class {.threadvar.}: Class\n")
  result.code.add("var " & stem & "_guard {.threadvar.}: CompiledDirectGuard\n")
  result.code.add("proc " & stem & "(owner, receiver: NodeValue, " & names.join(", ") & ": int): bool =\n")
  result.code.add("  if " & stem & "_class == nil: " & stem & "_class = compiledClassValue(\"" & owner & "\").classVal\n")
  var checks = @["not hostRoutingActive()", "canDirectCompiledSend(receiver, " & stem & "_class, \"" & selector & "\", " & target & ", " & stem & "_guard)"]
  for slot in plan.touchedSlots:
    checks.add(receiverType & "_direct_" & mangleSlot(slot) & "_guard(receiver)")
  result.code.add("  if " & checks.join(" and ") & ":\n")
  result.code.add("    return " & stem & "_native(" &
    (if usesSelf: receiverType & "(receiver.instVal.compiledOwner), " else: "") &
    names.join(", ") & ")\n")
  result.code.add("  isTruthy(cachedSendBound(owner, receiver, \"" & selector & "\", [" &
    names.mapIt("toValue(" & it & ")").join(", ") & "]))\n\n")

proc emitIntegerResult*(owner, selector: string, parameters: seq[string],
                        plan: IntegerCallPlan): tuple[code, helper: string] =
  ## Integer-returning variant for use inside a native expression. The helper
  ## reports success separately instead of returning a sentinel: a replacement,
  ## subclass override or redirected accessor must fall back to the ordinary
  ## send, and a fabricated int cannot express that.
  let stem = "integerResult_" & mangleClass(owner) & "_" & mangleSlot(selector)
  let receiverType = mangleClass(owner)
  let usesSelf = plan.touchedSlots.len > 0 or plan.needsReceiver
  proc paramType(name: string): string =
    if name in plan.objectParameters: "Instance" else: "int"
  let names = parameters.mapIt(mangleIdentifier(it) & ": NodeValue")
  let nativeNames = parameters.mapIt((if plan.statements.len > 0: "hardingNativeArg_" else: "") &
    mangleIdentifier(it) & ": " & paramType(it))
  let target = receiverType & "_" & mangleSelector(selector)
  result.helper = stem
  # The forward declaration belongs to emitIntegerCall, which always runs for the
  # same plan; declaring it here too makes Nim expect two implementations.
  result.code = "proc " & stem & "_native*(" &
    (if usesSelf: "self: " & receiverType & ", " else: "") & nativeNames.join(", ") & "): int =\n"
  if plan.statements.len > 0: result.code.add(plan.statements)
  else: result.code.add("  " & plan.expression & "\n")
  result.code.add("var " & stem & "_class {.threadvar.}: Class\n")
  result.code.add("var " & stem & "_guard {.threadvar.}: CompiledDirectGuard\n")
  result.code.add("proc " & stem & "(owner, receiver: NodeValue, " &
    "hardingIntegerOut: var int" &
    (if names.len > 0: ", " & names.join(", ") else: "") & "): bool =\n")
  result.code.add("  if " & stem & "_class == nil: " & stem & "_class = compiledClassValue(\"" & owner & "\").classVal\n")
  var checks = @["not hostRoutingActive()"]
  for index, name in parameters:
    if name in plan.objectParameters:
      checks.add("compiledObjectArgumentMatches(" & mangleIdentifier(name) & ", \"" &
                 plan.objectParameters[name] & "\")")
      if name in plan.fieldReadObjects:
        checks.add("not isNilValue(" & mangleIdentifier(name) & ")")
    else:
      checks.add(mangleIdentifier(name) & ".kind == vkInt")
  checks.add("canDirectCompiledSend(receiver, " & stem & "_class, \"" & selector & "\", " & target & ", " & stem & "_guard)")
  for slot in plan.touchedSlots:
    checks.add(receiverType & "_direct_" & mangleSlot(slot) & "_guard(receiver)")
  result.code.add("  if " & checks.join(" and ") & ":\n")
  result.code.add("    hardingIntegerOut = " & stem & "_native(" &
    (if usesSelf: receiverType & "(receiver.instVal.compiledOwner), " else: "") &
    parameters.mapIt(if it in plan.objectParameters:
                       "(if isNilValue(" & mangleIdentifier(it) & "): nil else: " &
                       mangleIdentifier(it) & ".instVal)"
                     else: mangleIdentifier(it) & ".intVal").join(", ") & ")\n")
  result.code.add("    return true\n")
  result.code.add("  false\n\n")

proc referencesSelf*(node: Node): bool =
  ## True if the body can observe its receiver (directly, through a slot-like
  ## identifier, or inside a nested block). A receiver-free body is safe to call
  ## through a call-site guard, because no stale entry can see a different self.
  if node == nil: return false
  case node.kind
  of nkPseudoVar:
    node.PseudoVarNode.name == "self"
  of nkSlotAccess, nkNamedAccess: true
  of nkMessage:
    let message = node.MessageNode
    if referencesSelf(message.receiver): return true
    for argument in message.arguments:
      if referencesSelf(argument): return true
    false
  of nkAssign:
    let assignment = node.AssignNode
    referencesSelf(assignment.expression)
  of nkReturn:
    referencesSelf(node.ReturnNode.expression)
  of nkBlock:
    let blk = node.BlockNode
    for statement in blk.body:
      if referencesSelf(statement): return true
    false
  of nkIf:
    let branch = node.IfNode
    referencesSelf(branch.condition) or referencesSelf(branch.thenBranch) or
      referencesSelf(branch.elseBranch)
  of nkWhile:
    let loop = node.WhileNode
    referencesSelf(loop.condition) or referencesSelf(loop.body)
  of nkLiteral:
    let value = node.LiteralNode.value
    if value.kind == vkBlock and value.blockVal != nil:
      for statement in value.blockVal.body:
        if referencesSelf(statement): return true
    false
  else: false

proc bodyReferencesSelf*(body: seq[Node]): bool =
  for node in body:
    if referencesSelf(node): return true
  false

proc planStaticClassCall*(owner: string, parameters: seq[string], body: seq[Node],
                          temporaries: seq[string] = @[]): IntegerCallPlan =
  ## Reuse the Integer region planner for a class-side method that provably does
  ## not depend on the receiver at all.
  if parameters.len == 0 or bodyReferencesSelf(body): return
  result = planIntegerCall(owner, parameters, body,
                           initTable[string, IntegerCallPlan](), temporaries, nil)

proc booleanReturnExpression*(body: seq[Node], parameter: string): string =
  ## A pure Boolean-return projection. Only literal returns or the Boolean
  ## argument are accepted; no callbacks, slots, primitives or extra statements.
  if body.len != 1 or body[0].kind != nkReturn: return ""
  let value = body[0].ReturnNode.expression
  if value == nil: return ""
  if value.kind == nkIdent and value.IdentNode.name == parameter: return "right"
  if value.kind == nkPseudoVar and value.PseudoVarNode.name in ["true", "false"]:
    return value.PseudoVarNode.name
  if value.kind == nkLiteral and value.LiteralNode.value.kind == vkBool:
    return $value.LiteralNode.value.boolVal

proc nilPredicateExpression*(selector: string, bodies: Table[string, BlockNode],
                             trueNot, falseNot: string): tuple[expression: string, dependencies: seq[string]] =
  ## Expand a pure self-send chain from source, ending at identity equality and
  ## source-derived Boolean negation. The caller guards every expanded method.
  var dependencies: seq[string]
  proc expand(node: Node, environment: Table[string, Node], depth: int): tuple[code: string, boolean: bool] =
    if node == nil or depth > 8: return
    case node.kind
    of nkIdent:
      if node.IdentNode.name in environment:
        return expand(environment[node.IdentNode.name], initTable[string, Node](), depth + 1)
    of nkPseudoVar:
      case node.PseudoVarNode.name
      of "self": return ("receiver", false)
      of "nil": return ("NodeValue(kind: vkNil)", false)
      else: discard
    of nkLiteral:
      if node.LiteralNode.value.kind == vkNil: return ("NodeValue(kind: vkNil)", false)
    of nkMessage:
      let message = node.MessageNode
      let receiver = expand(message.receiver, environment, depth + 1)
      if receiver.code.len == 0: return
      if message.selector == "==" and message.arguments.len == 1:
        let other = expand(message.arguments[0], environment, depth + 1)
        if other.code.len > 0 and not receiver.boolean and not other.boolean:
          return ("compiledIdentityEqual(" & receiver.code & ", " & other.code & ")", true)
      if message.selector == "not" and message.arguments.len == 0 and receiver.boolean and
         trueNot.len > 0 and falseNot.len > 0:
        return ("(if " & receiver.code & ": " & trueNot & " else: " & falseNot & ")", true)
      if receiver.code != "receiver" or receiver.boolean or message.selector notin bodies: return
      let body = bodies[message.selector]
      if body.temporaries.len != 0 or body.body.len != 1 or body.body[0].kind != nkReturn or
         body.parameters.len != message.arguments.len: return
      var arguments: Table[string, Node]
      for index, name in body.parameters:
        let argument = message.arguments[index]
        # Only nil constants are passed through self-call chains here.
        if argument.kind != nkPseudoVar or argument.PseudoVarNode.name != "nil": return
        arguments[name] = argument
      if message.selector notin dependencies: dependencies.add(message.selector)
      return expand(body.body[0].ReturnNode.expression, arguments, depth + 1)
    else: discard
  let entry = MessageNode(receiver: PseudoVarNode(name: "self"), selector: selector)
  let planned = expand(entry, initTable[string, Node](), 0)
  if planned.boolean:
    result = (planned.code, dependencies)

proc emitStaticClassCall*(owner, selector: string, parameters: seq[string],
                          plan: IntegerCallPlan): tuple[code, nativeName: string] =
  ## The native entry takes only Integers. The call site guards the exact class
  ## object identity and the class-method registration before using it, so a
  ## subclass override or a replaced method keeps the ordinary send.
  let stem = "integerClassCall_" & mangleClass(owner) & "_" & mangleSlot(selector)
  let args = parameters.mapIt((if plan.statements.len > 0: "hardingNativeArg_" else: "") &
    mangleIdentifier(it) & ": " & (if it in plan.objectParameters: "Instance" else: "int"))
  result.nativeName = stem & "_native"
  result.code = "proc " & result.nativeName & "*(" & args.join(", ") & "): int =\n"
  if plan.statements.len > 0: result.code.add(plan.statements)
  else: result.code.add("  " & plan.expression & "\n")

proc integerSlotGuardName*(owner, slot: string): string =
  ## The per-slot accessor guard is a property of the class and slot, not of a
  ## method, so it must be defined once per class/slot and shared by every region
  ## that touches it. Emitting it per method redefines the proc.
  "nativeSlotAccessorGuard_" & mangleClass(owner) & "_" & mangleSlot(slot)

proc emitIntegerCall*(owner, selector: string, parameters: seq[string],
                      plan: IntegerCallPlan): tuple[code, helper: string] =
  ## Arguments arrive evaluated before any guard. The entire pure call chain
  ## stays in int signatures; boxing happens only at this dynamic boundary.
  let stem = integerStem(owner, selector)
  proc paramType(name: string): string =
    if name in plan.objectParameters: "Instance" else: "int"
  let args = parameters.mapIt((if plan.statements.len > 0: "hardingNativeArg_" else: "") & mangleIdentifier(it) & ": " & paramType(it))
  let boundary = parameters.mapIt("argument_" & mangleIdentifier(it))
  let usesSelf = plan.touchedSlots.len > 0 or plan.needsReceiver
  result.helper = stem
  # A region that touches slots takes the typed receiver, so field access is a
  # plain load/store instead of an accessor call per read and write.
  result.code = "proc " & stem & "_native*(" &
                (if usesSelf: "self: " & mangleClass(owner) & ", " else: "") &
                args.join(", ") & "): int =\n"
  if plan.statements.len > 0: result.code.add(plan.statements)
  else: result.code.add("  " & plan.expression & "\n")
  for dependency in @[selector] & plan.dependencies:
    result.code.add("var " & stem & "_guard_" & mangleSlot(dependency) & " {.threadvar.}: CompiledDirectGuard\n")
  result.code.add("proc " & stem & "(owner, receiver: NodeValue, " & boundary.join(", ") & ": NodeValue): NodeValue =\n")
  var checks: seq[string]
  for index, name in parameters:
    let arg = boundary[index]
    if name in plan.objectParameters:
      checks.add("compiledObjectArgumentMatches(" & arg & ", \"" & plan.objectParameters[name] & "\")")
      if name in plan.fieldReadObjects:
        # A nil argument must take the ordinary send so `nil slot` raises the
        # same MessageNotUnderstood it always did.
        checks.add("not isNilValue(" & arg & ")")
    else:
      checks.add(arg & ".kind == vkInt")
  # A region that reads or writes slots touches storage the accessor table can
  # redirect (registerSlotAccessor / a redefined getter). The per-access guards
  # in ordinary code exist for that; here the same check runs once at entry, so
  # a replaced accessor falls back to normal dispatch instead of being bypassed.
  for slot in plan.touchedSlots:
    checks.add(integerSlotGuardName(owner, slot) & "(receiver)")
  for dependency in @[selector] & plan.dependencies:
    checks.add("canDirectCompiledSend(receiver, compiledClassValue(\"" & owner & "\").classVal, \"" & dependency & "\", " & mangleClass(owner) & "_" & mangleSelector(dependency) & ", " & stem & "_guard_" & mangleSlot(dependency) & ")")
  result.code.add("  if " & checks.join(" and ") & ":\n")
  let nativeCall = stem & "_native(" &
                   (if usesSelf: "cast[" & mangleClass(owner) & "](receiver.instVal.compiledOwner)" & (if boundary.len > 0: ", " else: "") else: "") &
                   boundary.mapIt(if parameters[boundary.find(it)] in plan.objectParameters:
                                    "(if isNilValue(" & it & "): nil else: " & it & ".instVal)"
                                  else: it & ".intVal").join(", ") & ")"
  result.code.add("    return toValue(" & nativeCall & ")\n")
  result.code.add("  sendMessageBound(owner, receiver, \"" & selector & "\", [" & boundary.join(", ") & "])\n\n")
