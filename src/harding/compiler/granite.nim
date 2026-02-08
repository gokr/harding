#!/usr/bin/env nim
#
# Harding Compiler - Standalone compiler binary
#
# Compiles Harding source (.hrd) to Nim code (.nim)

import std/[os, strutils, parseopt, strformat, logging]
import ../parser/parser
import ../parser/lexer
import ../codegen/module
import ../compiler/context

proc mangleModuleName(name: string): string =
  ## Convert module name to valid Nim identifier
  if name.len > 0 and name[0] in {'0'..'9'}:
    return "module_" & name
  return name

const VERSION* = block:
  const nimblePath = currentSourcePath().parentDir().parentDir().parentDir().parentDir() / "harding.nimble"
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
  echo "Harding Compiler - Class-based Smalltalk for Nim"
  echo ""
  echo "Usage:"
  echo "  granite <command> [options] <file.hrd>"
  echo ""
  echo "Commands:"
  echo "  compile               Compile Harding to Nim source code"
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
  echo "  granite compile examples/demo.hrd -o demo.nim"
  echo "  granite build examples/demo.hrd -d build/"
  echo "  granite run examples/demo.hrd --release"
  echo "  granite compile myprog.hrd --ast --loglevel DEBUG"
  echo ""

proc showVersion() =
  echo "Harding Compiler v" & VERSION

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
  ## Compile Harding source to Nim
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

  let rawModuleName = changeFileExt(extractFilename(config.inputFile), "")
  let moduleName = mangleModuleName(rawModuleName)
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

proc computeOutputPath(config: Config): string =
  ## Compute the output Nim file path
  if config.outputFile.len > 0:
    result = config.outputFile
  else:
    let rawModuleName = changeFileExt(extractFilename(config.inputFile), "")
    let moduleName = mangleModuleName(rawModuleName)
    result = config.outputDir / moduleName & ".nim"

proc buildFile(config: Config): bool =
  ## Compile Harding and build with Nim compiler
  if not config.compileFile():
    return false

  let outputFile = computeOutputPath(config)
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

  let outputFile = computeOutputPath(config)
  let baseName = changeFileExt(outputFile, "")

  echo "Running: ", baseName
  let exitCode = execShellCmd(baseName)

  if exitCode == 0:
    return true
  else:
    echo "Program exited with code: ", exitCode
    return false

proc setupLogging(config: Config) =
  ## Configure logging based on config
  var consoleLogger = newConsoleLogger()
  consoleLogger.levelThreshold = config.logLevel
  addHandler(consoleLogger)

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
      echo "Usage: granite compile <file.hrd> [options]"
      quit(1)

    if config.help:
      showUsage()
      quit(0)

    setupLogging(config)

    let success = config.compileFile()
    quit(if success: 0 else: 1)

  of "build":
    var config = parseArgs()
    config.build = true
    config.inputFile = if args.len >= 2: args[1] else: ""

    if config.inputFile.len == 0:
      echo "Error: No input file specified"
      echo "Usage: granite build <file.hrd> [options]"
      quit(1)

    if config.help:
      showUsage()
      quit(0)

    setupLogging(config)

    let success = config.buildFile()
    quit(if success: 0 else: 1)

  of "run":
    var config = parseArgs()
    config.run = true
    config.inputFile = if args.len >= 2: args[1] else: ""

    if config.inputFile.len == 0:
      echo "Error: No input file specified"
      echo "Usage: granite run <file.hrd> [options]"
      quit(1)

    if config.help:
      showUsage()
      quit(0)

    setupLogging(config)

    let success = config.runFile()
    quit(if success: 0 else: 1)

  else:
    # Treat as file path for backward compatibility
    if fileExists(command) and command.endsWith(".hrd"):
      var config = parseArgs()
      config.compile = true
      config.inputFile = command

      if config.version:
        showVersion()
        quit(0)

      if config.help:
        showUsage()
        quit(0)

      setupLogging(config)

      let success = config.compileFile()
      quit(if success: 0 else: 1)
    else:
      echo "Unknown command or invalid file: ", command
      echo "Run 'granite --help' for usage"
      quit(1)

when isMainModule:
  main()
