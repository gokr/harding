# MyApp - Example Harding Application (Pattern 1: Interpreter)
version = "1.0.0"
author = "Your Name"
description = "Example Harding application using interpreter pattern"
license = "MIT"

srcDir = "src"
bin = @["myapp"]

# Harding as a dependency
requires "https://github.com/gokr/harding.git >= 0.7.0"

import os

task build, "Build the application":
  ## Build release version
  exec "nim c -d:release -o:myapp src/myapp.nim"

task run, "Run the application":
  ## Build and run
  exec "nim c -o:myapp src/myapp.nim"
  exec "./myapp"

task dev, "Development build":
  ## Build debug version
  exec "nim c -o:myapp src/myapp.nim"

task test, "Run tests":
  ## Run test suite
  exec "nim c -r tests/test_myapp.nim"
