import std/[tables, deques]
import ../core/types

# ============================================================================
# Green Threads - Cooperative Process Scheduler
# Phase 1: Core Scheduler with explicit yields
# ============================================================================

type
  ProcessState* = enum
    psReady       ## Process is ready to run
    psRunning     ## Process is currently executing
    psBlocked     ## Process is blocked on a synchronization primitive
    psSuspended   ## Process is suspended (for debugger)
    psTerminated  ## Process has finished execution

  WaitKind* = enum
    wkNone        ## Not waiting
    wkMonitor     ## Waiting on a Monitor
    wkSemaphore   ## Waiting on a Semaphore
    wkQueueFull   ## Waiting for queue space (producer)
    wkQueueEmpty  ## Waiting for queue item (consumer)
    wkChannel     ## Waiting on a NimChannel for external data

  WaitCondition* = object
    kind*: WaitKind
    target*: pointer  ## The monitor/queue being waited on

  # Forward declaration - Interpreter defined in vm.nim
  # We use a pointer to avoid circular import
  InterpreterRef* = pointer

  Process* = ref object
    pid*: uint64
    name*: string
    interpreter*: InterpreterRef  ## Each process has its own interpreter
    state*: ProcessState
    blockedOn*: WaitCondition     ## Valid when state == psBlocked
    priority*: int                ## Higher = runs first (0 = normal)

  Scheduler* = ref object
    readyQueue*: Deque[Process]
    blockedProcesses*: seq[Process]
    allProcesses*: Table[uint64, Process]
    currentProcess*: Process
    nextPid: uint64
    sharedGlobals*: ref Table[string, NodeValue]
    rootObject*: Instance
    running*: bool
    yieldEveryNSends*: int  ## 0 = yield only on explicit yield/block

# ============================================================================
# Scheduler Creation
# ============================================================================

proc newScheduler*(globals: ref Table[string, NodeValue] = nil,
                   root: Instance = nil): Scheduler =
  ## Create a new scheduler
  result = Scheduler(
    readyQueue: initDeque[Process](),
    blockedProcesses: @[],
    allProcesses: initTable[uint64, Process](),
    currentProcess: nil,
    nextPid: 1,
    sharedGlobals: globals,
    rootObject: root,
    running: false,
    yieldEveryNSends: 0
  )

# ============================================================================
# Process Management
# ============================================================================

proc getNextPid*(sched: Scheduler): uint64 =
  ## Get next available process ID
  result = sched.nextPid
  inc sched.nextPid

proc addProcess*(sched: Scheduler, process: Process) =
  ## Add a process to the scheduler
  sched.allProcesses[process.pid] = process
  if process.state == psReady:
    sched.readyQueue.addLast(process)

proc removeProcess*(sched: Scheduler, pid: uint64) =
  ## Remove a process from the scheduler
  if pid in sched.allProcesses:
    let process = sched.allProcesses[pid]
    process.state = psTerminated
    sched.allProcesses.del(pid)
    # Note: Process will be cleaned from readyQueue naturally when popped

proc getProcess*(sched: Scheduler, pid: uint64): Process =
  ## Get a process by ID
  if pid in sched.allProcesses:
    return sched.allProcesses[pid]
  return nil

proc processCount*(sched: Scheduler): int =
  ## Get total number of processes
  sched.allProcesses.len

proc readyCount*(sched: Scheduler): int =
  ## Get number of ready processes
  sched.readyQueue.len

proc blockedCount*(sched: Scheduler): int =
  ## Get number of blocked processes
  sched.blockedProcesses.len

# ============================================================================
# Process State Transitions
# ============================================================================

proc blockProcess*(sched: Scheduler, process: Process, condition: WaitCondition) =
  ## Block a process on a condition
  process.state = psBlocked
  process.blockedOn = condition
  sched.blockedProcesses.add(process)

proc unblockProcess*(sched: Scheduler, process: Process) =
  ## Unblock a process and add it to ready queue
  if process.state != psBlocked:
    return

  process.state = psReady
  process.blockedOn = WaitCondition(kind: wkNone)

  # Remove from blocked list
  var idx = -1
  for i, p in sched.blockedProcesses:
    if p.pid == process.pid:
      idx = i
      break
  if idx >= 0:
    sched.blockedProcesses.delete(idx)

  # Add to ready queue
  sched.readyQueue.addLast(process)

proc suspendProcess*(sched: Scheduler, process: Process) =
  ## Suspend a process (for debugger)
  if process.state == psReady or process.state == psRunning:
    process.state = psSuspended

proc resumeProcess*(sched: Scheduler, process: Process) =
  ## Resume a suspended process
  if process.state == psSuspended:
    process.state = psReady
    sched.readyQueue.addLast(process)

proc terminateProcess*(sched: Scheduler, process: Process) =
  ## Terminate a process
  process.state = psTerminated
  # Remove from blocked list if blocked
  var idx = -1
  for i, p in sched.blockedProcesses:
    if p.pid == process.pid:
      idx = i
      break
  if idx >= 0:
    sched.blockedProcesses.delete(idx)

# ============================================================================
# Scheduling
# ============================================================================

proc yieldCurrentProcess*(sched: Scheduler) =
  ## Yield the current process - put it back in ready queue
  if sched.currentProcess != nil and sched.currentProcess.state == psRunning:
    sched.currentProcess.state = psReady
    sched.readyQueue.addLast(sched.currentProcess)

proc selectNextProcess*(sched: Scheduler): Process =
  ## Select the next process to run (round-robin for now)
  ## Returns nil if no process is ready
  if sched.readyQueue.len == 0:
    return nil

  # Simple round-robin: take from front
  result = sched.readyQueue.popFirst()
  result.state = psRunning
  sched.currentProcess = result

proc hasReadyProcesses*(sched: Scheduler): bool =
  ## Check if there are any ready processes
  sched.readyQueue.len > 0

proc isRunning*(sched: Scheduler): bool =
  ## Check if scheduler is running
  sched.running

# ============================================================================
# Main Scheduler Loop (single step)
# ============================================================================

proc runOneSlice*(sched: Scheduler): bool =
  ## Run one process for one time slice
  ## Returns true if a process was run, false if no ready processes

  if sched.readyQueue.len == 0:
    sched.currentProcess = nil
    return false

  # Select next process
  let process = sched.selectNextProcess()
  if process == nil:
    return false

  # The actual execution happens in the interpreter
  # This proc just manages the scheduling
  # The caller (evaluator) will:
  # 1. Switch to this process's interpreter
  # 2. Run one message send (or more if yieldEveryNSends > 0)
  # 3. Call yieldCurrentProcess or blockProcess as needed

  return true

proc start*(sched: Scheduler) =
  ## Start the scheduler
  sched.running = true

proc stop*(sched: Scheduler) =
  ## Stop the scheduler
  sched.running = false

# ============================================================================
# Process Creation Helper
# ============================================================================

proc newProcess*(sched: Scheduler, name: string = ""): Process =
  ## Create a new process (interpreter must be set separately)
  let pid = sched.getNextPid()
  result = Process(
    pid: pid,
    name: if name.len > 0: name else: "Process-" & $pid,
    interpreter: nil,
    state: psReady,
    blockedOn: WaitCondition(kind: wkNone),
    priority: 0
  )

# ============================================================================
# Debug/Inspection
# ============================================================================

proc listProcesses*(sched: Scheduler): seq[tuple[pid: uint64, name: string, state: ProcessState]] =
  ## List all processes with their state
  result = @[]
  for pid, process in sched.allProcesses:
    result.add((pid, process.name, process.state))

proc printStatus*(sched: Scheduler): string =
  ## Get scheduler status as string
  result = "Scheduler Status:\n"
  result.add("  Running: " & $sched.running & "\n")
  result.add("  Ready: " & $sched.readyCount & "\n")
  result.add("  Blocked: " & $sched.blockedCount & "\n")
  result.add("  Total: " & $sched.processCount & "\n")
  if sched.currentProcess != nil:
    result.add("  Current: " & sched.currentProcess.name & " (pid " & $sched.currentProcess.pid & ")\n")
  else:
    result.add("  Current: none\n")
