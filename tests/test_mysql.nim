## ============================================================================
## MySQL Integration Tests
## Tests for MySQL database integration with Harding
## ============================================================================

when defined(harding_mysql):
  import std/[osproc, strutils, unittest]

  suite "MySQL Integration":
    test "MysqlConnection can be instantiated without explicit bootstrap load":
      let cmd = "./harding -e \"Conn := MysqlConnection new. Conn class name println. Conn isConnected println\""
      let (output, exitCode) = execCmdEx(cmd)
      check exitCode == 0
      check output.contains("MysqlConnection")
      check output.contains("False")

else:
  echo "MySQL tests skipped (compile with -d:harding_mysql)"
