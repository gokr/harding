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
  test "GtkEventController resolves Ctrl+I key":
    if not hasGuiDisplay():
      skip()

    var interp = newGuiInterpreter()
    let (result, err) = interp.doit("""
      GtkEventController key: "i"
    """)

    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 105)

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

  test "clicked callback resolves method-local class":
    if not hasGuiDisplay():
      skip()

    var interp = newGuiInterpreter()
    let (result, err) = interp.doit("""
      Captured := nil.
      LocalClass := Object derive.
      Btn := GtkButton newLabel: "Run".
      Btn clicked: [
        Captured := LocalClass name.
      ].
      Btn emit: "clicked".
      GtkWidget flushEvents: 5.
      Captured
    """)

    check(err.len == 0)
    check(result.kind == vkString)
    check(result.strVal == "LocalClass")

  test "clicked callback resolves class via Harding at:":
    if not hasGuiDisplay():
      skip()

    var interp = newGuiInterpreter()
    let (result, err) = interp.doit("""
      Captured := nil.
      Btn := GtkButton newLabel: "Run".
      Btn clicked: [
        | cls |
        cls := Harding at: "Object".
        Captured := cls name.
      ].
      Btn emit: "clicked".
      GtkWidget flushEvents: 5.
      Captured
    """)

    check(err.len == 0)
    check(result.kind == vkString)
    check(result.strVal == "Object")

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

  test "method returns self after listbox callback fires":
    if not hasGuiDisplay():
      skip()

    var interp = newGuiInterpreter()
    loadIdeToolFiles(interp)

    let (result, err) = interp.doit("""
      Probe := Object derive.
      Probe>>run [
        | pane |
        pane := BrowserPane new.
        pane createWidgets.
        pane onSelectionChanged: [:item | self className ].
        pane items: #("One" "Two").
        GtkWidget flushEvents: 10.
        ^ self
      ].

      Obj := Probe new.
      Res := Obj run.
      Res className
    """)

    check(err.len == 0)
    check(result.kind == vkString)
    check(result.strVal == "Probe")

  test "Builder openFor returns Builder instance":
    if not hasGuiDisplay():
      skip()

    var interp = newGuiInterpreter()
    loadIdeToolFiles(interp)

    let (result, err) = interp.doit("""
      TestOwner := Object derive.
      TestOwner>>addWindow: aWindow [ ^ self ].
      Owner := TestOwner new.
      Built := Builder openFor: Owner.
      GtkWidget flushEvents: 5.
      Built className
    """)

    check(err.len == 0)
    check(result.kind == vkString)
    check(result.strVal == "Builder")

  test "Inspector opens on slotted object":
    if not hasGuiDisplay():
      skip()

    var interp = newGuiInterpreter()
    loadIdeToolFiles(interp)

    let (result, err) = interp.doit("""
      Person := Object derive: #(name age).
      Obj := Person new.
      Insp := Inspector openOn: Obj.
      GtkWidget flushEvents: 10.
      Obj slotNames size
    """)

    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 2)
