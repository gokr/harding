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

## Global state for GTK4 application flow
when not defined(gtk3):
  var
    gAppOptions: CliOptions
    gAppInterp: ptr Interpreter
    gAppActivated: bool = false

## Callback for GTK4 application activate signal
when not defined(gtk3):
  proc onAppActivate(app: GtkApplication, userData: pointer) {.cdecl.} =
    ## Called when the application is activated (startup signal has been emitted)
    ## This is where we can safely create windows in GTK4
    debug("GTK4 application activated")
    gAppActivated = true

    # Launch the IDE by calling Launcher open
    let launchCode = "Launcher open"
    let (_, err) = gAppInterp[].evalStatements(launchCode)
    if err.len > 0:
      stderr.writeLine("Error launching IDE: ", err)
      quit(1)

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

  # Set default application icon
  # For GTK4, install icon in user icon theme if file exists, then use icon name
  # For GTK3, can use file path directly
  let logoPath = "website/content/images/harding-simple.png"
  let iconName = "harding"

  when defined(gtk3):
    if fileExists(logoPath):
      let success = setGtkDefaultIcon(logoPath)
      if success:
        debug("Set default application icon from file: ", logoPath)
      else:
        debug("Failed to set default application icon, using fallback")
    else:
      debug("Logo file not found: ", logoPath, ", using default icon")
      discard setGtkDefaultIcon("applications-development")
  else:
    # GTK4: Install icon in user theme directory for development
    let iconDir = getHomeDir() / ".local/share/icons"
    let iconPath48 = iconDir / "hicolor/48x48/apps" / (iconName & ".png")
    let iconPath256 = iconDir / "hicolor/256x256/apps" / (iconName & ".png")

    if fileExists(logoPath):
      createDir(iconDir / "hicolor/48x48/apps")
      createDir(iconDir / "hicolor/256x256/apps")

      if not fileExists(iconPath48):
        copyFile(logoPath, iconPath48)
        debug("Installed 48px icon to: ", iconPath48)

      if not fileExists(iconPath256):
        copyFile(logoPath, iconPath256)
        debug("Installed 256px icon to: ", iconPath256)

      # Note: GTK4 doesn't have gtk_icon_theme_invalidate(), but modern GTK
      # will pick up the icon from the theme directory automatically

      discard setGtkDefaultIcon(iconName)
      debug("Set default application icon name: ", iconName)
    else:
      debug("Logo file not found: ", logoPath, ", using default icon")
      discard setGtkDefaultIcon("applications-development")

  # Load Harding-side GTK wrapper files
  loadGtkWrapperFiles(interp)
  debug("GTK wrapper files loaded")

  # Load IDE tool files
  loadIdeToolFiles(interp)
  debug("IDE tool files loaded")

  # Run GTK main loop
  debug("Starting GTK main loop")

  when not defined(gtk3):
    # GTK4: Create application and run it properly for desktop integration
    let app = gtkApplicationNew("org.harding-lang.bona", GAPPLICATIONFLAGSNONE)
    if app == nil:
      echo "Failed to create GTK application"
      quit(1)

    # Store globals for the activate callback
    gAppOptions = opts
    gAppInterp = addr(interp)

    # Set the global application reference so window creation can use it
    setGtkApplication(app)
    debug("GTK4 application created with ID: org.harding-lang.bona")

    # Connect to the activate signal
    let gObject = cast[GObject](app)
    discard gSignalConnect(gObject, "activate",
                           cast[GCallback](onAppActivate), nil)

    # Run the application - this blocks and runs the main loop
    # The onAppActivate callback will be called where we create the window
    discard gApplicationRun(cast[GApplication](app), 0, nil)
  else:
    # GTK3: Launch IDE and run main loop directly
    let launchCode = "Launcher open"
    let (_, err) = interp.evalStatements(launchCode)
    if err.len > 0:
      stderr.writeLine("Error launching IDE: ", err)
      quit(1)
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
