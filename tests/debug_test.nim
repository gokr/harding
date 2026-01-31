import std/[logging, tables]
import ../src/nimtalk/core/types
import ../src/nimtalk/interpreter/evaluator
import ../src/nimtalk/parser/parser

echo "=== Parsing: self < 0 ifTrue: [ 1 ] ==="
let (ast1, _) = parse("self < 0 ifTrue: [ 1 ]")
if ast1.len > 0:
  let node1 = ast1[0]
  if node1 of MessageNode:
    let msg = MessageNode(node1)
    echo "Selector: ", msg.selector
    echo "Receiver type: ", if msg.receiver of MessageNode: "MessageNode" 
                           elif msg.receiver of PseudoVarNode: "PseudoVar" 
                           elif msg.receiver of LiteralNode: "Literal"
                           else: "other"
    if msg.receiver of MessageNode:
      let inner = MessageNode(msg.receiver)
      echo "Inner selector: ", inner.selector

echo ""
echo "=== Parsing: (self < 0) ifTrue: [ 1 ] ==="
let (ast2, _) = parse("(self < 0) ifTrue: [ 1 ]")
if ast2.len > 0:
  let node2 = ast2[0]
  if node2 of MessageNode:
    let msg = MessageNode(node2)
    echo "Selector: ", msg.selector
    echo "Receiver type: ", if msg.receiver of MessageNode: "MessageNode" 
                           elif msg.receiver of PseudoVarNode: "PseudoVar" 
                           elif msg.receiver of LiteralNode: "Literal"
                           else: "other"
    if msg.receiver of MessageNode:
      let inner = MessageNode(msg.receiver)
      echo "Inner selector: ", inner.selector
