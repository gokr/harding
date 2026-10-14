# Harding Echo Package - Example of Nim+Harding package model
version = "0.1.0"
author = "Göran Krampe"
description = "Example package demonstrating Harding+Nim integration"
license = "MIT"

srcDir = "src"

# Harding is required as a dependency
# Use direct git URL or local path during development
requires "https://github.com/gokr/harding.git >= 0.7.0"

import os

task example, "Run the echo example":
  ## Run the example demonstrating the echo package
  exec "nim c -r examples/demo.nim"

task test, "Test the echo package":
  ## Run package tests
  exec "nim c -r tests/test_echo.nim"
