## Test that simulates Bona's callback pattern
## This test creates a Launcher-like pattern with window tracking

import std/os
import src/harding/core/types
import src/harding/core/scheduler
import src/harding/interpreter/vm
import src/harding/gui/gtk/bridge

proc hasGuiDisplay(): bool =
  existsEnv("DISPLAY") or existsEnv("WAYLAND_DISPLAY")

proc newGuiInterpreter(): Interpreter =
  result = newInterpreter()
  initGlobals(result)
  initProcessorGlobal(result)
  loadStdlib(result)
  initGtkBridge(result)
  loadGtkWrapperFiles(result)

when isMainModule:
  if not hasGuiDisplay():
    echo "Skipping test - no display available"
    quit(0)

  var interp = newGuiInterpreter()

  echo "Testing Bona-style callback pattern..."

  # This test simulates what happens in Bona:
  # 1. Create a Launcher-like object that tracks windows
  # 2. Create a button that opens a "workspace" window
  # 3. The callback needs to access the launcher's methods/slots

  let (result, err) = interp.doit("""
    # Simulate a Workspace window
    TestWindow := Object derive: #(id).
    TestWindow>>initialize [
      id := 0.
      ^ self
    ].
    TestWindow>>id: anId [
      id := anId.
    ].
    TestWindow>>id [
      ^ id
    ].

    # Simulate a Launcher that tracks windows
    Launcher := Object derive: #(windows nextId).
    Launcher>>initialize [
      windows := #().
      nextId := 1.
      ^ self
    ].
    Launcher>>openWindow [
      | w id |
      w := TestWindow new initialize.
      id := self nextWindowId.
      w id: id.
      windows add: w.
      nextId := nextId + 1.
      ^ w
    ].
    Launcher>>nextWindowId [
      ^ nextId
    ].
    Launcher>>getWindowCount [
      ^ windows size
    ].

    # Create launcher
    L := Launcher new initialize.

    # Create a button that opens a window via callback
    Btn := GtkButton newLabel: "Open".
    Btn clicked: [
      L openWindow.
    ].

    # Initially no windows
    InitialCount := L getWindowCount.

    # Trigger callback
    Btn emit: "clicked".
    GtkWidget flushEvents: 5.

    # Check window count after callback
    AfterFirst := L getWindowCount.

    # Trigger again
    Btn emit: "clicked".
    GtkWidget flushEvents: 5.

    AfterSecond := L getWindowCount.

    # Return results
    #(InitialCount AfterFirst AfterSecond)
  """)

  if err.len > 0:
    echo "FAILED: ", err
    quit(1)
  else:
    echo "Result: ", result.toString()
    echo "Test completed"
