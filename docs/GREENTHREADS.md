# Green Threads and GTK Integration Plan

This document outlines the implementation plan for cooperative green threads (green processes) and their integration with the GTK4 UI toolkit, creating a reactive GUI environment where all UI code is written in Nimtalk.

**See also**:
- [Concurrency Design](CONCURRENCY.md) – background and theory.
- [Gtk Intro](GINTRO.md) – notes about the Nim Gtk4 bindings.
- [Green Thread Scheduler Design](./GREENTHREADS‑DETAILS.md) – internal Nim‑side scheduler design.

---

## 1. What we are building

We implement a cooperative user‑space scheduler that lets Nimtalk code run in **green processes**, each having its own interpreter and activation stack, but no separate OS‑thread. The same scheduler will also drive the GTK4 event loop, so that the UI stays responsive while Nimtalk code can do arbitrary work in the background (e.g., file I/O, number crunching, network).

All GTK widgets will be exposed as Nimtalk objects; the application UI can be live‑edited without restarting the process.

---

## 2. Core Design Principles

### 2.1. Green‑process Model (co‑operative)
- **No pre‑emption** – a process runs until it yields.
- **Explicit yield points**:
  1. Explicit `Processor yield.` in Nimtalk.
  2. Implicit yield after each message send (configurable).
  3. Automatic yield when a process blocks (channel empty/full, semaphore wait, sleep).
- **No kernel‑level thread** – one OS thread for all Nimtalk code and GTK main‑loop.
- **Shared‑nothing by default** – processes share the same heap, but only communicate via channels, mailboxes or (thread‑safe) shared data structures.

### 2.2. Scheduler
The scheduler is a plain Nim `seq` of run‑ready processes.
The ready queue is priority‑based; same‑priority processes are served in a round‑robin fashion.

### 2.3. Inter‑process communication
- **Channel** – bounded or unbounded blocking queue (Nim’s `std/channels` with Nimtalk wrappers).
- **Semaphores** for classical synchronisation.
- **Actor‑style mailboxes** for the actor‑model extension (future phase).

### 2.4. Debugging and inspection
A Nimtalk‑language debugger can attach to any process, suspend it, step through its code, and inspect the activation stack. This is possible because each process has a private `interpreter` field; the debugger can temporarily replace it with a “single‑step” interpreter.

---

## 3. Nim‑Side Data Structures

The Nim‑side definitions for a process and the scheduler.

```nim
type
  ProcessState = enum
    psReady
    psRunning
    psBlocked
    psSuspended
    psTerminated

  WaitConditionKind = enum
    wcNone
    wcSemaphore
    wcChannel
    wcTimeout

  WaitCondition = object
    case kind: WaitConditionKind
    of wcNone: discard
    of wcSemaphore: sem: Semaphore
    of wcChannel: chan: NimChannel[NodeValue]    # `NodeValue` = Nimtalk value
    of wcTimeout: deadline: MonoTime

  Process = ref object of RootObj
    state: ProcessState
    pid: uint64              # unique identifier
    name: string
    priority: int
    waitingOn: WaitCondition
    interpreter: Interpreter  # each process gets its own interpreter
    # Scheduler maintains the rest of the state (previous, next pointer, etc.)

  Scheduler = ref object
    readyQueue: seq[Process]
    allProcesses: Table[uint64, Process]
    currentProcess: Process
    nextPid: uint64
```

Every process has its own `Interpreter` instance; there is no sharing of activations, local variables, or local heaps. The Nimtalk side does **not** hold a Nim‑side Process pointer; it holds a lightweight proxy object that can be stored inside a Nimtalk Process object.

---

## 4. Nim‑side Scheduler

The scheduler is a pure‑Nim loop that:

1. Pops the highest‑priority, ready‑to‑run process from the ready queue.
2. Switches the `currentProcess` and its interpreter.
3. Runs the interpreter **for one quantum**, a single Nimtalk message‑send or a defined number of byte‑code instructions (TBD).
4. If the process yields or blocks, puts it back in the ready queue (or the appropriate blocked‑set).
5. When no Nimtalk process is ready, the scheduler invokes `gtk_main_iteration(0)` to handle GTK input and timer events.

Because the same Nim‑thread runs GTK’s event loop, we can schedule a GTK idle‑callback that yields to other Nimtalk processes, making the UI stay alive while Nimtalk code runs.

---

## 5. Yielding and Blocking Points

A Nimtalk process can yield or block in several ways:

| Event                       | Action |
| -------------------------- | ----------------------------------------------- |
| `Processor yield`           | Voluntary yield; the process is requeued at the end of its ready‑queue. |
| Channel send on a full channel | Moved to “blocked” set; woken up when a receive occurs. |
| Receive on an empty channel  | Block until a sender supplies a value.                 |
| Wait on a semaphore with zero count | Block until a `signal` occurs. |
| Wait for a timeout          | Process moves to a timeout‑queue; scheduler will wake it. |

Yielding can be **explicit** via the Nimtalk primitive `Processor yield.` or **implicit** (optionally) after each Nimtalk message‑send.

---

## 6. Communication Primitives

Three kinds of inter‑process communication are planned; for the first implementation, only channels will be supported.

1. **Channels** (preferred)
   - Bounded or unbounded (preferably bounded to back‑pressure over‑producers).
   - Sending to a full channel blocks the sender; receiving from empty blocks the receiver.

2. **Semaphores** (binary, counting)
   - Classical `signal`/`wait`.
   - Mostly for porting code.

3. **Actor‑style mailboxes** (later phase)
   - Each process can optionally hold a mailbox (a `Channel[Message]`) which is the process’s address for actor‑model message‑passing.

A Channel is a Nimtalk object:

```smalltalk
ch := Channel new.
ch send: 42.     "block if full"
value := ch receive.
```

Nimtalk channels wrap Nim's `Channel[NodeValue]`.

---

## 7. Integration with GTK

### 7.1. Gtk main‑loop
GTK’s main loop (`gtk_main()`) is incompatible with a busy‑loop that never returns. The solution is a **g‑main‑context**–aware idle‑callback that runs the Nimtalk scheduler for one quantum, then returns control to GTK.

```nim
# Simplified main loop in Nim
proc gtkTick =
  if gtk_pending():
    discard main_context_iteration(nil, false)
  else:
    let
      p = scheduler.scheduleNext()
      p.runForOneQuantum()
    if noReadyProcess and not gtk_events_pending():
      # no UI events and nothing to run: just block until GTK input
      gtk_main_iteration()

scheduler.gtk_timeout_id = g_timeout_add(20, gtkTick)
```

### 7.2. GTK callbacks
GTK signals (button‑click, mouse‑move) are queued as callbacks in Nimtalk:

```nim
# Connect GTK signal to Nimtalk block
proc onClick(button: ptr GtkButton, userData: NimtalkBlock) =
  let nimtalkCb: NimtalkBlock = cast[ptr Block](userData)
  # Enqueue the Nimtalk block for execution in the proper interpreter.
```

This callback must:
- convert GTK‑side arguments to Nimtalk objects;
- store the Nimtalk block as a GC‑rooted reference;
- schedule the block’s evaluation on the Nimtalk interpreter of its owning process.

### 7.3. Nimtalk‑side GTK objects

```nimtalk
window := GtkWindow new.
button := GtkButton withLabel: 'Click me'.
button onClick: [Transcript show: 'clicked'].
window addChild: button.
```

The Nimtalk object `GtkButton` holds a Nim‑side pointer to the C GTK object. When the Nimtalk object is GC'd, a Nim‑side finalizer is invoked that calls the GTK reference‑count decrement (or marks a "destroy" for the next idle‑callback). This means **we can implement the whole GTK widget tree as Nimtalk objects**, not just opaque FFI handles.

---

## 8. Debugging, Stepping and Inspection

The **debugger** is a Nimtalk program, using the same `Process`, `Scheduler`, and `Interpreter` APIs.

```smalltalk
Process class withDebugger: aDebugger [
    "Suspend this process, set a single‑step flag, and allow the debugger to
    walk the process' interpreter’s stack."
]
```

The debugger can be invoked at a breakpoint, or the debugger‑window can be opened on a particular process. The debugger may be used from within Nimtalk, thus we can inspect and change other processes.

---

## 9. Roadmap

### Phase 1 – Scheduler & basic processes  (current phase)
- [ ] `Process` and `Scheduler` types in Nim.
- [ ] `Channel[T]` with Nim‑side `send`/`receive` primitives.
- [ ] `yield` and `suspend` primitives.
- [ ] Nim‑side scheduler loop with single‑quantum time‑slicing.
- [ ] GTK idle‑callback integration.

### Phase 2 – Basic process‑to‑process messaging
- [ ] Semaphores (counting, binary).
- [ ] `Process spawn:` primitive for creating a new green thread.
- [ ] Nimtalk‑side `Process` class with debug‑inspection methods.

### Phase 3 – UI integration
- [ ] GTK widget objects (Nimtalk classes for Button, Window, TextArea, etc.)
- [ ] Glib main‑loop vs. GTK main‑loop coordination.
- [ ] Automatic memory‑management (GTK widget lifetime = Nimtalk object lifetime).

### Phase 4 – Actor‑model extensions
- [ ] Mailbox processes (actor‑style “receive”).
- [ ] Process‑linking, supervisor trees.
- [ ] Distributed actor discovery.

---

## 10. Open questions / decisions

*Timeout for channel operations*: A `select` with a timeout, or per‑operation timeout (e.g., channel receive with 0.5 s deadline).

*Priority inversions* – priority‑inheritance in the Nim‑side scheduler, or keep it simple (FIFO per priority‑group).

*GTK‑Nimtalk bridge*: Should GTK objects be Nimtalk objects with finalizers, or Nim‑side only? We propose the former: a Nim‑side type that holds a pointer to a Nimtalk proxy.

*Nimtalk‑side scheduler*: Should there be a Nimtalk‑level `Scheduler` class that can be used from Nimtalk? Probably not; scheduling is a low‑level concept.

---

## 11. Implementation Status

**Phase 1** has been designed but not yet implemented. Current Nimtalk does not contain the Process or Scheduler types yet.

**Phase 2** (Actor‑style mailboxes) and **Phase 3** (GTK integration) are blocked on Phase 1.

The first step is to create the `Process`, `Channel` and `Scheduler` Nim types, plus the Nim‑side scheduler loop that also drives the GTK event loop.

---

**Plan approved** 2025‑01‑30. Implementation started 2025‑0‑‑ (still pending).