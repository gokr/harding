##
## test_myapp.nim - Tests for MyApp
##

import std/[unittest, os]
import harding/interpreter/vm

suite "MyApp Tests":
  test "Application loads without errors":
    var interp = newInterpreter()
    initGlobals(interp)
    loadStdlib(interp)
    
    interp.commandLineArgs = @["test"]
    
    let appSource = readFile("lib/myapp/main.hrd")
    let (_, err) = interp.evalStatements(appSource)
    
    check err.len == 0
  
  test "Calculator works with add":
    var interp = newInterpreter()
    initGlobals(interp)
    loadStdlib(interp)
    
    interp.commandLineArgs = @["add", "5", "3"]
    
    let appSource = readFile("lib/myapp/main.hrd")
    let (_, err) = interp.evalStatements(appSource)
    
    check err.len == 0

when isMainModule:
  echo "Running MyApp tests..."
