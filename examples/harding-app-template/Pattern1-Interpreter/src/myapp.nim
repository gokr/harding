##
## myapp.nim - Main entry point for MyApp
##
## This demonstrates Pattern 1: Interpreter-based entry point
##
## The application:
## 1. Creates a Harding interpreter
## 2. Loads the stdlib
## 3. Loads the application logic from Harding files
## 4. Executes the application
##

import std/[os, logging]
import harding/interpreter/vm

proc main() =
  # Get command-line arguments
  let args = commandLineParams()
  
  echo "=== MyApp (Pattern 1: Interpreter) ==="
  echo ""
  
  # Create and initialize interpreter
  var interp = newInterpreter()
  initGlobals(interp)
  loadStdlib(interp)
  
  # Pass CLI args to interpreter (available as System arguments)
  interp.commandLineArgs = args
  
  # Load and execute the application logic
  # In a real app, you might load multiple files or a main entry point
  let appSource = readFile("lib/myapp/main.hrd")
  let (_, err) = interp.evalStatements(appSource)
  
  if err.len > 0:
    stderr.writeLine("Error: ", err)
    quit(1)
  
  echo ""
  echo "=== Application Complete ==="

when isMainModule:
  main()
