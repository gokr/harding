import std/[unittest, tables]
import ../src/harding/core/types
import ../src/harding/interpreter/vm
import ../src/harding/gui/gtk/[application_backend, interpreted_application]

var interp = newInterpreter()
initGlobals(interp)
interp.hardingHome = "."
loadStdlib(interp)
registerGtkApplication(interp)

proc noDispatch(receiver: NodeValue, selector: string, args: seq[NodeValue]): NodeValue =
  nilValue()

suite "Shared GTK application backend":
  test "bad arguments are rejected before crossing the C ABI":
    let cls = interp.globals[]["GtkBox"]
    expect ValueError:
      discard gtkCall(cls, "newOrientation:spacing:", @[toValue(2), toValue(0)], noDispatch, initTable[string, Class]())
    expect ValueError:
      discard gtkCall(cls, "newOrientation:spacing:", @[toValue("horizontal"), toValue(0)], noDispatch, initTable[string, Class]())
    expect ValueError:
      discard gtkCall(cls, "newOrientation:spacing:", @[], noDispatch, initTable[string, Class]())
    expect ValueError:
      discard gtkCall(cls, "marginTop:", @[toValue(-1)], noDispatch, initTable[string, Class]())
    check gtkResourceCounts() == (0, 0, false)

  test "activation blocks must match the void callback ABI":
    let (callback, error) = interp.doit("[:argument | argument]")
    require error.len == 0
    expect ValueError:
      discard gtkCall(interp.globals[]["GtkApplication"], "run:activate:",
        @[toValue("org.hardinglang.BadCallback"), callback], noDispatch, initTable[string, Class]())
    check gtkResourceCounts() == (0, 0, false)

  test "application IDs are validated before allocation":
    let (callback, error) = interp.doit("[]")
    require error.len == 0
    for id in ["invalid", "", "org.hardinglang.Bad\0suffix"]:
      expect ValueError:
        discard gtkCall(interp.globals[]["GtkApplication"], "run:activate:",
          @[toValue(id), callback], noDispatch, initTable[string, Class]())
    check gtkResourceCounts() == (0, 0, false)

  test "same Harding protocol updates widgets and releases connections on every run":
    for iteration in 0..<3:
      let (_, error) = interp.evalStatements("""
        GtkApplication run: "org.hardinglang.GtkBackendTest" activate: [
          | window box label button clicks |
          clicks := 0.
          window := GtkWindow title: "Backend test" width: 240 height: 120.
          box := (GtkBox column: 8) padding: 12.
          label := GtkLabel text: "zero".
          button := GtkButton primary: "Increment" action: [
            clicks := clicks + 1. label text: clicks printString
          ].
          box add: label. box add: button.
          window child: box.
          button emitSignal: "clicked". button emitSignal: "clicked".
          LastText := label text.
          SavedLabel := label.
          GtkApplication quit
        ]
      """)
      require error.len == 0
      check interp.globals[]["LastText"].strVal == "2"
      check gtkResourceCounts() == (0, 0, false)
      expect ValueError:
        discard gtkCall(interp.globals[]["SavedLabel"], "text", @[], noDispatch, initTable[string, Class]())

  test "activation failure cannot hang the event loop or retain widget callbacks":
    let (status, error) = interp.doit("GtkApplication run: \"org.hardinglang.ActivationFailure\" activate: [Error signal: \"activation failure\"]")
    require error.len == 0
    check status.intVal == 1
    check gtkResourceCounts() == (0, 0, false)

  test "invalid signal signatures are rejected and cleanup still completes":
    let (status, error) = interp.doit("GtkApplication run: \"org.hardinglang.BadSignal\" activate: [(GtkButton new) connect: \"notify\" do: []]")
    require error.len == 0
    check status.intVal == 1
    check gtkResourceCounts() == (0, 0, false)
