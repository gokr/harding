# Concurrency Design for Nimtalk

This document explores concurrency models for Nimtalk, comparing different approaches and their implications for the language design, debugger implementation, and compilation strategy.

## Goals

Nimtalk aims to support:

1. **Smalltalk-style debugging** - A debugger written in Nimtalk itself that can manipulate other processes (step, pause, continue, introspect stacks)
2. **Efficient compilation** - Nimtalk programs compile to efficient Nim code for deployment
3. **Native thread utilization** - Take advantage of Nim's threading capabilities

## Current Architecture Context

Nimtalk's interpreter uses:

- **Per-Interpreter activation stack** - Each `Interpreter` has `activationStack: seq[Activation]`, naturally isolating Process state
- **Spaghetti stack** - Activations link via `sender` for non-local returns
- **Ref objects** - `ProtoObject` is GC-managed, safe to share between threads with synchronization
- **Native method interface** - Methods can have `nativeImpl` for compiled code or access interpreter state

## Concurrency Models Compared

### 1. Green Threads (Classic Smalltalk)

**Core abstraction**: Cooperative lightweight threads managed by a VM-level scheduler. Each Process has its own isolated Interpreter.

**Characteristics**:
- Cooperative multitasking - Processes yield at specific points
- Each Process owns an `Interpreter` with isolated `activationStack`
- Full control over scheduling enables deterministic debugging
- Processes can be suspended, resumed, and introspected

**Nimtalk mapping**:
```nim
type
  Process* = ref object of ProtoObject
    interpreter*: Interpreter     # Own interpreter with isolated stack
    state*: ProcessState          # running, ready, blocked, suspended
    priority*: int
    name*: string
```

**Scheduling points**:
- Explicit `yield` message
- Message send boundaries (configurable)
- Blocking operations (semaphore wait, I/O)

**Debugger support**:
```smalltalk
debugger := Debugger new.
debugger attachTo: someProcess.
debugger step.           "Execute one message send"
debugger continue.       "Resume process"
debugger inspectStack.   "Return array of activations"
```

Each `Activation` exposes:
- `receiver` - the self object
- `locals` - all variables including parameters and temporaries
- `currentMethod` - the executing method/block
- `pc` - which statement is next

---

### 2. Actor Model (Erlang/Elixir-inspired)

**Core abstraction**: Entities with identity, state, and a mailbox. No shared memory - all communication via asynchronous message passing.

**Key semantics**:
- Each actor has an address (PID) - you send messages to an identity
- Each actor has a mailbox - incoming messages queue up
- Single-threaded per actor - handles one message at a time
- Long-lived - persists until explicitly terminated
- No shared mutable state by design

**Nimtalk mapping**:
```nim
type
  Pid* = ref object of ProtoObject
    id*: uint64
    mailbox*: Channel[Message]
    process*: Process

  Message* = object
    sender*: Pid
    selector*: string
    args*: seq[NodeValue]
```

**Nimtalk syntax**:
```smalltalk
"Spawn a new actor process"
pid := [self receive: [:msg | msg process]] spawn.

"Send messages (async, no shared state)"
pid send: #compute with: 42.

"Receive with pattern matching"
self receive: [
  #compute -> [:n | n * 2].
  #stop -> [self terminate].
  #default -> [:msg | "Unknown: " + msg printString]
].
```

**Difference from green threads**: An actor is like an object that happens to run concurrently; a green thread is just execution context.

---

### 3. Goroutines (Go-inspired)

**Core abstraction**: Lightweight concurrent functions that communicate via typed channels.

**Key semantics**:
- Anonymous - spawned and potentially forgotten
- Shared memory is possible (though channels are encouraged)
- Channels are the communication mechanism
- No inherent identity

**Nimtalk mapping**:
```nim
type
  Channel*[T] = ref object of ProtoObject
    nimChannel*: NimChannel[T]
    closed*: bool

  Goroutine* = ref object
    fn*: BlockNode
    interpreter*: Interpreter
    nativeThread*: Thread[void]
```

**Nimtalk syntax**:
```smalltalk
"Create a channel"
ch := Channel new: 10.

"Spawn a goroutine"
go: [
  ch send: 42.
  ch close
].

"Receive (blocks if empty)"
value := ch receive.

"Select statement"
select: [
  ch1 -> [:val | "Got from ch1: " + val].
  ch2 -> [:val | "Got from ch2: " + val].
  default -> ["No channels ready"]
].
```

**Hybrid execution**:
- Interpreted goroutines: Run on pool of green threads
- Compiled goroutines: Each becomes native Nim thread
- Channel bridging: Nim's `std/channels` works between both

---

### 4. Continuations (call/cc or delimited)

**Core abstraction**: "The rest of the computation" captured as a first-class value.

**Key semantics**:
- Captures call stack - saves entire execution context
- Can be resumed later
- Can be resumed multiple times (undelimited) or once (delimited)
- Not inherently concurrent - enables concurrency implementations

**Nimtalk mapping**:
```nim
type
  Continuation* = ref object
    activationStack*: seq[Activation]
    prompt*: Prompt

  Prompt* = ref object
    id*: int
    handler*: BlockNode
```

**Nimtalk syntax**:
```smalltalk
"Capture current continuation"
continuation := self callcc: [:cont |
  savedCont := cont.
  42
].

"Resume elsewhere"
savedCont value: 100.

"Delimited version"
self reset: [
  self shift: [:cont |
    saved := cont.
    1
  ].
  2 + 3
].
```

**Use cases**:
- Live migration - serialize continuation, send to another node, resume
- Fault tolerance - snapshot continuations periodically, restore on crash
- Generators - yield values from deep in call stack

---

## Semantic Comparison

| Aspect | Green Threads | Actors | Goroutines | Continuations |
|--------|--------------|--------|-----------|---------------|
| **Identity** | Process object | PID/Address | Anonymous | First-class value |
| **State** | Interpreter stack | Encapsulated | Closure capture | Captured stack |
| **Communication** | Shared objects (with locks) | Messages to PID | Channels | Not built-in |
| **Shared memory** | Possible | Impossible | Possible | N/A |
| **Lifetime** | Until terminates | Until terminated | Until returns | Until invoked |
| **Debugger view** | Full stack inspection | Mailbox + state | Hard to track | Serializable |

---

## Relationship Between Models

Continuations are the primitive. Both green threads and actors can be built using continuations:

```
Continuations (primitive)
    ↓
Green Threads (suspend/resume via continuations)
    ↓
    ├── Goroutines (green threads + channels)
    └── Actors (green threads + mailboxes + PIDs)
```

**Building green threads with continuations**:
1. When a Process yields, capture its continuation
2. Store it in scheduler's queue
3. Resume by invoking continuation

**Building actors with continuations**:
1. Each actor has a mailbox
2. When processing needs to wait, capture continuation
3. Resume when message arrives

---

## Recommended Implementation Path

### Phase 1: Green Threads (Foundation)

Implement pure green threads first:

1. **Fits current architecture** - each Process gets own `Interpreter`
2. **Enables debugger** - full introspection of Process stacks
3. **Cooperative scheduling** - simpler, no preemption complexity
4. **Minimal evaluator changes** - add yield check at message sends

```nim
# In evaluator - yield check at message boundaries
proc evalMessage(interp: var Interpreter, msgNode: MessageNode): NodeValue =
  if shouldYield(interp):
    suspendCurrentProcess()
    switchToNextProcess()
  # ... message send logic
```

### Phase 2: Add Channels

Add channel-based communication:

1. **Thread-safe** - Nim's `std/channels` provides synchronization
2. **Composes well** - green threads block on channels, scheduler handles it
3. **Forward compatible** - same API works with native threads later

### Phase 3: Native Thread Compilation

When compiling to Nim:

1. Each Process becomes a Nim `Thread`
2. Message sends to other Processes become channel operations
3. Shared objects use Nim's `Lock` for multi-thread access

---

## Critical Design Decisions

### Scheduler Location

**Option A: Nim-level** (start here)
```nim
proc runScheduler() =
  while true:
    let next = readyQueue.dequeue()
    currentProcess = next
    resume(next.interpreter)
```

**Option B: Nimtalk-level** (migrate here)
```smalltalk
Scheduler runLoop: [
  self nextProcess ifNotNil: [:p |
    self activate: p.
    p runFor: 10 ms.
    p isRunning ifTrue: [self readyQueue add: p]
  ]
].
```

### Shared Object Access

Since `ProtoObject` is `ref object`, multiple threads can reference it:

**Start with**: Explicit locks/mutexes (simple, predictable)
```smalltalk
mutex := Mutex new.
mutex critical: [
  "Exclusive access"
].
```

**Future**: Software transactional memory (STM) for optimistic concurrency

### Process State for Debugging

A Process must expose:
```smalltalk
process inspectStack    "Array of activation descriptions"
process step            "Execute one message send"
process continueUntil: conditionBlock
```

---

## Summary

| Approach | Debuggability | Performance | Implementation | Compilation |
|----------|--------------|-------------|----------------|-------------|
| Green Threads | Excellent | Good | Easiest | Fallback to interp |
| Actors | Good | Good | Medium | Channel-based |
| Goroutines | Good | Better | Medium | Native threads |
| Hybrid | Good | Best | Harder | Migration logic |
| Continuations | Excellent | Good | Hardest | Serialization |

**Recommendation**: Green Threads + Channels hybrid, evolving toward native thread compilation as the compiler matures.

**Key insight**: Continuations capture "where you are" in computation, actors capture "who you are" in the system, goroutines capture "what you're doing" without identity.
