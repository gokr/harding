# begin Nimble config (version 2)
when withDir(thisDir(), system.fileExists("nimble.paths")):
  include "nimble.paths"
# end Nimble config

# Try pure ARC (no cycle detection)
switch("mm", "arc")
# switch("mm", "orc")

# Add src to path for proper module resolution
switch("path", "src")
