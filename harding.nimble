# Harding - Modern Smalltalk dialect
version = "0.3.0"
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

task install_bona, "Install bona desktop integration (.desktop file and icon)":
  ## Install bona.desktop file and icon to user's local applications directory
  ## This enables proper icon display in Ubuntu dock and Alt-Tab switcher
  let home = getHomeDir()
  let desktopDir = home / ".local/share/applications"
  let iconsDir = home / ".local/share/icons/hicolor/256x256/apps"
  let cwd = getCurrentDir()

  # Create directories using shell commands
  echo "Creating directories..."
  exec "mkdir -p " & (desktopDir).quoteShell()
  exec "mkdir -p " & (iconsDir).quoteShell()

  # Copy .desktop file and update Exec, Path, and StartupWMClass
  echo "Installing bona.desktop..."
  let bonaPath = cwd / "bona"
  exec "cp " & (cwd / "bona.desktop").quoteShell() & " " & (desktopDir / "bona.desktop").quoteShell()
  # Update Exec path to actual binary location
  exec "sed -i 's|Exec=.*|Exec=" & bonaPath & "|g' " & (desktopDir / "bona.desktop").quoteShell()
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

task gui, "Build the GUI IDE with GTK4 (legacy, use 'bona' instead)":
  # Build the GUI IDE with GTK4 (default)
  exec "nim c -d:gtk4 -o:bona src/harding/gui/bona.nim"
  echo "GUI binary available as bona (GTK4)"

task gui3, "Build the GUI IDE with GTK3 (legacy, use 'bona' instead)":
  # Build the GUI IDE with GTK3
  exec "nim c -o:bona src/harding/gui/bona.nim"
  echo "GUI binary available as bona (GTK3)"

task clean, "Clean build artifacts using build.nims":
  exec "nim e build.nims clean"


task vsix, "Build the VS Code extension (vsix file)":
  ## Build the Harding VS Code extension package
  ## Requires vsce to be installed: npm install -g vsce
  if not "package.json".fileExists:
    echo "Error: package.json not found in current directory"
    system.quit(1)
  exec "vsce package"
  echo "VSIX file built successfully"

task js, "Compile Harding interpreter to JavaScript":
  ## Build the Harding interpreter for JavaScript/Node.js
  ## Output: website/dist/harding.js
  exec "nim js -d:js -o:website/dist/harding.js src/harding/repl/hardingjs.nim"
  echo "JavaScript build complete: website/dist/harding.js"

task jsrelease, "Compile optimized JS for production":
  ## Build optimized JavaScript for production
  exec "nim js -d:js -d:release -o:website/dist/harding.js src/harding/repl/hardingjs.nim"
  echo "JavaScript release build complete: website/dist/harding.js"
