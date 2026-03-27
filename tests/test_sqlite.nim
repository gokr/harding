## ============================================================================
## SQLite Integration Tests
## Tests for SQLite database integration with Harding
## ============================================================================

when defined(harding_sqlite):
  import std/[osproc, strutils, unittest]

  suite "SQLite Integration":
    test "SqliteConnection can be instantiated without explicit bootstrap load":
      let cmd = "./harding -e \"Conn := SqliteConnection new. Conn class name println. Conn isConnected println\""
      let (output, exitCode) = execCmdEx(cmd)
      check exitCode == 0
      check output.contains("SqliteConnection")
      check output.contains("False")

    test "SqliteConnection supports in-memory queries":
      let cmd = "./harding external/sqlite/tests/sqlite_roundtrip.hrd"
      let (output, exitCode) = execCmdEx(cmd)
      check exitCode == 0
      check output.contains("2")
      check output.contains("Grace=>1337")
      check output.contains("Ada=>1200")

else:
  echo "SQLite tests skipped (compile with -d:harding_sqlite)"
