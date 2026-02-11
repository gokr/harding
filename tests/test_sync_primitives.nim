import std/[unittest, tables, sequtils, strutils]
import ../src/harding/core/types
import ../src/harding/core/scheduler
import ../src/harding/interpreter/vm
import ../src/harding/interpreter/objects

suite "Multi-Process: Monitor":
  discard initCoreClasses()

  test "Monitor critical: provides mutual exclusion for shared counter":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()
    loadStdlib(interp)

    # Fork a coordinator process that sets up and runs the test
    let result = interp.evalStatements("""
      Coordinator := Processor fork: [
        M := Monitor new.
        Counter := 0.
        Done := 0.
        P1 := Processor fork: [
          10 timesRepeat: [
            M critical: [Counter := Counter + 1].
            Processor yield.
          ].
          Done := Done + 1.
        ].
        P2 := Processor fork: [
          10 timesRepeat: [
            M critical: [Counter := Counter + 1].
            Processor yield.
          ].
          Done := Done + 1.
        ].
        # Wait for both workers to complete
        [Done >= 2] whileFalse: [Processor yield].
        Result := Counter.
      ].
      # Start the coordinator and wait for it
      [Coordinator state = "terminated"] whileFalse: [Scheduler step].
      Result
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 20)

  test "Monitor reentrant lock allows same process to acquire multiple times":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()
    loadStdlib(interp)

    let result = interp.evalStatements("""
      M := Monitor new.
      Result := 0.
      M critical: [
        M critical: [
          M critical: [Result := 42].
        ].
      ].
      Result
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 42)

suite "Multi-Process: Semaphore":
  discard initCoreClasses()

  test "Binary semaphore ensures mutual exclusion":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()
    loadStdlib(interp)

    let result = interp.evalStatements("""
      Coordinator := Processor fork: [
        Sem := Semaphore forMutualExclusion.
        Counter := 0.
        Done := 0.
        P1 := Processor fork: [
          5 timesRepeat: [
            Sem wait.
            Counter := Counter + 1.
            Sem signal.
            Processor yield.
          ].
          Done := Done + 1.
        ].
        P2 := Processor fork: [
          5 timesRepeat: [
            Sem wait.
            Counter := Counter + 1.
            Sem signal.
            Processor yield.
          ].
          Done := Done + 1.
        ].
        [Done >= 2] whileFalse: [Processor yield].
        Result := Counter.
      ].
      [Coordinator state = "terminated"] whileFalse: [Scheduler step].
      Result
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 10)

  test "Counting semaphore allows limited concurrent access":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()
    loadStdlib(interp)

    let result = interp.evalStatements("""
      Coordinator := Processor fork: [
        Sem := Semaphore new: 2.
        Active := 0.
        MaxActive := 0.
        Done := 0.
        P1 := Processor fork: [
          Sem wait.
          Active := Active + 1.
          Active > MaxActive ifTrue: [MaxActive := Active].
          Processor yield.
          Active := Active - 1.
          Sem signal.
          Done := Done + 1.
        ].
        P2 := Processor fork: [
          Sem wait.
          Active := Active + 1.
          Active > MaxActive ifTrue: [MaxActive := Active].
          Processor yield.
          Active := Active - 1.
          Sem signal.
          Done := Done + 1.
        ].
        P3 := Processor fork: [
          Sem wait.
          Active := Active + 1.
          Active > MaxActive ifTrue: [MaxActive := Active].
          Processor yield.
          Active := Active - 1.
          Sem signal.
          Done := Done + 1.
        ].
        P4 := Processor fork: [
          Sem wait.
          Active := Active + 1.
          Active > MaxActive ifTrue: [MaxActive := Active].
          Processor yield.
          Active := Active - 1.
          Sem signal.
          Done := Done + 1.
        ].
        P5 := Processor fork: [
          Sem wait.
          Active := Active + 1.
          Active > MaxActive ifTrue: [MaxActive := Active].
          Processor yield.
          Active := Active - 1.
          Sem signal.
          Done := Done + 1.
        ].
        [Done >= 5] whileFalse: [Processor yield].
        Result := MaxActive.
      ].
      [Coordinator state = "terminated"] whileFalse: [Scheduler step].
      Result
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal <= 2)

  test "Semaphore signal unblocks waiting process":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()
    loadStdlib(interp)

    let result = interp.evalStatements("""
      Coordinator := Processor fork: [
        Sem := Semaphore new.
        Result := 0.
        P1 := Processor fork: [
          Sem wait.
          Result := Result + 1.
        ].
        P2 := Processor fork: [
          Sem wait.
          Result := Result + 10.
        ].
        # Let workers start waiting
        Processor yield.
        Processor yield.
        Sem signal.
        Sem signal.
        [Result >= 11] whileFalse: [Processor yield].
        Result.
      ].
      [Coordinator state = "terminated"] whileFalse: [Scheduler step].
      Result
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 11)

suite "Multi-Process: SharedQueue":
  discard initCoreClasses()

  test "SharedQueue producer-consumer pattern":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()
    loadStdlib(interp)

    let result = interp.evalStatements("""
      Coordinator := Processor fork: [
        Q := SharedQueue new.
        Sum := 0.
        Done := 0.
        Producer := Processor fork: [
          Q nextPut: 1.
          Q nextPut: 2.
          Q nextPut: 3.
          Done := Done + 1.
        ].
        Consumer := Processor fork: [
          Counter := 0.
          [Counter < 3] whileTrue: [
            Item := Q next.
            Sum := Sum + Item.
            Counter := Counter + 1.
          ].
          Done := Done + 1.
        ].
        [Done >= 2] whileFalse: [Processor yield].
        Result := Sum.
      ].
      [Coordinator state = "terminated"] whileFalse: [Scheduler step].
      Result
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 6)

  test "SharedQueue multiple producers and consumers":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()
    loadStdlib(interp)

    let result = interp.evalStatements("""
      Coordinator := Processor fork: [
        Q := SharedQueue new.
        TotalSum := 0.
        Done := 0.
        P1 := Processor fork: [
          Counter := 0.
          [Counter < 5] whileTrue: [Q nextPut: 1. Counter := Counter + 1].
          Done := Done + 1.
        ].
        P2 := Processor fork: [
          Counter := 0.
          [Counter < 5] whileTrue: [Q nextPut: 1. Counter := Counter + 1].
          Done := Done + 1.
        ].
        C1 := Processor fork: [
          Counter := 0.
          [Counter < 5] whileTrue: [
            Item := Q next.
            TotalSum := TotalSum + Item.
            Counter := Counter + 1.
          ].
          Done := Done + 1.
        ].
        C2 := Processor fork: [
          Counter := 0.
          [Counter < 5] whileTrue: [
            Item := Q next.
            TotalSum := TotalSum + Item.
            Counter := Counter + 1.
          ].
          Done := Done + 1.
        ].
        [Done >= 4] whileFalse: [Processor yield].
        Result := TotalSum.
      ].
      [Coordinator state = "terminated"] whileFalse: [Scheduler step].
      Result
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 10)

  test "SharedQueue bounded queue blocks when full":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()
    loadStdlib(interp)

    let result = interp.evalStatements("""
      Coordinator := Processor fork: [
        Q := SharedQueue new: 2.
        ItemsAdded := 0.
        Done := 0.
        Producer := Processor fork: [
          Q nextPut: 1. ItemsAdded := ItemsAdded + 1.
          Q nextPut: 2. ItemsAdded := ItemsAdded + 1.
          Q nextPut: 3. ItemsAdded := ItemsAdded + 1.
          Q nextPut: 4. ItemsAdded := ItemsAdded + 1.
          Q nextPut: 5. ItemsAdded := ItemsAdded + 1.
          Done := Done + 1.
        ].
        Consumer := Processor fork: [
          Counter := 0.
          [Counter < 5] whileTrue: [Q next. Counter := Counter + 1].
          Done := Done + 1.
        ].
        [Done >= 2] whileFalse: [Processor yield].
        Result := ItemsAdded.
      ].
      [Coordinator state = "terminated"] whileFalse: [Scheduler step].
      Result
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal == 5)

suite "Multi-Process: Combined Synchronization":
  discard initCoreClasses()

  test "Monitor with Semaphore for resource pooling":
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()
    loadStdlib(interp)

    let result = interp.evalStatements("""
      Coordinator := Processor fork: [
        PoolLock := Monitor new.
        Available := Semaphore new: 3.
        UsedCount := 0.
        MaxUsed := 0.
        Done := 0.
        W1 := Processor fork: [
          Available wait.
          PoolLock critical: [
            UsedCount := UsedCount + 1.
            UsedCount > MaxUsed ifTrue: [MaxUsed := UsedCount].
          ].
          Processor yield.
          PoolLock critical: [UsedCount := UsedCount - 1].
          Available signal.
          Done := Done + 1.
        ].
        W2 := Processor fork: [
          Available wait.
          PoolLock critical: [
            UsedCount := UsedCount + 1.
            UsedCount > MaxUsed ifTrue: [MaxActive := UsedCount].
          ].
          Processor yield.
          PoolLock critical: [UsedCount := UsedCount - 1].
          Available signal.
          Done := Done + 1.
        ].
        W3 := Processor fork: [
          Available wait.
          PoolLock critical: [
            UsedCount := UsedCount + 1.
            UsedCount > MaxUsed ifTrue: [MaxUsed := UsedCount].
          ].
          Processor yield.
          PoolLock critical: [UsedCount := UsedCount - 1].
          Available signal.
          Done := Done + 1.
        ].
        W4 := Processor fork: [
          Available wait.
          PoolLock critical: [
            UsedCount := UsedCount + 1.
            UsedCount > MaxUsed ifTrue: [MaxUsed := UsedCount].
          ].
          Processor yield.
          PoolLock critical: [UsedCount := UsedCount - 1].
          Available signal.
          Done := Done + 1.
        ].
        W5 := Processor fork: [
          Available wait.
          PoolLock critical: [
            UsedCount := UsedCount + 1.
            UsedCount > MaxUsed ifTrue: [MaxUsed := UsedCount].
          ].
          Processor yield.
          PoolLock critical: [UsedCount := UsedCount - 1].
          Available signal.
          Done := Done + 1.
        ].
        [Done >= 5] whileFalse: [Processor yield].
        Result := MaxUsed.
      ].
      [Coordinator state = "terminated"] whileFalse: [Scheduler step].
      Result
    """)
    check(result[1].len == 0)
    check(result[0][^1].kind == vkInt)
    check(result[0][^1].intVal <= 3)
