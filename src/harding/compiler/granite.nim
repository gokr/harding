#!/usr/bin/env nim
#
# Harding Compiler - Standalone compiler binary
#
# Compiles Harding source (.hrd) to Nim code (.nim)
#
# NOTE: This compiler initializes the full Harding VM to ensure access to
# the complete class model, enabling accurate compilation with type information.

import std/[os, strutils, parseopt, strformat, logging]
import ../parser/parser
import ../parser/lexer
import ../codegen/module
import ../compiler/context
import ../core/scheduler
import ../interpreter/vm
import ../repl/cli

proc mangleModuleName(name: string): string =
  ## Convert module name to valid Nim identifier
  ## Module names starting with digits are invalid in Nim, use -o flag to specify output name
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
    mixed: bool
    help: bool
    version: bool
    logLevel: Level
    dumpAst: bool
    hardingHome: string
    bootstrapFile: string
    maxStackDepth: int

proc newConfig(): Config =
  Config(
    inputFile: "",
    outputFile: "",
    outputDir: "./build",
    compile: false,
    build: false,
    run: false,
    release: false,
    mixed: false,
    help: false,
    version: false,
    logLevel: lvlError,  # Default to ERROR level
    dumpAst: false,
    hardingHome: getEnv("HARDING_HOME", "."),
    bootstrapFile: "",
    maxStackDepth: 10000
  )

proc showUsage() =
  echo "Harding Compiler - Class-based Smalltalk for Nim"
  echo ""
  echo "Usage:"
  echo "  granite <command> [options] <file.hrd>"
  echo ""
  echo "Commands:"
  echo "  compile (c)           Compile Harding to Nim source code"
  echo "  build (b)             Compile to Nim and build executable"
  echo "  run (r)               Compile, build, and execute"
  echo "  help                  Show this help"
  echo "  version               Show version"
  echo ""
  echo "Options:"
  echo "  -o, --output <file>   Output Nim file path (compile only)"
  echo "  -d, --dir <dir>       Output directory (default: ./build)"
  echo "  -r, --release         Build with --release flag for optimization"
  echo "  --mixed               Enable mixed mode (embed interpreter for fallback)"
  echo "  --home <path>         Set HARDING_HOME directory (default: current directory)"
  echo "  --bootstrap <file>    Use custom bootstrap file (default: lib/core/Bootstrap.hrd)"
  echo "  --ast                 Dump AST after parsing and before compiling"
  echo "  --loglevel <level>    Set log level: DEBUG, INFO, WARN, ERROR (default: ERROR)"
  echo "  -h, --help            Show this help"
  echo "  -v, --version         Show version"
  echo ""
  echo "Environment Variables:"
  echo "  HARDING_HOME          Default home directory for loading libraries"
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

proc parseArgs(argsToParse: seq[string] = @[]): Config =
  result = newConfig()
  let args = if argsToParse.len > 0: argsToParse else: commandLineParams()
  var p = initOptParser(args)

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
      of "home":
        result.hardingHome = p.val
      of "bootstrap":
        result.bootstrapFile = p.val
      of "loglevel":
        result.logLevel = parseLogLevel(p.val)
      of "ast":
        result.dumpAst = true
      of "mixed":
        result.mixed = true
      else:
        echo "Unknown option: ", p.key
        quit(1)
    of cmdArgument:
      # For cmdArgument, the value is in p.key, not p.val
      if result.inputFile.len == 0:
        result.inputFile = p.key
      else:
        echo "Unexpected argument: ", p.key
        quit(1)

proc compileFile(config: Config): bool =
  ## Compile Harding source to Nim using the unified VM-based pipeline
  if not fileExists(config.inputFile):
    echo "Error: Input file not found: ", config.inputFile
    return false

  echo "Compiling: ", config.inputFile

  # Initialize the Harding VM with full stdlib (unified pipeline)
  # This gives us access to the complete class model for accurate compilation
  let schedCtx = newSchedulerContext()
  var interp = schedCtx.mainProcess.getInterpreter()
  interp.hardingHome = config.hardingHome
  
  # Load standard library
  let bootstrapFile = if config.bootstrapFile.len > 0: 
                        config.bootstrapFile 
                      else: 
                        config.hardingHome / "lib" / "core" / "Bootstrap.hrd"
  loadStdlib(interp, bootstrapFile)

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

  let outputDir = if config.outputDir.len > 0: config.outputDir else: "./build"

  # Determine module name: if -o is specified, use that name (for valid identifiers)
  # otherwise use input filename
  let moduleName = if config.outputFile.len > 0:
                     changeFileExt(extractFilename(config.outputFile), "")
                   else:
                     mangleModuleName(changeFileExt(extractFilename(config.inputFile), ""))

  # Nim file always goes in build directory
  let outputPath = outputDir / moduleName & ".nim"

  var ctx = newCompiler(outputDir, moduleName)
  let nimCode = genModule(ctx, nodes, moduleName, config.mixed, config.inputFile)

  createDir(outputDir)
  writeFile(outputPath, nimCode)

  echo "Generated: ", outputPath
  return true

proc computeBinaryName(config: Config): string =
  ## Compute the binary output name
  ## If -o is specified, use that; otherwise derive from input file
  let outputDir = if config.outputDir.len > 0: config.outputDir else: "./build"
  if config.outputFile.len > 0:
    result = config.outputFile
  else:
    let rawModuleName = changeFileExt(extractFilename(config.inputFile), "")
    let moduleName = mangleModuleName(rawModuleName)
    result = outputDir / moduleName

proc buildFile(config: Config): bool =
  ## Compile Harding and build with Nim compiler
  if not config.compileFile():
    return false

  let outputDir = if config.outputDir.len > 0: config.outputDir else: "./build"
  let moduleName = if config.outputFile.len > 0:
                     changeFileExt(extractFilename(config.outputFile), "")
                   else:
                     mangleModuleName(changeFileExt(extractFilename(config.inputFile), ""))
  let nimFile = outputDir / moduleName & ".nim"
  let binaryName = computeBinaryName(config)
  let releaseFlag = if config.release: " -d:release" else: ""
  let cmd = fmt("nim c{releaseFlag} -o:{binaryName} {nimFile}")

  echo "Building: ", cmd
  let exitCode = execShellCmd(cmd)

  if exitCode == 0:
    echo "Build successful: ", binaryName
    return true
  else:
    echo "Build failed with exit code: ", exitCode
    return false

proc runFile(config: Config): bool =
  ## Compile, build, and run the program
  if not config.buildFile():
    return false

  let binaryName = computeBinaryName(config)
  # If binary is in current directory (no path separator), prefix with ./
  let runCmd = if binaryName.contains("/") or binaryName.contains("\\"): binaryName else: "./" & binaryName

  echo "Running: ", runCmd
  let exitCode = execShellCmd(runCmd)

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
  of "compile", "c":
    var config = if args.len > 1: parseArgs(args[1..^1]) else: parseArgs(@[])
    config.compile = true

    if config.inputFile.len == 0:
      echo "Error: No input file specified"
      echo "Usage: granite compile <file.hrd> [options]"
      quit(1)

    if config.help:
      showUsage()
      quit(0)

    # Set HARDING_HOME environment for child processes
    putEnv("HARDING_HOME", config.hardingHome)
    
    setupLogging(config)

    let success = config.compileFile()
    quit(if success: 0 else: 1)

  of "build", "b":
    var config = if args.len > 1: parseArgs(args[1..^1]) else: parseArgs(@[])
    config.build = true

    if config.inputFile.len == 0:
      echo "Error: No input file specified"
      echo "Usage: granite build <file.hrd> [options]"
      quit(1)

    if config.help:
      showUsage()
      quit(0)

    # Set HARDING_HOME environment for child processes
    putEnv("HARDING_HOME", config.hardingHome)
    
    setupLogging(config)

    let success = config.buildFile()
    quit(if success: 0 else: 1)

  of "run", "r":
    var config = if args.len > 1: parseArgs(args[1..^1]) else: parseArgs(@[])
    config.run = true

    if config.inputFile.len == 0:
      echo "Error: No input file specified"
      echo "Usage: granite run <file.hrd> [options]"
      quit(1)

    if config.help:
      showUsage()
      quit(0)

    # Set HARDING_HOME environment for child processes
    putEnv("HARDING_HOME", config.hardingHome)
    
    setupLogging(config)

    let success = config.runFile()
    quit(if success: 0 else: 1)

  else:
    # Treat as file path for backward compatibility
    if fileExists(command) and command.endsWith(".hrd"):
      var config = if args.len > 1: parseArgs(args[1..^1]) else: parseArgs(@[])
      config.compile = true
      config.inputFile = command

      if config.version:
        showVersion()
        quit(0)

      if config.help:
        showUsage()
        quit(0)

      # Set HARDING_HOME environment for child processes
      putEnv("HARDING_HOME", config.hardingHome)
      
      setupLogging(config)

      let success = config.compileFile()
      quit(if success: 0 else: 1)
    else:
      echo "Unknown command or invalid file: ", command
      echo "Run 'granite --help' for usage"
      quit(1)

when isMainModule:
  main()
