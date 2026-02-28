##
## test_myapp.nim - Tests for MyApp (Granite Pattern)
##
## Note: Testing Granite-compiled apps requires either:
## 1. Running the compiled binary and checking output
## 2. Testing the Harding code with the interpreter
##

import std/[unittest, os, osproc]

suite "MyApp Tests":
  test "Application compiles successfully":
    # Test that granite compilation works
    let (output, exitCode) = execCmdEx("granite compile src/main.hrd -o src/main_test.nim")
    check exitCode == 0
    
    # Clean up test file
    if fileExists("src/main_test.nim"):
      removeFile("src/main_test.nim")
  
  test "Application runs with arguments":
    # First build the app
    let buildResult = execCmdEx("nimble granite_dev")
    check buildResult.exitCode == 0
    
    # Test with argument
    let (output, exitCode) = execCmdEx("./myapp TestUser")
    check exitCode == 0
    check "Hello, TestUser!" in output

when isMainModule:
  echo "Running MyApp (Granite) tests..."
  echo ""
  echo "Note: These tests require Granite and the Harding binary to be available."
