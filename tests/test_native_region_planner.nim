import std/[unittest, tables, strutils]
import ../src/harding/core/types
import ../src/harding/parser/parser
import ../src/harding/codegen/native_calls
import ../src/harding/compiler/[symbols, context, types]

proc plan(source: string, temporaries: seq[string]): IntegerCallPlan =
  let (nodes, syntax) = parse(source)
  doAssert not syntax.hasError
  planIntegerCall("Planner", @["n"], nodes, initTable[string, IntegerCallPlan](), temporaries)

suite "Source-derived Boolean return plans":
  test "literal returns and argument projections are derived from the body":
    check booleanReturnExpression(@[Node(ReturnNode(expression: PseudoVarNode(name: "true")))], "other") == "true"
    check booleanReturnExpression(@[Node(ReturnNode(expression: PseudoVarNode(name: "false")))], "other") == "false"
    check booleanReturnExpression(@[Node(ReturnNode(expression: IdentNode(name: "other")))], "other") == "right"
    check booleanReturnExpression(@[Node(ReturnNode(expression: IdentNode(name: "self")))], "other") == ""
    check booleanReturnExpression(@[Node(ReturnNode(expression: LiteralNode(value: toValue(4))))], "other") == ""
    check booleanReturnExpression(@[Node(AssignNode(variable: "x", expression: IdentNode(name: "other"))), Node(ReturnNode(expression: IdentNode(name: "other")))], "other") == ""

suite "Source-derived nil predicates":
  test "pure self chains expand and retain their dependencies":
    let selfNode = Node(PseudoVarNode(name: "self"))
    let nilNode = Node(PseudoVarNode(name: "nil"))
    var bodies: Table[string, BlockNode]
    bodies["="] = BlockNode(parameters: @["other"], body: @[Node(ReturnNode(expression:
      MessageNode(receiver: selfNode, selector: "==", arguments: @[Node(IdentNode(name: "other"))])))])
    bodies["isNil"] = BlockNode(body: @[Node(ReturnNode(expression:
      MessageNode(receiver: selfNode, selector: "=", arguments: @[nilNode])))])
    bodies["notNil"] = BlockNode(body: @[Node(ReturnNode(expression:
      MessageNode(receiver: MessageNode(receiver: selfNode, selector: "isNil"), selector: "not")))])
    let projection = nilPredicateExpression("notNil", bodies, "false", "true")
    check projection.expression.contains("compiledIdentityEqual(receiver, NodeValue(kind: vkNil))")
    for dependency in ["notNil", "isNil", "="]:
      check dependency in projection.dependencies
    check nilPredicateExpression("notNil", bodies, "", "").expression == ""
    bodies["isNil"].body.add(Node(ReturnNode(expression: nilNode)))
    check nilPredicateExpression("isNil", bodies, "false", "true").expression == ""

suite "Native region definite initialization":
  test "both branches initialize a local":
    let p = plan("n > 0 ifTrue: [x := n] ifFalse: [x := 0 - n]. ^x", @["x"])
    check p.eligible
    check p.statements.contains("if ")

  test "one branch cannot establish initialization":
    check not plan("n > 0 ifTrue: [x := n]. ^x", @["x"]).eligible

  test "a possibly empty loop cannot establish initialization":
    check not plan("[n < 0] whileTrue: [x := n]. ^x", @["x"]).eligible

  test "loop-local initialization cannot escape its iteration":
    check not plan("i := 0. [i < n] whileTrue: [x := i. i := i + 1]. ^x", @["i", "x"]).eligible

  test "read before write cannot become zero":
    check not plan("x := x + n. ^x", @["x"]).eligible

  test "integer parameter mutation stays in the guarded native region":
    let p = plan("n := n + 1. ^n", @[])
    check p.eligible
    check p.statements.contains("var n = hardingNativeArg_n")
    check p.statements.contains("n = (n + 1)")
    check not plan("n := 2.5. ^n", @[]).eligible
    check not plan("x := n. x := 2.5. ^x", @["x"]).eligible

  test "parameter mutation coexists with a touched integer slot":
    let source = "n := n + 1. value := value + n. ^value"
    let (nodes, syntax) = parse(source)
    require not syntax.hasError
    let cls = newClassInfo("Planner")
    discard cls.addSlot("value", tcInt)
    let p = planIntegerCall("Planner", @["n"], nodes,
      initTable[string, IntegerCallPlan](), @[], cls)
    check p.eligible
    let emitted = emitIntegerCall("Planner", "advance:", @["n"], p)
    check emitted.code.contains("self[]." & mangleSlot("value"))
    check not emitted.code.contains("var self =")

  test "branch-local shadowing refuses":
    check not plan("x := n. n > 0 ifTrue: [| x | x := 1]. ^x", @["x"]).eligible

  test "callbacks and nonlocal returns inside a loop refuse":
    check not plan("x := n. [x > 0] whileTrue: [^x]. ^x", @["x"]).eligible
    check not plan("x := n. [x > 0] whileTrue: [x := action value]. ^x", @["x"]).eligible
