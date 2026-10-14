# MyApp - Example Harding Application (Pattern 2: Granite)
version = "1.0.0"
author = "Your Name"
description = "Example Harding application using Granite compilation"
license = "MIT"

srcDir = "src"
bin = @["myapp"]

# Harding is needed for Granite compiler
requires "https://github.com/gokr/harding.git >= 0.7.0"

import os

task granite_build, "Build with Granite":
  ## Compile Harding to Nim, then to binary
  echo "Compiling Harding to Nim..."
  exec "granite compile src/main.hrd -o src/main_gen.nim"
  echo "Compiling Nim to binary..."
  exec "nim c -d:release -o:myapp src/main_gen.nim"

task granite_dev, "Development build with Granite":
  ## Debug build
  exec "granite compile src/main.hrd -o src/main_gen.nim"
  exec "nim c -o:myapp src/main_gen.nim"

task run, "Run the application":
  ## Build and run
  exec "nimble granite_dev"
  exec "./myapp"

task clean, "Clean generated files":
  ## Remove generated Nim files
  exec "rm -f src/main_gen.nim"
  exec "rm -f myapp"

task test, "Run tests":
  ## Run test suite
  exec "nim c -r tests/test_myapp.nim"
