# Harding Implementation Guide

## Overview

This document describes Harding's implementation internals, architecture, and development details.

## Table of Contents

1. [Architecture](#architecture)
2. [Stackless VM](#stackless-vm)
3. [Core Types](#core-types)
4. [Method Dispatch](#method-dispatch)
5. [Scheduler and Processes](#scheduler-and-processes)
6. [Activation Stack](#activation-stack)
7. [Slot-Based Instance Variables](#slot-based-instance-variables)

---

## Architecture

Harding consists of several subsystems:

| Component | Location | Purpose |
|-----------|----------|---------|
| Lexer | `src/harding/parser/lexer.nim` | Tokenization of source code |
| Parser | `src/harding/parser/parser.nim` | AST construction |
| Core Types | `src/harding/core/types.nim` | Node, Instance, Class definitions |
| VM | `src/harding/interpreter/vm.nim` | Stackless VM execution and method dispatch |
| Objects | `src/harding/interpreter/objects.nim` | Object system, class creation, native methods |
| Scheduler | `src/harding/core/scheduler.nim` | Green thread scheduling |
| Process | `src/harding/core/process.nim` | Process type definitions |
| REPL | `src/harding/repl/` | Interactive interface |
| Code Generation | `src/harding/codegen/` | Shared Nim code generation pipeline |
| Compiler | `src/harding/compiler/` | Granite compiler entry points |
| GTK Bridge | `src/harding/gui/gtk/` | GTK widget integration |

### Data Flow

```
Source Code (.hrd)
       ↓
   Lexer
       ↓
  Tokens
       ↓
  Parser
       ↓
  AST (Abstract Syntax Tree)
       ↓
  Stackless VM (work queue + eval stack)
       ↓
  Method Dispatch → Native Methods or Interpreted Bodies
       ↓
  Result
```

---

## Bootstrap Architecture

Harding uses a two-phase bootstrap process that balances Nim's performance with Harding's flexibility. The bootstrap Harding is the absolute minimum hard-coded into the VM to allow it to parse and load the standard library (`.hrd` files).

### Two-Phase Bootstrap

1. **Nim Bootstrap Phase**: VM initialization creates core classes and registers essential methods
2. **Stdlib Loading Phase**: Bootstrap.hrd is evaluated, defining methods using primitive syntax

### Core Class Hierarchy

The `initCoreClasses()` procedure in `src/harding/interpreter/objects.nim` creates these core classes:

```
Root (empty - for DNU proxies/wrappers)
  └── Object (core methods)
      ├── Integer
      ├── Float
      ├── String
      ├── Array
      ├── Table
      ├── Block
      ├── Boolean (parent for True and False)
      ├── Library
      └── Set
```

### Three Categories of Methods

| Category | Location | Count | Example |
|----------|----------|-------|---------|
| **Bootstrap Methods** | `objects.nim`, `vm.nim` | ~10 | `selector:put:`, `new`, `load:` |
| **Primitive Selectors** | Registered in `vm.nim`, used by `.hrd` | ~70 | `primitivePlus:`, `primitiveStringSize` |
| **User-Facing Methods** | `.hrd` files | ~200 | `+`, `-`, `printString`, `size`, `at:put:` |

### Bootstrap Methods (Required in Nim)

These methods MUST be defined in Nim because they're needed **before** `.hrd` files can be loaded:

| Selector | Purpose | Why Bootstrap? |
|----------|---------|---------------|
| `selector:put:` | Define instance method (used by `>>` syntax) | Needed to parse method definitions in .hrd files |
| `classSelector:put:` | Define class method | Needed to parse class method definitions |
| `derive:` | Create subclass with slots | Needed to define new classes |
| `new` | Create instance | Needed before `.hrd` files can define initialization |
| `load:` | Load and evaluate a `.hrd` file | Required to load stdlib |

### Primitive Selectors

Primitive selectors provide efficient implementations that `.hrd` methods can call:

```harding
# In Integer.hrd:
Integer>>+ other <primitive primitivePlus: other>

# What happens when evaluating "3 + 4":
1. Parser creates MessageNode for "+"
2. VM looks up method "+" on Integer class
3. Returns method from Integer.hrd (a BlockNode with primitive selector)
4. VM executes primitive by looking up `primitivePlus:` selector
5. Finds Nim implementation in Integer class
6. Calls the native implementation directly
```

### Declarative Primitive Syntax

The `.hrd` files use declarative primitive syntax to define user-facing methods:

```harding
# Declarative form
Integer>>+ other <primitive primitivePlus: other>

# Inline form (with validation)
Array>>at: index [
    index < 1 ifTrue: [self error: "Index out of bounds"].
    ^ <primitive primitiveAt: index>
]
```

This provides a clean separation:
- **Nim code**: Foundation mechanism (bootstrapping and performance-critical primitives)
- **Harding code (`.hrd`)**: Language definition and user-facing API

### For More Information

See [bootstrap.md](bootstrap.md) for complete details on the bootstrap architecture, including:
- Complete list of bootstrap methods
- Stdlib loading order
- Extending Harding with new features

---

## Stackless VM

### Overview

The Harding VM implements an iterative AST interpreter using an explicit work queue instead of recursive Nim procedure calls. This enables:

1. **True cooperative multitasking** - yield within statements
2. **Stack reification** - `thisContext` accessible from Harding
3. **No Nim stack overflow** - on deep recursion
4. **Easier debugging and profiling** - flat execution loop

### Why Stackless?

The VM uses an explicit work queue rather than recursive Nim procedure calls:

| Aspect | Benefit |
|--------|---------|
| Execution model | Explicit work queue, no recursive Nim calls |
| Stack depth | User-managed work queue, no Nim stack overflow risk |
| Multitasking | Full cooperative multitasking with yield at any point |
| Debugging | Single-stepping through a flat loop |
| State | All execution state is explicit and inspectable |

### VM Architecture

#### WorkFrame

Each unit of work is a `WorkFrame` pushed onto the work queue. Frame kinds include:

- `wfEvalNode` - Evaluate an AST node
- `wfSendMessage` - Send message with args on stack
- `wfAfterReceiver` - After receiver eval, evaluate args
- `wfAfterArg` - After arg N eval, continue to arg N+1 or send
- `wfApplyBlock` - Apply block with captured environment
- `wfPopActivation` - Pop activation and restore state
- `wfReturnValue` - Handle return statement
- `wfBuildArray` - Build array from N values on stack
- `wfBuildTable` - Build table from key-value pairs on stack
- `wfCascade` - Cascade messages to same receiver
- `wfCascadeMessage` - Send one message in a cascade
- `wfCascadeMessageDiscard` - Send message and discard result
- `wfRestoreReceiver` - Restore receiver after cascade
- `wfIfBranch` - Conditional branch (ifTrue:, ifFalse:)
- `wfWhileLoop` - While loop (whileTrue:, whileFalse:)
- `wfPushHandler` - Push exception handler onto handler stack
- `wfPopHandler` - Pop exception handler from handler stack
- `wfSignalException` - Signal exception and search for handler

#### Execution Loop

```nim
while interp.hasWorkFrames():
  let frame = interp.popWorkFrame()
  case frame.kind
  of wfEvalNode: handleEvalNode(...)
  of wfSendMessage: handleContinuation(...)
  # ... all operations handled uniformly
```

#### Execution Example

Evaluating `3 + 4`:

```
Initial workQueue: [wfEvalNode(MessageNode(receiver=3, selector="+", args=[4]))]

Step 1: Pop wfEvalNode(Message)
        - Recognizes message send
        - Push wfAfterReceiver("+", [4])
        - Push wfEvalNode(Literal(3))

Step 2: Pop wfEvalNode(Literal(3))
        - Push 3 to evalStack

Step 3: Pop wfAfterReceiver("+", [4])
        - Receiver (3) is on evalStack
        - Push wfAfterArg("+", [4], index=0)
        - Push wfEvalNode(Literal(4))

Step 4: Pop wfEvalNode(Literal(4))
        - Push 4 to evalStack

Step 5: Pop wfAfterArg("+", [4], index=0)
        - All args evaluated
        - Push wfSendMessage("+", argCount=1)

Step 6: Pop wfSendMessage("+", 1)
        - Pop args: [4]
        - Pop receiver: 3
        - Look up + method on Integer
        - Create activation
        - Push wfPopActivation
        - Push method body statements
```

### VM Status

The VM returns a `VMStatus` indicating execution outcome:

- `vmRunning` - Normal execution (internal use)
- `vmYielded` - Processor yielded, can be resumed
- `vmCompleted` - Execution finished
- `vmError` - Error occurred

### Design Strengths

1. **True Stacklessness**: The work queue enables cooperative multitasking—execution can yield at any point

2. **Deterministic State**: All execution state is explicit (`workQueue`, `evalStack`, `activationStack`)

3. **Simpler Debugging**: Single-stepping through a flat loop

4. **No Stack Overflow**: Deep recursion won't crash the Nim interpreter

5. **Stack Reification**: The entire Harding call stack is accessible as data

### Quick Primitives

Quick Primitives provide special-case optimizations for common operations:

- **Inline arithmetic/tagged value operations**: Direct dispatch for `+`, `-`, `*`, `/` on small integers
- **Specialized work frames**: Fast-path frames for frequently executed primitives
- **Avoid activation creation**: Primitive results are pushed directly to eval stack

Quick Primitives bypass normal method dispatch and activation creation for performance-critical operations:

```nim
# Normal message send: creates activation, executes method body
3 + 4  -> MIC cache hit -> method lookup -> activation -> return value

# Quick primitive: tagged value dispatch, no activation
primitiveQuickPlus(3, 4) -> tagged arithmetic -> push 7 to eval stack
```

### Work Frame Pooling

To reduce garbage collection pressure for ARC/ORC memory management, Harding uses a work frame pool:

- Frames are recycled instead of allocated for each operation
- Pool size: 64 frames (default)
- Reduces GC overhead by ~30% for tight loops

The pool is bypassed when:
- Frame count exceeds pool size (fallback to allocation)
- ARC is disabled (traditional GC)

### ARC Memory Management

Harding is compatible with Nim's ARC (Automatic Reference Counting) and ORC (ARC with cycle collection):

- **Keep-alive registries**: Raw pointers to Nim refs must be registered to prevent premature collection
- **`.acyclic.` pragmas**: Types involved in cross-thread references marked to prevent cycle detection crashes
- **Closure elimination**: Callbacks use raw pointers instead of closures to prevent ORC tracking issues

**Keep-Alive Registries:**
- `blockNodeRegistry` in `types.nim` - for BlockNodes
- `processProxies` in `scheduler.nim` - for ProcessProxy
- `schedulerProxies` in `scheduler.nim` - for SchedulerProxy
- `monitorProxies` in `scheduler.nim` - for MonitorProxy
- `sharedQueueProxies` in `scheduler.nim` - for SharedQueueProxy
- `semaphoreProxies` in `scheduler.nim` - for SemaphoreProxy
- `globalTableProxies` in `vm.nim` - for GlobalTableProxy

### Exception Handling with Signal Point Preservation

Harding uses Smalltalk-style exception handling that preserves the signal point for resumable exceptions (introduced in v0.6.0).

#### How It Works

1. **`on:do:` Primitive**: Schedules three work frames: `[pushHandler][evalBlock][popHandler]`

2. **Handler Installation**: `wfPushHandler` creates an `ExceptionHandler` record with saved depths:
   - `stackDepth`: Activation stack depth
   - `workQueueDepth`: Work queue depth
   - `evalStackDepth`: Evaluation stack depth
   - `protectedBlock`: Reference to the protected block (for `retry`)

3. **Exception Signaling**: `primitiveSignalImpl` creates an `ExceptionContext` capturing the full signal point state, then truncates VM state to the handler's checkpoint:
   - Creates `ExceptionContext` with activation stack snapshot, work queue depth, eval stack depth
   - Truncates work queue to handler's saved depth
   - Truncates eval stack to handler's saved depth
   - Pops activation stack to handler's saved depth

4. **Handler Execution**: Schedules handler block with exception as argument

5. **Cleanup**: `wfPopHandler` removes handler when block completes normally

#### Resumable Exception Actions

The preserved `ExceptionContext` enables Smalltalk-style handler actions:

- **`resume`** / **`resume: value`**: Restores the signal point work queue and activation stack from the ExceptionContext, then continues execution. The `signal` expression returns nil or the provided value.
- **`retry`**: Rewinds to the handler install point and re-executes the protected block.
- **`pass`**: Delegates to the next outer matching handler.
- **`return: value`**: Returns value from the `on:do:` expression, unwinding the handler.

#### Key Characteristics

**Advantages:**
- **Stackless**: No native stack unwinding—exceptions work with green threads
- **Predictable**: VM state is explicitly restored to known checkpoint
- **Debuggable**: Original activation records still exist (not destroyed)
- **Composable**: Multiple handlers can be nested

**Trade-offs:**
- Frames above the handler are truncated, but preserved in ExceptionContext for resume
- Non-resumable handlers discard the ExceptionContext after use
- Stack traces show handler installation point for non-resumed exceptions

#### Example: Exception Handling Flow

```smalltalk
# Harding code
[
    "outer" printLine.
    Error signal: "Something went wrong"
] on: Error do: [:ex |
    "Caught: " , ex message printLine
]
```

Execution flow:
1. `wfPushHandler` creates handler at depth 0
2. Block evaluation starts, prints "outer"
3. `Error signal:` creates exception instance
4. `primitiveSignalImpl` finds handler, truncates to saved depth
5. Handler block receives exception, prints "Caught: Something went wrong"
6. `wfPopHandler` removes handler

---

## Core Types

### NodeValue

Wrapper for all Harding values:

```nim
type
  ValueKind* = enum
    vkNil, vkBool, vkInt, vkFloat, vkString, vkSymbol,
    vkArray, vkTable, vkObject, vkBlock

  NodeValue* = object
    kind*: ValueKind
    boolVal*: bool
    intVal*: int64
    floatVal*: float64
    strVal*: string
    symVal*: string
    arrVal*: seq[NodeValue]
    tblVal*: Table[string, NodeValue]
    objVal*: Instance
    blkVal*: BlockNode
```

### Instance

Represents a class instance:

```nim
type
  InstanceObj = object
    class*: Class
    slots*: seq[NodeValue]        # Indexed slots (instance variables)
    properties*: Table[string, NodeValue]  # Dynamic properties

  Instance* = ref InstanceObj
```

### Class

Represents a class definition:

```nim
type
  ClassObj = object
    name*: string
    superclass*: Class
    parents*: seq[Class]          # Multiple inheritance
    methods*: Table[string, Method]
    allMethods*: Table[string, Method]  # Merged method table (own + inherited)
    slotsDefinition*: seq[string] # Slot names
    version*: int                 # Incremented on method changes (cache invalidation)
    methodsDirty*: bool           # Lazy rebuilding flag

  Class* = ref ClassObj
```

### BlockNode

Represents a block (closure):

```nim
type
  BlockNode = ref object
    params*: seq[string]
    temporaries*: seq[string]
    body*: seq[Node]
    env*: Environment            # Captured environment
```

---

## Method Dispatch

### Method Lookup

The VM implements the full method dispatch chain via `lookupMethod`:

1. **Direct lookup** - Check method on receiver's class
2. **Direct parent lookup** - Check each parent class directly
3. **Inherited lookup** - Check superclass chain
4. **Parent inheritance lookup** - Check superclass chain of each parent
5. **doesNotUnderstand:** - Fallback when method is not found

### Monomorphic Inline Cache (MIC) and Polymorphic Inline Cache (PIC)

Harding uses inline caching to accelerate message sends:

**MIC (Monomorphic Inline Cache):**
- Each call site caches a single `(classId, method)` pair for O(1) hit performance
- Cache miss falls back to full `lookupMethod` and updates cache

**PIC (Polymorphic Inline Cache):**
- Caches up to 4 different class/method pairs for polymorphic call sites
- LRU swap on hits to promote hot entries to MIC
- Megamorphic flag skips caching at highly polymorphic sites

**Version-Based Invalidation:**
- Classes have a version counter incremented on method changes
- Cache entries are validated against class versions on each hit
- Stale entries trigger cache miss and re-lookup
- Proper invalidation when methods are added or rebuilt

Performance improvement: ~2-3x faster message sends for repeated receivers.

### Super Sends

Qualified super sends `super<Class>>method` dispatch directly to the specified parent class, bypassing normal method lookup on the receiver's class.

### Native Methods

Native methods are Nim procedures registered on classes:

```nim
# Native methods can have two signatures:
# Without interpreter context:
proc(self: Instance, args: seq[NodeValue]): NodeValue
# With interpreter context:
proc(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue
```

Control flow primitives (`ifTrue:`, `ifFalse:`, `whileTrue:`, `whileFalse:`, block `value:`) are handled directly by the VM's work frame system rather than as native methods, enabling proper stackless execution.

### Tagged Values

For performance, Harding uses tagged value representation for common types:

- Small integers are tagged and stored directly (no heap allocation)
- Booleans and nil use tagged representation
- Fast paths for integer arithmetic and comparisons
- Transparent fallback to heap objects for large values

---

## Scheduler and Processes

### Process Structure

Each green process has its own interpreter:

```nim
type
  ProcessState* = enum
    psReady, psRunning, psBlocked, psSuspended, psTerminated

  Process* = ref object
    id*: int
    interpreter*: Interpreter
    state*: ProcessState
    priority*: int
    name*: string
```

### Scheduler

Round-robin scheduler for cooperative multitasking:

```nim
proc runScheduler(interp: var Interpreter) =
  while true:
    let process = selectNextProcess()
    if process == nil: break
    process.state = psRunning
    let evalResult = interp.evalForProcess(stmt)
    if process.state != psRunning:
        # Process yielded or terminated
```

### Yield Points

Yielding occurs at:
- Explicit `Processor yield` calls
- Message send boundaries (configurable)
- Blocking operations (Monitor acquire, Semaphore wait, SharedQueue next/nextPut:)

### Synchronization Primitives

Harding provides three synchronization primitives for coordinating between green processes:

#### Monitor

Monitor provides mutual exclusion with reentrant locking:

```smalltalk
monitor := Monitor new
monitor critical: [
    # Critical section - only one process at a time
    sharedCounter := sharedCounter + 1
]
```

Implementation details:
- Tracks owning process and reentrancy count
- Waiting queue for blocked processes
- Automatically transfers ownership when releasing if waiters exist

#### Semaphore

Counting semaphore for resource control:

```smalltalk
sem := Semaphore new: 5          # Allow 5 concurrent accesses
sem := Semaphore forMutualExclusion  # Binary semaphore (count 1)

sem wait                          # Decrement, block if < 0
sem signal                        # Increment, unblock waiter if any
```

Implementation details:
- Maintains internal counter
- FIFO queue for waiting processes
- Signal unblocks first waiting process without incrementing if waiters exist

#### SharedQueue

Thread-safe queue with blocking operations:

```smalltalk
queue := SharedQueue new          # Unbounded queue
queue := SharedQueue new: 10      # Bounded queue (capacity 10)

queue nextPut: item               # Add item (blocks if bounded and full)
item := queue next                # Remove and return (blocks if empty)
```

Implementation details:
- Separate waiting queues for readers and writers
- Bounded mode blocks writers when capacity reached
- Writers unblock when items are consumed

#### Blocking Implementation

When a primitive blocks:

1. Process state changes to `psBlocked`
2. Process is added to appropriate waiting queue
3. `interp.shouldYield` is set to stop execution
4. Program counter is decremented so statement re-executes when unblocked
5. When unblocked, process state returns to `psReady` and is added to ready queue

This ensures proper resumption of blocked operations without losing state.

---

## Activation Stack

### Activation Object

Represents a method/block invocation:

```nim
type
  Activation* = ref object
    receiver*: Instance
    currentMethod*: Method
    locals*: Table[string, NodeValue]
    sender*: Activation              # Spaghetti stack for non-local returns
```

### Non-Local Returns

The `sender` chain enables non-local returns from deep blocks:

```
Caller Activation
    ↓ sender
Method Activation
    ↓ sender
Block Activation (executes return)
    ↑
Non-local return follows sender chain to find method activation
```

---

## Slot-Based Instance Variables

### Design

When a class defines instance variables:

```smalltalk
Point := Object derive: #(x y)
```

The compiler generates:
1. Slot indices (`x`→0, `y`→1)
2. O(1) access methods within methods

### Slot Access

**Direct slot access (inside methods):**
```nim
proc getX(this: Instance): NodeValue =
  result = this.slots[0]  # O(1) lookup
```

**Named slot access (dynamic):**
```nim
proc atPut(this: Instance, key: string, value: NodeValue) =
  this.properties[key] = value  # Hash table lookup (slower)
```

### Performance Comparison

Per 100k operations:
- Direct slot access: ~0.8ms
- Named slot access: ~67ms
- Property bag access: ~119ms

Slot-based access is **149x faster** than property bag access.

### Implementation

The compiler stores slot mappings in methods:

```nim
type
  Method* = ref object
    selector*: string
    body*: seq[Node]
    slotIndices*: Table[string, int]  # Maps var name → slot index
```

When a method accesses a variable:
1. Look up in `slotIndices`
2. If found, use direct slot access
3. Otherwise, fall back to property access

---

## Variable Resolution

### Lookup Order

Harding follows Smalltalk-style variable resolution with the following priority:

1. **Local variables** (temporaries, parameters, block parameters)
2. **Instance variables** (slots on `self`)
3. **Globals** (class names, global variables)

This ordering ensures that:
- Method temporaries shadow slots (allowing local computation with same names)
- Slots shadow globals (consistent Smalltalk semantics)
- Globals are accessible as fallback

### No Parent Activation Access

Unlike some interpreted languages, Harding does **not** allow methods to access the local variables of their calling method. Each method activation has its own isolated local scope:

```smalltalk
# This is INVALID - methods cannot see caller's locals
foo [
  | localVar |
  localVar := 42.
  self bar.  # bar cannot see 'localVar'
]

bar [
  localVar.  # ERROR: 'localVar' not found
]
```

This design:
- Prevents accidental coupling between methods
- Enables proper encapsulation
- Allows methods to use slot names without conflicting with caller's locals

### Implementation Details

The variable lookup in `vm.nim` checks in this order:

1. Current activation locals (`activation.locals[name]`)
2. Slots on current receiver if it's an object (`getSlotIndex(receiver.class, name)`)
3. Globals (`globals[name]`)

Previously, the VM incorrectly checked parent activation locals before slots, which could cause a caller's local variable to shadow the receiver's slot. This has been fixed to follow proper Smalltalk semantics.

---

## Directory Structure

```
src/harding/
├── core/                # Core type definitions
│   ├── types.nim        # Node, Instance, Class, WorkFrame
│   ├── process.nim      # Process type for green threads
│   └── scheduler.nim    # Scheduler type definitions
├── parser/              # Lexer and parser
│   ├── lexer.nim
│   └── parser.nim
├── interpreter/         # Execution engine
│   ├── vm.nim           # Stackless VM, method dispatch, native methods
│   ├── objects.nim      # Object system, class creation
│   ├── activation.nim   # Activation records
│   └── process.nim      # Process and scheduler types
├── core/                # Core type definitions
│   ├── types.nim        # Node, Instance, Class, WorkFrame
│   ├── process.nim      # Process type for green threads
│   └── scheduler.nim    # Green thread scheduler implementation
├── repl/                # Interactive interface
│   ├── doit.nim         # REPL context and script execution
│   └── interact.nim     # Line editing
├── codegen/             # Shared Nim code generation
│   ├── module.nim       # Top-level module generation (genModule)
│   ├── expression.nim   # Expression and statement generation with inline control flow
│   ├── methods.nim      # Method body generation
│   └── blocks.nim       # Block registry, captures, runtime helpers
├── compiler/            # Granite compiler entry points
│   ├── granite.nim      # CLI entry point (compile/build/run)
│   ├── analyzer.nim     # Class/method analysis
│   ├── context.nim      # Compiler context
│   └── compiler_primitives.nim  # In-VM compiler primitives
└── gui/                 # GTK bridge
    └── gtk/             # GTK4 wrappers and bridge
```

---

## Granite Compiler (Harding → Nim)

### Overview

Granite compiles Harding source code to Nim, producing native binaries. The compilation pipeline lives in `src/harding/codegen/` and is shared between the CLI tool and the in-VM compiler.

### Pipeline

```
.hrd source → Lexer → Parser → AST → Code Generator → .nim source → Nim compiler → binary
```

### Code Generation Modules

| Module | Purpose |
|--------|---------|
| `codegen/module.nim` | Top-level generation: imports, runtime helpers, block procedures, main proc |
| `codegen/expression.nim` | Expression and statement generation, inline control flow |
| `codegen/methods.nim` | Method body compilation |
| `codegen/blocks.nim` | Block registry, capture analysis, environment structs, runtime helpers |

### Inline Control Flow

Literal blocks in control flow messages are compiled to native Nim constructs:

| Harding | Generated Nim |
|---------|--------------|
| `cond ifTrue: [body]` | `if isTruthy(cond): body` |
| `cond ifTrue: [a] ifFalse: [b]` | `if isTruthy(cond): a else: b` |
| `[cond] whileTrue: [body]` | `while isTruthy(cond): body` |
| `[cond] whileFalse: [body]` | `while not isTruthy(cond): body` |
| `n timesRepeat: [body]` | `for i in 0..<toInt(n): body` |

This avoids block object creation and dispatch overhead for common patterns.

### Runtime Value System

Generated code uses the same `NodeValue` variant type as the interpreter:

```nim
type NodeValue = object
  case kind: ValueKind
  of vkInt: intVal: int64
  of vkFloat: floatVal: float64
  of vkBool: boolVal: bool
  of vkString: strVal: string
  # ... etc
```

Arithmetic and comparison operators are compiled to helper functions (`nt_plus`, `nt_minus`, etc.) that handle type dispatch at runtime.

### Performance

Compiled code runs significantly faster than interpreted:

| Mode | Relative Speed |
|------|---------------|
| Interpreter (debug) | 1x baseline |
| Interpreter (release) | ~10x |
| Compiled (debug) | ~330x |
| Compiled (release) | ~2300x |

(Based on sieve of Eratosthenes benchmark, primes up to 5000)

---

## For More Information

- [MANUAL.md](MANUAL.md) - Core language manual
- [GTK.md](GTK.md) - GTK integration
- [TOOLS_AND_DEBUGGING.md](TOOLS_AND_DEBUGGING.md) - Tool usage
- [FUTURE.md](FUTURE.md) - Future plans
- [research/](research/) - Historical design documents
