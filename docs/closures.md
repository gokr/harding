# Closures in Nimtalk

Nimtalk implements Smalltalk-style lexical closures with full environment capture, mutable shared state, and non-local returns.

## Overview

Closures (blocks) in Nimtalk capture their lexical environment when created. This allows them to:

- Access variables from their defining scope
- Share mutable state between multiple closures
- Outlive their defining scope
- Perform non-local returns

## Syntax

```smalltalk
"Block with no parameters"
[ | temporaries | statements ]

"Block with parameters"
[ :param1 :param2 | statements ]

"Block with parameters and temporaries"
[ :param1 :param2 | temp1 temp2 | statements ]
```

The `|` separator marks the boundary between parameters/temporaries and the body.

## Implementation

### Environment Capture

When a block literal is evaluated, `captureEnvironment()` walks the activation chain and copies local variables into the block's `capturedEnv`:

```nim
proc captureEnvironment(interp: Interpreter, blockNode: BlockNode)
```

**Capture process:**
1. Create a **new copy** of the BlockNode (each evaluation gets its own captured environment)
2. Initialize `capturedEnv` as an empty table
3. Walk up the activation chain from current to root
4. For each activation, copy locals (except `self` and `super`)
5. Wrap each captured value in a `MutableCell` for shared mutability
6. Store the current activation as `homeActivation` for non-local returns

**Block Copying:**
Each time a block literal is evaluated, a fresh BlockNode is created. This ensures that multiple invocations of the same block definition (e.g., `makeCounter`) create independent closures with isolated captured variables.

**Inherited Captures:**
Nested closures automatically inherit captured variables from their enclosing block:

```nim
if currentMethod.capturedEnv.len > 0:
  for name, cell in currentMethod.capturedEnv:
    blockNode.capturedEnv[name] = cell
```

This ensures that closures at different nesting levels share the same `MutableCell` instances.

**Sibling Block Sharing:**
Multiple blocks created in the same scope (e.g., a table of closures) share captured variables through the activation's `capturedVars` table:

```nim
# When capturing, check if sibling block already captured this variable
if activation.capturedVars.hasKey(name):
  cell = activation.capturedVars[name]  # Share existing cell
else:
  cell = MutableCell(value: value)       # Create new cell
  activation.capturedVars[name] = cell   # Store for siblings
```

### MutableCell

The `MutableCell` type enables shared mutable state between closures:

```nim
type
  MutableCell = ref object
    value: NodeValue
```

When a variable is captured, it's wrapped in a `MutableCell`. Multiple closures capturing the same variable all reference the same cell, so changes made by one closure are visible to others.

### Block Invocation

Blocks are invoked via the `value:` message family:

- `value` - invoke with no arguments
- `value:` - invoke with 1 argument
- `value:value:` - invoke with 2 arguments
- etc.

The `invokeBlock()` procedure:

1. Checks argument count matches parameter count
2. Creates a new activation with the block's defining receiver
3. Binds captured environment variables to activation locals
4. Binds parameters to arguments
5. Executes the block body
6. Saves modified captured values back to their cells
7. Returns the result

```nim
proc invokeBlock(interp: var Interpreter, blockNode: BlockNode,
                 args: seq[NodeValue]): NodeValue
```

### Variable Lookup

When a variable is assigned, `setVariable()` checks:

1. **Current method's captured environment first** (via `MutableCell`) - this ensures shared state is updated
2. Current activation locals
3. Globals (if variable exists in global scope)
4. Creates new local if not found

This allows closures to both read and write captured variables, with changes visible to other closures sharing the same captured cell.

### Non-Local Returns

Smalltalk's `^` (return) from within a block exits the method that lexically contains the block:

```smalltalk
findFirst: [ :arr :predicate |
  1 to: arr do: [ :i |
    elem := arr at: i.
    (predicate value: elem) ifTrue: [ ^elem ]  "Returns from findFirst:"
  ].
  ^nil
]
```

**Implementation:**

1. When a block is created, its `homeActivation` is set to the current activation
2. When `^expression` is evaluated in a block:
   - If the block's `homeActivation` exists, set its `hasReturned` and `returnValue`
   - Otherwise, walk up the chain to find the nearest method activation
3. The interpreter checks `hasReturned` after each statement and unwinds if set

## Examples

### Counter Closure

```smalltalk
makeCounter := [ |
  count := 0.
  ^[ |
    count := count + 1.
    ^count
  ]
].

counter := makeCounter value.
counter value.  "Returns 1"
counter value.  "Returns 2"
counter value.  "Returns 3"
```

Each call to `makeCounter` creates a new closure with its own `count` variable.

### Shared State

```smalltalk
makePair := [ |
  value := 10.
  ^#{#inc -> [ value := value + 1 ], #dec -> [ value := value - 1 ], #get -> [ ^value ]}
].

pair := makePair value.
(pair at: #get) value.   "Returns 10"
(pair at: #inc) value.   "Returns 11 (the new value)"
(pair at: #get) value.   "Returns 11"
```

All three closures share the same `value` variable through their captured environment. Note the use of `#symbol` for selectors and `->` for table literal key-value pairs.

### Non-Local Return

```smalltalk
findFirstEven := [ :arr |
  1 to: arr do: [ :i |
    elem := arr at: i.
    (elem % 2) == 0 ifTrue: [ ^elem ]  "Returns from findFirstEven:"
  ].
  ^nil
].

numbers := #(1 3 5 7 9 2 4 6).
findFirstEven value: numbers.  "Returns 2"
```

The inner block's `^elem` exits `findFirstEven:`, not just the inner block.

## Key Design Decisions

### Why MutableCell?

Nim's value semantics mean that simple assignment copies values. Without `MutableCell`, each closure would get its own copy of captured variables, and changes wouldn't be shared.

### Activation Chain Walking

The capture walks the entire activation chain rather than just the immediate parent. This ensures that deeply nested closures capture all in-scope variables.

### Home Activation Tracking

Storing `homeActivation` directly in the block is more efficient than searching the chain at return time, and it correctly handles cases where the block is passed to different contexts.

## Debugging

Enable debug logging to trace closure behavior:

```bash
ntalk --loglevel DEBUG script.nt
```

Look for:
- "Capturing environment for block"
- "Captured variable: name = value"
- "Invoking block with N arguments"
- "Non-local return from block to home activation"
