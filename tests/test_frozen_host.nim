import std/[unittest, tables, os]
import ../src/harding/core/types
import ../src/harding/core/scheduler
import ../src/harding/interpreter/vm
import ../src/harding/runtime/runtime

suite "Embedded frozen source ownership":
  test "package-only loading ignores colliding disk sources and propagates to evaluate":
    createDir("build/frozen-host-sources")
    let path = "build/frozen-host-sources/collision.hrd"
    writeFile(path, "CollisionValue := 99.")
    defer: removeFile(path)
    let ctx = newSchedulerContext()
    var interp = ctx.mainProcess.getInterpreter()
    interp.packageSources[][path] = "CollisionValue := 42."
    interp.packageOnlyLoads = true
    let evaluation = interp.evaluateIsolated("Harding load: \"" & path & "\". CollisionValue")
    check evaluation.error.len == 0
    check evaluation.value.intVal == 42
    interp.packageSources[].del(path)
    let missing = interp.evaluateIsolated("Harding load: \"" & path & "\"")
    check missing.error.len > 0
    check interp.globals[]["CollisionValue"].intVal == 42

  test "missing or invalid embedded bootstrap fails instead of partially starting":
    expect ValueError:
      discard newEmbeddedFrozenHost([])
    expect ValueError:
      discard newEmbeddedFrozenHost([("lib/core/Bootstrap.hrd", "Broken := #(")])
