# Nemo Implementation Guide

## Overview

This document describes Nemo's implementation internals, architecture, and development details.

## Table of Contents

1. [Architecture](#architecture)
2. [Stackless VM](#stackless-vm)
3. [Core Types](#core-types)
4. [Evaluator](#evaluator)
5. [Scheduler and Processes](#scheduler-and-processes)
6. [Activation Stack](#activation-stack)
7. [Slot-Based Instance Variables](#slot-based-instance-variables)

---

## Architecture

Nemo consists of several subsystems:

| Component | Location | Purpose |
|-----------|----------|---------|
| Lexer | `src/nemo/parser/lexer.nim` | Tokenization of source code |
| Parser | `src/nemo/parser/parser.nim` | AST construction |
| Core Types | `src/nemo/core/types.nim` | Node, Instance, Class definitions |
| Interpreter | `src/nemo/interpreter/vm.nim` | Stackless VM execution |
| Evaluator | `src/nemo/interpreter/objects.nim` | Method lookup and invocation |
| Scheduler | `src/nemo/interpreter/scheduler.nim` | Green thread scheduling |
| REPL | `src/nemo/repl/` | Interactive interface |
| Compiler | `src/nemo/compiler/` | Nemo to Nim code generation |
| GTK Bridge | `src/nemo/gui/gtk4/` | GTK widget integration |

### Data Flow

```
Source Code (.nemo)
       ↓
   Lexer
       ↓
  Tokens
       ↓
  Parser
       ↓
  AST (Abstract Syntax Tree)
       ↓
  Stackless VM
       ↓
  Activation Stack + Eval Stack
       ↓
  Evaluator (method dispatch)
       ↓
  Native Methods or Interpreted Bodies
       ↓
  Result
```

---

## Stackless VM

### Overview

The Nemo VM implements an iterative AST interpreter using an explicit work queue instead of recursive Nim procedure calls. This enables:

1. **True cooperative multitasking** - yield within statements
2. **Stack reification** - `thisContext` accessible from Nemo
3. **No Nim stack overflow** - on deep recursion
4. **Easier debugging and profiling** - flat execution loop

### Why Stackless?

| Aspect | Recursive Evaluator | Stackless VM |
|--------|---------------------|--------------|
| Lines of code | ~3,260 | ~1,200 |
| Execution model | Recursive Nim calls | Explicit work queue |
| Stack depth | Nim call stack | User-managed work queue |
| Multitasking | Limited | Full cooperative |

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

5. **Stack Reification**: The entire Nemo call stack is accessible as data

---

## Core Types

### NodeValue

Wrapper for all Nemo values:

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
    slotsDefinition*: seq[string] # Slot names

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

## Evaluator

### Method Lookup

The evaluator implements the full method dispatch chain:

1. **Direct lookup** - Check method on receiver's class
2. **Direct parent lookup** - Check each parent class directly
3. **Inherited lookup** - Check superclass chain
4. **Parent inheritance lookup** - Check superclass chain of each parent
5. **class method lookup** - For `ClassName>>method` syntax

### Super Sends

Qualified super sends `super<Class>>method` dispatch directly to the specified parent:

```nim
proc invokeSuper(interp: var Interpreter, method: Method,
                 receiver: Instance, args: seq[NodeValue],
                 superClass: Class): NodeValue =
  # Bypass normal lookup, use provided superClass
```

### Native Methods

Native methods are Nim functions that implement Nemo methods:

```nim
type
  MethodImpl* = proc(interp: var Interpreter,
                     self: Instance,
                     args: seq[NodeValue]): NodeValue {.gcsafe.}

  Method* = ref object
    selector*: string
    body*: seq[Node]
    nativeImpl*: MethodImpl
```

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
- Blocking operations (when implemented)

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

## Directory Structure

```
src/nemo/
├── core/                # Core type definitions
│   └── types.nim        # Node, Instance, Class
├── parser/              # Lexer and parser
│   ├── lexer.nim
│   └── parser.nim
├── interpreter/         # Execution engine
│   ├── vm.nim          # Stackless VM
│   ├── objects.nim     # Method dispatch
│   └── scheduler.nim   # Green thread scheduler
├── repl/                # Interactive interface
│   ├── doit.nim
│   └── interact.nim
├── compiler/            # Nemo to Nim compilation
│   └── ...
└── gui/                 # GTK bridge
    ├── gtk4/           # GTK4 wrappers
    └── ...
```

---

## For More Information

- [MANUAL.md](MANUAL.md) - Core language manual
- [GTK.md](GTK.md) - GTK integration
- [TOOLS_AND_DEBUGGING.md](TOOLS_AND_DEBUGGING.md) - Tool usage
- [FUTURE.md](FUTURE.md) - Future plans
- [research/](research/) - Historical design documents
