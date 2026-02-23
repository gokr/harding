#!/usr/bin/env nim
#
# Detailed example test with output comparison
#

import std/[os, strutils, strformat, sequtils]

type
  TestResult = object
    name: string
    pureCompiles: bool
    mixedCompiles: bool
    pureError: string
    mixedError: string
    interpOutput: string
    pureOutput: string
    mixedOutput: string
    matchesInterp: bool

proc runCommand(cmd: string, timeoutSecs: int = 30): tuple[exitCode: int, output: string] =
  let tempFile = getTempDir() / "test_output.txt"
  let fullCmd = cmd & " > " & tempFile & " 2>&1"
  let exitCode = execShellCmd(fullCmd)
  result.exitCode = exitCode
  if fileExists(tempFile):
    result.output = readFile(tempFile)
    removeFile(tempFile)
  else:
    result.output = ""

proc testExample(name: string): TestResult =
  result.name = name
  let file = "examples/" & name & ".hrd"
  
  # Test pure mode compilation
  echo "Testing ", name, "..."
  let (pureExit, pureErr) = runCommand("./granite_test build " & file & " 2>&1", 60)
  result.pureCompiles = (pureExit == 0)
  if not result.pureCompiles:
    result.pureError = pureErr.splitLines()[^1]
  else:
    # Run pure binary
    let (_, pureOut) = runCommand("./build/" & name, 10)
    result.pureOutput = pureOut
  
  # Test mixed mode compilation
  let (mixedExit, mixedErr) = runCommand("./granite_test build " & file & " --mixed 2>&1", 60)
  result.mixedCompiles = (mixedExit == 0)
  if not result.mixedCompiles:
    result.mixedError = mixedErr.splitLines()[^1]
  else:
    # Run mixed binary
    let (_, mixedOut) = runCommand("./build/" & name, 10)
    result.mixedOutput = mixedOut
  
  # Get interpreter output
  let (_, interpOut) = runCommand("./harding " & file & " 2>&1", 10)
  result.interpOutput = interpOut
  
  # Check if outputs match
  if result.pureCompiles:
    result.matchesInterp = (result.pureOutput.strip() == result.interpOutput.strip())

proc main() =
  let examples = [
    "hello", "arithmetic", "variables", "objects", "classes",
    "methods", "control_flow", "collections", "blocks",
    "inheritance", "multiple_inheritance", "fibonacci",
    "stdlib", "benchmark_blocks", "simple_test",
    "compiler_examples", "compiled_blocks", "bitbarrel_demo", "process_demo"
  ]
  
  echo "=========================================="
  echo "Detailed Example Test Results"
  echo "=========================================="
  echo ""
  
  var results: seq[TestResult] = @[]
  
  for name in examples:
    if fileExists("examples/" & name & ".hrd"):
      results.add(testExample(name))
  
  # Print matrix
  echo ""
  echo "MATRIX:"
  echo "----------------------------------------------"
  for r in results:
    let status = if r.pureCompiles:
      if r.matchesInterp: "✅ PASS" else: "⚠️  DIFF"
    else:
      if r.mixedCompiles: "🔶 MIXED" else: "❌ FAIL"
    
    echo fmt"{r.name:25} {status:10}"
    
    if not r.pureCompiles and r.pureError.len > 0:
      echo fmt"  Pure error: {r.pureError}"
    if not r.mixedCompiles and r.mixedError.len > 0:
      echo fmt"  Mixed error: {r.mixedError}"
  
  echo ""
  echo "SUMMARY:"
  echo "--------"
  let passCount = results.countIt(it.pureCompiles and it.matchesInterp)
  let diffCount = results.countIt(it.pureCompiles and not it.matchesInterp)
  let mixedCount = results.countIt(not it.pureCompiles and it.mixedCompiles)
  let failCount = results.countIt(not it.pureCompiles and not it.mixedCompiles)
  
  echo fmt"Pass (pure, matches interpreter):     {passCount}"
  echo fmt"Diff (pure, output differs):          {diffCount}"
  echo fmt"Mixed only (needs --mixed):           {mixedCount}"
  echo fmt"Fail (compilation fails):             {failCount}"

when isMainModule:
  main()
