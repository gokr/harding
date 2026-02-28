import std/[unittest, os, osproc, strutils]

var cachedHardingBin = ""

proc shellQuote(s: string): string =
  "\"" & s.replace("\"", "\\\"") & "\""

proc ensureHardingBinary(): string =
  if cachedHardingBin.len > 0 and fileExists(cachedHardingBin):
    return cachedHardingBin

  let repoRoot = getCurrentDir()
  let rootBinary = repoRoot / "harding"
  if fileExists(rootBinary):
    cachedHardingBin = rootBinary
    return cachedHardingBin

  let tempBinary = getTempDir() / "harding_cli_args_test_bin"
  let sourcePath = repoRoot / "src" / "harding" / "repl" / "harding.nim"
  let buildCmd = "nim c -o:" & shellQuote(tempBinary) & " " & shellQuote(sourcePath)
  let buildRun = execCmdEx(buildCmd, workingDir = repoRoot)
  check(buildRun.exitCode == 0)
  if buildRun.exitCode != 0:
    check(buildRun.output.len == 0)
    return ""

  cachedHardingBin = tempBinary
  return cachedHardingBin

suite "CLI args forwarding":
  test "script receives args after --":
    let binPath = ensureHardingBinary()
    check(binPath.len > 0)
    if binPath.len > 0:
      let repoRoot = getCurrentDir()
      let scriptPath = getTempDir() / "harding_cli_args_script.hrd"
      defer:
        if fileExists(scriptPath):
          removeFile(scriptPath)

      writeFile(scriptPath, """
        Stdout writeline: (System arguments at: 0).
        Stdout writeline: (System arguments at: 1).
      """)

      let runCmd = shellQuote(binPath) &
                   " --home " & shellQuote(repoRoot) &
                   " " & shellQuote(scriptPath) &
                   " -- one two"
      let run = execCmdEx(runCmd, workingDir = repoRoot)
      check(run.exitCode == 0)
      check("one" in run.output)
      check("two" in run.output)

  test "-e mode receives args after --":
    let binPath = ensureHardingBinary()
    check(binPath.len > 0)
    if binPath.len > 0:
      let repoRoot = getCurrentDir()
      let runCmd = shellQuote(binPath) &
                   " --home " & shellQuote(repoRoot) &
                   " -e \"System arguments size\" -- red blue green"
      let run = execCmdEx(runCmd, workingDir = repoRoot)
      check(run.exitCode == 0)
      check(run.output.strip() == "3")
