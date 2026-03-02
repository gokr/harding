## ============================================================================
## BitBarrel Bridge Initialization
## Registers all BitBarrel wrapper classes with Harding globals
## ============================================================================

when defined(bitbarrel):
  import std/[tables, strutils, os]
  import ../core/types
  import ../interpreter/objects
  import ../interpreter/vm
  import ./barrel
  import ./barrel_table
  import ./barrel_sorted_table

  ## Forward declarations
  proc loadBitBarrelFiles*(interp: var Interpreter, basePath: string = "")

  ## Initialize BitBarrel and register all BitBarrel classes
  proc initBitBarrelBridge*(interp: var Interpreter) =
    ## Initialize BitBarrel bridge - call this before using any BitBarrel functionality
    debug("Initializing BitBarrel bridge...")

    # Initialize Barrel management class
    initBarrelClass(interp)
    debug("Barrel class initialized")

    # Initialize BarrelTable class
    initBarrelTableClass(interp)
    debug("BarrelTable class initialized")

    # Initialize BarrelSortedTable class
    initBarrelSortedTableClass(interp)
    debug("BarrelSortedTable class initialized")

    debug("BitBarrel bridge initialization complete")

  ## Load Harding-side BitBarrel wrapper files
  proc loadBitBarrelFiles*(interp: var Interpreter, basePath: string = "") =
    ## Load the Harding-side BitBarrel wrapper classes from lib/bitbarrel/
    let libPath = if basePath.len > 0: basePath / "lib" / "bitbarrel" else: "lib" / "bitbarrel"

    debug("Loading BitBarrel files from: ", libPath)

    let bitbarrelFiles = [
      "Bootstrap.hrd"
    ]

    for filename in bitbarrelFiles:
      let filepath = libPath / filename
      if fileExists(filepath):
        debug("Loading BitBarrel file: ", filepath)
        let source = readFile(filepath)
        let (_, err) = interp.evalStatements(source)
        if err.len > 0:
          warn("Failed to load ", filepath, ": ", err)
        else:
          debug("Successfully loaded: ", filepath)
      else:
        debug("BitBarrel file not found (optional): ", filepath)

else:
  # Stub implementations when BitBarrel is not enabled
  import ../core/types
  import ../interpreter/objects

  proc initBitBarrelBridge*(interp: var Interpreter) =
    ## Stub - BitBarrel support not compiled in
    debug("BitBarrel support not enabled (compile with -d:bitbarrel)")

  proc loadBitBarrelFiles*(interp: var Interpreter, basePath: string = "") =
    ## Stub - BitBarrel support not compiled in
    discard
