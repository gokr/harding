# Native Nim reference for benchmark/tree.hrd (object graphs across call boundaries).
#
# The "aim" for the Harding version: the same traversal in idiomatic Nim, where a
# node is a ref object and passing one costs a pointer. Representation reference, not
# a semantics oracle; compare trends, not exact multipliers.
#
# The Harding program builds a 2047-node tree and walks it three ways (sum, depth,
# leaf count) on every pass.
import std/[os, strutils]

type
  Node = ref object
    value: int
    left, right: Node

  Tree = object

proc build(tree: Tree, node: Node, depth: int): Node =
  if depth <= 0: return node
  node.left = tree.build(Node(value: depth), depth - 1)
  node.right = tree.build(Node(value: depth), depth - 1)
  node

proc sumAll(tree: Tree, node: Node): int =
  if node == nil: return 0
  node.value + tree.sumAll(node.left) + tree.sumAll(node.right)

proc maxDepth(tree: Tree, node: Node): int =
  if node == nil: return 0
  let l = tree.maxDepth(node.left)
  let r = tree.maxDepth(node.right)
  1 + (if l > r: l else: r)

proc leaves(tree: Tree, node: Node): int =
  if node == nil: return 0
  if node.left == nil and node.right == nil: return 1
  tree.leaves(node.left) + tree.leaves(node.right)

proc runTree(tree: Tree, root: Node): int =
  tree.sumAll(root) + tree.maxDepth(root) + tree.leaves(root)

when isMainModule:
  let repetitions = if paramCount() > 0: parseInt(paramStr(1)) else: 1
  doAssert repetitions >= 0
  let tree = Tree()
  let root = Node(value: 1)
  discard tree.build(root, 11)
  var total = 0
  for _ in 0..<repetitions:
    total += tree.runTree(root)
  doAssert total == 10227 * repetitions, "tree total differs: " & $total
  echo total
