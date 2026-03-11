## ============================================================================
## External Libraries Integration
## Tracked wrapper around a machine-local generated file
## ============================================================================

import std/os

const GeneratedExternalLibsFile = currentSourcePath().parentDir / "external_libs_generated.nim"
const HasGeneratedExternalLibs = staticExec("test -f \"" & GeneratedExternalLibsFile & "\" && printf 1 || printf 0") == "1"

when HasGeneratedExternalLibs:
  include external_libs_generated
else:
  import ../core/types
  import discovery

  proc installExternalLibraries*(interp: var Interpreter) =
    ## Install all discovered and enabled external libraries.
    ##
    ## This proc is called by loadStdlib after the standard library is loaded.
    ## Each library is conditionally compiled based on whether it's installed
    ## and enabled via compile flags.
    let installedLibs = discoverInstalledLibraries()
    discard installedLibs
    debug("No external libraries found in external/")

  proc getExternalCompileFlags*(): string =
    ## Get compile flags for all installed external libraries.
    ##
    ## This is used by the build system to automatically enable
    ## all installed libraries when compiling Harding.
    var flags: seq[string] = @[]
    discard flags
    return ""

  proc getBuiltExternalLibraries*(): seq[string] =
    ## Get the external libraries compiled into the current binary.
    @[]
