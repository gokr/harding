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
| `load:` | Load/evaluate `.hrd` from filesystem or embedded package sources | Required to load stdlib and packaged libraries |

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

See [BOOTSTRAP.md](BOOTSTRAP.md) for complete details on the bootstrap architecture, including:
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

Wrapper for all Harding values using a case variant:

```nim
type
  ValueKind* = enum
    vkInt, vkFloat, vkString, vkSymbol, vkBool, vkNil, vkBlock,
    vkArray, vkTable, vkClass, vkInstance

  NodeValue* = object
    case kind*: ValueKind
    of vkInt: intVal*: int64
    of vkFloat: floatVal*: float64
    of vkString: strVal*: string
    of vkSymbol: symVal*: string
    of vkBool: boolVal*: bool
    of vkNil: discard
    of vkBlock: blockVal*: BlockNode
    of vkArray: arrayVal*: seq[NodeValue]
    of vkTable: tableVal*: Table[NodeValue, NodeValue]
    of vkClass: classVal*: Class
    of vkInstance: instVal*: Instance
```

### Instance

Represents a class instance:

```nim
type
  InstanceObj = object
    class*: Class
    slots*: seq[NodeValue]        # Indexed slots (slots)
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

When a class defines slots:

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

## Nim Coding Guidelines

### Code Style and Conventions

- **Use camelCase**, not snake_case (avoid `_` in naming)
- **Do not shadow the local `result` variable** - Nim provides an implicit `result` variable; declaring a local variable named `result` shadows it and causes warnings
- **Doc comments**: Use `##` placed **after** proc signature
- **Prefer generics or object variants** over methods and type inheritance
- **Use `return expression`** for early exits
- **Prefer direct field access** over getters/setters
- **NO `asyncdispatch`** - use threads or taskpools for concurrency
- **Remove old code during refactoring** - don't leave commented-out code
- **Import full modules**, not selected symbols
- **Use `*`** to export fields that should be publicly accessible
- **ALWAYS write `fmt("...")`** not `fmt"..."` (escaped characters)

### Memory Management: var, ref, and ptr

**Nim is Value-Based**: Understanding Nim's value semantics is critical for memory safety.

#### var (Value Types)
- Creates stack-allocated values with copy-on-assignment semantics
- `var x = y` creates a copy of `y` (except for ref/ptr types)
- Use for objects that don't need shared ownership or heap allocation
- Default for most types - safer and more efficient

#### ref (Traced References)
- Garbage-collected heap references (preferred for shared objects)
- Use `new()` to allocate: `var obj = new(MyType)`
- Assignment copies the reference, not the object
- Automatically managed by Nim's garbage collector
- Use when you need shared ownership or want to avoid copying

#### ptr (Untraced Pointers)
- Manually managed memory (unsafe)
- Use with `alloc()`/`dealloc()`: must manage lifetime yourself
- Required for FFI or low-level system programming
- Must call `reset()` on GC objects before deallocating to prevent leaks
- Avoid unless absolutely necessary

#### ref Objects Design Pattern

For objects that will frequently be shared, define them as `ref object` from the start:

```nim
type
  DataFile = ref object
    handle: File
    size: uint64
    lock: Lock

# Usage: no wrapping needed
proc createDataFile(): DataFile =
  result = DataFile(handle: open(...), size: 0)
```

This provides natural shared ownership semantics and avoids constant dereferencing.

#### Common Pitfalls

**NEVER take address of temporary copies:**
```nim
# DANGEROUS - undefined behavior!
proc badExample(): ptr int =
  var x = 42
  var table = {"key": x}
  result = addr table["key"]  # Points to temporary copy!
```

**Rule of Thumb:**
- Use `var` for stack-local and simple values
- Use `ref object` for types intended to be shared
- Use `ref` wrapping only when retrofitting existing value types
- Use `ptr` only for FFI or when you specifically need manual memory management
- Never use `addr` and `cast` to create refs from value types in containers

### ARC Memory Management and Pointer Safety

**Critical for ARC/ORC**: Raw `pointer` types can cause memory corruption if not handled properly with ARC.

#### The Problem

When storing a Nim `ref` object in an `Instance.nimValue` field as a raw `pointer`:

```nim
# DANGEROUS with ARC/ORC
blockNode = BlockNode()
instance.nimValue = cast[pointer](blockNode)  # ARC loses track
# ... later ...
blockNode2 = cast[BlockNode](instance.nimValue)  # CRASH! Collected!
```

#### The Solution: Keep-Alive Registries

Create a global seq that keeps references alive:

```nim
var blockNodeRegistry*: seq[BlockNode] = @[]

proc registerBlockNode*(blk: BlockNode) =
  if blk != nil and blk notin blockNodeRegistry:
    blockNodeRegistry.add(blk)
```

When storing in nimValue:
```nim
registerBlockNode(receiverVal.blockVal)  # Keep alive
instance = Instance(
  kind: ikObject,
  class: blockClass,
  nimValue: cast[pointer](receiverVal.blockVal)  # Now safe
)
```

#### Existing Registries

The codebase already has several keep-alive registries:

- `blockNodeRegistry` in `types.nim`
- `processProxies`, `schedulerProxies`, `monitorProxies` in `scheduler.nim`
- `globalTableProxies` in `vm.nim`

**Rule**: When adding new pointer storage to `nimValue`, always add to the appropriate keep-alive registry first.

### Thread Safety

**Important**: Do not use asyncdispatch. Use regular threading or taskpools for concurrency.

#### Lock-Protected Data Structures
- Use `Lock` for concurrent access to shared data structures
- Use condition variables for coordination when needed

#### GC Safety Pattern

For threaded code that accesses shared state, use `{.gcsafe.}` blocks:

```nim
proc someThreadedProc*() {.gcsafe.} =
  {.gcsafe.}:
    # Access to shared state that is actually thread-safe
    withLock(keydir.lock):
      keydir.entries[key] = entry
```

Use `{.gcsafe.}:` blocks only when certain the code is actually thread-safe.

### ORC Crash Prevention

Nim's ORC garbage collector can crash when cleaning up objects with circular references across thread boundaries (Nim issue #25253).

#### Prevention with {.acyclic.}

Mark types that participate in cross-thread references:
```nim
BarrelObj {.acyclic.} = object
  # ...
```

#### Eliminate Closures in Cross-Thread Code

**Problem**: Closures create GC-managed environments that ORC tracks. When objects are destroyed across thread boundaries, ORC can crash.

**Solution**: Store raw pointers directly instead of closures:

```nim
# BAD - closures cause ORC crashes
type Callback = proc(key: string, entry: KeyDirEntry) {.gcsafe.}

# GOOD - direct pointer storage, no closures
type CompactControllerObj = object
  indexMode: IndexMode
  keyDirPtr: pointer    # Raw pointer, not tracked by ORC
  critBitPtr: pointer
```

#### Cleanup Order

Shutdown controllers BEFORE deinitializing resources:
```nim
proc close*(barrel: Barrel) =
  # Wait for threads to complete
  barrel.joinCompactionThread()

  # Shutdown controller BEFORE deinit
  if barrel.compactController != nil:
    barrel.compactController.shutdown()
    barrel.compactController = nil

  # Now safe to deinit
  barrel.keyDir.deinit()
```

### Function and Return Style

- **Single-line functions**: Use direct expression without `result =` or `return`
- **Multi-line functions**: Use `result =` assignment and `return` for clarity
- **Early exits**: Use `return value` instead of `result = value; return`
- **Exception handlers**: Use `return expression` for error cases

### Comments and Documentation

- Do not add comments talking about how good something is
- Do not add comments that reflect what has changed (use git)
- Do not add unnecessary commentary or explain self-explanatory code

### Refactoring

- Remove old unused code during refactoring
- Delete deprecated methods, unused types, and obsolete code paths immediately
- Keep the codebase lean and focused

### Code Quality and Testing

- **All tests must pass**: Green tests are non-negotiable
- **No warnings in test compilation**: Test code should compile without warnings
- **Check for and remove compiler warnings**: unused imports, unused variables, unused parameters
- **Use `_` prefix** for intentionally unused parameters

---

## Nim Doc Comment Guidelines

### Basic Syntax

**Documentation comments** use double hash (`##`):
```nim
## This is a documentation comment - will appear in generated docs
```

**Regular comments** use single hash (`#`):
```nim
# This is a regular comment - will NOT appear in generated docs
```

### Placement

- **Module docs**: At the top of the file, before imports
- **Type docs**: After the type definition
- **Proc docs**: After the proc signature
- **Field docs**: Using `##` after each field

### Important Rule: Exports

**Documentation will only be generated for exported types/procedures.**

Use `*` following the name to export:
```nim
type Record* = object    ## Will generate docs (exported)
type Person = object     ## Will NOT generate docs (not exported)

proc open*(path: string): DataFile =  ## Will generate docs
proc close(path: string) =            ## Will NOT generate docs
```

### Standard Sections

**Description**: First line or paragraph
```nim
proc len*(keyDir: var KeyDir): int =
  ## Get the number of entries in the KeyDir
```

**Parameters**: Inline format
```nim
## limit: Maximum number of items to return (default: 1000)
## cursor: Last key from previous page
```

**Code Examples**: Using `**Example:**`
```nim
## **Example:**
## ```nim
## var t = {"name": "John"}.newStringTable
## doAssert t.len == 2
## ```
```

### Formatting

**Backticks for code identifiers**:
```nim
## Use `open` to create a new data file
```

**Double backticks for format specs**:
```nim
## Returns: ``(items: seq[(string, string)], nextCursor: string, hasMore: bool)``
```

### Best Practices

1. **Add exactly one space after `##`**
2. **Always include code examples** for key public APIs
3. **Document all export parameters**
4. **Document return types**

### Writing Style

- Use neutral, factual language
- Avoid superlatives and hype words
- Focus on implementation details and behavior

**Do's and Don'ts**:
- Do: "Fast recovery", "Provides good performance"
- Don't: "Ultra-fast recovery", "Optimal performance", "Maximum performance"

---

## For More Information

- [MANUAL.md](MANUAL.md) - Core language manual
- [GTK.md](GTK.md) - GTK integration
- [TOOLS_AND_DEBUGGING.md](TOOLS_AND_DEBUGGING.md) - Tool usage and debugging
- [FUTURE.md](FUTURE.md) - Future plans
- [research/](research/) - Historical design documents
