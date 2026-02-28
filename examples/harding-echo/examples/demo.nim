##
## demo.nim - Example usage of the harding-echo package
##

import std/[os, logging]
import harding/interpreter/vm
import harding_echo/package

proc main() =
  echo "=== Harding Echo Package Demo ==="
  echo ""
  
  # Create interpreter
  var interp = newInterpreter()
  initGlobals(interp)
  loadStdlib(interp)
  
  # Install the echo package
  echo "Installing echo package..."
  if not installEchoPackage(interp):
    echo "Failed to install echo package"
    quit(1)
  
  echo "Package installed successfully!"
  echo ""
  
  # Example 1: Basic echo
  echo "Example 1: Basic echo"
  var (_, err) = interp.evalStatements("""
    result := Echo echo: "Hello from Harding!"
    Stdout writeline: result
  """)
  if err.len > 0:
    echo "Error: ", err
  
  echo ""
  
  # Example 2: Echo with prefix
  echo "Example 2: Echo with prefix"
  (_, err) = interp.evalStatements("""
    result := Echo echo: "World" withPrefix: "Hello, "
    Stdout writeline: result
  """)
  if err.len > 0:
    echo "Error: ", err
  
  echo ""
  
  # Example 3: Counter
  echo "Example 3: Counter"
  (_, err) = interp.evalStatements("""
    count := Echo count
    Stdout writeline: ("Echo called " , count asString , " times")
    
    Echo reset
    Stdout writeline: "Counter reset"
    
    Echo echo: "One"
    Echo echo: "Two"
    count := Echo count
    Stdout writeline: ("Now called " , count asString , " times")
  """)
  if err.len > 0:
    echo "Error: ", err
  
  echo ""
  echo "=== Demo Complete ==="

when isMainModule:
  main()
