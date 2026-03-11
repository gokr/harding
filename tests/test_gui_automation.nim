import std/[unittest, os, tables]

import ../src/harding/core/types
import ../src/harding/core/scheduler
import ../src/harding/interpreter/vm
import ../src/harding/gui/gtk/bridge
import ../src/harding/gui/gtk/widget
import ../src/harding/gui/gtk/popover
import ../src/harding/gui/gtk/ffi

var sharedGuiInterp: Interpreter
var sharedGuiInterpReady = false
var sharedIdeInterp: Interpreter
var sharedIdeInterpReady = false

proc hasGuiDisplay(): bool =
  existsEnv("DISPLAY") or existsEnv("WAYLAND_DISPLAY")

proc newGuiInterpreter(): Interpreter =
  result = newInterpreter()
  initGlobals(result)
  initProcessorGlobal(result)
  loadStdlib(result)
  initGtkBridge(result)
  loadGtkWrapperFiles(result)

proc resetGuiHarnessState() =
  proxyTable.clear()
  pendingGtkCallbacks.setLen(0)
  signalConnectionTable.clear()
  nextSignalConnectionId = 0
  popoverTable.clear()

proc guiInterp(): ptr Interpreter =
  if not sharedGuiInterpReady:
    sharedGuiInterp = newGuiInterpreter()
    sharedGuiInterpReady = true
  resetGuiHarnessState()
  addr(sharedGuiInterp)

proc ideInterp(): ptr Interpreter =
  if not sharedIdeInterpReady:
    sharedIdeInterp = newGuiInterpreter()
    loadIdeToolFiles(sharedIdeInterp)
    sharedIdeInterpReady = true
  resetGuiHarnessState()
  addr(sharedIdeInterp)

proc arrayElements(value: NodeValue): seq[NodeValue] =
  case value.kind
  of vkArray:
    value.arrayVal
  of vkInstance:
    if value.instVal != nil and value.instVal.kind == ikArray:
      value.instVal.elements
    else:
      @[]
  else:
    @[]

suite "GTK automation helpers":
  test "GtkEventController resolves Ctrl+I key":
    if not hasGuiDisplay():
      skip()

    let interp = guiInterp()
    let (result, err) = interp[].doit("""
      GtkEventController key: "i"
    """)

    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 105)

  test "emitSignal drives clicked callbacks":
    if not hasGuiDisplay():
      skip()

    let interp = guiInterp()
    let (result, err) = interp[].doit("""
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

    let interp = guiInterp()
    let (result, err) = interp[].doit("""
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

    let interp = guiInterp()
    let (result, err) = interp[].doit("""
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

  test "clicked callback retains escaped loop captures after setup returns":
    if not hasGuiDisplay():
      skip()

    let interp = guiInterp()
    let (result, err) = interp[].doit("""
      Probe := Object derive: #(buttons results).
      Probe>>initialize [
        buttons := Array new.
        results := Array new.
        ^ self
      ].
      Probe>>setup [
        | i btn |
        i := 0.
        [ i < 3 ] whileTrue: [
          | current |
          current := i.
          btn := GtkButton newLabel: "Run".
          btn clicked: [ results add: current ].
          buttons add: btn.
          i := i + 1.
        ].
        ^ self
      ].
      Probe>>trigger: index [
        | btn |
        btn := buttons at: index.
        btn emit: "clicked".
        GtkWidget flushEvents: 5.
        ^ results
      ].

      P := Probe new initialize.
      P setup.
      P trigger: 1.
      P trigger: 2
    """)

    check(err.len == 0)
    let elems = arrayElements(result)
    check(elems.len == 2)
    check(elems[0].kind == vkInt)
    check(elems[0].intVal == 1)
    check(elems[1].kind == vkInt)
    check(elems[1].intVal == 2)

  test "clicked callback retains nested escaped helper block captures":
    if not hasGuiDisplay():
      skip()

    let interp = guiInterp()
    let (result, err) = interp[].doit("""
      Probe := Object derive: #(button total).
      Probe>>initialize [
        total := 0.
        ^ self
      ].
      Probe>>setup [
        | helper local |
        local := 40.
        helper := [ local := local + 1. total := local ].
        button := GtkButton newLabel: "Run".
        button clicked: [ helper value. helper value ].
        ^ self
      ].
      Probe>>fire [
        button emit: "clicked".
        GtkWidget flushEvents: 5.
        ^ total
      ].

      P := Probe new initialize.
      P setup.
      P fire
    """)

    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 42)

  test "listbox callback retains escaped captures after setup returns":
    if not hasGuiDisplay():
      skip()

    let interp = guiInterp()
    let (result, err) = interp[].doit("""
      Probe := Object derive: #(listBox seen).
      Probe>>initialize [
        seen := Array new.
        ^ self
      ].
      Probe>>setup [
        | helper |
        helper := [:index | seen add: index ].
        listBox := GtkListBox singleSelection.
        listBox append: (GtkLabel new: "One").
        listBox append: (GtkLabel new: "Two").
        listBox append: (GtkLabel new: "Three").
        listBox onRowSelected: [:index | helper value: index ].
        ^ self
      ].
      Probe>>select: index [
        listBox selectIndex: index.
        GtkWidget flushEvents: 5.
        ^ seen
      ].

      P := Probe new initialize.
      P setup.
      P select: 2
    """)

    check(err.len == 0)
    let elems = arrayElements(result)
    check(elems.len > 0)
    check(elems[^1].kind == vkInt)
    check(elems[^1].intVal == 2)

  test "multiple clicked handlers all fire once":
    if not hasGuiDisplay():
      skip()

    let interp = guiInterp()
    let (result, err) = interp[].doit("""
      A := 0.
      B := 0.
      Btn := GtkButton newLabel: "Run".
      Btn clicked: [ A := A + 1 ].
      Btn clicked: [ B := B + 1 ].
      Btn emit: "clicked".
      GtkWidget flushEvents: 5.
      (A * 10) + B
    """)

    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 11)

  test "connect:do: dispatches all handlers for the exact signal":
    if not hasGuiDisplay():
      skip()

    let interp = guiInterp()
    let (result, err) = interp[].doit("""
      A := 0.
      B := 0.
      Btn := GtkButton newLabel: "Run".
      Btn connect: "clicked" do: [ A := A + 1 ].
      Btn connect: "clicked" do: [ B := B + 1 ].
      Btn emit: "clicked".
      GtkWidget flushEvents: 5.
      (A * 10) + B
    """)

    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 11)

  test "deferred GTK callback queue preserves escaped captures":
    let interp = guiInterp()
    let (_, err) = interp[].doit("""
      DeferredResult := 0.
      DeferredBlock := [
        | base |
        base := 40.
        [ DeferredResult := base + 2 ]
      ] value.
    """)

    check(err.len == 0)
    check("DeferredBlock" in interp[].globals[])

    let blockVal = interp[].globals[]["DeferredBlock"]
    check(blockVal.kind == vkBlock)

    enqueueGtkCallback(interp, blockVal.blockVal, @[])
    drainPendingGtkCallbacks(interp)

    let (result, verifyErr) = interp[].doit("""
      DeferredResult
    """)

    check(verifyErr.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 42)

  test "popover item callbacks route to the owning popover":
    if not hasGuiDisplay():
      skip()

    popoverTable.clear()
    let interp = guiInterp()
    let (_, err) = interp[].doit("""
      FirstCount := 0.
      SecondCount := 0.
      BtnOne := GtkButton newLabel: "One".
      BtnTwo := GtkButton newLabel: "Two".
      MenuOne := GtkPopover new: BtnOne.
      MenuTwo := GtkPopover new: BtnTwo.
      MenuOne addItem: "First item" do: [ FirstCount := FirstCount + 1 ].
      MenuTwo addItem: "Second item" do: [ SecondCount := SecondCount + 1 ].
    """)

    check(err.len == 0)
    check(popoverTable.len == 2)

    var targetButton: GtkWidget = nil
    for _, proxy in popoverTable:
      if proxy.menuItems.len == 1 and proxy.menuItems[0].label == "Second item":
        targetButton = proxy.menuItems[0].buttonWidget
        break

    check(targetButton != nil)
    gSignalEmitByName(cast[GObject](targetButton), "clicked")

    let (result, verifyErr) = interp[].doit("""
      (FirstCount * 10) + SecondCount
    """)

    check(verifyErr.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 1)

  test "Browser can open and close through owner callback":
    if not hasGuiDisplay():
      skip()

    let interp = ideInterp()

    let (result, err) = interp[].doit("""
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
      BrowserWindow := Browser openFor: Owner.
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

    let interp = ideInterp()

    let (result, err) = interp[].doit("""
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

    let interp = ideInterp()

    let (result, err) = interp[].doit("""
      TestOwner := Object derive.
      TestOwner>>addWindow: aWindow [ ^ self ].
      TestOwner>>removeWindow: aWindow [ ^ self ].
      Owner := TestOwner new.
      Built := Builder openFor: Owner.
      GtkWidget flushEvents: 5.
      Name := Built className.
      Built onClose.
      Name
    """)

    check(err.len == 0)
    check(result.kind == vkString)
    check(result.strVal == "Builder")

  test "Inspector opens on slotted object":
    if not hasGuiDisplay():
      skip()

    let interp = ideInterp()

    let (result, err) = interp[].doit("""
      Person := Object derive: #(name age).
      Obj := Person new.
      Insp := Inspector openOn: Obj.
      GtkWidget flushEvents: 10.
      Obj slotNames size
    """)

    check(err.len == 0)
    check(result.kind == vkInt)
    check(result.intVal == 2)

  test "Inspector renders nested collections without losing self":
    if not hasGuiDisplay():
      skip()

    let interp = ideInterp()

    let (result, err) = interp[].doit("""
      Obj := #{
        "items" -> #(1 #{"inner" -> 2})
      }.
      Insp := Inspector new initialize.
      Insp inspect: Obj.
      Box := GtkBox vertical.
      Insp renderSlotsOf: Obj atDepth: 0 pathPrefix: "root" into: Box.
      true
    """)

    check(err.len == 0)
    check(result.kind == vkBool)
    check(result.boolVal == true)
