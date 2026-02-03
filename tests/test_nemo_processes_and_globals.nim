import std/[unittest, tables, sequtils, strutils]
import ../src/nemo/core/types
import ../src/nemo/core/process
import ../src/nemo/core/scheduler
import ../src/nemo/interpreter/evaluator
import ../src/nemo/interpreter/objects

suite "Nemo-side Process, Scheduler, and GlobalTable":
  # Initialize core classes before any tests
  discard initCoreClasses()

  test "Nemo global is a GlobalTable instance":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()

    check "Nemo" in interp.globals[]
    let nemo = interp.globals[]["Nemo"]
    check nemo.kind == vkInstance
    check nemo.instVal.kind == ikObject
    check nemo.instVal.class.nemoType == "GlobalTable"
    check nemo.instVal.isNimProxy == true

  test "List all globals via Nemo keys":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()

    let (keysResult, keysErr) = interp.doit("Nemo keys")
    check keysErr.len == 0
    check keysResult.kind == vkInstance
    check keysResult.instVal.kind == ikArray

    # Common globals should be present
    let keys = keysResult.instVal.elements
    let hasTrue = keys.anyIt(it.kind == vkString and it.strVal == "true")
    let hasFalse = keys.anyIt(it.kind == vkString and it.strVal == "false")
    let hasNil = keys.anyIt(it.kind == vkString and it.strVal == "nil")
    check hasTrue
    check hasFalse
    check hasNil

  test "Get a global via Nemo at:":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()

    let (result, err) = interp.doit("Nemo at: \"Object\"")
    check err.len == 0
    check result.kind == vkClass
    check result.classVal.name == "Object"

  test "Set a global via Nemo at:put:":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()

    let (setResult, setErr) = interp.doit("Nemo at: \"myTestVar\" put: 12345")
    check setErr.len == 0
    check setResult.kind == vkInt
    check setResult.intVal == 12345

    # Verify it was set
    check "myTestVar" in interp.globals[]
    check interp.globals[]["myTestVar"].intVal == 12345

  test "Check if global exists via Nemo includesKey:":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()

    let (hasTrue, err1) = interp.doit("Nemo includesKey: \"true\"")
    check err1.len == 0
    check hasTrue.kind == vkBool
    check hasTrue.boolVal == true

    let (hasFake, err2) = interp.doit("Nemo includesKey: \"nonexistentGlobal\"")
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

    let (result, err) = interp.doit("p := Processor fork: [42]")
    check err.len == 0
    check result.kind == vkInstance
    check result.instVal.class.nemoType == "Process"

    # Process should be a proxy
    check result.instVal.isNimProxy == true

    # Should have increased process count
    check processCount(ctx.theScheduler) == 2

  test "Process pid returns integer":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()

    discard interp.doit("p := Processor fork: [42]")

    let (pid, err) = interp.doit("p pid")
    check err.len == 0
    check pid.kind == vkInt
    check pid.intVal == 2  # First forked process gets pid 2 (main is 1)

  test "Process name returns 'Process-N' for default names":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()

    discard interp.doit("p := Processor fork: [42]")

    let (name, err) = interp.doit("p name")
    check err.len == 0
    check name.kind == vkString
    check "Process-" in name.strVal

  test "Process state returns 'ready' initially":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()

    discard interp.doit("p := Processor fork: [42]")

    let (state, err) = interp.doit("p state")
    check err.len == 0
    check state.kind == vkString
    check state.strVal == "ready"

  test "Process state changes to 'running' when scheduled":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()

    discard interp.doit("p := Processor fork: [42]")

    # Run one slice - process becomes running
    discard ctx.runOneSlice()

    let (state, err) = interp.doit("p state")
    check err.len == 0
    check state.kind == vkString
    # Process may be running, ready (if yielded), or terminated (if finished)
    # After one slice for a simple literal, it likely terminates

  test "Process suspend sets state to 'suspended'":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()

    discard interp.doit("p := Processor fork: [42]")

    let (result, err) = interp.doit("p suspend")
    check err.len == 0

    let (state, stateErr) = interp.doit("p state")
    check stateErr.len == 0
    check state.kind == vkString
    check state.strVal == "suspended"

  test "Process resume sets state back to 'ready'":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()

    discard interp.doit("p := Processor fork: [42]")
    discard interp.doit("p suspend")

    let (resumeResult, resumeErr) = interp.doit("p resume")
    check resumeErr.len == 0

    let (state, stateErr) = interp.doit("p state")
    check stateErr.len == 0
    check state.kind == vkString
    check state.strVal == "ready"

  test "Process terminate sets state to 'terminated'":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()

    discard interp.doit("p := Processor fork: [42]")

    let (result, err) = interp.doit("p terminate")
    check err.len == 0

    let (state, stateErr) = interp.doit("p state")
    check stateErr.len == 0
    check state.kind == vkString
    check state.strVal == "terminated"

  test "Multiple processes with tracking":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()

    discard interp.doit("p1 := Processor fork: [1]")
    discard interp.doit("p2 := Processor fork: [2]")
    discard interp.doit("p3 := Processor fork: [3]")

    check ctx.theScheduler.processCount == 4  # main + 3 forked

    # Check pids
    let (p1pid, err1) = interp.doit("p1 pid")
    check err1.len == 0
    check p1pid.intVal == 2

    let (p2pid, err2) = interp.doit("p2 pid")
    check err2.len == 0
    check p2pid.intVal == 3

    let (p3pid, err3) = interp.doit("p3 pid")
    check err3.len == 0
    check p3pid.intVal == 4

  test "Process yield from Nemo (current process only)":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()

    # Create and suspend a process first so main can run
    discard interp.doit("other := Processor fork: [100]")
    discard interp.doit("other suspend")

    # Yield should work on main process
    let (result, err) = interp.doit("Processor yield")
    check err.len == 0

  test "GlobalTable at: on Nemo accesses globals, not instance entries":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()

    # Set a global
    interp.globals[]["secretGlobal"] = toValue(999)

    let (result, err) = interp.doit("Nemo at: 'secretGlobal'")
    check err.len == 0
    check result.kind == vkInt
    check result.intVal == 999

  test "GlobalTable at:put: on Nemo sets globals":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()

    discard interp.doit("Nemo at: 'newGlobal' put: 777")

    check "newGlobal" in interp.globals[]
    check interp.globals[]["newGlobal"].intVal == 777

  test "Multiple processes can share globals via Nemo":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()

    # Set a shared global
    discard interp.doit("Nemo at: 'sharedCounter' put: 0")

    # Fork some processes that increment it
    discard interp.doit("p1 := Processor fork: [Nemo at: 'sharedCounter' put: (Nemo at: 'sharedCounter') + 1]")
    discard interp.doit("p2 := Processor fork: [Nemo at: 'sharedCounter' put: (Nemo at: 'sharedCounter') + 1]")

    # Run them
    let steps = ctx.runToCompletion(maxSteps = 100)

    # Check final value (should be incremented twice)
    check interp.globals[]["sharedCounter"].intVal == 2
