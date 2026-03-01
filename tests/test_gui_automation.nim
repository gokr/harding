import std/[unittest, os]

import ../src/harding/core/types
import ../src/harding/core/scheduler
import ../src/harding/interpreter/vm
import ../src/harding/gui/gtk/bridge

proc hasGuiDisplay(): bool =
  existsEnv("DISPLAY") or existsEnv("WAYLAND_DISPLAY")

proc newGuiInterpreter(): Interpreter =
  result = newInterpreter()
  initGlobals(result)
  initProcessorGlobal(result)
  loadStdlib(result)
  initGtkBridge(result)
  loadGtkWrapperFiles(result)

suite "GTK automation helpers":
  test "emitSignal drives clicked callbacks":
    if not hasGuiDisplay():
      skip()

    var interp = newGuiInterpreter()
    let (result, err) = interp.doit("""
      Clicked := false.
      Btn := GtkButton newLabel: "Run".
      Btn clicked: [ Clicked := true ].
      Btn emit: "clicked".
      GtkWidget flushEvents: 5.
      Clicked
    """)

    check(err.len == 0)
    check(result.kind == vkBool)
    check(result.boolVal == true)

  test "Browser can open and close through owner callback":
    if not hasGuiDisplay():
      skip()

    var interp = newGuiInterpreter()
    loadIdeToolFiles(interp)

    let (result, err) = interp.doit("""
      TestOwner := Object derive: #(removed).
      TestOwner>>initialize [
        removed := false.
        ^ self
      ].
      TestOwner>>addWindow: aWindow [
        ^ self
      ].
      TestOwner>>removeWindow: aWindow [
        removed := true.
        ^ self
      ].
      TestOwner>>isRemoved [
        ^ removed
      ].

      Owner := TestOwner new initialize.
      BrowserWindow := SystemBrowser openFor: Owner.
      GtkWidget flushEvents: 10.
      BrowserWindow close.
      GtkWidget flushEvents: 20.
      Owner isRemoved
    """)

    check(err.len == 0)
    check(result.kind == vkBool)
    check(result.boolVal == true)
