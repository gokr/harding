## ============================================================================
## Nemo IDE - Main entry point
## Initializes the interpreter, loads GTK bridge, and launches the IDE
## ============================================================================

import std/[os, strutils, logging, tables]
import nemo/core/types
import nemo/core/scheduler
import nemo/interpreter/evaluator
import nemo/interpreter/objects
import nemo/repl/doit
import nemo/gui/gtk4/bridge
import nemo/gui/gtk4/ffi
import nemo/gui/gtk4/widget

## Version constant
const VERSION* = "0.1.0"

proc showUsage() =
  echo "Nemo IDE - GTK-based graphical IDE"
  echo ""
  echo "Usage:"
  echo "  nemo-ide [options]                # Start the IDE"
  echo "  nemo-ide --help                   # Show this help"
  echo "  nemo-ide --version                # Show version"
  echo ""
  echo "Options:"
  echo "  --loglevel <level>  Set log level: DEBUG, INFO, WARN, ERROR (default: ERROR)"
  echo ""

proc parseLogLevel(levelStr: string): Level =
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

proc runIde*(logLevel: Level = lvlError) =
  ## Main IDE entry point - initializes interpreter and launches IDE

  echo "Starting Nemo IDE..."
  debug("Initializing Nemo IDE")

  # Create scheduler context (this also initializes the interpreter)
  var ctx = newSchedulerContext()
  var interp = cast[Interpreter](ctx.mainProcess.interpreter)

  debug("Scheduler context created")

  # Initialize GTK bridge
  initGtkBridge(interp)
  debug("GTK bridge initialized")

  # Load Nemo-side GTK wrapper files
  loadGtkWrapperFiles(interp)
  debug("GTK wrapper files loaded")

  # Load IDE tool files
  loadIdeToolFiles(interp)
  debug("IDE tool files loaded")

  # Run GTK main loop
  debug("Starting GTK main loop")
  when defined(gtk4):
    # GTK4 uses GApplication with proper lifecycle
    let app = gtkApplicationNew("org.nemo.ide", GAPPLICATIONFLAGSNONE)

    # Store the application reference for window creation
    setGtkApplication(app)

    # Connect activate signal - this is where we create/show the window
    proc activateCallback(app: GApplication; data: pointer) {.cdecl.} =
      debug("GTK application activated")
      let interpPtr = cast[ptr Interpreter](data)
      # Launch the IDE by calling Launcher open
      let launchCode = "Launcher open"
      let (_, err) = interpPtr[].evalStatements(launchCode)
      if err.len > 0:
        stderr.writeLine("Error launching IDE: ", err)
        quit(1)

    discard g_signal_connect_data(app, "activate", cast[GCallback](activateCallback), cast[pointer](addr(interp)), nil, 0)

    discard gApplicationRun(cast[GApplication](app), 0, nil)
  else:
    # GTK3 uses gtk_main - simpler approach
    # Launch the IDE by calling Launcher open
    let launchCode = "Launcher open"
    let (_, err) = interp.evalStatements(launchCode)
    if err.len > 0:
      stderr.writeLine("Error launching IDE: ", err)
      quit(1)
    gtkMain()

  debug("GTK main loop exited")

proc main() =
  ## Main entry point

  # Default log level
  var logLevel = lvlError

  # Parse command line arguments
  let allArgs = commandLineParams()
  var i = 0
  while i < allArgs.len:
    case allArgs[i]
    of "--help", "-h":
      showUsage()
      quit(0)
    of "--version", "-v":
      echo "Nemo IDE ", VERSION
      quit(0)
    of "--loglevel":
      if i + 1 < allArgs.len:
        logLevel = parseLogLevel(allArgs[i + 1])
        inc i
      else:
        echo "Error: --loglevel requires a value"
        quit(1)
    else:
      echo "Unknown option: ", allArgs[i]
      showUsage()
      quit(1)
    inc i

  # Configure logging
  var consoleLogger = newConsoleLogger()
  consoleLogger.levelThreshold = logLevel
  addHandler(consoleLogger)

  # Run the IDE
  runIde(logLevel)

# Entry point
when isMainModule:
  main()
