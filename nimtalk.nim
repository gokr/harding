## NimTalk Entry Point
## This is the main module that exports all NimTalk functionality

# Export core modules
import nimtalk/core/[types]
import nimtalk/parser/[lexer, parser]
import nimtalk/interpreter/[evaluator, objects, activation]
import nimtalk/repl/[main, doit, interact]
import nimtalk/compiler/[codegen]

export types, lexer, parser, evaluator, objects, activation, main, doit, interact, codegen

# Convenience proc to create and run interpreter
proc run*(code: string): string =
  ## Run NimTalk code and return result as string
  var interp = newInterpreter()
  initGlobals(interp)

  let (result, err) = interp.doit(code)
  if err.len > 0:
    return "Error: " & err
  else:
    return result.toString()

# Version constant
const version* = "0.1.0"

# Simple evaluation demo
when isMainModule:
  echo "NimTalk v" & version
  echo "Use 'nimble build' to build the REPL"
