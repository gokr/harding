## GTK-enabled interpreter for the shared Harding application library.
import std/os
import ../core/types
import ../interpreter/vm
import ../core/scheduler
import ../gui/gtk/interpreted_application

proc main(): int =
  if paramCount() < 1:
    stderr.writeLine("Usage: harding_gtk app.hrd")
    return 2
  let context = newSchedulerContext()
  var interp = context.mainProcess.getInterpreter()
  interp.hardingHome = getEnv("HARDING_HOME", ".")
  interp.commandLineArgs = commandLineParams()[1..^1]
  loadStdlib(interp)
  registerGtkApplication(interp)
  let (_, error) = interp.evalStatements(readFile(paramStr(1)))
  if error.len > 0:
    stderr.writeLine(error)
    return 1
  0

when isMainModule:
  quit(main())
