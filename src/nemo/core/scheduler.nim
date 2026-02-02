import std/[tables, logging]
import ../core/types
import ../core/process
import ../interpreter/objects
import ../interpreter/activation

# ============================================================================
# Scheduler Integration with Interpreter
# This module connects the green threads scheduler with the Nemo interpreter
# ============================================================================

# Forward declarations for procs defined in this module but called from evaluator
proc createProcessClass*(): Class
proc createSchedulerClass*(): Class

# Forward declarations for procs defined in evaluator.nim
proc newInterpreter(): Interpreter
proc newInterpreterWithShared(globals: ref Table[string, NodeValue],
                              root: Instance): Interpreter
proc initGlobals(interp: Interpreter)
proc initProcessorGlobal*(interp: var Interpreter)
proc nilValue(): NodeValue
proc eval(interp: Interpreter, node: Node): NodeValue

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
  result.scheduler = newScheduler(
    globals = mainInterp.globals,
    root = mainInterp.rootObject
  )

  # Create main process
  result.mainProcess = result.scheduler.newProcess("main")
  result.mainProcess.interpreter = cast[InterpreterRef](mainInterp)
  result.scheduler.addProcess(result.mainProcess)

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
  ## Create a new green process from a Nemo block
  ## The new process will execute the block when scheduled

  let sched = ctx.scheduler

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
  let sched = ctx.scheduler
  if sched.currentProcess == nil:
    return nilValue()

  var interp = sched.currentProcess.getInterpreter()
  let activation = interp.currentActivation

  if activation == nil or activation.currentMethod == nil:
    # Process has finished
    sched.terminateProcess(sched.currentProcess)
    return nilValue()

  # Check if process has already returned
  if activation.hasReturned:
    sched.terminateProcess(sched.currentProcess)
    return activation.returnValue

  # Get next statement to execute
  let body = activation.currentMethod.body
  if activation.pc >= body.len:
    # Finished all statements
    sched.terminateProcess(sched.currentProcess)
    return interp.lastResult

  # Execute one statement
  let stmt = body[activation.pc]
  inc activation.pc

  try:
    result = interp.eval(stmt)
    interp.lastResult = result
  except EvalError as e:
    # Process encountered an error - terminate it
    debug("Process ", sched.currentProcess.name, " error: ", e.msg)
    sched.terminateProcess(sched.currentProcess)
    return nilValue()

  # Check if block finished
  if activation.pc >= body.len or activation.hasReturned:
    sched.terminateProcess(sched.currentProcess)

proc runOneSlice*(ctx: SchedulerContext): bool =
  ## Run one complete time slice (one statement from one process)
  ## Returns true if something was executed, false if no ready processes
  let sched = ctx.scheduler

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
  let sched = ctx.scheduler
  while result < maxSteps:
    if not ctx.runOneSlice():
      # No ready processes - check if any are blocked
      if sched.blockedCount == 0:
        break  # All done
      # Some are blocked - would need external event to unblock
      break
    inc result

# ============================================================================
# Nemo-side Processor Object
# ============================================================================

# Processor yield implementation
proc processorYieldImpl(interp: var Interpreter, self: Instance,
                        args: seq[NodeValue]): NodeValue =
  ## Processor yield - yields the current process
  ## This is called from Nemo code and triggers a context switch
  ## The actual yield happens in the scheduler loop, so we just return nil
  ## and the scheduler will handle the yield after this method returns
  debug("Processor yield called")
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

# ============================================================================
# Process Proxy and Class
# ============================================================================

type
  ProcessProxy* = ref object
    process*: Process

proc createProcessProxy*(process: Process): NodeValue =
  ## Create a proxy object that wraps a Nim Process
  let proxy = ProcessProxy(process: process)
  let obj = Instance(kind: ikObject, class: processClass, slots: @[])
  obj.isNimProxy = true
  obj.nimValue = cast[pointer](proxy)
  return obj.toValue()

proc asProcessProxy*(inst: Instance): ProcessProxy =
  ## Extract ProcessProxy from a Nemo instance
  if inst.isNimProxy and inst.nimValue != nil:
    return cast[ProcessProxy](inst.nimValue)
  return nil

# Process native method implementations

proc processPidImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Get process ID
  let proxy = self.asProcessProxy()
  if proxy != nil:
    return toValue(int(proxy.process.pid))
  return nilValue()

proc processNameImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Get process name
  let proxy = self.asProcessProxy()
  if proxy != nil:
    return toValue(proxy.process.name)
  return nilValue()

proc processStateImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Get process state
  let proxy = self.asProcessProxy()
  if proxy != nil:
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
  if ctx != nil and ctx.scheduler.currentProcess != nil:
    let proxy = self.asProcessProxy()
    if proxy != nil and proxy.process == ctx.scheduler.currentProcess:
      ctx.scheduler.yieldCurrentProcess()
  return nilValue()

proc processSuspendImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Suspend this process
  let ctx = cast[SchedulerContext](interp.schedulerContextPtr)
  if ctx != nil:
    let proxy = self.asProcessProxy()
    if proxy != nil:
      ctx.scheduler.suspendProcess(proxy.process)
  return nilValue()

proc processResumeImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Resume this process
  let ctx = cast[SchedulerContext](interp.schedulerContextPtr)
  if ctx != nil:
    let proxy = self.asProcessProxy()
    if proxy != nil:
      ctx.scheduler.resumeProcess(proxy.process)
  return nilValue()

proc processTerminateImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Terminate this process
  let ctx = cast[SchedulerContext](interp.schedulerContextPtr)
  if ctx != nil:
    let proxy = self.asProcessProxy()
    if proxy != nil:
      ctx.scheduler.terminateProcess(proxy.process)
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
  processClass.nemoType = "Process"

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
    scheduler*: Scheduler
    context*: SchedulerContext

proc createSchedulerProxy*(ctx: SchedulerContext): NodeValue =
  ## Create a proxy object that wraps a Nim Scheduler
  let proxy = SchedulerProxy(scheduler: ctx.scheduler, context: ctx)
  let obj = Instance(kind: ikObject, class: schedulerClass, slots: @[])
  obj.isNimProxy = true
  obj.nimValue = cast[pointer](proxy)
  return obj.toValue()

proc asSchedulerProxy*(inst: Instance): SchedulerProxy =
  ## Extract SchedulerProxy from a Nemo instance
  if inst.isNimProxy and inst.nimValue != nil:
    return cast[SchedulerProxy](inst.nimValue)
  return nil

# Scheduler native method implementations

proc schedulerProcessCountImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Get total number of processes
  let proxy = self.asSchedulerProxy()
  if proxy != nil:
    return toValue(proxy.scheduler.processCount())
  return nilValue()

proc schedulerReadyCountImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Get number of ready processes
  let proxy = self.asSchedulerProxy()
  if proxy != nil:
    return toValue(proxy.scheduler.readyCount())
  return nilValue()

proc schedulerBlockedCountImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Get number of blocked processes
  let proxy = self.asSchedulerProxy()
  if proxy != nil:
    return toValue(proxy.scheduler.blockedCount())
  return nilValue()

proc schedulerCurrentProcessImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Get the current process
  let proxy = self.asSchedulerProxy()
  if proxy != nil and proxy.scheduler.currentProcess != nil:
    return createProcessProxy(proxy.scheduler.currentProcess)
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
  let proxy = self.asSchedulerProxy()
  if proxy != nil:
    discard proxy.context.runOneSlice()
  return nilValue()

proc schedulerRunToCompletionImpl(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Run all processes to completion
  let proxy = self.asSchedulerProxy()
  if proxy != nil:
    let maxSteps = if args.len > 0 and args[0].kind == vkInt:
                     args[0].intVal
                   else:
                     100000
    let stepsExecuted = proxy.context.runToCompletion(maxSteps)
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
  schedulerClass.nemoType = "Scheduler"

  # Add processCount method
  let processCountMethod = createCoreMethod("processCount")
  processCountMethod.nativeImpl = cast[pointer](schedulerProcessCountImpl)
  processCountMethod.hasInterpreterParam = true
  addMethodToClass(schedulerClass, "processCount", processCountMethod)

  # Add readyCount method
  let readyCountMethod = createCoreMethod("readyCount")
  readyCountMethod.nativeImpl = cast[pointer](schedulerReadyCountImpl)
  readyCountMethod.hasInterpreterParam = true
  addMethodToClass(schedulerClass, "readyCount", readyCountMethod)

  # Add blockedCount method
  let blockedCountMethod = createCoreMethod("blockedCount")
  blockedCountMethod.nativeImpl = cast[pointer](schedulerBlockedCountImpl)
  blockedCountMethod.hasInterpreterParam = true
  addMethodToClass(schedulerClass, "blockedCount", blockedCountMethod)

  # Add currentProcess method
  let currentProcessMethod = createCoreMethod("currentProcess")
  currentProcessMethod.nativeImpl = cast[pointer](schedulerCurrentProcessImpl)
  currentProcessMethod.hasInterpreterParam = true
  addMethodToClass(schedulerClass, "currentProcess", currentProcessMethod)

  # Add fork:name: method
  let forkNameMethod = createCoreMethod("fork:name:")
  forkNameMethod.nativeImpl = cast[pointer](schedulerForkNameImpl)
  forkNameMethod.hasInterpreterParam = true
  addMethodToClass(schedulerClass, "fork:name:", forkNameMethod)

  # Add step method
  let stepMethod = createCoreMethod("step")
  stepMethod.nativeImpl = cast[pointer](schedulerStepImpl)
  stepMethod.hasInterpreterParam = true
  addMethodToClass(schedulerClass, "step", stepMethod)

  # Add runToCompletion: method
  let runToCompletionMethod = createCoreMethod("runToCompletion:")
  runToCompletionMethod.nativeImpl = cast[pointer](schedulerRunToCompletionImpl)
  runToCompletionMethod.hasInterpreterParam = true
  addMethodToClass(schedulerClass, "runToCompletion:", runToCompletionMethod)

  return schedulerClass
