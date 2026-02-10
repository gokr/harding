#
# Harding JS - JavaScript entry point for Harding interpreter
# Compiles to JavaScript using Nim's JS backend for embedding in websites
#
# This module provides:
# - Embedded library files (no file I/O in browser)
# - JavaScript-facing API via jsDoit()
# - Output capture for println etc
#

when not defined(js):
  {.error: "This module is only for JavaScript compilation. Use harding.nim for native builds.".}

import std/[tables, strutils, logging]
import ../core/types
import ../parser/[lexer, parser]
import ../interpreter/vm
import ../interpreter/objects
import jslib  # Embedded library files

const VERSION* = "0.3.0"  ## Harding version for JS builds

# ============================================================================
# Output Capture for JS Environment
# ============================================================================

var jsOutputBuffer*: string = ""  ## Captured output from println etc

proc getAndClearOutput*(): string =
  ## Get captured output and clear buffer
  result = jsOutputBuffer
  jsOutputBuffer = ""

# ============================================================================
# JavaScript-Facing API
# ============================================================================

var jsInterpreter*: Interpreter  ## Global interpreter instance
var jsInitialized* = false       ## Whether interpreter is initialized

proc initJSInterpreter*() =
  ## Initialize the interpreter with embedded libraries
  if jsInitialized:
    return  # Already initialized

  # Create interpreter
  jsInterpreter = newInterpreter()
  initGlobals(jsInterpreter)

  # Load embedded standard library
  loadEmbeddedStdlib(jsInterpreter)

  jsInitialized = true

proc jsDoit*(source: cstring): cstring {.exportc.} =
  ## Evaluate Harding code and return result as string
  ## This is the main entry point called from JavaScript

  # Initialize interpreter on first call
  if not jsInitialized:
    initJSInterpreter()

  # Clear output buffer
  jsOutputBuffer = ""

  # Evaluate the code
  let (result, err) = jsInterpreter.doit($source)

  if err.len > 0:
    # Return error prefixed with "ERROR:"
    return cstring("ERROR: " & err)
  else:
    # Return result + any captured output
    let output = jsOutputBuffer
    let resultStr = result.toString()
    if output.len > 0 and resultStr.len > 0:
      return cstring(output & resultStr)
    elif output.len > 0:
      return cstring(output)
    else:
      return cstring(resultStr)

proc jsDoitWithOutput*(source: cstring, output: var cstring): cstring {.exportc.} =
  ## Evaluate Harding code and return result, with output via out parameter
  ## Allows JavaScript to separate result from printed output

  # Initialize interpreter on first call
  if not jsInitialized:
    initJSInterpreter()

  # Clear output buffer
  jsOutputBuffer = ""

  # Evaluate the code
  let (result, err) = jsInterpreter.doit($source)

  output = cstring(jsOutputBuffer)
  if err.len > 0:
    return cstring("ERROR: " & err)
  else:
    return cstring(result.toString())

proc jsGetVersion*(): cstring {.exportc.} =
  ## Get Harding version string
  return cstring(VERSION)

proc jsIsInitialized*(): bool {.exportc.} =
  ## Check if interpreter is initialized
  return jsInitialized

# ============================================================================
# JavaScript Export
# ============================================================================

{.emit: """
// Export Harding API to global scope for browser access
if (typeof window !== 'undefined') {
  window.Harding = {
    doit: function(code) {
      return jsDoit(code);
    },
    doitWithOutput: function(code) {
      var outputPtr = { ptr: null };
      var result = jsDoitWithOutput(code, outputPtr);
      // In JS backend, we need to handle the output differently
      // For now, return both in result or use a wrapper
      return { result: result, output: window.Harding.getOutput() };
    },
    version: function() {
      return jsGetVersion();
    },
    isInitialized: function() {
      return jsIsInitialized();
    }
  };
}
// Also support Node.js module exports
if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    doit: jsDoit,
    doitWithOutput: jsDoitWithOutput,
    version: jsGetVersion,
    isInitialized: jsIsInitialized
  };
}
""".}
