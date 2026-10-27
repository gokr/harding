import std/[unittest, os]
import ../src/harding/core/types
import ../src/harding/interpreter/vm
import ./stdlib_test_support

var interp = newSharedStdlibInterpreter()
let root = currentSourcePath().parentDir.parentDir
let (_, sourceError) = interp.evalStatements(readFile(root / "demos/native-gtk-counter/counter_model.hrd"))
doAssert sourceError.len == 0, sourceError
let (_, viewError) = interp.evalStatements("""
CounterView>>text: value [ LastText := value. ^ self ].
Model := CounterModel new startOn: CounterView new.
Increment := Model incrementAction.
Reset := Model resetAction.
""")
doAssert viewError.len == 0, viewError

suite "Native GTK demo Harding model in the interpreter":
  test "starts at zero and formats the view":
    let (value, error) = interp.doit("Model count = 0 and: [LastText = \"Count: 0\"]")
    require error.len == 0
    check value.boolVal

  test "retained action blocks update the same model and view":
    let (value, error) = interp.doit("Increment value. Increment value. Model count = 2 and: [LastText = \"Count: 2\"]")
    require error.len == 0
    check value.boolVal

  test "reset and reuse preserve receiver identity":
    let (value, error) = interp.doit("Reset value. Increment value. Model count = 1 and: [LastText = \"Count: 1\"]")
    require error.len == 0
    check value.boolVal

  test "deliberate action error is catchable and later actions still work":
    let (value, error) = interp.doit("Caught := [Model failingAction value] on: Error do: [:ex | ex message]. Increment value. Caught = \"Deliberate callback failure\" and: [Model count = 2]")
    require error.len == 0
    check value.boolVal
