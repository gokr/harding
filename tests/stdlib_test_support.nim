import ../src/harding/core/types
import ../src/harding/core/scheduler
import ../src/harding/interpreter/vm

proc newSharedStdlibInterpreter*(): Interpreter =
  result = newInterpreter()
  initGlobals(result)
  initProcessorGlobal(result)
  loadStdlib(result)
