# Nimtalk build script

import os, strutils

# Build the REPL
task "repl", "Build the Nimtalk REPL":
  exec "nimble build"

# Build tests
task "test", "Run tests":
  exec "nimble test"

# Clean build artifacts
task "clean", "Clean build artifacts":
  for dir in ["nimcache", "build"]:
    if dirExists(dir):
      removeDir(dir)
  if fileExists("ntalk"):
    removeFile("ntalk")
  if fileExists("ntalk.exe"):
    removeFile("ntalk.exe")

# Install binary
task "install", "Install Nimtalk":
  var binPath = getCurrentDir() / "ntalk"
  when defined(windows):
    binPath.add(".exe")

  if fileExists(binPath):
    let dest = getHomeDir() / ".local" / "bin" / "ntalk"
    when defined(windows):
      # On Windows, install to a common location
      let winDest = getHomeDir() / "ntalk" / "ntalk.exe"
      createDir(getHomeDir() / "ntalk")
      copyFile(binPath, winDest)
      echo "Installed to: " & winDest
    else:
      copyFile(binPath, dest)
      discard execShellCmd("chmod +x " & dest)
      echo "Installed to: " & dest
  else:
    echo "Error: ntalk binary not found. Run 'nimble build' first."
