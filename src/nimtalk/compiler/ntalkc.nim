#!/usr/bin/env nim
#
# Nimtalk Compiler - Standalone compiler binary
#
# Compiles Nimtalk source (.nt) to Nim code (.nim)

import std/[os, strutils, parseopt, strformat, logging]
import ../parser/parser
import ../parser/lexer
import ../codegen/module
import ../compiler/context

const VERSION* = block:
  const nimblePath = currentSourcePath().parentDir().parentDir().parentDir().parentDir() / "nimtalk.nimble"
  const nimbleContent = staticRead(nimblePath)
  var versionStr = "unknown"
  for line in nimbleContent.splitLines():
    let trimmed = line.strip()
    if trimmed.startsWith("version"):
      let parts = trimmed.split("=")
      if parts.len >= 2:
        versionStr = parts[1].strip().strip(chars={'\"', '\''})
        break
  versionStr

type
  Config = ref object
    inputFile: string
    outputFile: string
    outputDir: string
    compile: bool
    build: bool
    run: bool
    release: bool
    help: bool
    version: bool
    logLevel: Level
    dumpAst: bool

proc newConfig(): Config =
  Config(
    inputFile: "",
    outputFile: "",
    outputDir: "./build",
    compile: false,
    build: false,
    run: false,
    release: false,
    help: false,
    version: false,
    logLevel: lvlError,  # Default to ERROR level
    dumpAst: false
  )

proc showUsage() =
  echo "Nimtalk Compiler - Class-based Smalltalk for Nim"
  echo ""
  echo "Usage:"
  echo "  ntalkc <command> [options] <file.nt>"
  echo ""
  echo "Commands:"
  echo "  compile               Compile Nimtalk to Nim source code"
  echo "  build                 Compile to Nim and build executable"
  echo "  run                   Compile, build, and execute"
  echo "  help                  Show this help"
  echo "  version               Show version"
  echo ""
  echo "Options:"
  echo "  -o, --output <file>   Output Nim file path (compile only)"
  echo "  -d, --dir <dir>       Output directory (default: ./build)"
  echo "  -r, --release         Build with --release flag for optimization"
  echo "  --ast                 Dump AST after parsing and before compiling"
  echo "  --loglevel <level>    Set log level: DEBUG, INFO, WARN, ERROR (default: ERROR)"
  echo "  -h, --help            Show this help"
  echo "  -v, --version         Show version"
  echo ""
  echo "Examples:"
  echo "  ntalkc compile examples/demo.nt -o demo.nim"
  echo "  ntalkc build examples/demo.nt -d build/"
  echo "  ntalkc run examples/demo.nt --release"
  echo "  ntalkc compile myprog.nt --ast --loglevel DEBUG"
  echo ""

proc showVersion() =
  echo "Nimtalk Compiler v" & VERSION

proc parseLogLevel(levelStr: string): Level =
  ## Parse log level string to Level enum
  case levelStr.toUpperAscii()
  of "DEBUG":
    return lvlDebug
  of "INFO":
    return lvlInfo
  of "WARN", "WARNING":
    return lvlWarn
  of "ERROR":
    return lvlError
  of "FATAL":
    return lvlFatal
  else:
    echo "Invalid log level: ", levelStr
    echo "Valid levels: DEBUG, INFO, WARN, ERROR, FATAL"
    quit(1)

proc parseArgs(): Config =
  result = newConfig()
  var p = initOptParser(commandLineParams())

  while true:
    p.next()
    case p.kind
    of cmdEnd: break
    of cmdShortOption, cmdLongOption:
      case p.key
      of "o", "output":
        result.outputFile = p.val
      of "d", "dir":
        result.outputDir = p.val
      of "r", "release":
        result.release = true
      of "h", "help":
        result.help = true
      of "v", "version":
        result.version = true
      of "loglevel":
        result.logLevel = parseLogLevel(p.val)
      of "ast":
        result.dumpAst = true
      else:
        echo "Unknown option: ", p.key
        quit(1)
    of cmdArgument:
      if result.inputFile.len == 0:
        result.inputFile = p.val
      else:
        echo "Unexpected argument: ", p.val
        quit(1)

proc compileFile(config: Config): bool =
  ## Compile Nimtalk source to Nim
  if not fileExists(config.inputFile):
    echo "Error: Input file not found: ", config.inputFile
    return false

  echo "Compiling: ", config.inputFile

  let source = readFile(config.inputFile)
  let tokens = lex(source)

  var parser = initParser(tokens)
  parser.lastLine = 1
  let nodes = parser.parseStatements()

  if parser.hasError:
    echo "Parse error: ", parser.errorMsg
    return false

  # Dump AST if requested
  if config.dumpAst:
    echo "AST:"
    for node in nodes:
      echo printAST(node)

  let moduleName = changeFileExt(extractFilename(config.inputFile), "")
  let outputDir = if config.outputDir.len > 0: config.outputDir else: "./build"

  var ctx = newCompiler(outputDir, moduleName)
  let nimCode = genModule(ctx, nodes, moduleName)

  var outputPath: string
  if config.outputFile.len > 0:
    outputPath = config.outputFile
  else:
    outputPath = outputDir / moduleName & ".nim"

  createDir(parentDir(outputPath))
  writeFile(outputPath, nimCode)

  echo "Generated: ", outputPath
  return true

proc buildFile(config: Config): bool =
  ## Compile Nimtalk and build with Nim compiler
  if not config.compileFile():
    return false

  var outputFile = if config.outputFile.len > 0:
                     config.outputFile
                   else:
                     let moduleName = changeFileExt(extractFilename(config.inputFile), "")
                     config.outputDir / moduleName & ".nim"

  let baseName = changeFileExt(outputFile, "")
  let releaseFlag = if config.release: " --release" else: ""
  let cmd = fmt("nim c{releaseFlag} -o:{baseName} {outputFile}")

  echo "Building: ", cmd
  let exitCode = execShellCmd(cmd)

  if exitCode == 0:
    echo "Build successful: ", baseName
    return true
  else:
    echo "Build failed with exit code: ", exitCode
    return false

proc runFile(config: Config): bool =
  ## Compile, build, and run the program
  if not config.buildFile():
    return false

  var outputFile = if config.outputFile.len > 0:
                     config.outputFile
                   else:
                     let moduleName = changeFileExt(extractFilename(config.inputFile), "")
                     config.outputDir / moduleName & ".nim"

  let baseName = changeFileExt(outputFile, "")

  echo "Running: ", baseName
  let exitCode = execShellCmd(baseName)

  if exitCode == 0:
    return true
  else:
    echo "Program exited with code: ", exitCode
    return false

proc main() =
  let args = commandLineParams()

  if args.len == 0:
    showUsage()
    quit(0)

  var command = ""
  if args.len >= 1:
    command = args[0]

  case command
  of "--help", "-h", "help":
    showUsage()
  of "--version", "-v", "version":
    showVersion()
  of "compile":
    var config = parseArgs()
    config.compile = true
    config.inputFile = if args.len >= 2: args[1] else: ""

    if config.inputFile.len == 0:
      echo "Error: No input file specified"
      echo "Usage: ntalkc compile <file.nt> [options]"
      quit(1)

    if config.help:
      showUsage()
      quit(0)

    # Configure logging
    var consoleLogger = newConsoleLogger()
    consoleLogger.levelThreshold = config.logLevel
    addHandler(consoleLogger)

    let success = config.compileFile()
    quit(if success: 0 else: 1)

  of "build":
    var config = parseArgs()
    config.build = true
    config.inputFile = if args.len >= 2: args[1] else: ""

    if config.inputFile.len == 0:
      echo "Error: No input file specified"
      echo "Usage: ntalkc build <file.nt> [options]"
      quit(1)

    if config.help:
      showUsage()
      quit(0)

    # Configure logging
    var consoleLogger = newConsoleLogger()
    consoleLogger.levelThreshold = config.logLevel
    addHandler(consoleLogger)

    let success = config.buildFile()
    quit(if success: 0 else: 1)

  of "run":
    var config = parseArgs()
    config.run = true
    config.inputFile = if args.len >= 2: args[1] else: ""

    if config.inputFile.len == 0:
      echo "Error: No input file specified"
      echo "Usage: ntalkc run <file.nt> [options]"
      quit(1)

    if config.help:
      showUsage()
      quit(0)

    # Configure logging
    var consoleLogger = newConsoleLogger()
    consoleLogger.levelThreshold = config.logLevel
    addHandler(consoleLogger)

    let success = config.runFile()
    quit(if success: 0 else: 1)

  else:
    # Treat as file path for backward compatibility
    if fileExists(command) and command.endsWith(".nt"):
      var config = parseArgs()
      config.compile = true
      config.inputFile = command

      if config.version:
        showVersion()
        quit(0)

      if config.help:
        showUsage()
        quit(0)

      # Configure logging for backward compat mode
      var consoleLogger = newConsoleLogger()
      consoleLogger.levelThreshold = config.logLevel
      addHandler(consoleLogger)

      let success = config.compileFile()
      quit(if success: 0 else: 1)
    else:
      echo "Unknown command or invalid file: ", command
      echo "Run 'ntalkc --help' for usage"
      quit(1)

when isMainModule:
  main()
