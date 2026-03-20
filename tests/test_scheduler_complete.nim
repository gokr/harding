import std/[unittest, tables, sequtils, strutils]
import ../src/harding/core/types
import ../src/harding/core/process
import ../src/harding/core/scheduler
import ../src/harding/interpreter/vm
import ../src/harding/interpreter/objects

suite "Process and Scheduler - Core":
  test "Create scheduler":
    let sched = newScheduler()
    check sched.processCount == 0
    check sched.readyCount == 0
    check not sched.isRunning

  test "Create process":
    let sched = newScheduler()
    let proc1 = sched.newProcess("test-process")

    check proc1.pid == 1
    check proc1.name == "test-process"
    check proc1.state == psReady

  test "Add process to scheduler":
    let sched = newScheduler()
    let proc1 = sched.newProcess("proc1")

    sched.addProcess(proc1)

    check sched.processCount == 1
    check sched.readyCount == 1
    check sched.getProcess(proc1.pid) == proc1

  test "Select next process":
    let sched = newScheduler()
    let proc1 = sched.newProcess("proc1")
    let proc2 = sched.newProcess("proc2")

    sched.addProcess(proc1)
    sched.addProcess(proc2)

    check sched.readyCount == 2

    let selected = sched.selectNextProcess()
    check selected == proc1
    check selected.state == psRunning
    check sched.currentProcess == proc1
    check sched.readyCount == 1

  test "Yield current process":
    let sched = newScheduler()
    let proc1 = sched.newProcess("proc1")

    sched.addProcess(proc1)
    discard sched.selectNextProcess()

    check proc1.state == psRunning
    check sched.readyCount == 0

    sched.yieldCurrentProcess()

    check proc1.state == psReady
    check sched.readyCount == 1

  test "Block and unblock process":
    let sched = newScheduler()
    let proc1 = sched.newProcess("proc1")

    sched.addProcess(proc1)
    discard sched.selectNextProcess()

    check proc1.state == psRunning

    let condition = WaitCondition(kind: wkMonitor, target: nil)
    sched.blockProcess(proc1, condition)

    check proc1.state == psBlocked
    check sched.blockedCount == 1
    check sched.readyCount == 0

    sched.unblockProcess(proc1)

    check proc1.state == psReady
    check sched.blockedCount == 0
    check sched.readyCount == 1

  test "Suspend and resume process":
    let sched = newScheduler()
    let proc1 = sched.newProcess("proc1")

    sched.addProcess(proc1)

    sched.suspendProcess(proc1)
    check proc1.state == psSuspended

    sched.resumeProcess(proc1)
    check proc1.state == psReady
    check sched.readyCount == 2  # Was in ready queue, now added again

  test "Round-robin scheduling":
    let sched = newScheduler()
    let proc1 = sched.newProcess("proc1")
    let proc2 = sched.newProcess("proc2")
    let proc3 = sched.newProcess("proc3")

    sched.addProcess(proc1)
    sched.addProcess(proc2)
    sched.addProcess(proc3)

    # First round
    var selected = sched.selectNextProcess()
    check selected == proc1
    sched.yieldCurrentProcess()

    selected = sched.selectNextProcess()
    check selected == proc2
    sched.yieldCurrentProcess()

    selected = sched.selectNextProcess()
    check selected == proc3
    sched.yieldCurrentProcess()

    # Second round - back to proc1
    selected = sched.selectNextProcess()
    check selected == proc1

  test "Terminate process":
    let sched = newScheduler()
    let proc1 = sched.newProcess("proc1")

    sched.addProcess(proc1)
    discard sched.selectNextProcess()

    sched.terminateProcess(proc1)
    check proc1.state == psTerminated

  test "Remove process":
    let sched = newScheduler()
    let proc1 = sched.newProcess("proc1")

    sched.addProcess(proc1)
    check sched.processCount == 1

    sched.removeProcess(proc1.pid)
    check sched.processCount == 0
    check sched.getProcess(proc1.pid) == nil

  test "Run one slice with no processes":
    let sched = newScheduler()
    let ran = sched.runOneSlice()
    check not ran

  test "Run one slice with process":
    let sched = newScheduler()
    let proc1 = sched.newProcess("proc1")

    sched.addProcess(proc1)
    let ran = sched.runOneSlice()

    check ran
    check sched.currentProcess == proc1
    check proc1.state == psRunning

  test "List processes":
    let sched = newScheduler()
    let proc1 = sched.newProcess("proc1")
    let proc2 = sched.newProcess("proc2")

    sched.addProcess(proc1)
    sched.addProcess(proc2)

    let list = sched.listProcesses()
    check list.len == 2

  test "Scheduler with shared globals":
    var globals = new(Table[string, NodeValue])
    globals[] = initTable[string, NodeValue]()
    globals[]["testVar"] = NodeValue(kind: vkInt, intVal: 42)

    let sched = newScheduler(globals = globals)

    check not sched.sharedGlobals.isNil
    check "testVar" in sched.sharedGlobals[]
    check sched.sharedGlobals[]["testVar"].kind == vkInt
    check sched.sharedGlobals[]["testVar"].intVal == 42


suite "Green Threads - Scheduler Integration":
  # Initialize core classes before any tests
  discard initCoreClasses()

  test "Create scheduler context":
    let ctx = newSchedulerContext()

    check ctx.theScheduler != nil
    check ctx.mainProcess != nil
    check ctx.theScheduler.processCount == 1
    check ctx.mainProcess.name == "main"

  test "Main process has interpreter":
    let ctx = newSchedulerContext()
    let interp = ctx.mainProcess.getInterpreter()

    check not interp.globals.isNil
    check interp.rootObject != nil

  test "Shared globals between interpreters":
    let ctx = newSchedulerContext()
    let mainInterp = ctx.mainProcess.getInterpreter()

    # Set a global in main interpreter
    mainInterp.globals[]["testVar"] = NodeValue(kind: vkInt, intVal: 42)

    # Create a second interpreter with shared state
    let newInterp = newInterpreterWithShared(
      ctx.theScheduler.sharedGlobals,
      ctx.theScheduler.rootObject
    )

    # Check that both interpreters share the same globals
    check "testVar" in newInterp.globals[]
    check newInterp.globals[]["testVar"].intVal == 42

    # Modify in new interpreter, check in main
    newInterp.globals[]["testVar"] = NodeValue(kind: vkInt, intVal: 100)
    check mainInterp.globals[]["testVar"].intVal == 100

  test "Fork process with block":
    let ctx = newSchedulerContext()

    let blockNode = BlockNode(
      parameters: @[],
      temporaries: @[],
      body: @[LiteralNode(value: NodeValue(kind: vkInt, intVal: 42)).Node],
      isMethod: false
    )

    let receiver = newInstance(objectClass)
    let newProc = ctx.forkProcess(blockNode, receiver, "test-fork")

    check newProc != nil
    check newProc.name == "test-fork"
    check newProc.state == psReady
    check ctx.theScheduler.processCount == 2

  test "Forked process has own interpreter":
    let ctx = newSchedulerContext()

    let blockNode = BlockNode(
      parameters: @[],
      temporaries: @[],
      body: @[LiteralNode(value: NodeValue(kind: vkInt, intVal: 1)).Node],
      isMethod: false
    )

    let receiver = newInstance(objectClass)
    let newProc = ctx.forkProcess(blockNode, receiver, "forked")
    let mainInterp = ctx.mainProcess.getInterpreter()
    let forkInterp = newProc.getInterpreter()

    # Different interpreter instances
    check cast[pointer](mainInterp) != cast[pointer](forkInterp)

    # But shared globals (same reference)
    check cast[pointer](mainInterp.globals) == cast[pointer](forkInterp.globals)

  test "Multiple processes scheduling":
    let ctx = newSchedulerContext()

    # Create processes
    for i in 1..3:
      let blockNode = BlockNode(
        parameters: @[],
        temporaries: @[],
        body: @[LiteralNode(value: NodeValue(kind: vkInt, intVal: i)).Node],
        isMethod: false
      )
      discard ctx.forkProcess(blockNode, newInstance(objectClass), "proc-" & $i)

    check ctx.theScheduler.processCount == 4
    check ctx.theScheduler.readyCount == 3

  test "Process lifecycle states":
    let ctx = newSchedulerContext()

    let blockNode = BlockNode(
      parameters: @[],
      temporaries: @[],
      body: @[LiteralNode(value: NodeValue(kind: vkInt, intVal: 1)).Node],
      isMethod: false
    )

    let proc1 = ctx.forkProcess(blockNode, newInstance(objectClass), "lifecycle")

    check proc1.state == psReady

    discard ctx.theScheduler.selectNextProcess()
    check ctx.theScheduler.currentProcess != nil
    check ctx.theScheduler.currentProcess.state == psRunning

  test "Processor global initialization":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()

    initProcessorGlobal(interp)

    check "Processor" in interp.globals[]
    let processorVal = interp.globals[]["Processor"]
    check processorVal.kind == vkInstance

  test "Run forked process to completion":
    let ctx = newSchedulerContext()

    let blockNode = BlockNode(
      parameters: @[],
      temporaries: @[],
      body: @[
        AssignNode(
          variable: "processResult",
          expression: LiteralNode(value: NodeValue(kind: vkInt, intVal: 99))
        ).Node
      ],
      isMethod: false
    )

    discard ctx.forkProcess(blockNode, newInstance(objectClass), "compute")
    let steps = ctx.runToCompletion(maxSteps = 100)
    check steps > 0

  test "Processor yield is callable":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()
    initProcessorGlobal(interp)

    let (_, err) = interp.doit("Processor yield")
    check err.len == 0

  test "Context preserves interpreter state":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()
    initGlobals(interp)

    discard interp.doit("X := 10")

    let (result, err) = interp.doit("X")
    check err.len == 0
    check result.kind == vkInt
    check result.intVal == 10


suite "Harding-side Process, Scheduler, and GlobalTable":
  discard initCoreClasses()

  test "Harding global is a GlobalTable instance":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()

    check "Harding" in interp.globals[]
    let harding = interp.globals[]["Harding"]
    check harding.kind == vkInstance
    check harding.instVal.kind == ikObject
    check harding.instVal.class.hardingType == "GlobalTable"
    check harding.instVal.isNimProxy == true

  test "List all globals via Harding keys":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()

    let (keysResult, keysErr) = interp.doit("Harding keys")
    check keysErr.len == 0
    check keysResult.kind == vkInstance
    check keysResult.instVal.kind == ikArray

    let keys = keysResult.instVal.elements
    let hasTrue = keys.anyIt(it.kind == vkString and it.strVal == "true")
    let hasFalse = keys.anyIt(it.kind == vkString and it.strVal == "false")
    let hasNil = keys.anyIt(it.kind == vkString and it.strVal == "nil")
    check hasTrue
    check hasFalse
    check hasNil

  test "Get a global via Harding at:":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()

    let (result, err) = interp.doit("Harding at: \"Object\"")
    check err.len == 0
    check result.kind == vkClass
    check result.classVal.name == "Object"

  test "Set a global via Harding at:put:":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()

    let (setResult, setErr) = interp.doit("Harding at: \"myTestVar\" put: 12345")
    check setErr.len == 0
    check setResult.kind == vkInt
    check setResult.intVal == 12345

    check "myTestVar" in interp.globals[]
    check interp.globals[]["myTestVar"].intVal == 12345

  test "Check if global exists via Harding includesKey:":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()

    let (hasTrue, err1) = interp.doit("Harding includesKey: \"true\"")
    check err1.len == 0
    check hasTrue.kind == vkBool
    check hasTrue.boolVal == true

    let (hasFake, err2) = interp.doit("Harding includesKey: \"nonexistentGlobal\"")
    check err2.len == 0
    check hasFake.kind == vkBool
    check hasFake.boolVal == false

  test "Process class exists":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()

    check "Process" in interp.globals[]
    let processClass = interp.globals[]["Process"]
    check processClass.kind == vkClass
    check processClass.classVal.name == "Process"

  test "Scheduler class exists":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()

    check "Scheduler" in interp.globals[]
    let schedulerClass = interp.globals[]["Scheduler"]
    check schedulerClass.kind == vkClass
    check schedulerClass.classVal.name == "Scheduler"

  test "Processor fork: creates and returns Process object":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()

    let (result, err) = interp.doit("P := Processor fork: [42]")
    check err.len == 0
    check result.kind == vkInstance
    check result.instVal.class.hardingType == "Process"
    check result.instVal.isNimProxy == true
    check processCount(ctx.theScheduler) == 2

  test "Process pid returns integer":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()

    discard interp.doit("P := Processor fork: [42]")

    let (pid, err) = interp.doit("P pid")
    check err.len == 0
    check pid.kind == vkInt
    check pid.intVal == 2

  test "Process name returns 'Process-N' for default names":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()

    discard interp.doit("P := Processor fork: [42]")

    let (name, err) = interp.doit("P name")
    check err.len == 0
    check name.kind == vkString
    check "Process-" in name.strVal

  test "Process state returns 'ready' initially":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()

    discard interp.doit("P := Processor fork: [42]")

    let (state, err) = interp.doit("P state")
    check err.len == 0
    check state.kind == vkString
    check state.strVal == "ready"

  test "Process state changes when scheduled":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()

    discard interp.doit("P := Processor fork: [42]")
    discard ctx.runOneSlice()

    let (state, err) = interp.doit("P state")
    check err.len == 0
    check state.kind == vkString

  test "Process suspend sets state to 'suspended'":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()

    discard interp.doit("P := Processor fork: [42]")

    let (result, err) = interp.doit("P suspend")
    check err.len == 0

    let (state, stateErr) = interp.doit("P state")
    check stateErr.len == 0
    check state.kind == vkString
    check state.strVal == "suspended"

  test "Process resume sets state back to 'ready'":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()

    discard interp.doit("P := Processor fork: [42]")
    discard interp.doit("P suspend")

    let (resumeResult, resumeErr) = interp.doit("P resume")
    check resumeErr.len == 0

    let (state, stateErr) = interp.doit("P state")
    check stateErr.len == 0
    check state.kind == vkString
    check state.strVal == "ready"

  test "Process terminate sets state to 'terminated'":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()

    discard interp.doit("P := Processor fork: [42]")

    let (result, err) = interp.doit("P terminate")
    check err.len == 0

    let (state, stateErr) = interp.doit("P state")
    check stateErr.len == 0
    check state.kind == vkString
    check state.strVal == "terminated"

  test "Multiple processes with tracking":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()

    discard interp.doit("P1 := Processor fork: [1]")
    discard interp.doit("P2 := Processor fork: [2]")
    discard interp.doit("P3 := Processor fork: [3]")

    check ctx.theScheduler.processCount == 4

    let (p1pid, err1) = interp.doit("P1 pid")
    check err1.len == 0
    check p1pid.intVal > 0

    let (p2pid, err2) = interp.doit("P2 pid")
    check err2.len == 0
    check p2pid.intVal > 0

    let (p3pid, err3) = interp.doit("P3 pid")
    check err3.len == 0
    check p3pid.intVal > 0

    check p1pid.intVal != p2pid.intVal
    check p2pid.intVal != p3pid.intVal
    check p1pid.intVal != p3pid.intVal

  test "Process yield from Harding (current process only)":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()

    discard interp.doit("Other := Processor fork: [100]")
    discard interp.doit("Other suspend")

    let (result, err) = interp.doit("Processor yield")
    check err.len == 0

  test "GlobalTable at: on Harding accesses globals, not instance entries":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()

    interp.globals[]["secretGlobal"] = toValue(999)

    let (result, err) = interp.doit("Harding at: \"secretGlobal\"")
    check err.len == 0
    check result.kind == vkInt
    check result.intVal == 999

  test "GlobalTable at:put: on Harding sets globals":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()

    discard interp.doit("Harding at: \"newGlobal\" put: 777")

    check "newGlobal" in interp.globals[]
    check interp.globals[]["newGlobal"].intVal == 777

  test "Multiple processes can share globals via Harding":
    discard
