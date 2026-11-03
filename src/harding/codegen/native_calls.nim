import std/[tables, strutils, sequtils]
import ../core/types
import ../compiler/symbols

type
  IntegerCallPlan* = object
    ## Pure Integer region. Every transitive method dependency must be guarded
    ## before entry; no callbacks or mutation can invalidate it inside the region.
    eligible*: bool
    arity*: int
    expression*: string
    dependencies*: seq[string]
  IntegerPlans* = Table[string, IntegerCallPlan]

proc integerStem*(owner, selector: string): string =
  "integerCall_" & mangleClass(owner) & "_" & mangleSlot(selector)

proc planIntegerCall*(owner: string, parameters: seq[string], body: seq[Node],
                      known: IntegerPlans): IntegerCallPlan =
  ## Explicit expression returns only. Fallthrough answers self. Calls are limited
  ## to lexical self and already planned methods: recursion remains dynamic.
  if parameters.len == 0 or body.len != 1 or body[0].kind != nkReturn: return
  var dependencies: seq[string]
  proc expression(node: Node): string =
    if node == nil: return ""
    case node.kind
    of nkIdent:
      if node.IdentNode.name in parameters: return mangleIdentifier(node.IdentNode.name)
    of nkLiteral:
      if node.LiteralNode.value.kind == vkInt: return $node.LiteralNode.value.intVal
    of nkMessage:
      let message = node.MessageNode
      if message.receiver != nil and message.receiver.kind == nkPseudoVar and
         message.receiver.PseudoVarNode.name == "self" and message.selector in known:
        var arguments: seq[string]
        for argument in message.arguments:
          let value = expression(argument)
          if value.len == 0: return ""
          arguments.add(value)
        if arguments.len != known[message.selector].arity: return ""
        for dependency in @[message.selector] & known[message.selector].dependencies:
          if dependency notin dependencies: dependencies.add(dependency)
        return integerStem(owner, message.selector) & "_native(" & arguments.join(", ") & ")"
      if message.arguments.len == 1 and message.selector in ["+", "-", "*"]:
        if message.receiver.kind == nkLiteral and message.arguments[0].kind == nkLiteral: return ""
        let left = expression(message.receiver)
        let right = expression(message.arguments[0])
        if left.len > 0 and right.len > 0:
          return "(" & left & " " & message.selector & " " & right & ")"
    else: discard
    return ""
  result.expression = expression(body[0].ReturnNode.expression)
  result.eligible = result.expression.len > 0
  result.arity = parameters.len
  result.dependencies = dependencies

proc emitIntegerCall*(owner, selector: string, parameters: seq[string],
                      plan: IntegerCallPlan): tuple[code, helper: string] =
  ## Arguments arrive evaluated before any guard. The entire pure call chain
  ## stays in int signatures; boxing happens only at this dynamic boundary.
  let stem = integerStem(owner, selector)
  let target = mangleClass(owner) & "_" & mangleSelector(selector)
  let args = parameters.mapIt(mangleIdentifier(it))
  let boundary = parameters.mapIt("argument_" & mangleIdentifier(it))
  result.helper = stem
  result.code = ""
  result.code.add("proc " & stem & "_native*(" & args.join(", ") & ": int): int =\n  " & plan.expression & "\n")
  for dependency in @[selector] & plan.dependencies:
    result.code.add("var " & stem & "_guard_" & mangleSlot(dependency) & " {.threadvar.}: CompiledDirectGuard\n")
  result.code.add("proc " & stem & "(owner, receiver: NodeValue, " & boundary.join(", ") & ": NodeValue): NodeValue =\n")
  var checks = boundary.mapIt(it & ".kind == vkInt")
  for dependency in @[selector] & plan.dependencies:
    checks.add("canDirectCompiledSend(receiver, compiledClassValue(\"" & owner & "\").classVal, \"" & dependency & "\", " & mangleClass(owner) & "_" & mangleSelector(dependency) & ", " & stem & "_guard_" & mangleSlot(dependency) & ")")
  result.code.add("  if " & checks.join(" and ") & ":\n")
  result.code.add("    return toValue(" & stem & "_native(" & boundary.mapIt(it & ".intVal").join(", ") & "))\n")
  result.code.add("  sendMessageBound(owner, receiver, \"" & selector & "\", @[" & boundary.join(", ") & "])\n\n")
