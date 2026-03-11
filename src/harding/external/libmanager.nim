## ============================================================================
## Library Manager
## Handles installation, metadata refresh, update, and removal of external libs
## ============================================================================

import std/[os, strutils, strformat, times, options, osproc]
import discovery
import generator
import external_libs

const
  ExternalDir = "external"

type
  InstallResult* = enum
    irSuccess
    irAlreadyInstalled
    irNotFound
    irCloneFailed
    irCheckoutFailed
    irNoGit

  RemoveResult* = enum
    rrSuccess
    rrNotInstalled
    rrRemoveFailed

  UpdateResult* = enum
    urSuccess
    urAlreadyLatest
    urNotInstalled
    urUpdateFailed
    urNoRemote

  FetchResult* = enum
    frSuccess
    frNotFound
    frNoGit
    frFetchFailed

proc runGitCommand(args: seq[string], workingDir = ""): tuple[output: string, exitCode: int] =
  var cmd = "git"
  for arg in args:
    cmd.add(" " & arg)

  let actualDir = if workingDir.len > 0: workingDir else: "."
  let prevDir = getCurrentDir()
  try:
    setCurrentDir(actualDir)
    let (output, exitCode) = execCmdEx(cmd)
    return (output: output, exitCode: exitCode)
  except:
    return (output: "", exitCode: 1)
  finally:
    setCurrentDir(prevDir)

proc isGitAvailable*(): bool =
  let (output, exitCode) = runGitCommand(@["--version"])
  exitCode == 0 and output.contains("git version")

proc cloneRepository(url: string, targetDir: string): bool =
  if not dirExists(ExternalDir):
    createDir(ExternalDir)
  let (_, exitCode) = runGitCommand(@["clone", url, targetDir], ".")
  exitCode == 0

proc checkoutVersion(libDir: string, version: string): bool =
  var target = version
  let maybeTag = "v" & version
  let (tagOutput, _) = runGitCommand(@["tag", "-l", maybeTag], libDir)
  if maybeTag in tagOutput:
    target = maybeTag
  let (_, exitCode) = runGitCommand(@["checkout", target], libDir)
  exitCode == 0

proc getCurrentCommit(libDir: string): string =
  let (output, exitCode) = runGitCommand(@["rev-parse", "HEAD"], libDir)
  if exitCode == 0:
    return output.strip()
  ""

proc getLatestTag(libDir: string): string =
  let (output, exitCode) = runGitCommand(@["describe", "--tags", "--abbrev=0"], libDir)
  if exitCode == 0:
    return output.strip().replace("v", "")
  ""

proc fetchUpdates(libDir: string): bool =
  let (_, exitCode) = runGitCommand(@["fetch", "--tags"], libDir)
  exitCode == 0

proc parseLibrarySpec*(spec: string): tuple[name: string, version: string] =
  if "@" in spec:
    let parts = spec.split("@", 1)
    return (name: parts[0].strip(), version: parts[1].strip())
  (name: spec.strip(), version: "")

proc fetchRegistryMetadata(libName: string, url: string): Option[NimbleMetadata] =
  if not isGitAvailable():
    return none(NimbleMetadata)

  let tmpDir = getTempDir() / fmt("harding-registry-{libName}-{epochTime().int}")
  defer:
    if dirExists(tmpDir):
      try:
        removeDir(tmpDir)
      except:
        discard

  let cloneArgs = @[
    "clone", "--depth", "1", "--filter=blob:none", "--sparse", url, tmpDir
  ]
  let (_, cloneExit) = runGitCommand(cloneArgs, ".")
  if cloneExit != 0:
    return none(NimbleMetadata)

  let nimbleName = libName & ".nimble"
  let (_, sparseExit) = runGitCommand(@["sparse-checkout", "set", "--no-cone", nimbleName], tmpDir)
  if sparseExit != 0:
    return none(NimbleMetadata)

  let nimblePath = tmpDir / nimbleName
  if not fileExists(nimblePath):
    return none(NimbleMetadata)

  some(parseNimbleFile(nimblePath))

proc fetchAndCacheRegistryMetadata*(libName: string): FetchResult =
  if not isGitAvailable():
    if isLibraryInstalled(libName):
      let installed = getInstalledLibrary(libName)
      if installed.isSome:
        let info = installed.get()
        cacheLibraryMetadata(libName, info.source, NimbleMetadata(
          version: info.version,
          description: info.description,
          author: info.author,
          requires: info.requires
        ))
        return frSuccess
    return frNoGit

  let url = getLibraryUrl(libName)
  if url.len == 0:
    return frNotFound

  let fetched = fetchRegistryMetadata(libName, url)
  if fetched.isNone:
    if isLibraryInstalled(libName):
      let meta = getNimbleMetadata(ExternalDir / libName)
      if meta.version.len > 0 or meta.description.len > 0 or meta.author.len > 0 or meta.requires.len > 0:
        cacheLibraryMetadata(libName, url, meta)
        return frSuccess
    return frFetchFailed

  cacheLibraryMetadata(libName, url, fetched.get())
  frSuccess

proc fetchAndCacheAllRegistryMetadata*(): seq[tuple[name: string, result: FetchResult]] =
  for item in listRegistryLibraries():
    result.add((name: item.name, result: fetchAndCacheRegistryMetadata(item.name)))

proc installLibrary*(libName: string, version: string = ""): InstallResult =
  if not isGitAvailable():
    return irNoGit
  if isLibraryInstalled(libName):
    return irAlreadyInstalled
  if not isLibraryInRegistry(libName):
    return irNotFound

  let url = getLibraryUrl(libName)
  if url.len == 0:
    return irNotFound

  let installVersion = if version.len > 0: version else: "HEAD"
  echo fmt("Installing {libName}@{installVersion}...")

  let targetDir = ExternalDir / libName
  if not cloneRepository(url, targetDir):
    return irCloneFailed

  if installVersion != "HEAD" and not checkoutVersion(targetDir, installVersion):
    try:
      removeDir(targetDir)
    except:
      discard
    return irCheckoutFailed

  let commit = getCurrentCommit(targetDir)
  let meta = getNimbleMetadata(targetDir)
  let resolvedVersion = if installVersion == "HEAD" and meta.version.len > 0: meta.version else: installVersion
  let info = LibraryInfo(
    name: libName,
    version: resolvedVersion,
    installedAt: now().utc,
    source: url,
    commit: commit,
    description: meta.description,
    author: meta.author,
    requires: meta.requires
  )
  saveLibraryMetadata(targetDir, info)
  cacheLibraryMetadata(libName, url, meta)

  echo "Regenerating library imports..."
  generateExternalLibsFile()
  irSuccess

proc installMultipleLibraries*(specs: seq[string]): seq[tuple[name: string, result: InstallResult]] =
  for spec in specs:
    let parsed = parseLibrarySpec(spec)
    result.add((name: parsed.name, result: installLibrary(parsed.name, parsed.version)))

proc removeLibrary*(libName: string): RemoveResult =
  if not isLibraryInstalled(libName):
    return rrNotInstalled

  try:
    removeDir(ExternalDir / libName)
    echo "Regenerating library imports..."
    generateExternalLibsFile()
    rrSuccess
  except:
    rrRemoveFailed

proc updateLibrary*(libName: string): UpdateResult =
  if not isLibraryInstalled(libName):
    return urNotInstalled

  let libDir = ExternalDir / libName
  if not fetchUpdates(libDir):
    return urNoRemote

  let currentOpt = getInstalledLibrary(libName)
  if currentOpt.isNone:
    return urUpdateFailed
  let current = currentOpt.get()

  var targetVersion = getLatestTag(libDir)
  if targetVersion.len == 0:
    targetVersion = "HEAD"
  if targetVersion == current.version:
    return urAlreadyLatest
  if targetVersion != "HEAD" and not checkoutVersion(libDir, targetVersion):
    return urUpdateFailed

  let meta = getNimbleMetadata(libDir)
  let resolvedVersion = if targetVersion == "HEAD" and meta.version.len > 0: meta.version else: targetVersion
  let updated = LibraryInfo(
    name: libName,
    version: resolvedVersion,
    installedAt: now().utc,
    source: current.source,
    commit: getCurrentCommit(libDir),
    description: meta.description,
    author: meta.author,
    requires: meta.requires
  )
  saveLibraryMetadata(libDir, updated)
  cacheLibraryMetadata(libName, current.source, meta)

  echo "Regenerating library imports..."
  generateExternalLibsFile()
  urSuccess

proc updateAllLibraries*(): seq[tuple[name: string, result: UpdateResult]] =
  for lib in discoverInstalledLibraries():
    result.add((name: lib.name, result: updateLibrary(lib.name)))

proc listAvailableLibraries*() =
  echo ""
  echo "Available libraries from registry:"
  echo ""

  let registry = listRegistryLibraries()
  if registry.len == 0:
    echo "  No libraries in registry."
    return

  for item in registry:
    let installed = getInstalledLibrary(item.name)
    if installed.isSome and installed.get().description.len > 0:
      let info = installed.get()
      let versionText = if info.version.len > 0: " (" & info.version & ")" else: ""
      echo fmt("  {item.name:12} - {info.description}{versionText}")
      if info.author.len > 0:
        echo fmt("               Author: {info.author}")
    else:
      let cached = getCachedLibraryMetadata(item.name)
      if cached.isSome and cached.get().description.len > 0:
        let meta = cached.get()
        let versionText = if meta.version.len > 0: " (" & meta.version & ")" else: ""
        echo fmt("  {item.name:12} - {meta.description}{versionText}")
        if meta.author.len > 0:
          echo fmt("               Author: {meta.author}")
      else:
        echo fmt("  {item.name:12} - {item.url}")

proc listInstalledLibraries*() =
  let libs = discoverInstalledLibraries()
  echo ""
  echo "Installed libraries:"
  echo ""
  if libs.len == 0:
    echo "  No libraries installed."
    echo ""
    echo "  Use 'harding lib list' to see available libraries."
    echo "  Use 'harding lib install <name>' to install a library."
    return

  for lib in libs:
    echo fmt("  {lib.name:12} {lib.version}")
    if lib.description.len > 0:
      echo fmt("               {lib.description}")
    if lib.author.len > 0:
      echo fmt("               Author: {lib.author}")
    echo ""

proc showLibraryInfo*(libName: string) =
  if not isLibraryInRegistry(libName):
    echo fmt("Library '{libName}' not found in registry.")
    return

  let url = getLibraryUrl(libName)
  let installed = getInstalledLibrary(libName)
  let cached = if installed.isSome: none(CachedLibraryMetadata) else: getCachedLibraryMetadata(libName)

  echo ""
  echo fmt("Library: {libName}")
  echo fmt("Repository: {url}")
  if cached.isSome:
    let meta = cached.get()
    if meta.version.len > 0:
      echo fmt("Latest known version: {meta.version}")
    if meta.description.len > 0:
      echo fmt("Description: {meta.description}")
    if meta.author.len > 0:
      echo fmt("Author: {meta.author}")
    if meta.requires.len > 0:
      echo fmt("Requires: {meta.requires.join(\", \")}")
  elif installed.isNone:
    echo "Metadata: not fetched yet"
    echo fmt("Fetch with: harding lib fetch {libName}")

  if installed.isSome:
    let info = installed.get()
    echo ""
    echo "Installed:"
    echo fmt("  Version: {info.version}")
    if info.commit.len >= 8:
      echo fmt("  Commit: {info.commit[0 .. 7]}")
    echo fmt("  Installed: {info.installedAt.format(\"yyyy-MM-dd HH:mm:ss\")}")
  else:
    echo ""
    echo "Not installed."
    echo fmt("Install with: harding lib install {libName}")

proc handleLibListCommand*() =
  listAvailableLibraries()

proc handleLibInstalledCommand*() =
  listInstalledLibraries()

proc handleLibBuiltCommand*() =
  let builtLibs = getBuiltExternalLibraries()
  echo ""
  echo "Libraries built into this Harding binary:"
  echo ""
  if builtLibs.len == 0:
    echo "  No external libraries compiled in."
    return

  for lib in builtLibs:
    echo fmt("  {lib}")

proc handleLibInfoCommand*(libName: string) =
  showLibraryInfo(libName)

proc handleLibFetchCommand*(args: seq[string]) =
  if not isGitAvailable():
    echo "Error: Git is not available. Please install Git to fetch library metadata."
    return

  var results: seq[tuple[name: string, result: FetchResult]] = @[]
  if args.len == 0 or (args.len == 1 and args[0] == "--all"):
    results = fetchAndCacheAllRegistryMetadata()
  else:
    for libName in args:
      results.add((name: libName, result: fetchAndCacheRegistryMetadata(libName)))

  echo ""
  echo "Metadata fetch results:"
  echo ""
  for res in results:
    case res.result:
    of frSuccess:
      echo fmt("  + {res.name} - Metadata updated")
    of frNotFound:
      echo fmt("  ! {res.name} - Not found in registry")
    of frNoGit:
      echo fmt("  ! {res.name} - Git not available")
    of frFetchFailed:
      echo fmt("  ! {res.name} - Metadata fetch failed")

  echo ""
  echo fmt("Cache file: {getRegistryCachePath()}")

proc handleLibInstallCommand*(args: seq[string]) =
  if args.len == 0:
    echo "Error: No library specified."
    echo "Usage: harding lib install <name>[@version] ..."
    return
  if not isGitAvailable():
    echo "Error: Git is not available. Please install Git to use library management."
    return

  let results = installMultipleLibraries(args)
  echo ""
  echo "Installation results:"
  echo ""
  var successCount = 0
  for res in results:
    case res.result:
    of irSuccess:
      echo fmt("  + {res.name} - Installed successfully")
      inc successCount
    of irAlreadyInstalled:
      echo fmt("  = {res.name} - Already installed")
    of irNotFound:
      echo fmt("  ! {res.name} - Not found in registry")
    of irCloneFailed:
      echo fmt("  ! {res.name} - Failed to clone repository")
    of irCheckoutFailed:
      echo fmt("  ! {res.name} - Failed to checkout version")
    of irNoGit:
      echo fmt("  ! {res.name} - Git not available")
  echo ""
  if successCount > 0:
    echo fmt("{successCount} library(s) installed successfully.")
    echo ""
    echo "Next steps:"
    echo "  1. Run 'nimble harding' to rebuild Harding with the new library"
    echo "  2. The library classes will be available in your Harding code"

proc handleLibUpdateCommand*(args: seq[string]) =
  if args.len == 0:
    echo "Error: No library specified."
    echo "Usage: harding lib update <name> | harding lib update --all"
    return
  if not isGitAvailable():
    echo "Error: Git is not available. Please install Git to use library management."
    return

  var results: seq[tuple[name: string, result: UpdateResult]] = @[]
  if args.len == 1 and args[0] == "--all":
    results = updateAllLibraries()
  else:
    for arg in args:
      results.add((name: arg, result: updateLibrary(arg)))

  echo ""
  echo "Update results:"
  echo ""
  for res in results:
    case res.result:
    of urSuccess:
      echo fmt("  + {res.name} - Updated successfully")
    of urAlreadyLatest:
      echo fmt("  = {res.name} - Already at latest version")
    of urNotInstalled:
      echo fmt("  ! {res.name} - Not installed")
    of urUpdateFailed:
      echo fmt("  ! {res.name} - Update failed")
    of urNoRemote:
      echo fmt("  ! {res.name} - Cannot connect to remote")
  echo ""
  echo "Run 'nimble harding' to rebuild with updated libraries."

proc handleLibRemoveCommand*(args: seq[string]) =
  if args.len == 0:
    echo "Error: No library specified."
    echo "Usage: harding lib remove <name> ..."
    return

  echo ""
  echo "Removing libraries:"
  echo ""
  for libName in args:
    case removeLibrary(libName):
    of rrSuccess:
      echo fmt("  + {libName} - Removed successfully")
    of rrNotInstalled:
      echo fmt("  ! {libName} - Not installed")
    of rrRemoveFailed:
      echo fmt("  ! {libName} - Failed to remove")
  echo ""
  echo "Run 'nimble harding' to rebuild without the removed libraries."

proc handleLibCommand*(args: seq[string]) =
  if args.len == 0:
    echo "Library management commands:"
    echo ""
    echo "  harding lib list                  List available libraries"
    echo "  harding lib built                 List libraries built into this binary"
    echo "  harding lib installed             List installed libraries"
    echo "  harding lib info <name>           Show library information"
    echo "  harding lib fetch [name|--all]    Fetch registry metadata"
    echo "  harding lib install <name>[@ver]  Install a library"
    echo "  harding lib update <name>         Update a library"
    echo "  harding lib update --all          Update all libraries"
    echo "  harding lib remove <name>         Remove a library"
    return

  let subcommand = args[0]
  let subargs = if args.len > 1: args[1 .. ^1] else: @[]
  case subcommand
  of "list":
    handleLibListCommand()
  of "installed":
    handleLibInstalledCommand()
  of "built":
    handleLibBuiltCommand()
  of "info":
    if subargs.len == 0:
      echo "Error: No library name specified."
      echo "Usage: harding lib info <name>"
    else:
      handleLibInfoCommand(subargs[0])
  of "install":
    handleLibInstallCommand(subargs)
  of "fetch":
    handleLibFetchCommand(subargs)
  of "update":
    handleLibUpdateCommand(subargs)
  of "remove":
    handleLibRemoveCommand(subargs)
  else:
    echo fmt("Unknown library command: {subcommand}")
    echo "Use 'harding lib' for available commands."
