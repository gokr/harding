import std/unittest
import ../src/harding/core/types
import ../src/harding/interpreter/vm

suite "Browser deferred callbacks":
  test "dialog validation does not return to a finished home":
    var interp = newInterpreter()
    initGlobals(interp)
    loadStdlib(interp)
    for path in ["lib/gui/bona/Catalog.hrd", "lib/gui/bona/BrowserModel.hrd", "lib/gui/bona/Browser.hrd"]:
      let (_, err) = interp.evalStatements(readFile(path))
      require err.len == 0
    let (_, setupError) = interp.evalStatements("""
      Transcript := Object derive: #().
      Transcript class>>showCr: message [ ].
      CallbackButtons := Table new.
      CallbackInput := nil.
      CallbackRows := nil.
      CallbackWidget := Object derivePublic: #(text, label, callback, rowCallback, closed).
      CallbackWidget>>initialize [ text := "". closed := false ].
      CallbackWidget>>doesNotUnderstand: selector [ ^ self ].
      CallbackWidget class>>vertical [ ^ self new ].
      CallbackWidget class>>horizontal [ ^ self new ].
      CallbackWidget class>>new: title [ ^ self new ].
      CallbackWidget class>>newLabel: title [
        | widget |
        widget := self new.
        widget label: title.
        CallbackButtons at: title put: widget.
        ^ widget
      ].
      CallbackWidget>>placeholderText: value [ CallbackInput := self ].
      CallbackWidget>>clicked: block [ callback := block ].
      CallbackWidget>>onRowSelected: block [ rowCallback := block. CallbackRows := self ].
      CallbackWidget>>close [ closed := true ].
      GtkWindow := CallbackWidget.
      GtkBox := CallbackWidget.
      GtkLabel := CallbackWidget.
      GtkEntry := CallbackWidget.
      GtkButton := CallbackWidget.
      GtkListBox := CallbackWidget.
      CallbackBrowser := Browser derivePublic: #(errorText, selectedLibrary, selectedMixin).
      CallbackBrowser>>showErrorDialog: value [ errorText := value ].
      CallbackBrowser>>populateLibraries [ ].
      CallbackBrowser>>selectLibrary: value [ selectedLibrary := value ].
      CallbackBrowser>>addMixinToClass: name mixinName: value [ selectedMixin := value ].
      CallbackBrowser>>testLibraryPane: widget [ libraryPane := widget ].
      TestBrowser := CallbackBrowser new.
      TestBrowser testLibraryPane: CallbackWidget new.
    """)
    checkpoint setupError
    require setupError.len == 0
    let (libraryResult, libraryError) = interp.doit("""
      TestBrowser showNewLibraryDialog.
      (CallbackButtons at: "Create") callback value.
      EmptyRejected := TestBrowser errorText = "Library name cannot be empty.".
      CallbackInput text: "Core".
      (CallbackButtons at: "Create") callback value.
      EmptyRejected and: [TestBrowser selectedLibrary = "Core"]
    """)
    checkpoint libraryError
    require libraryError.len == 0
    check libraryResult.kind == vkBool
    check libraryResult.boolVal
    let (mixinResult, mixinError) = interp.doit("""
      TestBrowser showAddMixinDialog: "Object".
      (CallbackButtons at: "Add") callback value.
      NoMixin := TestBrowser selectedMixin isNil.
      SelectedRow := CallbackWidget new.
      SelectedRow label: "Comparable".
      CallbackRows rowCallback value: SelectedRow.
      (CallbackButtons at: "Add") callback value.
      NoMixin and: [TestBrowser selectedMixin = "Comparable"]
    """)
    checkpoint mixinError
    require mixinError.len == 0
    check mixinResult.kind == vkBool
    check mixinResult.boolVal
