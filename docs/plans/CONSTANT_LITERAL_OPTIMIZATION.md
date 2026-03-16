# Constant Literal Optimization Plan

## Overview

This document outlines a plan to optimize Array and Table literals by detecting when all their elements (recursively) are constant literals (no message sends, no variables) and evaluating them at parse time instead of runtime.

## Current State

### Array/Table Literals
- **Syntax**: `#(1 2 3)` for arrays, `#{"key" -> "value"}` for tables
- **AST Nodes**: `ArrayNode` (elements: seq[Node]), `TableNode` (entries: seq[(key, value)])
- **Current Evaluation**: 
  - Interpreter: Pushes work frames for each element, then builds collection
  - Granite: Generates runtime code that evaluates each element

### What Counts as Constant
A node is **constant** if it contains no runtime computation:
- `LiteralNode` (integers, floats, strings, symbols, booleans, nil)
- `ArrayNode` where ALL elements are constant
- `TableNode` where ALL keys and values are constant
- `PseudoVarNode` for `true`, `false`, `nil` (these are singleton values)

### What is NOT Constant
- `IdentNode` (variables) - except bare identifiers in array literals (become symbols)
- `MessageNode` (message sends)
- `BlockNode` (blocks)
- `AssignNode` (assignments)
- `SuperSendNode`, `CascadeNode`, etc.

## Implementation Plan

### Phase 1: Add Cache Fields to AST Nodes

**File**: `src/harding/core/types.nim`

Add optional cached values to ArrayNode and TableNode:

```nim
ArrayNode* = ref object of Node
    elements*: seq[Node]
    cachedValue*: Option[NodeValue]  # nil if not evaluated yet
    isConstant*: bool                # true if all elements are constant

TableNode* = ref object of Node
    entries*: seq[tuple[key: Node, value: Node]]
    cachedValue*: Option[NodeValue]  # nil if not evaluated yet
    isConstant*: bool                # true if all entries are constant
```

### Phase 2: Create Constant Analysis Function

**File**: `src/harding/parser/constant_analysis.nim` (new file)

Create a recursive function to analyze if a node is constant:

```nim
proc isConstantNode*(node: Node): bool =
    ## Check if a node evaluates to a constant value (no runtime computation)
    case node.kind
    of nkLiteral:
        return true
    of nkPseudoVar:
        # true, false, nil are constant
        return true
    of nkArray:
        let arr = cast[ArrayNode](node)
        # Empty array is constant
        if arr.elements.len == 0:
            return true
        # Check all elements recursively
        for elem in arr.elements:
            if not isConstantNode(elem):
                return false
        return true
    of nkTable:
        let tbl = cast[TableNode](node)
        # Empty table is constant
        if tbl.entries.len == 0:
            return true
        # Check all keys and values recursively
        for entry in tbl.entries:
            if not isConstantNode(entry.key):
                return false
            if not isConstantNode(entry.value):
                return false
        return true
    else:
        return false

proc evaluateConstant*(node: Node): NodeValue =
    ## Evaluate a constant node to its value (must check isConstant first)
    case node.kind
    of nkLiteral:
        return cast[LiteralNode](node).value
    of nkPseudoVar:
        let name = cast[PseudoVarNode](node).name
        case name
        of "true": return trueValue
        of "false": return falseValue
        of "nil": return nilValue()
        else: raise newException(ValueError, "Unknown pseudo-variable: " & name)
    of nkArray:
        let arr = cast[ArrayNode](node)
        var elements: seq[NodeValue] = @[]
        for elem in arr.elements:
            elements.add(evaluateConstant(elem))
        return NodeValue(kind: vkArray, arrayVal: elements)
    of nkTable:
        let tbl = cast[TableNode](node)
        var entries = initTable[NodeValue, NodeValue]()
        for entry in tbl.entries:
            let key = evaluateConstant(entry.key)
            let val = evaluateConstant(entry.value)
            entries[key] = val
        return NodeValue(kind: vkTable, tableVal: entries)
    else:
        raise newException(ValueError, "Cannot evaluate non-constant node")
```

### Phase 3: Integrate into Parser

**File**: `src/harding/parser/parser.nim`

Modify `parseArrayLiteral` and `parseTableLiteral` to analyze and cache:

```nim
proc parseArrayLiteral(parser: var Parser): ArrayNode =
    # ... existing parsing code ...
    
    let array = ArrayNode()
    array.elements = @[]
    
    # ... parse elements ...
    
    # Analyze if constant and cache value
    var isConst = true
    for elem in array.elements:
        if not isConstantNode(elem):
            isConst = false
            break
    
    array.isConstant = isConst
    if isConst:
        array.cachedValue = some(evaluateConstant(array))
    else:
        array.cachedValue = none(NodeValue)
    
    return array

proc parseTableLiteral(parser: var Parser): TableNode =
    # ... existing parsing code ...
    
    let table = TableNode()
    table.entries = @[]
    
    # ... parse entries ...
    
    # Analyze if constant and cache value
    var isConst = true
    for entry in table.entries:
        if not isConstantNode(entry.key) or not isConstantNode(entry.value):
            isConst = false
            break
    
    table.isConstant = isConst
    if isConst:
        table.cachedValue = some(evaluateConstant(table))
    else:
        table.cachedValue = none(NodeValue)
    
    return table
```

### Phase 4: Update Interpreter

**File**: `src/harding/interpreter/vm.nim`

Modify the `nkArray` and `nkTable` cases in `evalNode` to use cached values:

```nim
of nkArray:
    let arr = cast[ArrayNode](node)
    
    # Fast path: use cached constant value
    if arr.isConstant and arr.cachedValue.isSome:
        let cached = arr.cachedValue.get()
        if arrayClass != nil:
            interp.pushValue(newArrayInstance(arrayClass, cached.arrayVal).toValue())
        else:
            interp.pushValue(cached)
        return true
    
    # Slow path: existing runtime evaluation
    if arr.elements.len == 0:
        if arrayClass != nil:
            interp.pushValue(newArrayInstance(arrayClass, @[]).toValue())
        else:
            interp.pushValue(NodeValue(kind: vkArray, arrayVal: @[]))
    else:
        # Push build-array frame first (will execute last)
        interp.pushWorkFrame(newBuildArrayFrame(arr.elements.len))
        # Push element evaluation frames in reverse order
        for i in countdown(arr.elements.len - 1, 0):
            let elem = arr.elements[i]
            # Handle special cases for array literals (symbols, keywords)
            if elem.kind == nkIdent:
                let ident = cast[IdentNode](elem)
                case ident.name
                of "true":
                    interp.pushWorkFrame(newEvalFrame(PseudoVarNode(name: "true")))
                of "false":
                    interp.pushWorkFrame(newEvalFrame(PseudoVarNode(name: "false")))
                of "nil":
                    interp.pushWorkFrame(newEvalFrame(PseudoVarNode(name: "nil")))
                else:
                    # Bare identifier in array literal is treated as symbol
                    interp.pushWorkFrame(newEvalFrame(LiteralNode(value: getSymbol(ident.name))))
            else:
                interp.pushWorkFrame(newEvalFrame(elem))
    return true

of nkTable:
    let tab = cast[TableNode](node)
    
    # Fast path: use cached constant value
    if tab.isConstant and tab.cachedValue.isSome:
        let cached = tab.cachedValue.get()
        if tableClass != nil:
            interp.pushValue(newTableInstance(tableClass, cached.tableVal).toValue())
        else:
            interp.pushValue(cached)
        return true
    
    # Slow path: existing runtime evaluation
    if tab.entries.len == 0:
        if tableClass != nil:
            interp.pushValue(newTableInstance(tableClass, initTable[NodeValue, NodeValue]()).toValue())
        else:
            interp.pushValue(NodeValue(kind: vkTable, tableVal: initTable[NodeValue, NodeValue]()))
    else:
        # Push build-table frame first (will execute last)
        interp.pushWorkFrame(newBuildTableFrame(tab.entries.len * 2))
        # Push key-value evaluation frames in reverse order (values first, then keys)
        for i in countdown(tab.entries.len - 1, 0):
            let entry = tab.entries[i]
            interp.pushWorkFrame(newEvalFrame(entry.value))  # Value
            interp.pushWorkFrame(newEvalFrame(entry.key))    # Key
    return true
```

### Phase 5: Update Granite Compiler

**File**: `src/harding/codegen/expression.nim`

Modify `genExpression` to use pre-computed values:

```nim
of nkArray:
    let arr = node.ArrayNode
    
    # If constant, generate the pre-computed value directly
    if arr.isConstant and arr.cachedValue.isSome:
        let cached = arr.cachedValue.get()
        # Convert NodeValue to Nim code
        return genNodeValueLiteral(cached)
    
    # Otherwise, generate runtime code as before
    let elems = arr.elements.mapIt(genExpression(ctx, it)).join(", ")
    return fmt("NodeValue(kind: vkArray, arrayVal: @[{elems}])")

of nkTable:
    let tbl = node.TableNode
    
    # If constant, generate the pre-computed value directly
    if tbl.isConstant and tbl.cachedValue.isSome:
        let cached = tbl.cachedValue.get()
        # Convert NodeValue to Nim code
        return genNodeValueLiteral(cached)
    
    # Otherwise, generate runtime code as before
    var entries: seq[string] = @[]
    for (key, val) in tbl.entries:
        let keyCode = genExpression(ctx, key)
        let valCode = genExpression(ctx, val)
        entries.add(fmt("{keyCode}: {valCode}"))
    return fmt("NodeValue(kind: vkTable, tableVal: {{{entries.join(\", \")}}})")
```

Add helper to generate Nim code from NodeValue:

```nim
proc genNodeValueLiteral*(val: NodeValue): string =
    ## Generate Nim code that recreates a NodeValue at compile time
    case val.kind
    of vkInt:
        return fmt("NodeValue(kind: vkInt, intVal: {val.intVal})")
    of vkFloat:
        return fmt("NodeValue(kind: vkFloat, floatVal: {val.floatVal})")
    of vkString:
        let escaped = val.strVal.escapeString()
        return fmt("NodeValue(kind: vkString, strVal: \"{escaped}\")")
    of vkSymbol:
        return fmt("getSymbol(\"{val.symVal}\")")
    of vkBool:
        return if val.boolVal: "trueValue" else: "falseValue"
    of vkNil:
        return "nilValue()"
    of vkArray:
        var elems: seq[string] = @[]
        for elem in val.arrayVal:
            elems.add(genNodeValueLiteral(elem))
        return fmt("NodeValue(kind: vkArray, arrayVal: @[{elems.join(\", \")}])")
    of vkTable:
        var entries: seq[string] = @[]
        for key, val in val.tableVal.pairs:
            entries.add(fmt("{genNodeValueLiteral(key)}: {genNodeValueLiteral(val)}"))
        return fmt("NodeValue(kind: vkTable, tableVal: {{{entries.join(\", \")}}})")
    else:
        return "NodeValue(kind: vkNil)"  # Fallback
```

## Benefits

### Interpreter
- **Performance**: Constant literals evaluated once at parse time, not every time code runs
- **Memory**: Shared immutable values (can reference same cached instance)
- **Startup**: Pre-computed values available immediately

### Granite Compiler
- **Compile-time evaluation**: All constant literals become compile-time Nim constants
- **Better optimization**: Nim compiler can optimize known constant values
- **Smaller code**: No runtime evaluation code for constant literals
- **Faster startup**: No need to build collections at runtime

## Examples

### Before Optimization
```harding
# This creates work frames and evaluates at runtime every time
const := #(1 2 3).
```

Runtime work queue:
1. wfEvalNode(element 3)
2. wfEvalNode(element 2)
3. wfEvalNode(element 1)
4. wfBuildArray

### After Optimization
```harding
# This is evaluated at parse time, cached in AST
const := #(1 2 3).
```

Runtime work queue:
1. Push pre-computed value directly (single operation)

## Testing Strategy

1. **Unit tests**: Verify `isConstantNode` correctly identifies constant/non-constant nodes
2. **Integration tests**: Verify cached values are used correctly in interpreter
3. **Granite tests**: Verify generated code produces correct constant values
4. **Edge cases**:
   - Empty arrays/tables
   - Nested constant structures
   - Mixed constant/non-constant (only outer should be cached if all inner are constant)
   - Large literals (memory considerations)

## Migration Path

1. Implement Phase 1-3 (AST changes and parser integration)
2. Add feature flag `--constant-literals` to enable
3. Test thoroughly with existing codebase
4. Enable by default once stable
5. Implement Phase 4-5 (interpreter and Granite updates)

## Future Enhancements

1. **Deep constant folding**: Detect constant expressions like `1 + 2` (no message sends, but operations on literals)
2. **String interpolation**: Cache interpolated strings with only literal parts
3. **Method inlining**: For methods that return constant values
4. **Global constant pooling**: Deduplicate identical constant literals across the program
