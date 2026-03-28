import std/[unittest]

import ../src/harding/core/types
import ../src/harding/core/scheduler
import ../src/harding/interpreter/vm

proc loadHeadlessToolFile(interp: var Interpreter, relativePath: string) =
  let source = readFile(relativePath)
  let (_, err) = interp.evalStatements(source)
  check(err.len == 0)

proc newHeadlessToolInterpreter(): Interpreter =
  result = newInterpreter()
  initGlobals(result)
  initProcessorGlobal(result)
  loadStdlib(result)

  for path in [
    "lib/gui/bona/Catalog.hrd",
    "lib/gui/bona/BrowserModel.hrd",
    "lib/gui/bona/BuilderModel.hrd",
    "lib/gui/bona/InspectorModel.hrd",
  ]:
    loadHeadlessToolFile(result, path)

suite "Bona headless models":
  test "Catalog lists libraries and resolves Object":
    var interp = newHeadlessToolInterpreter()
    let (result, err) = interp.doit("""
      Cat := Catalog new.
      Names := Cat allLibraryNames.
      HasCore := (Names includes: "Core") or: [ Names includes: "Harding" ].
      Obj := Cat classForName: "Object" currentLibrary: "Core".
      Obj isNil ifTrue: [
        Obj := Cat classForName: "Object" currentLibrary: "Harding"
      ].
      HasCore and: [ Obj notNil ]
    """)

    check(err.len == 0)
    check(result.kind == vkBool)
    check(result.boolVal)

  test "Catalog finds available class names":
    var interp = newHeadlessToolInterpreter()
    let (result, err) = interp.doit("""
      ExistingHeadlessApp := Application derive: #().
      (Catalog new nextAvailableClassNameFrom: "ExistingHeadlessApp") ~= "ExistingHeadlessApp"
    """)

    check(err.len == 0)
    check(result.kind == vkBool)
    check(result.boolVal)

  test "Catalog merges dynamically loaded classes into library views":
    var interp = newHeadlessToolInterpreter()
    let (result, err) = interp.doit("""
      DynamicBrowserProbe := Object derive: #().
      Harding load: "lib/web/Bootstrap.hrd".
      Harding load: "lib/web/todo/Bootstrap.hrd".
      Cat := Catalog new.
      HardingNames := Cat classNamesForLibrary: "Harding".
      WebNames := Cat classNamesForLibrary: "Web".
      WebTodoNames := Cat classNamesForLibrary: "WebTodo".
      (HardingNames includes: "DynamicBrowserProbe") and: [
        (WebNames includes: "Html") and: [
          WebTodoNames includes: "TodoApp"
        ]
      ]
    """)

    check(err.len == 0)
    check(result.kind == vkBool)
    check(result.boolVal)

  test "BrowserModel tracks dirty state and pending selection":
    var interp = newHeadlessToolInterpreter()
    let (result, err) = interp.doit("""
      M := BrowserModel new.
      M currentLibrary: "Core".
      M currentClass: "Object".
      M markSourceClean: "Object".
      M markSourceModified.
      Dirty := M hasUnsavedChangesFor: "Changed".
      M pendingTarget: "String".
      M pendingPrevClass: "Object".
      Dirty and: [
        (M currentLibrary = "Core") and: [
          (M currentClass = "Object") and: [
            (M pendingTarget = "String") and: [ M pendingPrevClass = "Object" ]
          ]
        ]
      ]
    """)

    check(err.len == 0)
    check(result.kind == vkBool)
    check(result.boolVal)

  test "InspectorModel tracks selection and expansion":
    var interp = newHeadlessToolInterpreter()
    let (result, err) = interp.doit("""
      M := InspectorModel new.
      Obj := #("one", "two").
      M inspect: Obj.
      M togglePath: "root.[0]".
      M selectValue: 42 name: "answer".
      Expanded := M expandedPaths at: "root.[0]" ifAbsent: [ false ].
      Expanded and: [
        (M workspaceLabelText includesSubString: "answer") and: [
          (M formatValue: Obj) = "Array(2)"
        ]
      ]
    """)

    check(err.len == 0)
    check(result.kind == vkBool)
    check(result.boolVal)

  test "BuilderModel discovers application subclasses":
    var interp = newHeadlessToolInterpreter()
    let (result, err) = interp.doit("""
      HeadlessBuilderApp := Application derive: #().
      M := BuilderModel new.
      Apps := M findApplicationSubclasses.
      Found := false.
      Apps do: [:each |
        ((each name asString) = "HeadlessBuilderApp") ifTrue: [
          Found := true
        ]
      ].
      Found and: [ (M uniqueAppName: "HeadlessBuilderApp") ~= "HeadlessBuilderApp" ]
    """)

    check(err.len == 0)
    check(result.kind == vkBool)
    check(result.boolVal)
