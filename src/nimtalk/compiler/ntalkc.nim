#!/usr/bin/env nim
#
# Nimtalk Compiler - Standalone compiler binary
#
# This is a stub implementation that will be expanded later.

import std/[os, strutils]
import ../compiler/codegen

proc showUsage() =
  echo "Nimtalk Compiler - Prototype-based Smalltalk for Nim"
  echo ""
  echo "Usage:"
  echo "  ntalkc <file.nt>          # Compile Nimtalk file to Nim"
  echo "  ntalkc --help             # Show this help"
  echo ""
  echo "Note: Compiler functionality is not yet implemented."

proc main() =
  let args = commandLineParams()

  if args.len == 0:
    showUsage()
    quit(1)

  case args[0]:
  of "--help", "-h":
    showUsage()
  of "--version", "-v":
    echo "Nimtalk Compiler v0.1.0"
  else:
    echo "Compiler not yet implemented. File: ", args[0]
    echo "Use 'ntalk' to run interpreter."
    quit(1)

when isMainModule:
  main()