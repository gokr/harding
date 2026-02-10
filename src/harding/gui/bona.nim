## ============================================================================
## Bonadventure IDE - Main entry point
## Initializes the interpreter, loads GTK bridge, and launches the IDE
## ============================================================================

import std/[os, logging]
import harding/core/types
import harding/core/scheduler
import harding/interpreter/vm
import harding/repl/cli
import harding/gui/gtk/bridge
import harding/gui/gtk/ffi

const
  AppName = "bona"
  AppDesc = "Bonadventure IDE - GTK-based graphical IDE"

proc runIde*(opts: CliOptions) =
  ## Main IDE entry point - initializes interpreter and launches IDE

  echo "Starting Bonadventure IDE..."
  debug("Initializing Bonadventure IDE")

  # Set HARDING_HOME environment
  putEnv("HARDING_HOME", opts.hardingHome)

  # Create scheduler context (this also initializes the interpreter)
  var ctx = newSchedulerContext()
  var interp = cast[Interpreter](ctx.mainProcess.interpreter)

  # Set hardingHome on the interpreter
  interp.hardingHome = opts.hardingHome

  debug("Scheduler context created")

  # Load standard library
  loadStdlib(interp, opts.bootstrapFile)
  debug("Standard library loaded")

  # Initialize GTK bridge
  initGtkBridge(interp)
  debug("GTK bridge initialized")

  # Set default application icon from project logo if available
  let logoPath = "website/content/images/harding-simple.png"
  if fileExists(logoPath):
    let success = setGtkDefaultIcon(logoPath)
    if success:
      debug("Set default application icon: ", logoPath)
    else:
      debug("Failed to set default application icon, using fallback")
  else:
    debug("Logo file not found: ", logoPath)

  # Load Harding-side GTK wrapper files
  loadGtkWrapperFiles(interp)
  debug("GTK wrapper files loaded")

  # Load IDE tool files
  loadIdeToolFiles(interp)
  debug("IDE tool files loaded")

  # Run GTK main loop
  debug("Starting GTK main loop")

  # Launch the IDE by calling Launcher open
  let launchCode = "Launcher open"
  let (_, err) = interp.evalStatements(launchCode)
  if err.len > 0:
    stderr.writeLine("Error launching IDE: ", err)
    quit(1)

  when not defined(gtk3):
    # GTK4: run the GLib main loop to process events
    while true:
      discard gMainContextIteration(nil, 1.cint)
  else:
    gtkMain()

  debug("GTK main loop exited")

proc main() =
  ## Main entry point

  # Parse command line arguments
  let opts = parseCliOptions(commandLineParams(), AppName, AppDesc)

  # Handle help and version first
  if opts.positionalArgs.len == 1:
    case opts.positionalArgs[0]:
    of "--help", "-h":
      showUsage(AppName, AppDesc)
      quit(0)
    of "--version", "-v":
      echo "Bonadventure IDE ", VERSION
      quit(0)

  # Configure logging
  setupLogging(opts.logLevel)

  # Run the IDE
  runIde(opts)

# Entry point
when isMainModule:
  main()
