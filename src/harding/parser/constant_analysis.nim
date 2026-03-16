# ============================================================================
# Constant Analysis for Literal Optimization
# ============================================================================
#
# This module provides functions to analyze whether AST nodes are constant
# (can be evaluated at parse time) and to evaluate them.
#
# A node is constant if it contains no runtime computation - only literals,
# pseudo-variables (true/false/nil), and other constant nodes.

import std/[tables]
import ../core/types

proc isConstantNode*(node: Node): bool =
    ## Check if a node evaluates to a constant value (no runtime computation).
    ## Returns true for literals, pseudo-variables, and nested constant arrays/tables.
    if node == nil:
        return true  # nil is considered constant (represents empty)

    case node.kind
    of nkLiteral:
        return true

    of nkPseudoVar:
        # true, false, nil are constant values
        let name = cast[PseudoVarNode](node).name
        return name in ["true", "false", "nil"]

    of nkIdent:
        # Identifiers in array literals become symbols, but otherwise not constant
        # The parser handles this specially in array context
        return false

    of nkArray:
        let arr = cast[ArrayNode](node)
        # Empty array is constant
        if arr.elements.len == 0:
            return true
        # Check all elements - must be scalar constants (no nested arrays/tables)
        # Nested collections cause issues because cached values are vkArray/vkTable,
        # but runtime expects vkInstance (wrapped in an Instance object)
        for elem in arr.elements:
            if not isConstantNode(elem):
                return false
            # Disallow nested arrays/tables to avoid type mismatch issues
            if elem.kind == nkArray or elem.kind == nkTable:
                return false
        return true

    of nkTable:
        let tbl = cast[TableNode](node)
        # Empty table is constant
        if tbl.entries.len == 0:
            return true
        # Check all keys and values - must be scalar constants
        for entry in tbl.entries:
            if not isConstantNode(entry.key):
                return false
            if not isConstantNode(entry.value):
                return false
            # Disallow nested arrays/tables
            if entry.key.kind == nkArray or entry.key.kind == nkTable:
                return false
            if entry.value.kind == nkArray or entry.value.kind == nkTable:
                return false
        return true

    else:
        # Message sends, blocks, assignments, etc. are not constant
        return false

proc evaluateConstantNode*(node: Node): NodeValue =
    ## Evaluate a constant node to its NodeValue.
    ## Precondition: isConstantNode(node) must return true.
    if node == nil:
        return nilValue()

    case node.kind
    of nkLiteral:
        return cast[LiteralNode](node).value

    of nkPseudoVar:
        let name = cast[PseudoVarNode](node).name
        case name
        of "true":
            return NodeValue(kind: vkBool, boolVal: true)
        of "false":
            return NodeValue(kind: vkBool, boolVal: false)
        of "nil":
            return nilValue()
        else:
            raise newException(ValueError, "Unknown pseudo-variable: " & name)

    of nkArray:
        let arr = cast[ArrayNode](node)
        var elements: seq[NodeValue] = @[]
        for elem in arr.elements:
            elements.add(evaluateConstantNode(elem))
        return NodeValue(kind: vkArray, arrayVal: elements)

    of nkTable:
        let tbl = cast[TableNode](node)
        var entries = initTable[NodeValue, NodeValue]()
        for entry in tbl.entries:
            let key = evaluateConstantNode(entry.key)
            let val = evaluateConstantNode(entry.value)
            entries[key] = val
        return NodeValue(kind: vkTable, tableVal: entries)

    else:
        raise newException(ValueError, "Cannot evaluate non-constant node of kind: " & $node.kind)

proc analyzeAndCacheArray*(arr: ArrayNode) =
    ## Analyze an ArrayNode and cache its value if constant.
    ## Called by the parser after constructing the array.
    arr.isConstant = isConstantNode(cast[Node](arr))
    if arr.isConstant:
        arr.cachedValue = evaluateConstantNode(cast[Node](arr))
    else:
        # Mark as non-constant with empty cached value
        arr.cachedValue = nilValue()
        arr.isConstant = false

proc analyzeAndCacheTable*(tbl: TableNode) =
    ## Analyze a TableNode and cache its value if constant.
    ## Called by the parser after constructing the table.
    tbl.isConstant = isConstantNode(cast[Node](tbl))
    if tbl.isConstant:
        tbl.cachedValue = evaluateConstantNode(cast[Node](tbl))
    else:
        # Mark as non-constant with empty cached value
        tbl.cachedValue = nilValue()
        tbl.isConstant = false
