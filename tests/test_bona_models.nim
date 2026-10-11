import std/[unittest, os, strutils, tempfiles, tables]

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
  test "Browser rewrite preserves shared files and rejects invalid source":
    var interp = newHeadlessToolInterpreter()
    loadHeadlessToolFile(interp, "lib/gui/bona/Browser.hrd")
    loadHeadlessToolFile(interp, "lib/gui/bona/Transcript.hrd")
    createDir("build")
    let directory = createTempDir("browser-edit-", "", "build")
    defer: removeDir(directory)
    let path = directory / "shared.hrd"
    let original = """# shared file
BrowserEditFoo := Object derive: #().
BrowserEditFoo>>answer [ ^ 1 ]. # keep this
BrowserEditBar := Object derive: #().
BrowserEditBar>>answer [ ^ 2 ].
BrowserEditSentinel := 42.
"""
    writeFile(path, original)
    interp.globals[]["BrowserEditPath"] = toValue(path)
    let (value, err) = interp.doit("""
      EditingBrowser := Browser new.
      EditingBrowser currentClass: "BrowserEditFoo".
      EditingBrowser currentMethodFile: BrowserEditPath.
      EditingBrowser rewriteManagedClassFileWithClassDefinition: nil
        overridingSelector: "answer" methodText: "BrowserEditFoo>>answer [ ^ 3 ]" removeSelector: nil.
      true
    """)
    check(err.len == 0)
    check(value.kind == vkBool)
    check(readFile(path) == original.replace("^ 1", "^ 3"))

    let (rejected, rejectErr) = interp.doit("""
      (EditingBrowser rewriteManagedClassFileWithClassDefinition: nil
        overridingSelector: "answer" methodText: "BrowserEditFoo>>answer [" removeSelector: nil) isNil
    """)
    check(rejectErr.len == 0)
    check(rejected.kind == vkBool)
    check(rejected.boolVal)
    check(readFile(path) == original.replace("^ 1", "^ 3"))

    let (_, deleteErr) = interp.doit("""
      EditingBrowser rewriteManagedClassFileWithClassDefinition: nil
        overridingSelector: nil methodText: nil removeSelector: "answer"
    """)
    check(deleteErr.len == 0)
    check(readFile(path) == original.replace("BrowserEditFoo>>answer [ ^ 1 ]", ""))

  test "default bootstrap loads Granite classes and preserves identity on reload":
    var interp = newHeadlessToolInterpreter()
    let (value, err) = interp.doit("""
      OriginalApplication := Application.
      OriginalGranite := Granite.
      Harding load: "lib/granite/Bootstrap.hrd".
      Application isClass and: [
        Granite isClass and: [
          (Application == OriginalApplication) and: [
            Granite == OriginalGranite
          ]
        ]
      ]
    """)

    check(err.len == 0)
    check(value.kind == vkBool)
    check(value.boolVal)

  test "Granite bootstrap initializes a library containing metadata":
    var interp = newInterpreter()
    initGlobals(interp)
    initProcessorGlobal(interp)
    loadStdlib(interp)
    let (value, err) = interp.doit("""
      (GraniteLibrary at: "__sourceDir") = "lib/granite" and: [
        (GraniteLibrary at: "__initialized") and: [
          (GraniteLibrary at: "Application") isClass and: [
            (GraniteLibrary at: "Granite") isClass
          ]
        ]
      ]
    """)

    check(err.len == 0)
    check(value.kind == vkBool)
    check(value.boolVal)

  test "Transcript retains bounded output while its window is closed":
    var interp = newHeadlessToolInterpreter()
    loadHeadlessToolFile(interp, "lib/gui/bona/Transcript.hrd")
    let (value, err) = interp.doit("""
      Transcript clear.
      Transcript show: "early".
      Transcript cr.
      Transcript showSpace: 42.
      Transcript tab.
      SavedTranscript := Transcript contents.
      Transcript current onDestroy.
      Retained := Transcript contents = SavedTranscript.
      Transcript show: ("x" repeat: 70000).
      Bounded := Transcript contents size = 65536.
      Transcript clear.
      Retained and: [ Bounded and: [ Transcript contents isEmpty ] ]
    """)
    check(err.len == 0)
    check(value.kind == vkBool)
    check(value.boolVal)

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
