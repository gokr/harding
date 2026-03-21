# Harding - Modern Smalltalk dialect
version = "0.8.0"
author = "Göran Krampe"
description = "Modern Smalltalk dialect written in Nim"
license = "MIT"

srcDir = "src"

# Add external directory to Nim search path
--path:"external"

# Current Nim version
requires "nim == 2.2.6"

# FFI dependencies
when defined(linux):
  requires "libffi"

# MummyX HTTP server support (compile with -d:mummyx to enable)
requires "mummy >= 0.4.6"

import os, strutils, sequtils

const ExternalLibsGeneratedFile = "src/harding/external/external_libs_generated.nim"

# Helper proc to get external library compile flags
proc getExternalLibFlags(): string =
  var flags: seq[string] = @[]
  if dirExists("external"):
    for kind, path in walkDir("external"):
      if kind == pcDir:
        let libName = lastPathPart(path)
        let metadataFile = path / ".harding-lib.json"
        if fileExists(metadataFile):
          flags.add("-d:harding_" & libName)
  return flags.join(" ")

proc parseNimbleRequires(nimblePath: string): seq[string] =
  if not fileExists(nimblePath):
    return @[]

  for line in readFile(nimblePath).splitLines():
    let trimmed = line.strip()
    if not trimmed.startsWith("requires "):
      continue

    let firstQuote = trimmed.find('"')
    if firstQuote < 0:
      continue
    let secondQuote = trimmed.find('"', firstQuote + 1)
    if secondQuote <= firstQuote:
      continue

    let spec = trimmed[(firstQuote + 1) ..< secondQuote]
    var pkgName = spec.splitWhitespace()[0]
    if pkgName.startsWith("https://") or pkgName.startsWith("http://"):
      let parts = pkgName.split("/")
      if parts.len > 0:
        pkgName = parts[^1]
        if pkgName.endsWith(".git"):
          pkgName = pkgName[0 .. ^5]
    if pkgName.len > 0:
      result.add(pkgName)

proc addDependencyPath(pkgName: string, pathFlags: var seq[string], seen: var seq[string]) =
  if pkgName in seen:
    return

  seen.add(pkgName)

  let pkgPathOutput = staticExec("nimble path " & pkgName).strip()
  var pkgPath = ""
  for line in pkgPathOutput.splitLines():
    let candidate = line.strip()
    if candidate.len > 0 and dirExists(candidate):
      pkgPath = candidate

  if pkgPath.len == 0:
    return

  pathFlags.add("-p:" & pkgPath.quoteShell())

  let nimbleFile = pkgPath / (pkgName & ".nimble")
  if not fileExists(nimbleFile):
    return

  for depName in parseNimbleRequires(nimbleFile):
    addDependencyPath(depName, pathFlags, seen)

proc getExternalDependencyPaths(): string =
  var pathFlags: seq[string] = @[]
  var seen: seq[string] = @[]

  if not dirExists("external"):
    return ""

  for kind, path in walkDir("external"):
    if kind != pcDir:
      continue

    let libName = lastPathPart(path)
    let metadataFile = path / ".harding-lib.json"
    let nimbleFile = path / (libName & ".nimble")
    if not fileExists(metadataFile) or not fileExists(nimbleFile):
      continue

    for pkgName in parseNimbleRequires(nimbleFile):
      addDependencyPath(pkgName, pathFlags, seen)

  return pathFlags.join(" ")

proc ensureExternalLibsFile() =
  if fileExists(ExternalLibsGeneratedFile):
    return

  echo "Generated external library integration file is missing; running nimble discover..."
  exec "nim c -r src/harding/external/generator.nim"

task discover, "Scan external/ and regenerate external_libs_generated.nim":
  ## Discover installed libraries and regenerate the import file
  exec "nim c -r src/harding/external/generator.nim"

proc addUniqueDir(path: string, dirs: var seq[string]) =
  if path.len == 0 or not dirExists(path):
    return
  let normalized = absolutePath(path)
  if normalized notin dirs:
    dirs.add(normalized)

proc getExternalTestRoots(): seq[string] =
  ## Collect roots that may contain installed external libraries.
  ## Libraries are installed under external/ relative to the current Harding home.
  addUniqueDir("external", result)
  let hardingHome = getEnv("HARDING_HOME", "")
  if hardingHome.len > 0:
    addUniqueDir(hardingHome / "external", result)

proc getExternalTestPatterns(): string =
  ## Collect test patterns from external libraries
  ## Convention: external library tests live in <lib>/tests/test_*.nim
  var patterns: seq[string] = @[]
  for root in getExternalTestRoots():
    for kind, path in walkDir(root):
      if kind != pcDir:
        continue
      let metadataFile = path / ".harding-lib.json"
      let testDir = path / "tests"
      if fileExists(metadataFile) and dirExists(testDir):
        patterns.add(testDir / "test_*.nim")
  return patterns.join(" ")

# Test groups - defined as test sets
const TestCore = """
tests/test_interpreter_core.nim
tests/test_precedence.nim
tests/test_primitives.nim
tests/test_exception_handling.nim
tests/test_closures.nim
tests/test_scheduler_complete.nim
tests/test_sync_primitives.nim
tests/test_tagged.nim
tests/test_vm_regressions.nim
tests/test_nil_conditionals.nim
tests/test_dynamic_features.nim
tests/test_literals.nim
tests/test_slot_ivars.nim
tests/test_extend.nim
tests/test_cascade.nim
tests/test_float_operations.nim
tests/test_class_model.nim
"""

const TestStdlib = """
tests/test_stdlib_basics.nim
tests/test_stdlib_strings.nim
tests/test_stdlib_collections.nim
tests/test_stdlib_intervals.nim
tests/test_stdlib_io_and_packages.nim
tests/test_stdlib_utilities.nim
tests/test_set_operations.nim
tests/test_json_literal.nim
tests/test_json_serialization.nim
"""

const TestOther = """
tests/test_compiler_basic.nim
tests/test_compiler_block_parity.nim
tests/test_website_examples.nim
tests/test_cli_args.nim
tests/test_bona_models.nim
tests/test_gui_automation.nim
tests/test_html_canvas.nim
tests/test_html2_dyn_cache.nim
tests/test_web_html_template_cache.nim
tests/test_signal_point_debugging.nim
tests/test_bitbarrel.nim
"""

task test, "Run all tests including external libraries":
  ## Run tests from tests/ and installed external library repos.
  ## External library tests follow convention: <lib>/tests/test_*.nim
  ensureExternalLibsFile()
  let externalTestPatterns = getExternalTestPatterns()
  exec """
    echo "Running Harding test suite..."
    echo "=== Running core tests/test_*.nim ==="
    testament pattern "tests/test_*.nim" || true
  """
  if externalTestPatterns.len > 0:
    exec """
      echo "=== Running external library tests ==="
      testament pattern """ & externalTestPatterns & """ || true
    """
  else:
    echo "No external library tests found."

task testRelease, "Run all tests compiled in release mode (faster execution)":
  ## Compile and run all tests in release mode for faster execution
  ensureExternalLibsFile()
  let externalTestPatterns = getExternalTestPatterns()
  exec """
    echo "Running Harding test suite (release mode)..."
    echo "=== Running core tests/test_*.nim (release) ==="
    testament pattern "tests/test_*.nim" --nim:"nim c -d:release" || true
  """
  if externalTestPatterns.len > 0:
    exec """
      echo "=== Running external library tests (release) ==="
      testament pattern """ & externalTestPatterns & """ --nim:"nim c -d:release" || true
    """
  else:
    echo "No external library tests found."

proc runTestGroup(groupName: string, testFiles: string, releaseMode: bool = false) =
  let modeFlag = if releaseMode: " --nim:\"nim c -d:release\"" else: ""
  let modeName = if releaseMode: " (release)" else: ""
  echo "Running Harding " & groupName & " tests" & modeName & "..."
  for file in testFiles.splitWhitespace():
    echo "  Running: " & file
    exec "testament pattern " & file & modeFlag & " || true"

task testCore, "Run core VM and language tests only":
  ## Run core Harding tests (VM, interpreter, language features)
  runTestGroup("core", TestCore, false)

task testCoreRelease, "Run core VM and language tests in release mode":
  ## Run core tests compiled in release mode for faster execution
  runTestGroup("core", TestCore, true)

task testStdlib, "Run standard library tests only":
  ## Run stdlib tests (collections, strings, intervals, I/O, etc.)
  runTestGroup("stdlib", TestStdlib, false)

task testStdlibRelease, "Run standard library tests in release mode":
  ## Run stdlib tests compiled in release mode for faster execution
  runTestGroup("stdlib", TestStdlib, true)

task testOther, "Run compiler, IDE, and integration tests":
  ## Run compiler, GUI, and other integration tests
  runTestGroup("other", TestOther, false)

task testOtherRelease, "Run compiler, IDE, and integration tests in release mode":
  ## Run other tests compiled in release mode for faster execution
  runTestGroup("other", TestOther, true)

task harding, "Build harding REPL (debug) in repo root":
  # Build REPL in debug mode, output to repo root, with external libraries
  ensureExternalLibsFile()
  let externalFlags = getExternalLibFlags()
  let dependencyPaths = getExternalDependencyPaths()
  exec "nim c -p:external " & dependencyPaths & " " & externalFlags & " -o:harding src/harding/repl/harding.nim"
  echo "Binary available as ./harding (debug)"

task harding_release, "Build harding REPL (release) in repo root":
  # Build REPL in release mode, output to repo root, with external libraries
  ensureExternalLibsFile()
  let externalFlags = getExternalLibFlags()
  let dependencyPaths = getExternalDependencyPaths()
  exec "nim c -p:external " & dependencyPaths & " -d:release " & externalFlags & " -o:harding src/harding/repl/harding.nim"
  echo "Binary available as ./harding (release)"

task bona, "Build bona IDE (debug) in repo root":
  # Build GUI IDE in debug mode with GTK4 + Granite primitives, output to repo root
  ensureExternalLibsFile()
  let externalFlags = getExternalLibFlags()
  let dependencyPaths = getExternalDependencyPaths()
  exec "nim c -p:external " & dependencyPaths & " -d:gtk4 -d:granite " & externalFlags & " -o:bona src/harding/gui/bona.nim"
  echo "Binary available as ./bona (debug)"

task bona_release, "Build bona IDE (release) in repo root":
  # Build GUI IDE in release mode with GTK4 + Granite primitives, output to repo root
  ensureExternalLibsFile()
  let externalFlags = getExternalLibFlags()
  let dependencyPaths = getExternalDependencyPaths()
  exec "nim c -p:external " & dependencyPaths & " -d:release -d:gtk4 -d:granite " & externalFlags & " -o:bona src/harding/gui/bona.nim"
  echo "Binary available as ./bona (release)"

task install_bona, "Install bona binary and desktop integration (.desktop file and icon)":
  ## Install bona binary to ~/.local/bin and install .desktop file + icon
  ## This enables running bona from anywhere and proper icon display in dock
  let home = getHomeDir()
  let desktopDir = home / ".local/share/applications"
  let iconsDir = home / ".local/share/icons/hicolor/256x256/apps"
  when defined(windows):
    let binDir = home / "bin"
  else:
    let binDir = home / ".local/bin"
  let cwd = getCurrentDir()

  # Create directories using shell commands
  echo "Creating directories..."
  exec "mkdir -p " & desktopDir.quoteShell()
  exec "mkdir -p " & iconsDir.quoteShell()
  exec "mkdir -p " & binDir.quoteShell()

  # Install bona binary
  let bonaSource = cwd / "bona"
  let bonaDest = binDir / "bona"
  if not fileExists(bonaSource):
    echo "Error: bona binary not found. Run 'nimble bona' first."
    system.quit(1)
  echo "Installing bona binary to " & bonaDest & "..."
  exec "cp " & bonaSource.quoteShell() & " " & bonaDest.quoteShell()
  when not defined(windows):
    exec "chmod +x " & bonaDest.quoteShell()

  # Copy .desktop file and update Exec, Path, and StartupWMClass
  echo "Installing bona.desktop..."
  exec "cp " & (cwd / "bona.desktop").quoteShell() & " " & (desktopDir / "bona.desktop").quoteShell()
  # Update Exec path to installed binary location
  exec "sed -i 's|Exec=.*|Exec=" & bonaDest & "|g' " & (desktopDir / "bona.desktop").quoteShell()
  # Update Path to repo root so bona can find lib/core/Bootstrap.hrd
  exec "sed -i 's|Path=.*|Path=" & cwd & "|g' " & (desktopDir / "bona.desktop").quoteShell()
  # Update StartupWMClass to match the application ID (org.harding-lang.bona)
  exec "sed -i 's|StartupWMClass=.*|StartupWMClass=org.harding-lang.bona|g' " & (desktopDir / "bona.desktop").quoteShell()

  # Copy icon if available
  let iconSource = cwd / "website/content/images/harding-simple.png"
  echo "Installing harding icon..."
  exec "cp " & iconSource.quoteShell() & " " & (iconsDir / "harding.png").quoteShell() & " || echo 'Icon not found, skipping'"

  # Update desktop database
  echo "Updating desktop database..."
  exec "update-desktop-database " & desktopDir.quoteShell() & " 2>/dev/null || true"

  echo ""
  echo "Bona desktop integration installed successfully!"
  echo "You may need to log out and back in for the icon to appear in the applications menu."

task bona_gtk3, "Build the GUI IDE with GTK3 (legacy, use 'bona' instead)":
  # Build the GUI IDE with GTK3
  exec "nim c -o:bona src/harding/gui/bona.nim"
  echo "GUI binary available as bona (GTK3)"

task install_harding, "Install harding binary to user's bin directory":
  ## Install harding binary to ~/.local/bin (Unix/Linux/macOS) or appropriate Windows location
  let home = getHomeDir()
  when defined(windows):
    let binDir = home / "bin"
  else:
    let binDir = home / ".local/bin"

  # Create directory using shell command (createDir not available in NimScript)
  echo "Creating " & binDir & "..."
  exec "mkdir -p " & binDir.quoteShell()

  # Copy binary
  let cwd = getCurrentDir()
  let sourcePath = cwd / "harding"
  let destPath = binDir / "harding"

  if not fileExists(sourcePath):
    echo "Error: harding binary not found. Run 'nimble harding' first."
    system.quit(1)

  echo "Copying harding binary to " & destPath & "..."
  exec "cp " & sourcePath.quoteShell() & " " & destPath.quoteShell()
  when not defined(windows):
    # Make executable on Unix
    exec "chmod +x " & destPath.quoteShell()
  echo "harding installed successfully to " & binDir

task clean, "Clean build artifacts using build.nims":
  exec "nim e build.nims clean"


task vsix, "Build the VS Code extension (vsix file)":
  ## Build the Harding VS Code extension package with LSP and DAP support
  ## Requires vsce to be installed: npm install -g vsce
  let extDir = "vscode-harding"
  if not (extDir / "package.json").fileExists:
    echo "Error: package.json not found in " & extDir
    system.quit(1)

  # Build harding-lsp first
  echo "Building Harding Language Server..."
  exec "nim c -o:harding-lsp src/harding/lsp/main.nim"

  # Install npm dependencies and compile TypeScript
  echo "Installing extension dependencies..."
  exec "cd " & extDir & " && npm install"
  echo "Compiling TypeScript..."
  exec "cd " & extDir & " && npm run compile"

  # Package the extension
  echo "Packaging extension..."
  exec "cd " & extDir & " && vsce package"
  echo "VSIX file built successfully in " & extDir

task harding_mummyx, "Build harding with MummyX HTTP server support":
  ## Build REPL with MummyX HTTP/WebSocket server support
  ensureExternalLibsFile()
  let externalFlags = getExternalLibFlags()
  let dependencyPaths = getExternalDependencyPaths()
  exec "nim c -p:external " & dependencyPaths & " -d:mummyx --threads:on --mm:orc " & externalFlags & " -o:harding src/harding/repl/harding.nim"
  echo "Binary available as ./harding (with MummyX support)"

task harding_mummyx_release, "Build harding with MummyX support (release)":
  ## Build REPL with MummyX support in release mode
  ensureExternalLibsFile()
  let externalFlags = getExternalLibFlags()
  let dependencyPaths = getExternalDependencyPaths()
  exec "nim c -p:external " & dependencyPaths & " -d:mummyx -d:release --threads:on --mm:orc " & externalFlags & " -o:harding src/harding/repl/harding.nim"
  echo "Binary available as ./harding (release with MummyX support)"

task bona_mummyx, "Build bona IDE with MummyX support (debug)":
  ## Build GUI IDE with GTK4 and MummyX HTTP server support
  ensureExternalLibsFile()
  let externalFlags = getExternalLibFlags()
  let dependencyPaths = getExternalDependencyPaths()
  exec "nim c -p:external " & dependencyPaths & " -d:gtk4 -d:granite -d:mummyx --threads:on --mm:orc " & externalFlags & " -o:bona src/harding/gui/bona.nim"
  echo "Binary available as ./bona (with MummyX support)"

task bona_mummyx_release, "Build bona IDE with MummyX support (release)":
  ## Build GUI IDE with GTK4 and MummyX support in release mode
  ensureExternalLibsFile()
  let externalFlags = getExternalLibFlags()
  let dependencyPaths = getExternalDependencyPaths()
  exec "nim c -p:external " & dependencyPaths & " -d:gtk4 -d:granite -d:mummyx -d:release --threads:on --mm:orc " & externalFlags & " -o:bona src/harding/gui/bona.nim"
  echo "Binary available as ./bona (release with MummyX support)"

task harding_debug, "Build harding with debugger support":
  ## Build REPL with debugger support for VSCode integration
  exec "nim c -d:debugger -o:harding_debug src/harding/repl/harding.nim"
  echo "Binary available as ./harding_debug (with debugger support)"
  echo "Run with: ./harding_debug --debugger-port 9877 script.hrd"

task harding_lsp, "Build Harding Language Server":
  ## Build LSP server for VSCode integration
  exec "nim c -o:harding-lsp src/harding/lsp/main.nim"
  echo "Binary available as ./harding-lsp"
  echo "Usage: harding-lsp --stdio"

task harding_perf, "Build harding optimized for perf profiling":
  ## Build REPL with release optimizations and debug info for perf/FlameGraph profiling
  exec "nim c -d:release --debuginfo --lineDir:on -o:harding_perf src/harding/repl/harding.nim"
  echo "Binary: ./harding_perf"
  echo "Usage: perf record -F 99 --call-graph dwarf ./harding_perf script.hrd"
  echo "       perf report --stdio"
  echo "FlameGraph: perf script | /tmp/FlameGraph/stackcollapse-perf.pl | /tmp/FlameGraph/flamegraph.pl > flame.svg"

task harding_nimprof, "Build harding with built-in Nim profiler":
  ## Build REPL with Nim's embedded stack trace profiler (outputs profile_results.txt on exit)
  exec "nim c --profiler:on --stacktrace:on --lineDir:on -o:harding_nimprof src/harding/repl/harding.nim"
  echo "Binary: ./harding_nimprof"
  echo "Usage: ./harding_nimprof script.hrd"
  echo "       cat profile_results.txt"

task profile_nimprof, "Build and run nimprof on the sieve benchmark":
  ## Build with nimprof and run benchmark/sieve.hrd, then print profile_results.txt
  exec "nim c --profiler:on --stacktrace:on --lineDir:on -o:harding_nimprof src/harding/repl/harding.nim"
  exec "./harding_nimprof benchmark/sieve.hrd"
  exec "cat profile_results.txt"

task profile_perf, "Build and run perf on the sieve benchmark (outputs perf.data)":
  ## Build release+debuginfo binary and record a perf profile of benchmark/sieve.hrd
  ## Results are in perf.data; view with: perf report --stdio   or   perf report (TUI)
  exec "nim c -d:release --debuginfo --lineDir:on -o:harding_perf src/harding/repl/harding.nim"
  exec "perf record -F 99 --call-graph dwarf -o perf.data ./harding_perf benchmark/sieve.hrd"
  exec "perf report --stdio --no-children -n | head -60"
  echo ""
  echo "Full report: perf report --stdio"
  echo "Interactive: perf report"
  echo "FlameGraph:"
  echo "  git clone https://github.com/brendangregg/FlameGraph /tmp/FlameGraph"
  echo "  perf script | /tmp/FlameGraph/stackcollapse-perf.pl | /tmp/FlameGraph/flamegraph.pl > flame.svg"
