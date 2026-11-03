import std/[tables, strutils, sequtils, sets]
import ../core/types
import ../compiler/symbols

type
  IntegerCallPlan* = object
    ## Pure Integer region. Every transitive method dependency must be guarded
    ## before entry; no callbacks or heap mutation can invalidate it inside.
    eligible*: bool
    arity*: int
    expression*: string
    statements*: string
    dependencies*: seq[string]
  IntegerPlans* = Table[string, IntegerCallPlan]

proc integerStem*(owner, selector: string): string =
  "integerCall_" & mangleClass(owner) & "_" & mangleSlot(selector)

proc planIntegerCall*(owner: string, parameters: seq[string], body: seq[Node],
                      known: IntegerPlans, temporaries: seq[string] = @[]): IntegerCallPlan =
  ## Integer arguments, definitely initialized Integer locals, and structured
  ## branches/loops with an explicit final return. No escaping blocks, recursion,
  ## slots, parameter assignment, division, or non-local returns inside controls.
  if parameters.len == 0 or body.len == 0 or body[^1].kind != nkReturn: return
  var dependencies: seq[string]
  var initialized = initHashSet[string]()
  for name in parameters: initialized.incl(name)

  proc expression(node: Node, available: HashSet[string], boolean = false): string =
    if node == nil: return ""
    case node.kind
    of nkIdent:
      if not boolean and node.IdentNode.name in available:
        return mangleIdentifier(node.IdentNode.name)
    of nkLiteral:
      let value = node.LiteralNode.value
      if not boolean and value.kind == vkInt: return $value.intVal
      if boolean and value.kind == vkBool: return $value.boolVal
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
      if node == nil: return false
      case node.kind
      of nkAssign:
        let assignment = node.AssignNode
        if assignment.variable notin temporaries: return false
        let value = expression(assignment.expression, available)
        if value.len == 0: return false
        code.add(indent & mangleIdentifier(assignment.variable) & " = " & value & "\n")
        available.incl(assignment.variable)
      of nkIf:
        let branch = node.IfNode
        let test = condition(branch.condition, available)
        let yes = blockBody(branch.thenBranch)
        if test.len == 0 or yes.len == 0: return false
        var yesAvailable = available
        code.add(indent & "if " & test & ":\n")
        if not statements(yes, yesAvailable, depth + 2, code): return false
        if branch.elseBranch != nil:
          let no = blockBody(branch.elseBranch)
          if no.len == 0: return false
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
        if test.len == 0 or loopBody.len == 0: return false
        var loopAvailable = available
        code.add(indent & "while " & (if loop.isWhileTrue: test else: "not (" & test & ")") & ":\n")
        if not statements(loopBody, loopAvailable, depth + 2, code): return false
        # A zero-iteration loop cannot establish a local's initialization.
      else: return false
    return true

  var code: string
  if not statements(body[0 ..< body.len - 1], initialized, 2, code): return
  let answer = expression(body[^1].ReturnNode.expression, initialized)
  if answer.len == 0: return
  result.expression = answer
  if body.len > 1:
    for name in temporaries:
      code = "  var " & mangleIdentifier(name) & ": int\n" & code
    result.statements = code & "  return " & answer & "\n"
  result.eligible = true
  result.arity = parameters.len
  result.dependencies = dependencies

proc emitIntegerCall*(owner, selector: string, parameters: seq[string],
                      plan: IntegerCallPlan): tuple[code, helper: string] =
  ## Arguments arrive evaluated before any guard. The entire pure call chain
  ## stays in int signatures; boxing happens only at this dynamic boundary.
  let stem = integerStem(owner, selector)
  let args = parameters.mapIt(mangleIdentifier(it))
  let boundary = parameters.mapIt("argument_" & mangleIdentifier(it))
  result.helper = stem
  result.code = "proc " & stem & "_native*(" & args.join(", ") & ": int): int =\n"
  if plan.statements.len > 0: result.code.add(plan.statements)
  else: result.code.add("  " & plan.expression & "\n")
  for dependency in @[selector] & plan.dependencies:
    result.code.add("var " & stem & "_guard_" & mangleSlot(dependency) & " {.threadvar.}: CompiledDirectGuard\n")
  result.code.add("proc " & stem & "(owner, receiver: NodeValue, " & boundary.join(", ") & ": NodeValue): NodeValue =\n")
  var checks = boundary.mapIt(it & ".kind == vkInt")
  for dependency in @[selector] & plan.dependencies:
    checks.add("canDirectCompiledSend(receiver, compiledClassValue(\"" & owner & "\").classVal, \"" & dependency & "\", " & mangleClass(owner) & "_" & mangleSelector(dependency) & ", " & stem & "_guard_" & mangleSlot(dependency) & ")")
  result.code.add("  if " & checks.join(" and ") & ":\n")
  result.code.add("    return toValue(" & stem & "_native(" & boundary.mapIt(it & ".intVal").join(", ") & "))\n")
  result.code.add("  sendMessageBound(owner, receiver, \"" & selector & "\", @[" & boundary.join(", ") & "])\n\n")
