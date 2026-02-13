#
# main.nim - Harding Language Server entry point
#
# Entry point for the Harding LSP server (harding-lsp)
#

import std/[os, strutils]
import ./server

proc showHelp() =
  ## Show help message
  echo "Harding Language Server (LSP)"
  echo ""
  echo "Usage:"
  echo "  harding-lsp [options]"
  echo ""
  echo "Options:"
  echo "  --stdio    Use stdio for LSP communication (default)"
  echo "  --help     Show this help message"
  echo ""
  echo "The LSP server communicates via JSON-RPC over stdio."
  echo "It provides IDE features like completions, hover info, and go-to-definition."

proc main() =
  ## Main entry point
  let args = commandLineParams()

  for arg in args:
    if arg == "--help" or arg == "-h":
      showHelp()
      quit(0)
    elif arg == "--stdio":
      # Default behavior - continue to run
      discard
    else:
      stderr.writeLine("Unknown option: ", arg)
      showHelp()
      quit(1)

  # Run the LSP server
  runLspServer()

# Entry point
when isMainModule:
  main()
