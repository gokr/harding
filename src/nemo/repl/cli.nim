## ============================================================================
## Nemo CLI - Shared command-line utilities for REPL and IDE
## ============================================================================

import std/[os, strutils, logging]

# Version constant - shared across all entry points
const VERSION* = block:
  const nimblePath = currentSourcePath().parentDir().parentDir().parentDir().parentDir() / "nemo.nimble"
  const nimbleContent = staticRead(nimblePath)
  var versionStr = "unknown"
  for line in nimbleContent.splitLines():
    let trimmed = line.strip()
    if trimmed.startsWith("version"):
      let parts = trimmed.split("=")
      if parts.len >= 2:
        versionStr = parts[1].strip().strip(chars={'"', '\''})
        break
  versionStr

# Default configuration
const
  DefaultNemoHome* = "."
  DefaultBootstrapFile* = "lib/core/Bootstrap.nemo"
  DefaultLogLevel* = Level.lvlError
  DefaultStackDepth* = 10000

type
  CliOptions* = object
    ## Common CLI options shared between REPL and IDE
    logLevel*: Level
    dumpAst*: bool
    maxStackDepth*: int
    nemoHome*: string
    bootstrapFile*: string
    positionalArgs*: seq[string]

proc parseLogLevel*(levelStr: string): Level =
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

proc parseCliOptions*(allArgs: seq[string], appName: string, appDesc: string,
                     extraOptions: proc(): string = nil): CliOptions =
  ## Parse common CLI options from command line arguments
  result = CliOptions(
    logLevel: DefaultLogLevel,
    dumpAst: false,
    maxStackDepth: DefaultStackDepth,
    nemoHome: getEnv("NEMO_HOME", DefaultNemoHome),
    bootstrapFile: "",
    positionalArgs: @[]
  )

  var i = 0
  while i < allArgs.len:
    case allArgs[i]
    of "--loglevel":
      if i + 1 < allArgs.len:
        result.logLevel = parseLogLevel(allArgs[i + 1])
        inc i
      else:
        echo "Error: --loglevel requires a value"
        quit(1)
    of "--stack-depth":
      if i + 1 < allArgs.len:
        try:
          result.maxStackDepth = parseInt(allArgs[i + 1])
          if result.maxStackDepth < 100:
            echo "Error: --stack-depth must be at least 100"
            quit(1)
        except ValueError:
          echo "Error: --stack-depth requires an integer value"
          quit(1)
        inc i
      else:
        echo "Error: --stack-depth requires a value"
        quit(1)
    of "--home":
      if i + 1 < allArgs.len:
        result.nemoHome = allArgs[i + 1]
        inc i
      else:
        echo "Error: --home requires a value"
        quit(1)
    of "--bootstrap":
      if i + 1 < allArgs.len:
        result.bootstrapFile = allArgs[i + 1]
        inc i
      else:
        echo "Error: --bootstrap requires a value"
        quit(1)
    of "--ast":
      result.dumpAst = true
    of "--help", "-h", "--version", "-v", "--test":
      result.positionalArgs.add(allArgs[i])
    else:
      result.positionalArgs.add(allArgs[i])
    inc i

  # If no bootstrap file specified, use default relative to NEMO_HOME
  if result.bootstrapFile.len == 0:
    result.bootstrapFile = result.nemoHome / DefaultBootstrapFile

proc showUsage*(appName: string, appDesc: string, examples: seq[string] = @[],
               extraOptions: string = "") =
  ## Show usage information
  echo appDesc
  echo ""
  echo "Usage:"
  echo "  ", appName, " [options]                    # Start interactively"
  if appName == "nemo":
    echo "  ", appName, " [options] <file.nemo>      # Run script file"
    echo "  ", appName, " [options] -e \"<code>\"      # Evaluate expression"
  echo "  ", appName, " --help                       # Show this help"
  echo "  ", appName, " --version                    # Show version"
  echo ""
  echo "Options:"
  echo "  --home <path>      Set NEMO_HOME directory (default: current directory)"
  echo "  --bootstrap <file> Use custom bootstrap file (default: lib/core/Bootstrap.nemo)"
  echo "  --loglevel <level> Set log level: DEBUG, INFO, WARN, ERROR (default: ERROR)"
  echo "  --stack-depth <n>  Set maximum stack depth (default: 10000)"
  if appName == "nemo":
    echo "  --ast              Dump AST after parsing and continue execution"
  if extraOptions.len > 0:
    echo extraOptions
  echo ""
  echo "Environment Variables:"
  echo "  NEMO_HOME          Default home directory for loading libraries"
  echo ""
  if examples.len > 0:
    echo "Examples:"
    for example in examples:
      echo "  ", example
    echo ""

proc setupLogging*(logLevel: Level) =
  ## Configure logging with specified level
  var consoleLogger = newConsoleLogger()
  consoleLogger.levelThreshold = logLevel
  addHandler(consoleLogger)

proc resolvePath*(nemoHome: string, path: string): string =
  ## Resolve a path relative to NEMO_HOME if it's not absolute
  if path.isAbsolute:
    return path
  else:
    return nemoHome / path
