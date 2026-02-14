# Harding - Modern Smalltalk dialect
version = "0.4.0"
author = "Göran Krampe"
description = "Modern Smalltalk dialect written in Nim"
license = "MIT"

srcDir = "src"
bin = @["harding/repl/harding","harding/compiler/granite"]

# Current Nim version
requires "nim == 2.2.6"

# FFI dependencies
when defined(linux):
  requires "libffi"
when defined(macosx):
  passL "-ldl"

# BitBarrel support (optional)
when defined(bitbarrel):
  requires "whisky >= 0.2.0"

import os, strutils

task test, "Run all tests (automatic discovery via testament)":
  exec """
    echo "Running Harding test suite..."
    echo "=== Running tests/test_*.nim ==="
    testament pattern "tests/test_*.nim" || true
    # echo "=== Running tests/category/*.nim ==="
    # testament pattern "tests/**/*.nim" || true
    # echo "=== Running tests/category/subcategory/*.nim ==="
    # testament pattern "tests/**/**/*.nim" || true
  """

task harding, "Build harding REPL (debug) in repo root":
  # Build REPL in debug mode, output to repo root
  exec "nim c -o:harding src/harding/repl/harding.nim"
  echo "Binary available as ./harding (debug)"

task harding_release, "Build harding REPL (release) in repo root":
  # Build REPL in release mode, output to repo root
  exec "nim c -d:release -o:harding src/harding/repl/harding.nim"
  echo "Binary available as ./harding (release)"

task js, "Compile Harding interpreter to JavaScript":
  # Build JavaScript version for browser embedding
  exec "nim js -d:js -o:website/dist/harding.js src/harding/repl/hardingjs.nim"
  echo "JavaScript build available at website/dist/harding.js"

task bona, "Build bona IDE (debug) in repo root":
  # Build GUI IDE in debug mode with GTK4 (default), output to repo root
  exec "nim c -d:gtk4 -o:bona src/harding/gui/bona.nim"
  echo "Binary available as ./bona (debug)"

task bona_release, "Build bona IDE (release) in repo root":
  # Build GUI IDE in release mode with GTK4, output to repo root
  exec "nim c -d:release -d:gtk4 -o:bona src/harding/gui/bona.nim"
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

task local, "Build and copy binaries to root directory (legacy, use 'harding' instead)":
  # Build REPL and granite compiler directly
  exec "nim c -o:harding src/harding/repl/harding.nim"
  exec "nim c -o:granite src/harding/compiler/granite.nim"
  echo "Binaries available in root directory as harding and granite"

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

task jsrelease, "Compile optimized JS for production":
  ## Build optimized JavaScript for production
  exec "nim js -d:js -d:release -o:website/dist/harding.js src/harding/repl/hardingjs.nim"
  echo "JavaScript release build complete: website/dist/harding.js"

task harding_bitbarrel, "Build harding with BitBarrel support":
  ## Build REPL with BitBarrel database support
  exec "nim c -d:bitbarrel -o:harding src/harding/repl/harding.nim"
  echo "Binary available as ./harding (with BitBarrel support)"

task harding_bitbarrel_release, "Build harding with BitBarrel support (release)":
  ## Build REPL with BitBarrel support in release mode
  exec "nim c -d:bitbarrel -d:release -o:harding src/harding/repl/harding.nim"
  echo "Binary available as ./harding (release with BitBarrel support)"

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
