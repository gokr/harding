## ============================================================================
## GTK4 Bridge Initialization
## Registers all GTK wrapper classes with Harding globals
## ============================================================================

import std/[logging, os, tables]
import harding/core/types
import harding/interpreter/objects
import harding/interpreter/vm
import ./ffi
import ./widget
import ./window
import ./button
import ./box
when defined(gtk3):
  import ./menubar
  import ./menu
  import ./menuitem
import ./textview
import ./textbuffer
import ./label

## Forward declarations
proc initGtkBridge*(interp: var Interpreter)
proc loadGtkWrapperFiles*(interp: var Interpreter, basePath: string = "")
proc loadIdeToolFiles*(interp: var Interpreter, basePath: string = "")
proc setGtkApplication*(app: GtkApplication)
proc getGtkApplication*(): GtkApplication

## Global GTK application reference (for GTK4)
var gtkApp* {.global.}: GtkApplication = nil

proc setGtkApplication*(app: GtkApplication) =
  gtkApp = app

proc getGtkApplication*(): GtkApplication =
  gtkApp

## Forward declaration for launcher new implementation
proc launcherNewImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.cdecl.}

## Initialize GTK and register all GTK classes
proc initGtkBridge*(interp: var Interpreter) =
  ## Initialize GTK bridge - call this before using any GTK functionality
  debug("Initializing GTK bridge...")

  # Initialize GTK (if not already initialized)
  initGtk()
  debug("GTK initialized")

  # Create and register GTK wrapper classes
  # These are the Nim-side classes that will be derived from in Harding

  # Create Widget class (base class for all GTK widgets)
  let widgetCls = newClass(superclasses = @[objectClass], name = "GtkWidget")
  widgetCls.tags = @["GTK", "Widget"]
  widgetCls.isNimProxy = true
  widgetCls.hardingType = "GtkWidget"

  # Add Widget methods
  let widgetShowMethod = createCoreMethod("show")
  widgetShowMethod.nativeImpl = cast[pointer](widgetShowImpl)
  widgetShowMethod.hasInterpreterParam = true
  addMethodToClass(widgetCls, "show", widgetShowMethod)

  let widgetHideMethod = createCoreMethod("hide")
  widgetHideMethod.nativeImpl = cast[pointer](widgetHideImpl)
  widgetHideMethod.hasInterpreterParam = true
  addMethodToClass(widgetCls, "hide", widgetHideMethod)

  let widgetSetSizeRequestMethod = createCoreMethod("setSizeRequest:")
  widgetSetSizeRequestMethod.nativeImpl = cast[pointer](widgetSetSizeRequestImpl)
  widgetSetSizeRequestMethod.hasInterpreterParam = true
  addMethodToClass(widgetCls, "setSizeRequest:", widgetSetSizeRequestMethod)

  let widgetAddCssClassMethod = createCoreMethod("addCssClass:")
  widgetAddCssClassMethod.nativeImpl = cast[pointer](widgetAddCssClassImpl)
  widgetAddCssClassMethod.hasInterpreterParam = true
  addMethodToClass(widgetCls, "addCssClass:", widgetAddCssClassMethod)

  let widgetRemoveCssClassMethod = createCoreMethod("removeCssClass:")
  widgetRemoveCssClassMethod.nativeImpl = cast[pointer](widgetRemoveCssClassImpl)
  widgetRemoveCssClassMethod.hasInterpreterParam = true
  addMethodToClass(widgetCls, "removeCssClass:", widgetRemoveCssClassMethod)

  let widgetConnectDoMethod = createCoreMethod("connect:do:")
  widgetConnectDoMethod.nativeImpl = cast[pointer](widgetConnectDoImpl)
  widgetConnectDoMethod.hasInterpreterParam = true
  addMethodToClass(widgetCls, "connect:do:", widgetConnectDoMethod)

  interp.globals[]["GtkWidget"] = widgetCls.toValue()
  debug("Registered GtkWidget class")

  # Create Window class
  let windowCls = newClass(superclasses = @[widgetCls], name = "GtkWindow")
  windowCls.tags = @["GTK", "Window"]
  windowCls.isNimProxy = true
  windowCls.hardingType = "GtkWindow"

  # Add Window class methods (new)
  let windowNewMethod = createCoreMethod("new")
  windowNewMethod.nativeImpl = cast[pointer](windowNewImpl)
  windowNewMethod.hasInterpreterParam = true
  addMethodToClass(windowCls, "new", windowNewMethod, isClassMethod = true)

  # Add Window instance methods
  let windowSetTitleMethod = createCoreMethod("title:")
  windowSetTitleMethod.nativeImpl = cast[pointer](windowSetTitleImpl)
  windowSetTitleMethod.hasInterpreterParam = true
  addMethodToClass(windowCls, "title:", windowSetTitleMethod)

  let windowSetDefaultSizeMethod = createCoreMethod("setDefaultSize:height:")
  windowSetDefaultSizeMethod.nativeImpl = cast[pointer](windowSetDefaultSizeImpl)
  windowSetDefaultSizeMethod.hasInterpreterParam = true
  addMethodToClass(windowCls, "setDefaultSize:height:", windowSetDefaultSizeMethod)

  let windowSetChildMethod = createCoreMethod("setChild:")
  windowSetChildMethod.nativeImpl = cast[pointer](windowSetChildImpl)
  windowSetChildMethod.hasInterpreterParam = true
  addMethodToClass(windowCls, "setChild:", windowSetChildMethod)

  let windowPresentMethod = createCoreMethod("present")
  windowPresentMethod.nativeImpl = cast[pointer](windowPresentImpl)
  windowPresentMethod.hasInterpreterParam = true
  addMethodToClass(windowCls, "present", windowPresentMethod)

  let windowCloseMethod = createCoreMethod("close")
  windowCloseMethod.nativeImpl = cast[pointer](windowCloseImpl)
  windowCloseMethod.hasInterpreterParam = true
  addMethodToClass(windowCls, "close", windowCloseMethod)

  let windowConnectDestroyMethod = createCoreMethod("connectDestroy")
  windowConnectDestroyMethod.nativeImpl = cast[pointer](windowConnectDestroyImpl)
  windowConnectDestroyMethod.hasInterpreterParam = true
  addMethodToClass(windowCls, "connectDestroy", windowConnectDestroyMethod)

  let windowDestroyedMethod = createCoreMethod("destroyed:")
  windowDestroyedMethod.nativeImpl = cast[pointer](windowDestroyedImpl)
  windowDestroyedMethod.hasInterpreterParam = true
  addMethodToClass(windowCls, "destroyed:", windowDestroyedMethod)

  interp.globals[]["GtkWindow"] = windowCls.toValue()
  debug("Registered GtkWindow class")

  # Create Button class
  let buttonCls = newClass(superclasses = @[widgetCls], name = "GtkButton")
  buttonCls.tags = @["GTK", "Button"]
  buttonCls.isNimProxy = true
  buttonCls.hardingType = "GtkButton"

  # Add Button class methods
  let buttonNewMethod = createCoreMethod("new")
  buttonNewMethod.nativeImpl = cast[pointer](buttonNewImpl)
  buttonNewMethod.hasInterpreterParam = true
  addMethodToClass(buttonCls, "new", buttonNewMethod, isClassMethod = true)

  let buttonNewLabelMethod = createCoreMethod("newLabel:")
  buttonNewLabelMethod.nativeImpl = cast[pointer](buttonNewLabelImpl)
  buttonNewLabelMethod.hasInterpreterParam = true
  addMethodToClass(buttonCls, "newLabel:", buttonNewLabelMethod, isClassMethod = true)

  # Add Button instance methods
  let buttonSetLabelMethod = createCoreMethod("label:")
  buttonSetLabelMethod.nativeImpl = cast[pointer](buttonSetLabelImpl)
  buttonSetLabelMethod.hasInterpreterParam = true
  addMethodToClass(buttonCls, "label:", buttonSetLabelMethod)

  let buttonGetLabelMethod = createCoreMethod("label")
  buttonGetLabelMethod.nativeImpl = cast[pointer](buttonGetLabelImpl)
  buttonGetLabelMethod.hasInterpreterParam = true
  addMethodToClass(buttonCls, "label", buttonGetLabelMethod)

  let buttonClickedMethod = createCoreMethod("clicked:")
  buttonClickedMethod.nativeImpl = cast[pointer](buttonClickedImpl)
  buttonClickedMethod.hasInterpreterParam = true
  addMethodToClass(buttonCls, "clicked:", buttonClickedMethod)

  interp.globals[]["GtkButton"] = buttonCls.toValue()
  debug("Registered GtkButton class")

  # Create Box class
  let boxCls = newClass(superclasses = @[widgetCls], name = "GtkBox")
  boxCls.tags = @["GTK", "Box", "Layout"]
  boxCls.isNimProxy = true
  boxCls.hardingType = "GtkBox"

  # Add Box class methods
  let boxNewMethod = createCoreMethod("new")
  boxNewMethod.nativeImpl = cast[pointer](boxNewImpl)
  boxNewMethod.hasInterpreterParam = true
  addMethodToClass(boxCls, "new", boxNewMethod, isClassMethod = true)

  let boxHorizontalMethod = createCoreMethod("horizontal")
  boxHorizontalMethod.nativeImpl = cast[pointer](boxHorizontalImpl)
  boxHorizontalMethod.hasInterpreterParam = true
  addMethodToClass(boxCls, "horizontal", boxHorizontalMethod, isClassMethod = true)

  let boxVerticalMethod = createCoreMethod("vertical")
  boxVerticalMethod.nativeImpl = cast[pointer](boxVerticalImpl)
  boxVerticalMethod.hasInterpreterParam = true
  addMethodToClass(boxCls, "vertical", boxVerticalMethod, isClassMethod = true)

  let boxNewOrientationSpacingMethod = createCoreMethod("newOrientation:spacing:")
  boxNewOrientationSpacingMethod.nativeImpl = cast[pointer](boxNewOrientationSpacingImpl)
  boxNewOrientationSpacingMethod.hasInterpreterParam = true
  addMethodToClass(boxCls, "newOrientation:spacing:", boxNewOrientationSpacingMethod, isClassMethod = true)

  # Add Box instance methods
  let boxAppendMethod = createCoreMethod("append:")
  boxAppendMethod.nativeImpl = cast[pointer](boxAppendImpl)
  boxAppendMethod.hasInterpreterParam = true
  addMethodToClass(boxCls, "append:", boxAppendMethod)

  let boxPrependMethod = createCoreMethod("prepend:")
  boxPrependMethod.nativeImpl = cast[pointer](boxPrependImpl)
  boxPrependMethod.hasInterpreterParam = true
  addMethodToClass(boxCls, "prepend:", boxPrependMethod)

  let boxSetSpacingMethod = createCoreMethod("setSpacing:")
  boxSetSpacingMethod.nativeImpl = cast[pointer](boxSetSpacingImpl)
  boxSetSpacingMethod.hasInterpreterParam = true
  addMethodToClass(boxCls, "setSpacing:", boxSetSpacingMethod)

  interp.globals[]["GtkBox"] = boxCls.toValue()
  debug("Registered GtkBox class")

  # Create Label class (for display widgets)
  let labelCls = newClass(superclasses = @[widgetCls], name = "GtkLabel")
  labelCls.tags = @["GTK", "Label", "Display"]
  labelCls.isNimProxy = true
  labelCls.hardingType = "GtkLabel"

  # Add Label class methods
  let labelNewMethod = createCoreMethod("new")
  labelNewMethod.nativeImpl = cast[pointer](labelNewImpl)
  labelNewMethod.hasInterpreterParam = true
  addMethodToClass(labelCls, "new", labelNewMethod, isClassMethod = true)

  let labelNewLabelMethod = createCoreMethod("newLabel:")
  labelNewLabelMethod.nativeImpl = cast[pointer](labelNewLabelImpl)
  labelNewLabelMethod.hasInterpreterParam = true
  addMethodToClass(labelCls, "newLabel:", labelNewLabelMethod, isClassMethod = true)

  # Add Label instance methods
  let labelSetTextMethod = createCoreMethod("text:")
  labelSetTextMethod.nativeImpl = cast[pointer](labelSetTextImpl)
  labelSetTextMethod.hasInterpreterParam = true
  addMethodToClass(labelCls, "text:", labelSetTextMethod)

  let labelGetTextMethod = createCoreMethod("text")
  labelGetTextMethod.nativeImpl = cast[pointer](labelGetTextImpl)
  labelGetTextMethod.hasInterpreterParam = true
  addMethodToClass(labelCls, "text", labelGetTextMethod)

  interp.globals[]["GtkLabel"] = labelCls.toValue()
  debug("Registered GtkLabel class")

  # Create TextView class (for multiple line text editing)
  let textViewCls = newClass(superclasses = @[widgetCls], name = "GtkTextView")
  textViewCls.tags = @["GTK", "TextView", "Editor"]
  textViewCls.isNimProxy = true
  textViewCls.hardingType = "GtkTextView"

  # Add TextView class methods
  let textViewNewMethod = createCoreMethod("new")
  textViewNewMethod.nativeImpl = cast[pointer](textViewNewImpl)
  textViewNewMethod.hasInterpreterParam = true
  addMethodToClass(textViewCls, "new", textViewNewMethod, isClassMethod = true)

  # Add TextView instance methods
  let textViewGetBufferMethod = createCoreMethod("getBuffer:")
  textViewGetBufferMethod.nativeImpl = cast[pointer](textViewGetBufferImpl)
  textViewGetBufferMethod.hasInterpreterParam = true
  addMethodToClass(textViewCls, "getBuffer:", textViewGetBufferMethod)

  let textViewSetBufferMethod = createCoreMethod("setBuffer:")
  textViewSetBufferMethod.nativeImpl = cast[pointer](textViewSetBufferImpl)
  textViewSetBufferMethod.hasInterpreterParam = true
  addMethodToClass(textViewCls, "setBuffer:", textViewSetBufferMethod)

  let textViewGetTextMethod = createCoreMethod("getText:")
  textViewGetTextMethod.nativeImpl = cast[pointer](textViewGetTextImpl)
  textViewGetTextMethod.hasInterpreterParam = true
  addMethodToClass(textViewCls, "getText:", textViewGetTextMethod)

  let textViewSetTextMethod = createCoreMethod("setText:")
  textViewSetTextMethod.nativeImpl = cast[pointer](textViewSetTextImpl)
  textViewSetTextMethod.hasInterpreterParam = true
  addMethodToClass(textViewCls, "setText:", textViewSetTextMethod)

  interp.globals[]["GtkTextView"] = textViewCls.toValue()
  debug("Registered GtkTextView class")

  # Create TextBuffer class (for TextView text storage)
  let textBufferCls = newClass(superclasses = @[objectClass], name = "GtkTextBuffer")
  textBufferCls.tags = @["GTK", "TextBuffer"]
  textBufferCls.isNimProxy = true
  textBufferCls.hardingType = "GtkTextBuffer"

  # Add TextBuffer class methods
  let textBufferNewMethod = createCoreMethod("new")
  textBufferNewMethod.nativeImpl = cast[pointer](textBufferNewImpl)
  textBufferNewMethod.hasInterpreterParam = true
  addMethodToClass(textBufferCls, "new", textBufferNewMethod, isClassMethod = true)

  # Add TextBuffer instance methods
  let textBufferSetTextMethod = createCoreMethod("setText:")
  textBufferSetTextMethod.nativeImpl = cast[pointer](textBufferSetTextImpl)
  textBufferSetTextMethod.hasInterpreterParam = true
  addMethodToClass(textBufferCls, "setText:", textBufferSetTextMethod)

  let textBufferGetTextMethod = createCoreMethod("getText:")
  textBufferGetTextMethod.nativeImpl = cast[pointer](textBufferGetTextImpl)
  textBufferGetTextMethod.hasInterpreterParam = true
  addMethodToClass(textBufferCls, "getText:", textBufferGetTextMethod)

  let textBufferInsertAtMethod = createCoreMethod("insert:at:")
  textBufferInsertAtMethod.nativeImpl = cast[pointer](textBufferInsertAtImpl)
  textBufferInsertAtMethod.hasInterpreterParam = true
  addMethodToClass(textBufferCls, "insert:at:", textBufferInsertAtMethod)

  let textBufferDeleteToMethod = createCoreMethod("delete:to:")
  textBufferDeleteToMethod.nativeImpl = cast[pointer](textBufferDeleteToImpl)
  textBufferDeleteToMethod.hasInterpreterParam = true
  addMethodToClass(textBufferCls, "delete:to:", textBufferDeleteToMethod)

  interp.globals[]["GtkTextBuffer"] = textBufferCls.toValue()
  debug("Registered GtkTextBuffer class")

  when defined(gtk3):
    # Create MenuItem class (GTK3 only)
    let menuItemCls = newClass(superclasses = @[widgetCls], name = "GtkMenuItem")
    menuItemCls.tags = @["GTK", "MenuItem", "Menu"]
    menuItemCls.isNimProxy = true
    menuItemCls.hardingType = "GtkMenuItem"

    # Add MenuItem class methods
    let menuItemNewMethod = createCoreMethod("new")
    menuItemNewMethod.nativeImpl = cast[pointer](menuItemNewImpl)
    menuItemNewMethod.hasInterpreterParam = true
    addMethodToClass(menuItemCls, "new", menuItemNewMethod, isClassMethod = true)

    let menuItemNewLabelMethod = createCoreMethod("newLabel:")
    menuItemNewLabelMethod.nativeImpl = cast[pointer](menuItemNewLabelImpl)
    menuItemNewLabelMethod.hasInterpreterParam = true
    addMethodToClass(menuItemCls, "newLabel:", menuItemNewLabelMethod, isClassMethod = true)

    # Add MenuItem instance methods
    let menuItemActivateMethod = createCoreMethod("activate:")
    menuItemActivateMethod.nativeImpl = cast[pointer](menuItemActivateImpl)
    menuItemActivateMethod.hasInterpreterParam = true
    addMethodToClass(menuItemCls, "activate:", menuItemActivateMethod)

    interp.globals[]["GtkMenuItem"] = menuItemCls.toValue()
    debug("Registered GtkMenuItem class")

    # Create Menu class (GTK3 only)
    let menuCls = newClass(superclasses = @[objectClass], name = "GtkMenu")
    menuCls.tags = @["GTK", "Menu"]
    menuCls.isNimProxy = true
    menuCls.hardingType = "GtkMenu"

    # Add Menu instance methods
    let menuAppendMethod = createCoreMethod("append:")
    menuAppendMethod.nativeImpl = cast[pointer](menuAppendImpl)
    menuAppendMethod.hasInterpreterParam = true
    addMethodToClass(menuCls, "append:", menuAppendMethod)

    let menuPopupAtPointerMethod = createCoreMethod("popup")
    menuPopupAtPointerMethod.nativeImpl = cast[pointer](menuPopupAtPointerImpl)
    menuPopupAtPointerMethod.hasInterpreterParam = true
    addMethodToClass(menuCls, "popup", menuPopupAtPointerMethod)

    interp.globals[]["GtkMenu"] = menuCls.toValue()
    debug("Registered GtkMenu class")

    # Create MenuBar class (GTK3 only)
    let menuBarCls = newClass(superclasses = @[widgetCls], name = "GtkMenuBar")
    menuBarCls.tags = @["GTK", "MenuBar", "Menu"]
    menuBarCls.isNimProxy = true
    menuBarCls.hardingType = "GtkMenuBar"

    # Add MenuBar class method
    let menuBarNewMethod = createCoreMethod("new")
    menuBarNewMethod.nativeImpl = cast[pointer](menuBarNewImpl)
    menuBarNewMethod.hasInterpreterParam = true
    addMethodToClass(menuBarCls, "new", menuBarNewMethod, isClassMethod = true)

    # Add MenuBar instance method
    let menuBarAppendMethod = createCoreMethod("append:")
    menuBarAppendMethod.nativeImpl = cast[pointer](menuBarAppendImpl)
    menuBarAppendMethod.hasInterpreterParam = true
    addMethodToClass(menuBarCls, "append:", menuBarAppendMethod)

    interp.globals[]["GtkMenuBar"] = menuBarCls.toValue()
    debug("Registered GtkMenuBar class")

  # Register Launcher class (derived from GtkWindow)
  let launcherCls = newClass(superclasses = @[windowCls], slotNames = @["windows"], name = "Launcher")
  launcherCls.tags = @["GTK", "Window", "Launcher", "IDE"]
  launcherCls.isNimProxy = true
  launcherCls.hardingType = "Launcher"

  # Add Launcher class method - native new that creates a Launcher instance
  let launcherNewMethod = createCoreMethod("new")
  launcherNewMethod.nativeImpl = cast[pointer](launcherNewImpl)
  launcherNewMethod.hasInterpreterParam = true
  addMethodToClass(launcherCls, "new", launcherNewMethod, isClassMethod = true)

  interp.globals[]["Launcher"] = launcherCls.toValue()
  debug("Registered Launcher class")

  debug("GTK bridge initialization complete")

## Load Harding-side GTK wrapper files
proc loadGtkWrapperFiles*(interp: var Interpreter, basePath: string = "") =
  ## Load the Harding-side GTK wrapper classes from lib/harding/gui/Gtk4/
  let libPath = if basePath.len > 0: basePath / "lib" / "harding" / "gui" / "Gtk4" else: "lib" / "harding" / "gui" / "Gtk4"

  debug("Loading GTK wrapper files from: ", libPath)

  let wrapperFiles = [
    "Widget.hrd",
    "Window.hrd",
    "Button.hrd",
    "Box.hrd",
    "Label.hrd",
    "TextView.hrd",
    "TextBuffer.hrd"
  ]

  when defined(gtk3):
    let gtk3WrapperFiles = [
      "MenuItem.hrd",
      "Menu.hrd",
      "MenuBar.hrd"
    ]

  for filename in wrapperFiles:
    let filepath = libPath / filename
    if fileExists(filepath):
      debug("Loading GTK wrapper: ", filepath)
      let source = readFile(filepath)
      let (_, err) = interp.evalStatements(source)
      if err.len > 0:
        warn("Failed to load ", filepath, ": ", err)
      else:
        debug("Successfully loaded: ", filepath)
    else:
      debug("GTK wrapper file not found (optional): ", filepath)

  when defined(gtk3):
    for filename in gtk3WrapperFiles:
      let filepath = libPath / filename
      if fileExists(filepath):
        debug("Loading GTK wrapper: ", filepath)
        let source = readFile(filepath)
        let (_, err) = interp.evalStatements(source)
        if err.len > 0:
          warn("Failed to load ", filepath, ": ", err)
        else:
          debug("Successfully loaded: ", filepath)
      else:
        debug("GTK wrapper file not found (optional): ", filepath)

## Load IDE tool files
proc loadIdeToolFiles*(interp: var Interpreter, basePath: string = "") =
  ## Load the IDE tool classes from lib/harding/gui/Ide/
  let libPath = if basePath.len > 0: basePath / "lib" / "harding" / "gui" / "Ide" else: "lib" / "harding" / "gui" / "Ide"

  debug("Loading IDE tool files from: ", libPath)

  let toolFiles = [
    "Transcript.hrd",
    "Workspace.hrd",
    "Launcher.hrd"
  ]

  for filename in toolFiles:
    let filepath = libPath / filename
    if fileExists(filepath):
      debug("Loading IDE tool: ", filepath)
      let source = readFile(filepath)
      let (_, err) = interp.evalStatements(source)
      if err.len > 0:
        warn("Failed to load ", filepath, ": ", err)
      else:
        debug("Successfully loaded: ", filepath)
    else:
      debug("IDE tool file not found (optional): ", filepath)

## Launcher new implementation - separated to avoid closure capture issues
proc launcherNewImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.cdecl.} =
  when not defined(gtk3):
    # Use GtkApplicationWindow if we have an app, otherwise fallback to regular window
    var window: GtkWindow
    debug("Creating Launcher window, gtkApp=", repr(gtkApp))
    if gtkApp != nil:
      debug("Using gtk_application_window_new")
      window = gtkApplicationWindowNew(gtkApp)
    else:
      debug("Using gtk_window_new (no app)")
      window = gtkWindowNew()
    debug("Created window: ", repr(window))
  else:
    let window = gtkWindowNew(GTKWINDOWTOPLEVEL)

  # Store proxy in global table (not as raw pointer)
  discard newGtkWindowProxy(window, addr(interp))

  # Look up Launcher class from globals (prefer Launcher, fallback to GtkWindow)
  var cls: Class = nil
  if "Launcher" in interp.globals[]:
    let val = interp.globals[]["Launcher"]
    if val.kind == vkClass:
      cls = val.classVal
  if cls == nil and "GtkWindow" in interp.globals[]:
    let val = interp.globals[]["GtkWindow"]
    if val.kind == vkClass:
      cls = val.classVal
  if cls == nil:
    cls = objectClass

  let obj = newInstance(cls)
  obj.isNimProxy = true
  storeInstanceWidget(obj, window)
  obj.nimValue = cast[pointer](window)
  return obj.toValue()