## ============================================================================
## BitBarrel Integration Tests
## Tests for BitBarrel database integration with Harding
## ============================================================================

when defined(harding_bitbarrel):
  import std/[osproc, strutils, unittest]

  suite "BitBarrel Integration":
    test "external BitBarrel classes load in harding":
      let cmd = "./harding -e \"Barrel class name println. BarrelTable class name println. BarrelSortedTable class name println\""
      let (output, exitCode) = execCmdEx(cmd)
      check exitCode == 0
      check output.contains("Barrel")
      check output.contains("BarrelTable")
      check output.contains("BarrelSortedTable")

else:
  echo "BitBarrel tests skipped (compile with -d:harding_bitbarrel)"
