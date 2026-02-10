import std/[tables, deques, logging]
import ../core/types
import ../core/process
import ../interpreter/objects
import ../interpreter/activation
import ../interpreter/vm  # Stackless VM

# ============================================================================
# Scheduler Integration with Interpreter
# This module connects the green threads scheduler with the Harding interpreter
# ============================================================================

# ProcessProxy type - forward declaration, full definition below
type ProcessProxy = ref object
  process: Process

# Keep ProcessProxy references alive - since nimValue is a raw pointer,
# the GC doesn't know about these references and may reclaim the memory
var processProxies: seq[ProcessProxy] = @[]

# Keep Interpreter references alive - stored as raw pointers in Process objects,
# the GC needs to see actual Nim refs to prevent collection
var interpreterRefs: seq[Interpreter] = @[]

# Forward declarations for functions defined later in this file
proc createProcessClass*(): Class
proc createSchedulerClass*(): Class
proc createMonitorClass*(): Class
proc createSharedQueueClass*(): Class
proc createSemaphoreClass*(): Class
proc initProcessorGlobal*(interp: var Interpreter)

proc newSchedulerContext*(): SchedulerContext =
  ## Create a new scheduler context with a main interpreter
  result = SchedulerContext()

  # Create main interpreter
  var mainInterp = newInterpreter()
  initGlobals(mainInterp)

  # Initialize Processor global (also adds Process and Scheduler classes)
  initProcessorGlobal(mainInterp)

  # Set scheduler context on main interpreter so Processor fork: can access it
  mainInterp.schedulerContextPtr = cast[pointer](result)

  # Create scheduler with shared globals and rootObject
  result.theScheduler = newScheduler(
    globals = mainInterp.globals,
    root = mainInterp.rootObject
  )

  # Create main process (not added to ready queue since it's the host)
  result.mainProcess = result.theScheduler.newProcess("main")
  result.mainProcess.interpreter = cast[InterpreterRef](mainInterp)
  # Keep interpreter reference alive for GC
  interpreterRefs.add(mainInterp)
  # Main process is tracked but not scheduled - it's the host execution context
  result.theScheduler.allProcesses[result.mainProcess.pid] = result.mainProcess

proc getInterpreter*(process: Process): Interpreter =
  ## Get the interpreter for a process
  ## Note: Interpreter is already a ref object, so we just cast back
  cast[Interpreter](process.interpreter)

proc setInterpreter*(process: Process, interp: Interpreter) =
  ## Set the interpreter for a process
  ## Note: Interpreter is a ref object, store it as pointer to avoid circular import
  process.interpreter = cast[InterpreterRef](interp)

# ============================================================================
# Process Forking
# ============================================================================

proc forkProcess*(ctx: SchedulerContext, blockNode: BlockNode,
                  receiver: Instance, name: string = ""): Process =
  ## Create a new green process from a Harding block
  ## The new process will execute the block when scheduled
  let sched = ctx.theScheduler

  # Create new interpreter sharing globals and rootObject
  let newInterp = newInterpreterWithShared(
    sched.sharedGlobals,
    sched.rootObject
  )

  # Set scheduler context on new interpreter
  newInterp.schedulerContextPtr = cast[pointer](ctx)

  # Create the process
  result = sched.newProcess(name)
  result.setInterpreter(newInterp)

  # Keep interpreter reference alive for GC
  interpreterRefs.add(newInterp)

  # Ensure blockNode has initialized capturedEnv
  if not blockNode.capturedEnvInitialized:
    blockNode.capturedEnv = initTable[string, MutableCell]()
    blockNode.capturedEnvInitialized = true

  # Set up initial activation frame for the block
  let activation = newActivation(blockNode, receiver, nil)
  newInterp.activationStack.add(activation)
  newInterp.currentActivation = activation
  newInterp.currentReceiver = receiver

  # Add to scheduler
  sched.addProcess(result)

  debug("Forked new process: ", result.name, " (pid ", result.pid, ")")

# ============================================================================
# Execution Control
# ============================================================================

proc runCurrentProcess*(ctx: SchedulerContext): NodeValue =
  ## Run one evaluation step on the current process
  ## Returns the result of the last evaluated expression
  let sched = ctx.theScheduler
  if sched.currentProcess == nil:
    return nilValue()

  if sched.currentProcess.interpreter == nil:
    debug("Process ", sched.currentProcess.name, " has nil interpreter pointer, terminating")
    sched.terminateProcess(sched.currentProcess)
    return nilValue()

  var interp = cast[Interpreter](sched.currentProcess.interpreter)
  if interp == nil:
    debug("Process ", sched.currentProcess.name, " getInterpreter returned nil, terminating")
    sched.terminateProcess(sched.currentProcess)
    return nilValue()

  let activation = interp.currentActivation

  if activation == nil or activation.currentMethod == nil:
    # Process has finished
    sched.terminateProcess(sched.currentProcess)
    return nilValue()

  # Get next statement to execute
  let body = activation.currentMethod.body
  if activation.pc >= body.len and interp.workQueue.len == 0:
    # Finished all statements and no pending work
    sched.terminateProcess(sched.currentProcess)
    return interp.lastResult

  # Check if we have pending work (resuming from yield)
  # If work queue has frames, continue from there without advancing PC
  let stmt = if interp.workQueue.len > 0:
               # Resuming - work queue has pending frames
               nil
             else:
               # Get next statement and advance PC
               let s = body[activation.pc]
               inc activation.pc
               s

  let (evalResult, status) = interp.evalForProcess(stmt)
  result = evalResult
  interp.lastResult = result

  # Check if process was blocked by a primitive (before status handling)
  # If so, decrement PC so the statement will be re-executed when unblocked
  let wasBlocked = sched.currentProcess.state == psBlocked
  if wasBlocked:
    dec activation.pc

  # Handle VM status
  case status
  of vmYielded:
    # Process yielded - put back in ready queue (unless it was blocked by a primitive)
    # The work queue preserves state, so we can resume later
    debug("Process ", sched.currentProcess.name, " yielded")
    interp.shouldYield = false
    # Only yield if not already blocked (primitives like Semaphore wait block directly)
    if not wasBlocked:
      sched.yieldCurrentProcess()
    return nilValue()
  of vmError:
    # Process encountered an error - terminate it
    debug("Process ", sched.currentProcess.name, " error")
    sched.terminateProcess(sched.currentProcess)
    return nilValue()
  of vmCompleted:
    # Normal completion - continue to next statement
    discard
  of vmRunning:
    # Should not happen after runASTInterpreter returns
    discard

  # If process was blocked, return now (don't check for termination)
  if wasBlocked:
    return nilValue()

  # Check if block finished
  if activation.pc >= body.len:
    sched.terminateProcess(sched.currentProcess)

proc runOneSlice*(ctx: SchedulerContext): bool =
  ## Run one complete time slice (one statement from one process)
  ## Returns true if something was executed, false if no ready processes
  let sched = ctx.theScheduler

  if not sched.hasReadyProcesses():
    return false

  # Select next process
  let process = sched.selectNextProcess()
  if process == nil:
    return false

  # Run one step
  discard ctx.runCurrentProcess()

  # If process is still running (not terminated/blocked), yield it
  if process.state == psRunning:
    sched.yieldCurrentProcess()

  return true

proc runUntilIdle*(ctx: SchedulerContext, maxSteps: int = 10000): int =
  ## Run processes until none are ready or maxSteps reached
  ## Returns number of steps executed
  result = 0
  while result < maxSteps and ctx.runOneSlice():
    inc result

proc runToCompletion*(ctx: SchedulerContext, maxSteps: int = 100000): int =
  ## Run all processes until all are terminated or maxSteps reached
  ## Returns number of steps executed
  result = 0
  let sched = ctx.theScheduler
  var idleCount = 0
  while result < maxSteps:
    if ctx.runOneSlice():
      idleCount = 0  # Made progress, reset idle counter
      inc result
    else:
      # No ready processes
      if sched.blockedCount == 0:
        break  # All done
      # Some are blocked - check if main process can run
      # The main process might need to execute to unblock others
      if sched.currentProcess != nil and sched.currentProcess.state == psRunning:
        # Main process is still running but not in ready queue
        # Let it continue execution (it might unblock blocked processes)
        discard ctx.runCurrentProcess()
        inc result
      else:
        # No progress possible, increment idle count
        inc idleCount
        if idleCount > 10:  # Give up after several idle iterations
          break

# ============================================================================
# Harding-side Processor Object
# ============================================================================

# Processor yield implementation
proc processorYieldImpl(interp: var Interpreter, self: Instance,
                        args: seq[NodeValue]): NodeValue =
  ## Processor yield - sets flag for context switch after current message
  ## The flag is checked after block invocation to propagate yield upward
  debug("Processor yield called - setting shouldYield flag")
  interp.shouldYield = true
  return nilValue()

# Forward declarations for proxy creation functions
proc createProcessProxy*(process: Process): NodeValue
proc createSchedulerProxy*(ctx: SchedulerContext): NodeValue

# Processor fork: implementation
proc processorForkImpl(interp: var Interpreter, self: Instance,
                       args: seq[NodeValue]): NodeValue =
  ## Processor fork: aBlock - creates a new process to run aBlock
  if args.len < 1 or args[0].kind != vkBlock:
    return nilValue()

  let ctx = cast[SchedulerContext](interp.schedulerContextPtr)
  if ctx == nil:
    debug("Processor fork: called but no scheduler context")
    return nilValue()

  let blockNode = args[0].blockVal
  debug("Processor fork: called with block")

  # Create a new process with an objectClass instance as receiver
  let newProc = ctx.forkProcess(blockNode, newInstance(objectClass), "")
  return createProcessProxy(newProc)

# Processor current implementation
proc processorCurrentImpl(interp: var Interpreter, self: Instance,
                          args: seq[NodeValue]): NodeValue =
  ## Processor current - returns the current process (placeholder)
  debug("Processor current called")
  return nilValue()

var processorClass*: Class = nil

proc createProcessorClass*(): Class =
  ## Create the Processor class with yield, fork:, current methods
  if processorClass != nil:
    return processorClass

  # Ensure objectClass is initialized
  discard initCoreClasses()

  processorClass = newClass(superclasses = @[objectClass], name = "Processor")
  processorClass.tags = @["Processor", "Scheduler"]

  # Add yield method
  let yieldMethod = createCoreMethod("yield")
  yieldMethod.nativeImpl = cast[pointer](processorYieldImpl)
  yieldMethod.hasInterpreterParam = true
  addMethodToClass(processorClass, "yield", yieldMethod)

  # Add fork: method
  let forkMethod = createCoreMethod("fork:")
  forkMethod.nativeImpl = cast[pointer](processorForkImpl)
  forkMethod.hasInterpreterParam = true
  addMethodToClass(processorClass, "fork:", forkMethod)

  # Add current method
  let currentMethod = createCoreMethod("current")
  currentMethod.nativeImpl = cast[pointer](processorCurrentImpl)
  currentMethod.hasInterpreterParam = true
  addMethodToClass(processorClass, "current", currentMethod)

  return processorClass

proc initProcessorGlobal*(interp: var Interpreter) =
  ## Initialize the Processor global in the interpreter
  ## Processor is a singleton instance of ProcessorClass
  let cls = createProcessorClass()
  let processorInstance = newInstance(cls)
  interp.globals[]["Processor"] = processorInstance.toValue()

  # Also add Process and Scheduler classes
  let processCls = createProcessClass()
  if processCls != nil:
    interp.globals[]["Process"] = processCls.toValue()

  let schedulerCls = createSchedulerClass()
  if schedulerCls != nil:
    interp.globals[]["Scheduler"] = schedulerCls.toValue()

  # Add synchronization primitives
  let monitorCls = createMonitorClass()
  if monitorCls != nil:
    interp.globals[]["Monitor"] = monitorCls.toValue()

  let sharedQueueCls = createSharedQueueClass()
  if sharedQueueCls != nil:
    interp.globals[]["SharedQueue"] = sharedQueueCls.toValue()

  let semaphoreCls = createSemaphoreClass()
  if semaphoreCls != nil:
    interp.globals[]["Semaphore"] = semaphoreCls.toValue()

  # Protect process-related globals
  protectGlobal("Processor")
  protectGlobal("Process")
  protectGlobal("Scheduler")
  protectGlobal("Monitor")
  protectGlobal("SharedQueue")
  protectGlobal("Semaphore")

# ============================================================================
# Process Proxy and Class
# ============================================================================

proc createProcessProxy*(process: Process): NodeValue =
  ## Create a proxy object that wraps a Nim Process
  let proxy = ProcessProxy(process: process)
  processProxies.add(proxy)  # Keep reference alive for GC
  let obj = Instance(kind: ikObject, class: processClass, slots: @[])
  obj.isNimProxy = true
  obj.nimValue = cast[pointer](proxy)
  return obj.toValue()

proc asProcessProxy*(inst: Instance): ProcessProxy =
  ## Extract ProcessProxy from a Harding instance
  if inst.isNimProxy and nimValueIsSet(inst.nimValue):
    return cast[ProcessProxy](inst.nimValue)
  return nil

# Process native method implementations

proc processPidImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Get process ID
  let proxy = self.asProcessProxy()
  if proxy != nil and proxy.process != nil:
    return toValue(int(proxy.process.pid))
  return nilValue()

proc processNameImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Get process name
  let proxy = self.asProcessProxy()
  if proxy != nil and proxy.process != nil:
    return toValue(proxy.process.name)
  return nilValue()

proc processStateImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Get process state
  let proxy = self.asProcessProxy()
  if proxy != nil and proxy.process != nil:
    let stateStr = case proxy.process.state
                     of psReady: "ready"
                     of psRunning: "running"
                     of psBlocked: "blocked"
                     of psSuspended: "suspended"
                     of psTerminated: "terminated"
    return toValue(stateStr)
  return nilValue()

proc processYieldImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Yield the current process
  let ctx = cast[SchedulerContext](interp.schedulerContextPtr)
  if ctx != nil and ctx.theScheduler.currentProcess != nil:
    let proxy = self.asProcessProxy()
    if proxy != nil and proxy.process != nil and proxy.process == ctx.theScheduler.currentProcess:
      ctx.theScheduler.yieldCurrentProcess()
  return nilValue()

proc processSuspendImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Suspend this process
  let ctx = cast[SchedulerContext](interp.schedulerContextPtr)
  if ctx != nil:
    let proxy = self.asProcessProxy()
    if proxy != nil and proxy.process != nil:
      ctx.theScheduler.suspendProcess(proxy.process)
  return nilValue()

proc processResumeImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Resume this process
  let ctx = cast[SchedulerContext](interp.schedulerContextPtr)
  if ctx != nil:
    let proxy = self.asProcessProxy()
    if proxy != nil and proxy.process != nil:
      ctx.theScheduler.resumeProcess(proxy.process)
  return nilValue()

proc processTerminateImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Terminate this process
  let ctx = cast[SchedulerContext](interp.schedulerContextPtr)
  if ctx != nil:
    let proxy = self.asProcessProxy()
    if proxy != nil and proxy.process != nil:
      ctx.theScheduler.terminateProcess(proxy.process)
  return nilValue()

proc createProcessClass*(): Class =
  ## Create the Process class with native methods
  if processClass != nil:
    return processClass

  # Ensure objectClass is initialized
  discard initCoreClasses()

  processClass = newClass(superclasses = @[objectClass], name = "Process")
  processClass.tags = @["Process", "Proxy"]
  processClass.isNimProxy = true
  processClass.hardingType = "Process"

  # Add pid method
  let pidMethod = createCoreMethod("pid")
  pidMethod.nativeImpl = cast[pointer](processPidImpl)
  pidMethod.hasInterpreterParam = true
  addMethodToClass(processClass, "pid", pidMethod)

  # Add name method
  let nameMethod = createCoreMethod("name")
  nameMethod.nativeImpl = cast[pointer](processNameImpl)
  nameMethod.hasInterpreterParam = true
  addMethodToClass(processClass, "name", nameMethod)

  # Add state method
  let stateMethod = createCoreMethod("state")
  stateMethod.nativeImpl = cast[pointer](processStateImpl)
  stateMethod.hasInterpreterParam = true
  addMethodToClass(processClass, "state", stateMethod)

  # Add yield method
  let yieldMethod = createCoreMethod("yield")
  yieldMethod.nativeImpl = cast[pointer](processYieldImpl)
  yieldMethod.hasInterpreterParam = true
  addMethodToClass(processClass, "yield", yieldMethod)

  # Add suspend method
  let suspendMethod = createCoreMethod("suspend")
  suspendMethod.nativeImpl = cast[pointer](processSuspendImpl)
  suspendMethod.hasInterpreterParam = true
  addMethodToClass(processClass, "suspend", suspendMethod)

  # Add resume method
  let resumeMethod = createCoreMethod("resume")
  resumeMethod.nativeImpl = cast[pointer](processResumeImpl)
  resumeMethod.hasInterpreterParam = true
  addMethodToClass(processClass, "resume", resumeMethod)

  # Add terminate method
  let terminateMethod = createCoreMethod("terminate")
  terminateMethod.nativeImpl = cast[pointer](processTerminateImpl)
  terminateMethod.hasInterpreterParam = true
  addMethodToClass(processClass, "terminate", terminateMethod)

  return processClass

# ============================================================================
# Scheduler Proxy and Class
# ============================================================================

type
  SchedulerProxy* = ref object
    theScheduler*: Scheduler  # 'theScheduler' to avoid naming conflict
    context*: SchedulerContext

proc createSchedulerProxy*(ctx: SchedulerContext): NodeValue =
  ## Create a proxy object that wraps a Nim Scheduler
  let proxy = SchedulerProxy(theScheduler: ctx.theScheduler, context: ctx)
  let obj = Instance(kind: ikObject, class: schedulerClass, slots: @[])
  obj.isNimProxy = true
  obj.nimValue = cast[pointer](proxy)
  return obj.toValue()

proc asSchedulerProxy*(inst: Instance): SchedulerProxy =
  ## Extract SchedulerProxy from a Harding instance
  if inst.isNimProxy and nimValueIsSet(inst.nimValue):
    return cast[SchedulerProxy](inst.nimValue)
  return nil

# Scheduler native method implementations

proc schedulerProcessCountImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Get total number of processes
  let ctx = cast[SchedulerContext](interp.schedulerContextPtr)
  if ctx != nil:
    return toValue(ctx.theScheduler.processCount())
  return nilValue()

proc schedulerReadyCountImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Get number of ready processes
  let ctx = cast[SchedulerContext](interp.schedulerContextPtr)
  if ctx != nil:
    return toValue(ctx.theScheduler.readyCount())
  return nilValue()

proc schedulerBlockedCountImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Get number of blocked processes
  let ctx = cast[SchedulerContext](interp.schedulerContextPtr)
  if ctx != nil:
    return toValue(ctx.theScheduler.blockedCount())
  return nilValue()

proc schedulerCurrentProcessImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Get the current process
  let ctx = cast[SchedulerContext](interp.schedulerContextPtr)
  if ctx != nil and ctx.theScheduler.currentProcess != nil:
    return createProcessProxy(ctx.theScheduler.currentProcess)
  return nilValue()

proc schedulerForkNameImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Fork a new process with a block and optional name
  let ctx = cast[SchedulerContext](interp.schedulerContextPtr)
  if ctx == nil:
    return nilValue()

  if args.len < 1 or args[0].kind != vkBlock:
    return nilValue()

  let blockNode = args[0].blockVal
  let name = if args.len >= 2 and args[1].kind == vkString:
               args[1].strVal
             else:
               ""

  # Create a new process
  let newProc = ctx.forkProcess(blockNode, newInstance(objectClass), name)
  return createProcessProxy(newProc)

proc schedulerStepImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Run one time slice
  let ctx = cast[SchedulerContext](interp.schedulerContextPtr)
  if ctx != nil:
    discard ctx.runOneSlice()
  return nilValue()

proc schedulerRunToCompletionImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Run all processes to completion
  let ctx = cast[SchedulerContext](interp.schedulerContextPtr)
  if ctx != nil:
    let maxSteps = if args.len > 0 and args[0].kind == vkInt:
                     args[0].intVal
                   else:
                     100000
    let stepsExecuted = ctx.runToCompletion(maxSteps)
    return toValue(stepsExecuted)
  return nilValue()

proc createSchedulerClass*(): Class =
  ## Create the Scheduler class with native methods
  if schedulerClass != nil:
    return schedulerClass

  # Ensure objectClass is initialized
  discard initCoreClasses()

  schedulerClass = newClass(superclasses = @[objectClass], name = "Scheduler")
  schedulerClass.tags = @["Scheduler", "Proxy"]
  schedulerClass.isNimProxy = true
  schedulerClass.hardingType = "Scheduler"

  # Add processCount method
  let processCountMethod = createCoreMethod("processCount")
  processCountMethod.nativeImpl = cast[pointer](schedulerProcessCountImpl)
  processCountMethod.hasInterpreterParam = true
  addMethodToClass(schedulerClass, "processCount", processCountMethod, isClassMethod = true)

  # Add readyCount method
  let readyCountMethod = createCoreMethod("readyCount")
  readyCountMethod.nativeImpl = cast[pointer](schedulerReadyCountImpl)
  readyCountMethod.hasInterpreterParam = true
  addMethodToClass(schedulerClass, "readyCount", readyCountMethod, isClassMethod = true)

  # Add blockedCount method
  let blockedCountMethod = createCoreMethod("blockedCount")
  blockedCountMethod.nativeImpl = cast[pointer](schedulerBlockedCountImpl)
  blockedCountMethod.hasInterpreterParam = true
  addMethodToClass(schedulerClass, "blockedCount", blockedCountMethod, isClassMethod = true)

  # Add currentProcess method
  let currentProcessMethod = createCoreMethod("currentProcess")
  currentProcessMethod.nativeImpl = cast[pointer](schedulerCurrentProcessImpl)
  currentProcessMethod.hasInterpreterParam = true
  addMethodToClass(schedulerClass, "currentProcess", currentProcessMethod, isClassMethod = true)

  # Add fork:name: method
  let forkNameMethod = createCoreMethod("fork:name:")
  forkNameMethod.nativeImpl = cast[pointer](schedulerForkNameImpl)
  forkNameMethod.hasInterpreterParam = true
  addMethodToClass(schedulerClass, "fork:name:", forkNameMethod, isClassMethod = true)

  # Add step method
  let stepMethod = createCoreMethod("step")
  stepMethod.nativeImpl = cast[pointer](schedulerStepImpl)
  stepMethod.hasInterpreterParam = true
  addMethodToClass(schedulerClass, "step", stepMethod, isClassMethod = true)

  # Add runToCompletion: method
  let runToCompletionMethod = createCoreMethod("runToCompletion:")
  runToCompletionMethod.nativeImpl = cast[pointer](schedulerRunToCompletionImpl)
  runToCompletionMethod.hasInterpreterParam = true
  addMethodToClass(schedulerClass, "runToCompletion:", runToCompletionMethod, isClassMethod = true)

  return schedulerClass

# ============================================================================
# Monitor - Mutual Exclusion with Condition Variables
# ============================================================================

type
  Monitor* = ref object
    owner*: Process        ## Process currently holding the lock
    count*: int            ## Reentrancy count (for recursive locking)
    waitingQueue*: Deque[Process]  ## Queue of processes waiting for lock

  MonitorProxy* = ref object
    monitor*: Monitor

var monitorClass*: Class = nil

# Keep MonitorProxy references alive - since nimValue is a raw pointer,
# the GC doesn't know about these references and may reclaim the memory
var monitorProxies: seq[MonitorProxy] = @[]

proc newMonitor*(): Monitor =
  ## Create a new monitor (unlocked initially)
  result = Monitor(
    owner: nil,
    count: 0,
    waitingQueue: initDeque[Process]()
  )

proc acquire*(monitor: Monitor, process: Process, sched: Scheduler): bool =
  ## Acquire the monitor lock. Returns true if acquired, false if blocked.
  if monitor.owner == nil:
    # Lock is free, acquire it
    monitor.owner = process
    monitor.count = 1
    return true
  elif monitor.owner.pid == process.pid:
    # Reentrant lock - same process, increment count
    inc monitor.count
    return true
  else:
    # Lock held by another process - block this process
    monitor.waitingQueue.addLast(process)
    sched.blockProcess(process, WaitCondition(kind: wkMonitor, target: cast[pointer](monitor)))
    return false

proc release*(monitor: Monitor, process: Process, sched: Scheduler): bool =
  ## Release the monitor lock. Returns true if released successfully.
  if monitor.owner == nil or monitor.owner.pid != process.pid:
    # Not the owner - can't release
    return false

  dec monitor.count
  if monitor.count > 0:
    # Still holding lock (reentrant case)
    return true

  # Fully released, check if anyone is waiting
  monitor.owner = nil
  if monitor.waitingQueue.len > 0:
    # Wake up next waiting process
    let nextProcess = monitor.waitingQueue.popFirst()
    monitor.owner = nextProcess
    monitor.count = 1
    sched.unblockProcess(nextProcess)
  return true

# Monitor proxy creation
proc createMonitorProxy*(monitor: Monitor): NodeValue =
  ## Create a proxy object that wraps a Nim Monitor
  let proxy = MonitorProxy(monitor: monitor)
  monitorProxies.add(proxy)  # Keep reference alive for GC
  let obj = Instance(kind: ikObject, class: monitorClass, slots: @[])
  obj.isNimProxy = true
  obj.nimValue = cast[pointer](proxy)
  return obj.toValue()

proc asMonitorProxy*(inst: Instance): MonitorProxy =
  ## Extract MonitorProxy from a Harding instance
  if inst.isNimProxy and nimValueIsSet(inst.nimValue):
    return cast[MonitorProxy](inst.nimValue)
  return nil

# Native method implementations

proc monitorCriticalImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Monitor critical: aBlock - execute block with mutual exclusion
  ## Uses evalWithVM to run the block in a nested VM session, then releases lock
  if args.len < 1 or args[0].kind != vkBlock:
    return nilValue()

  let proxy = self.asMonitorProxy()
  if proxy == nil or proxy.monitor == nil:
    return nilValue()

  let ctx = cast[SchedulerContext](interp.schedulerContextPtr)
  let blockNode = args[0].blockVal
  var resultValue = nilValue()

  if ctx == nil:
    # No scheduler context - execute block without locking (for tests)
    if blockNode.body.len > 0:
      for stmt in blockNode.body:
        resultValue = interp.evalWithVM(stmt)
    return resultValue

  let sched = ctx.theScheduler
  let currentProc = sched.currentProcess
  if currentProc == nil:
    # No current process - execute block without locking (for tests)
    if blockNode.body.len > 0:
      for stmt in blockNode.body:
        resultValue = interp.evalWithVM(stmt)
    return resultValue

  # Try to acquire lock
  if not proxy.monitor.acquire(currentProc, sched):
    # We were blocked - return nil (will retry when unblocked)
    return nilValue()

  # We have the lock - execute the block using evalWithVM
  # Execute each statement in the block body
  if blockNode.body.len > 0:
    try:
      for stmt in blockNode.body:
        resultValue = interp.evalWithVM(stmt)
    except:
      # Block raised an error - still need to release lock
      discard proxy.monitor.release(currentProc, sched)
      raise

  # Always release the lock (ensure: pattern in Nim)
  discard proxy.monitor.release(currentProc, sched)

  return resultValue

proc monitorAcquireImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Monitor acquire - acquire the lock
  let ctx = cast[SchedulerContext](interp.schedulerContextPtr)
  if ctx == nil:
    return nilValue()

  let proxy = self.asMonitorProxy()
  if proxy == nil or proxy.monitor == nil:
    return nilValue()

  let sched = ctx.theScheduler
  let currentProc = sched.currentProcess
  if currentProc == nil:
    return nilValue()

  if proxy.monitor.acquire(currentProc, sched):
    return trueValue
  # Blocked - set yield flag so interpreter stops execution
  interp.shouldYield = true
  return nilValue()

proc monitorReleaseImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Monitor release - release the lock
  let ctx = cast[SchedulerContext](interp.schedulerContextPtr)
  if ctx == nil:
    return nilValue()

  let proxy = self.asMonitorProxy()
  if proxy == nil or proxy.monitor == nil:
    return nilValue()

  let sched = ctx.theScheduler
  let currentProc = sched.currentProcess
  if currentProc == nil:
    return nilValue()

  if proxy.monitor.release(currentProc, sched):
    return trueValue
  return nilValue()

proc monitorNewImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Monitor new - create a new monitor instance
  let monitor = newMonitor()
  return createMonitorProxy(monitor)

proc createMonitorClass*(): Class =
  ## Create the Monitor class with native methods
  if monitorClass != nil:
    return monitorClass

  discard initCoreClasses()

  monitorClass = newClass(superclasses = @[objectClass], name = "Monitor")
  monitorClass.tags = @["Monitor", "Synchronization"]
  monitorClass.isNimProxy = true
  monitorClass.hardingType = "Monitor"

  # Add new method (class method)
  let newMethod = createCoreMethod("new")
  newMethod.nativeImpl = cast[pointer](monitorNewImpl)
  newMethod.hasInterpreterParam = true
  addMethodToClass(monitorClass, "new", newMethod, isClassMethod = true)

  # Add critical: method
  let criticalMethod = createCoreMethod("critical:")
  criticalMethod.nativeImpl = cast[pointer](monitorCriticalImpl)
  criticalMethod.hasInterpreterParam = true
  addMethodToClass(monitorClass, "critical:", criticalMethod)

  # Add acquire method
  let acquireMethod = createCoreMethod("acquire")
  acquireMethod.nativeImpl = cast[pointer](monitorAcquireImpl)
  acquireMethod.hasInterpreterParam = true
  addMethodToClass(monitorClass, "acquire", acquireMethod)

  # Add release method
  let releaseMethod = createCoreMethod("release")
  releaseMethod.nativeImpl = cast[pointer](monitorReleaseImpl)
  releaseMethod.hasInterpreterParam = true
  addMethodToClass(monitorClass, "release", releaseMethod)

  return monitorClass

# ============================================================================
# SharedQueue - Thread-safe queue with blocking
# ============================================================================

type
  SharedQueue* = ref object
    items*: seq[NodeValue]       ## Queue storage
    maxSize*: int                ## 0 = unlimited, >0 = capacity limit
    waitingWriters*: Deque[Process]  ## Processes blocked on full queue
    waitingReaders*: Deque[Process]  ## Processes blocked on empty queue

  SharedQueueProxy* = ref object
    queue*: SharedQueue

var sharedQueueClass*: Class = nil
var sharedQueueProxies: seq[SharedQueueProxy] = @[]

proc newSharedQueue*(maxSize: int = 0): SharedQueue =
  ## Create a new shared queue
  result = SharedQueue(
    items: @[],
    maxSize: maxSize,
    waitingWriters: initDeque[Process](),
    waitingReaders: initDeque[Process]()
  )

proc nextPut*(queue: SharedQueue, item: NodeValue, process: Process, sched: Scheduler): bool =
  ## Add item to queue. Returns true if added, false if blocked.
  if queue.maxSize > 0 and queue.items.len >= queue.maxSize:
    # Queue is full - block the writer
    queue.waitingWriters.addLast(process)
    sched.blockProcess(process, WaitCondition(kind: wkQueueFull, target: cast[pointer](queue)))
    return false
  # Add item
  queue.items.add(item)
  # Wake up a waiting reader if any
  if queue.waitingReaders.len > 0:
    let reader = queue.waitingReaders.popFirst()
    sched.unblockProcess(reader)
  return true

proc next*(queue: SharedQueue, process: Process, sched: Scheduler): tuple[item: NodeValue, gotItem: bool] =
  ## Remove and return item from queue. Blocks if empty.
  if queue.items.len == 0:
    # Queue is empty - block the reader
    queue.waitingReaders.addLast(process)
    sched.blockProcess(process, WaitCondition(kind: wkQueueEmpty, target: cast[pointer](queue)))
    return (nilValue(), false)
  # Remove first item
  result.item = queue.items[0]
  result.gotItem = true
  queue.items.delete(0)
  # Wake up a waiting writer if any
  if queue.waitingWriters.len > 0:
    let writer = queue.waitingWriters.popFirst()
    sched.unblockProcess(writer)

proc size*(queue: SharedQueue): int =
  queue.items.len

proc isEmpty*(queue: SharedQueue): bool =
  queue.items.len == 0

# SharedQueue proxy creation
proc createSharedQueueProxy*(queue: SharedQueue): NodeValue =
  let proxy = SharedQueueProxy(queue: queue)
  sharedQueueProxies.add(proxy)
  let obj = Instance(kind: ikObject, class: sharedQueueClass, slots: @[])
  obj.isNimProxy = true
  obj.nimValue = cast[pointer](proxy)
  return obj.toValue()

proc asSharedQueueProxy*(inst: Instance): SharedQueueProxy =
  if inst.isNimProxy and nimValueIsSet(inst.nimValue):
    return cast[SharedQueueProxy](inst.nimValue)
  return nil

# Native method implementations

proc sharedQueueNewImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## SharedQueue new - create unbounded queue
  ## SharedQueue new: maxSize - create bounded queue
  let maxSize = if args.len > 0 and args[0].kind == vkInt: args[0].intVal else: 0
  let queue = newSharedQueue(maxSize)
  return createSharedQueueProxy(queue)

proc sharedQueueNextPutImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## SharedQueue nextPut: item - add item to queue
  if args.len < 1:
    return nilValue()

  let proxy = self.asSharedQueueProxy()
  if proxy == nil or proxy.queue == nil:
    return nilValue()

  let ctx = cast[SchedulerContext](interp.schedulerContextPtr)
  if ctx == nil:
    # No scheduler context - just add directly (non-blocking mode for tests)
    proxy.queue.items.add(args[0])
    return args[0]

  let sched = ctx.theScheduler
  let currentProc = sched.currentProcess
  if currentProc == nil:
    # No current process - add directly
    proxy.queue.items.add(args[0])
    return args[0]

  if proxy.queue.nextPut(args[0], currentProc, sched):
    return args[0]
  # Blocked - set yield flag so interpreter stops execution
  interp.shouldYield = true
  return nilValue()

proc sharedQueueNextImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## SharedQueue next - remove and return item (blocks if empty)
  let proxy = self.asSharedQueueProxy()
  if proxy == nil or proxy.queue == nil:
    return nilValue()

  let ctx = cast[SchedulerContext](interp.schedulerContextPtr)
  if ctx == nil:
    # No scheduler context - just get directly (non-blocking mode for tests)
    if proxy.queue.items.len == 0:
      return nilValue()
    let item = proxy.queue.items[0]
    proxy.queue.items.delete(0)
    return item

  let sched = ctx.theScheduler
  let currentProc = sched.currentProcess
  if currentProc == nil:
    # No current process - get directly
    if proxy.queue.items.len == 0:
      return nilValue()
    let item = proxy.queue.items[0]
    proxy.queue.items.delete(0)
    return item

  let (item, gotItem) = proxy.queue.next(currentProc, sched)
  if gotItem:
    return item
  # Blocked - set yield flag so interpreter stops execution
  interp.shouldYield = true
  return nilValue()

proc sharedQueueSizeImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## SharedQueue size
  let proxy = self.asSharedQueueProxy()
  if proxy == nil or proxy.queue == nil:
    return toValue(0)
  return toValue(proxy.queue.size())

proc sharedQueueIsEmptyImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## SharedQueue isEmpty
  let proxy = self.asSharedQueueProxy()
  if proxy == nil or proxy.queue == nil:
    return trueValue
  return toValue(proxy.queue.isEmpty())

proc createSharedQueueClass*(): Class =
  ## Create the SharedQueue class with native methods
  if sharedQueueClass != nil:
    return sharedQueueClass

  discard initCoreClasses()

  sharedQueueClass = newClass(superclasses = @[objectClass], name = "SharedQueue")
  sharedQueueClass.tags = @["SharedQueue", "Synchronization"]
  sharedQueueClass.isNimProxy = true
  sharedQueueClass.hardingType = "SharedQueue"

  # Add new method (class method) - unbounded
  let newMethod = createCoreMethod("new")
  newMethod.nativeImpl = cast[pointer](sharedQueueNewImpl)
  newMethod.hasInterpreterParam = true
  addMethodToClass(sharedQueueClass, "new", newMethod, isClassMethod = true)

  # Add new: method (class method) - bounded
  let newBoundedMethod = createCoreMethod("new:")
  newBoundedMethod.nativeImpl = cast[pointer](sharedQueueNewImpl)
  newBoundedMethod.hasInterpreterParam = true
  addMethodToClass(sharedQueueClass, "new:", newBoundedMethod, isClassMethod = true)

  # Add nextPut: method
  let nextPutMethod = createCoreMethod("nextPut:")
  nextPutMethod.nativeImpl = cast[pointer](sharedQueueNextPutImpl)
  nextPutMethod.hasInterpreterParam = true
  addMethodToClass(sharedQueueClass, "nextPut:", nextPutMethod)

  # Add next method
  let nextMethod = createCoreMethod("next")
  nextMethod.nativeImpl = cast[pointer](sharedQueueNextImpl)
  nextMethod.hasInterpreterParam = true
  addMethodToClass(sharedQueueClass, "next", nextMethod)

  # Add size method
  let sizeMethod = createCoreMethod("size")
  sizeMethod.nativeImpl = cast[pointer](sharedQueueSizeImpl)
  sizeMethod.hasInterpreterParam = true
  addMethodToClass(sharedQueueClass, "size", sizeMethod)

  # Add isEmpty method
  let isEmptyMethod = createCoreMethod("isEmpty")
  isEmptyMethod.nativeImpl = cast[pointer](sharedQueueIsEmptyImpl)
  isEmptyMethod.hasInterpreterParam = true
  addMethodToClass(sharedQueueClass, "isEmpty", isEmptyMethod)

  return sharedQueueClass

# ============================================================================
# Semaphore - Counting semaphore for resource control
# ============================================================================

type
  Semaphore* = ref object
    count*: int                  ## Current count
    waitingQueue*: Deque[Process]  ## Processes waiting for signal

  SemaphoreProxy* = ref object
    semaphore*: Semaphore

var semaphoreClass*: Class = nil
var semaphoreProxies: seq[SemaphoreProxy] = @[]

proc newSemaphore*(initialCount: int = 0): Semaphore =
  ## Create a new semaphore with given initial count
  result = Semaphore(
    count: initialCount,
    waitingQueue: initDeque[Process]()
  )

proc wait*(sem: Semaphore, process: Process, sched: Scheduler): bool =
  ## Wait on semaphore (decrement). Returns true if acquired, false if blocked.
  if sem.count > 0:
    dec sem.count
    return true
  # Need to block
  sem.waitingQueue.addLast(process)
  sched.blockProcess(process, WaitCondition(kind: wkSemaphore, target: cast[pointer](sem)))
  return false

proc signal*(sem: Semaphore, sched: Scheduler) =
  ## Signal semaphore (increment). Unblocks waiting process if any.
  if sem.waitingQueue.len > 0:
    # Unblock a waiting process
    let process = sem.waitingQueue.popFirst()
    sched.unblockProcess(process)
  else:
    # No waiters, just increment count
    inc sem.count

# Semaphore proxy creation
proc createSemaphoreProxy*(sem: Semaphore): NodeValue =
  let proxy = SemaphoreProxy(semaphore: sem)
  semaphoreProxies.add(proxy)
  let obj = Instance(kind: ikObject, class: semaphoreClass, slots: @[])
  obj.isNimProxy = true
  obj.nimValue = cast[pointer](proxy)
  return obj.toValue()

proc asSemaphoreProxy*(inst: Instance): SemaphoreProxy =
  if inst.isNimProxy and nimValueIsSet(inst.nimValue):
    return cast[SemaphoreProxy](inst.nimValue)
  return nil

# Native method implementations

proc semaphoreNewImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Semaphore new - create semaphore with count 0
  ## Semaphore new: n - create semaphore with count n
  let initialCount = if args.len > 0 and args[0].kind == vkInt: args[0].intVal else: 0
  let sem = newSemaphore(initialCount)
  return createSemaphoreProxy(sem)

proc semaphoreForMutualExclusionImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Semaphore forMutualExclusion - create binary semaphore (count 1)
  let sem = newSemaphore(1)
  return createSemaphoreProxy(sem)

proc semaphoreWaitImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Semaphore wait - decrement, block if would go negative
  let proxy = self.asSemaphoreProxy()
  if proxy == nil or proxy.semaphore == nil:
    return nilValue()

  let ctx = cast[SchedulerContext](interp.schedulerContextPtr)
  if ctx == nil:
    # No scheduler context - just decrement count if > 0 (for tests)
    if proxy.semaphore.count > 0:
      dec proxy.semaphore.count
      return trueValue
    return nilValue()

  let sched = ctx.theScheduler
  let currentProc = sched.currentProcess
  if currentProc == nil:
    # No current process - just decrement count if > 0 (for tests)
    if proxy.semaphore.count > 0:
      dec proxy.semaphore.count
      return trueValue
    return nilValue()

  if proxy.semaphore.wait(currentProc, sched):
    return trueValue  # Acquired immediately
  # Blocked - set yield flag so interpreter stops execution
  interp.shouldYield = true
  return nilValue()

proc semaphoreSignalImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Semaphore signal - increment, unblock waiter if any
  let proxy = self.asSemaphoreProxy()
  if proxy == nil or proxy.semaphore == nil:
    return nilValue()

  let ctx = cast[SchedulerContext](interp.schedulerContextPtr)
  if ctx == nil:
    # No scheduler context - just increment count (for tests)
    inc proxy.semaphore.count
    return trueValue

  let sched = ctx.theScheduler
  proxy.semaphore.signal(sched)
  return trueValue

proc semaphoreCountImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Semaphore count - return current count
  let proxy = self.asSemaphoreProxy()
  if proxy == nil or proxy.semaphore == nil:
    return toValue(0)
  return toValue(proxy.semaphore.count)

proc createSemaphoreClass*(): Class =
  ## Create the Semaphore class with native methods
  if semaphoreClass != nil:
    return semaphoreClass

  discard initCoreClasses()

  semaphoreClass = newClass(superclasses = @[objectClass], name = "Semaphore")
  semaphoreClass.tags = @["Semaphore", "Synchronization"]
  semaphoreClass.isNimProxy = true
  semaphoreClass.hardingType = "Semaphore"

  # Add new method (class method) - count 0
  let newMethod = createCoreMethod("new")
  newMethod.nativeImpl = cast[pointer](semaphoreNewImpl)
  newMethod.hasInterpreterParam = true
  addMethodToClass(semaphoreClass, "new", newMethod, isClassMethod = true)

  # Add new: method (class method) - specific count
  let newCountMethod = createCoreMethod("new:")
  newCountMethod.nativeImpl = cast[pointer](semaphoreNewImpl)
  newCountMethod.hasInterpreterParam = true
  addMethodToClass(semaphoreClass, "new:", newCountMethod, isClassMethod = true)

  # Add forMutualExclusion method (class method) - binary semaphore
  let forMutualExclusionMethod = createCoreMethod("forMutualExclusion")
  forMutualExclusionMethod.nativeImpl = cast[pointer](semaphoreForMutualExclusionImpl)
  forMutualExclusionMethod.hasInterpreterParam = true
  addMethodToClass(semaphoreClass, "forMutualExclusion", forMutualExclusionMethod, isClassMethod = true)

  # Add wait method
  let waitMethod = createCoreMethod("wait")
  waitMethod.nativeImpl = cast[pointer](semaphoreWaitImpl)
  waitMethod.hasInterpreterParam = true
  addMethodToClass(semaphoreClass, "wait", waitMethod)

  # Add signal method
  let signalMethod = createCoreMethod("signal")
  signalMethod.nativeImpl = cast[pointer](semaphoreSignalImpl)
  signalMethod.hasInterpreterParam = true
  addMethodToClass(semaphoreClass, "signal", signalMethod)

  # Add count method
  let countMethod = createCoreMethod("count")
  countMethod.nativeImpl = cast[pointer](semaphoreCountImpl)
  countMethod.hasInterpreterParam = true
  addMethodToClass(semaphoreClass, "count", countMethod)

  return semaphoreClass
