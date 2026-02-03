import std/[unittest, tables]
import ../src/nemo/core/types
import ../src/nemo/core/process
import ../src/nemo/core/scheduler
import ../src/nemo/interpreter/evaluator
import ../src/nemo/interpreter/objects

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
    # Note: newInterpreterWithShared still uses legacy RootObject type
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

    # Create a simple block
    let blockNode = BlockNode(
      parameters: @[],
      temporaries: @[],
      body: @[LiteralNode(value: NodeValue(kind: vkInt, intVal: 42)).Node],
      isMethod: false
    )

    # Fork a new process with a proper Instance receiver
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

    # Should have 4 processes (main + 3 forked)
    check ctx.theScheduler.processCount == 4
    check ctx.theScheduler.readyCount == 4

  test "Process lifecycle states":
    let ctx = newSchedulerContext()

    let blockNode = BlockNode(
      parameters: @[],
      temporaries: @[],
      body: @[LiteralNode(value: NodeValue(kind: vkInt, intVal: 1)).Node],
      isMethod: false
    )

    let proc1 = ctx.forkProcess(blockNode, newInstance(objectClass), "lifecycle")

    # Initially ready
    check proc1.state == psReady

    # Select it - becomes running
    discard ctx.theScheduler.selectNextProcess()
    check ctx.theScheduler.currentProcess != nil
    check ctx.theScheduler.currentProcess.state == psRunning

  test "Processor global initialization":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()

    # Initialize Processor global
    initProcessorGlobal(interp)

    check "Processor" in interp.globals[]
    let processorVal = interp.globals[]["Processor"]
    check processorVal.kind == vkInstance  # Processor is now an Instance

  test "Run forked process to completion":
    let ctx = newSchedulerContext()

    # Create a block that sets a global variable
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

    # Fork the process
    discard ctx.forkProcess(blockNode, newInstance(objectClass), "compute")

    # Run until done
    let steps = ctx.runToCompletion(maxSteps = 100)

    # Should have run some steps
    check steps > 0

  test "Processor yield is callable":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()
    initProcessorGlobal(interp)

    # Evaluate Processor yield
    let (_, err) = interp.doit("Processor yield")
    check err.len == 0

  test "Context preserves interpreter state":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()
    initGlobals(interp)

    # Set up some state
    discard interp.doit("x := 10")

    # Verify state persists
    let (result, err) = interp.doit("x")
    check err.len == 0
    check result.kind == vkInt
    check result.intVal == 10
