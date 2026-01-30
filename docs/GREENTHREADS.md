# Green Threads and GTK Integration Plan

This document outlines the implementation plan for cooperative green processes (green threads) and GTK4 integration for Nimtalk. The design centers around Monitors as the fundamental concurrency primitive, with shared heaps and copy-on-pass by reference.

**See also:**
- [Concurrency Design](./CONCURRENCY.md) – background theory and comparisons.
- [Gtk Intro](./GINTRO.md) – GTK4 Nim bindings.
- [Internal Details](./GREENTHREADS-DETAILS.md) – scheduler and Monitor details.

---

## 1. What we are building

We implement a **user‑space cooperative scheduler** for _green processes_, each with its own Nimtalk interpreter and activation stack. The scheduler runs all processes in a single Nim thread, sharing a common heap but with per‑process activation stacks.

A **Monitor** is the fundamental coordination primitive, providing re‑entrant mutual exclusion and condition variables. All other IPC (SharedQueue, Channel) is built on Monitors.

A GTK‑idle callback runs the scheduler; when the ready‑queue is empty, we yield to the GTK event loop, so GTK events are processed with soft real‑time responsiveness.

---

## 2. Core Concepts

### 2.1. Green‑process model (co‑operative)

- **Single‑threaded** Nimtalk VM (one OS thread, green processes scheduled cooperatively).
- **Explicit yield points** on `Processor yield`, when blocking on a synchronization primitive, or optionally after N message sends (configurable via `yieldEveryNSends`).
- Processes run in a **shared‑heap, private‑stack** model: the Nimtalk heap is common, but each process has its own activation stack and program‑counter‑like “instruction pointer”.
- Communication uses Monitors, built‑on‑them SharedQueues, and later channels (bounded buffers). No copying of objects passed via a channel (shared heap, pass‑by‑reference).
- **Blocking**: when a process would block on a Monitor, SharedQueue, or Channel, the scheduler moves it to a blocked set.

### 2.2. Synchronisation & Communication Primitives

Primitives in order of increasing abstraction:

1. **Monitor (core)** – re‑entrant lock + condition variables (`wait`, `notify`, `notifyAll`).
   - For single-threaded cooperative scheduling, monitors are pure bookkeeping (no OS locks needed).
   - Re‑entrancy is per‑process: the same green thread can lock a monitor it already holds.

2. **Semaphore (binary/counting)** – built on Monitor + an integer count. Classic `signal`/`wait`.

3. **SharedQueue (bounded)** – producer‑consumer queue built on a Monitor, with a fixed‑capacity array and two condition variables (`non‑empty`, `non‑full`). This is the primary IPC primitive.

4. **Channel (CSP style, bounded buffer)** – built on SharedQueue, typed messages.

5. **Actor‑style mailbox** – each process can have a mailbox (SharedQueue) that receives messages as (selector‑string, argument‑list).

### 2.3. Communication Primitives (Nim‑side Naming)

| Primitive           | Nim‑side type        | Nimtalk‑side class | Purpose                               |
|--------------------|---------------------|----------------------|---------------------------------------|
| Monitor            | `NimtalkMonitor`     | `Monitor`            | Re‑entrant mutex + condition vars   |
| Semaphore          | `NimtalkSemaphore`  | `Semaphore`          | Binary/counting semaphore            |
| SharedQueue        | `NimtalkSharedQueue` | `SharedQueue`        | Classic Smalltalk bounded queue      |
| Channel           | `NimtalkChannel`     | `Channel` (bounded)  | CSP‑style typed channel (future)    |

All primitives are designed to work purely cooperatively: when a green process blocks (waiting on a monitor or queue), the scheduler puts it aside and runs the next process.

### 2.4. Debugging & Inspection

Because each process has its own interpreter and activation stack, a debugger written in Nimtalk can:

1. Attach to any process (suspend it).
2. Walk its stack frames (each frame has `receiver`, `method`, locals, PC).
3. Step the process one Nimtalk message‑send at a time.

The debugger is just another Nimtalk process, using the same APIs that the Nim scheduler provides.

---

## 3. Implementation

### 3.1. Nim‑side Data Structures

```nim
type
  ProcessState* = enum
    psReady, psRunning, psBlocked, psSuspended, psTerminated

  WaitKind* = enum
    wkMonitor, wkSemaphore, wkQueueFull, wkQueueEmpty

  WaitCondition* = object
    kind*: WaitKind
    target*: pointer  # The monitor/queue being waited on

  Process* = ref object
    pid: uint64
    name: string
    interpreter: Interpreter  # Each process has its own interpreter
    state: ProcessState
    blockedOn: WaitCondition  # Valid when state == psBlocked
    priority: int             # Higher = runs first (0 = normal)
```

**Process/Interpreter Relationship:**
- Each `Process` contains its own `Interpreter` instance with its own activation stack
- The activation stack and program counter live inside the `Interpreter`, not duplicated in `Process`
- All interpreters share a common `globals` table (for global variables)
- All interpreters share a common `rootObject` (the prototype hierarchy root)

### 3.2. Green‑threads Scheduler

One global scheduler holds:

- `readyQueue: Deque[Process]`
- `blockedSet: Set[Process]`
- `allProcesses: Table[uint64, Process]`

Scheduler loop:

1. If `readyQueue` empty → remove GTK idle callback (nothing to do).
2. Pop first process from `readyQueue`.
3. Switch context (current interpreter = its interpreter; set current process).
4. Let the interpreter run **one Nimtalk message send** (or a time‑slice of byte‑code).
5. If the process didn't block, push back to tail of readyQueue.
6. If it blocked on a condition, move it to the appropriate blocked set.
7. Goto step 1.

**GTK Idle Callback Strategy**:
- Install an idle callback when processes become ready (e.g., after spawning or unblocking).
- Remove the callback when the ready queue becomes empty.
- Each callback invocation runs one process slice, then returns control to GTK.
- This ensures GTK events are processed with soft real-time responsiveness.

```nim
proc schedulerIdleCallback(): bool =
  ## Returns true to keep callback installed, false to remove it
  if sched.readyQueue.len == 0:
    return false  # Remove callback, nothing to run
  sched.runOneSlice()
  return true  # Keep callback installed
```

### 3.3. GTK Integration

Each Nimtalk‑side GTK widget holds a Nim‑side pointer to the underlying GTK widget and a finalizer.

When a GTK event occurs (button‑click), the GTK main loop invokes our Nim‑side callback, which does:

```nim
let process = processOwningThisWidget(proc)
var callbackBlock: BlockNode
# ... wrap GTK arguments into Nimtalk objects, push a new activation frame
pushActivation(proc, callbackBlock, args)
schedule(proc)
```

The callback is executed next time the associated Nimtalk process is scheduled.

### 3.4. Monitor Implementation

For single-threaded cooperative scheduling, monitors are just bookkeeping—no OS-level locks are needed since only one green process runs at a time:

```nim
type
  NimtalkMonitor* = ref object
    owner*: Process           # Which process holds the lock (nil = unlocked)
    lockCount*: int           # Re-entrancy count
    waitQueue*: seq[Process]  # Processes waiting to acquire

proc enter*(m: NimtalkMonitor, sched: Scheduler, caller: Process) =
  if m.owner == nil:
    m.owner = caller
    m.lockCount = 1
  elif m.owner == caller:
    inc m.lockCount  # Re-entrant
  else:
    m.waitQueue.add(caller)
    sched.block(caller, WaitCondition(kind: wkMonitor, target: cast[pointer](m)))

proc leave*(m: NimtalkMonitor, sched: Scheduler) =
  dec m.lockCount
  if m.lockCount == 0:
    m.owner = nil
    if m.waitQueue.len > 0:
      let next = m.waitQueue.pop()
      m.owner = next
      m.lockCount = 1
      sched.unblock(next)
```

### 3.5. SharedQueue (classic bounded buffer)

A bounded buffer with separate wait queues for producers and consumers:

```nim
type
  NimtalkSharedQueue*[T] = ref object
    data: seq[T]
    head, tail, count: int
    capacity: int
    waitingProducers: seq[Process]  # Blocked on "queue full"
    waitingConsumers: seq[Process]  # Blocked on "queue empty"

proc put*(q: NimtalkSharedQueue, sched: Scheduler, item: NodeValue, caller: Process) =
  if q.count == q.capacity:
    q.waitingProducers.add(caller)
    sched.block(caller, WaitCondition(kind: wkQueueFull, target: cast[pointer](q)))
    return

  q.data[q.tail] = item
  q.tail = (q.tail + 1) mod q.capacity
  inc q.count

  if q.waitingConsumers.len > 0:
    sched.unblock(q.waitingConsumers.pop())

proc take*(q: NimtalkSharedQueue, sched: Scheduler, caller: Process): NodeValue =
  if q.count == 0:
    q.waitingConsumers.add(caller)
    sched.block(caller, WaitCondition(kind: wkQueueEmpty, target: cast[pointer](q)))
    return nil  # Will resume with result when unblocked

  result = q.data[q.head]
  q.head = (q.head + 1) mod q.capacity
  dec q.count

  if q.waitingProducers.len > 0:
    sched.unblock(q.waitingProducers.pop())
```

### 3.6. Process Spawning Mechanics

When a Nimtalk program calls `Processor fork: aBlock`, the following Nim-side code runs:

```nim
proc forkProcess*(sched: var Scheduler, block: BlockNode, receiver: ProtoObject): Process =
  ## Create a new green process from a Nimtalk block
  let newInterp = newInterpreter()
  newInterp.globals = sched.sharedGlobals     # Share globals table
  newInterp.rootObject = sched.rootObject     # Share prototype root

  result = Process(
    pid: sched.nextPid(),
    interpreter: newInterp,
    state: psReady
  )

  # Set up initial activation frame for the block
  let activation = newActivation(receiver, block)
  newInterp.activationStack.add(activation)
  newInterp.currentActivation = activation

  # Add to scheduler
  sched.readyQueue.addLast(result)
  sched.allProcesses[result.pid] = result
```

### 3.7. Nimtalk API Examples

Here's what the Nimtalk programmer sees:

```smalltalk
"Fork a new process"
process := Processor fork: [
  1 to: 10 do: [:i | Transcript show: i]
]

"Explicit yield to other processes"
Processor yield

"Synchronization with Monitor"
lock := Monitor new.
lock critical: [
  sharedCounter := sharedCounter + 1
]

"Producer-consumer with SharedQueue"
queue := SharedQueue new: 10.
Processor fork: [1 to: 100 do: [:i | queue put: i]].
Processor fork: [100 timesRepeat: [Transcript show: queue take]]
```

### 3.8. Error Handling

**Process termination while holding locks:**
- Release all monitors held by the terminating process.
- Wake waiters with an error condition (ProcessTerminated).

**Uncaught exceptions in processes:**
- Terminate the process with state `psTerminated`.
- Log the error to a system transcript or error log.
- Other processes continue unaffected.

**Deadlock detection (optional enhancement):**
- Maintain a wait-for graph: edges from blocked process to the process holding what it waits on.
- Detect cycles in the graph to identify deadlocks.
- Report deadlock to debugger or system console.

---

## 4. Implementation Roadmap

### Phase 1: Core Scheduler and Monitor (1‑2 weeks)

- [ ] `nimtalk/core/process.nim`: Process, Scheduler types.
- [ ] Basic round‑robin scheduler, with only explicit yields.
- [ ] Monitor: Nim‑side re‑entrant lock + condition variable.
- [ ] Simple yield and block/unblock operations.

### Phase 2: Synchronisation Primitives (2‑3 weeks)

- [ ] Semaphore (binary, counting).
- [ ] SharedQueue (bounded buffer) atop Monitor.
- [ ] Nimtalk‑side `Monitor` and `SharedQueue` objects.
- [ ] Process spawning from Nimtalk: `Processor fork: aBlock`.
- [ ] Debugger: inspection of process stack frames.

### Phase 3: GTK Bridge (2 weeks)

- [ ] Basic GTK widget objects (Window, Button, Box, TextView).
- [ ] Event‑loop hook for GTK idles.
- [ ] Signal‑to‑callback mapping (GTK signal → Nimtalk block evaluation).

### Phase 4: Nimtalk‑side UI Framework (2‑3 weeks)

- [ ] `GtkApplication` Nimtalk‑side class.
- [ ] Example apps: Transcript, simple editor, process inspector.

### Phase 5: Channels and Actor‑style (future)

- [ ] Channels: bounded capacity, typed.
- [ ] Actor‑mailbox processes.
- [ ] Supervisor‑style process‑linking (re‑invent OTP for Nimtalk).

---

## 5. Open Questions / Design Decisions

- **Priority inversion** – simple strict FIFO of same priority. Could add priority inheritance later.
- **Process‑local GC heaps?** Not for now; single‑heap with sharing is fine for small objects.
- **Channel type safety** – Nim‑side generic channels possible; Nimtalk values carry type‑tags.

---

## 6. Why Monitors as Foundation?

1. **Familiar to Smalltalk programmers** (`Object‑‑MonitorState‑‑Process‑‑Condition`).
2. **Re‑entrant locks** are easier for Nimtalk: process can re‑enter a Monitor it already holds.
3. **Condition variables** are exactly the synchronization primitive we need for blocking queues, semaphores, etc.
4. Simple blocking semantics fit the green‑thread scheduler perfectly.

---

## 7. Summary: What This Gives Us

A simple, **debuggable** cooperative‑concurrency system, where all UI‑level constructs are just Nimtalk objects, fully inspectable and changeable at runtime.

The same cooperative scheduler that runs your GUI app can run the debugger that steps through it. The same green threads that handle UI events also run your application logic. All built from Monitors and one‑thread‑at‑a‑time execution.

---

**Plan approved** 2025‑01‑30.  **Current Phase** – Phase 1.