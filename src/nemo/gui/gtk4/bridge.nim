## ============================================================================
## GTK4 Bridge Initialization
## Registers all GTK wrapper classes with Nemo globals
## ============================================================================

import std/[logging, os, tables]
import nemo/core/types
import nemo/interpreter/objects
import nemo/interpreter/evaluator
import ./ffi
import ./widget
import ./window
import ./button
import ./box

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
  # These are the Nim-side classes that will be derived from in Nemo

  # Create Widget class (base class for all GTK widgets)
  let widgetCls = newClass(superclasses = @[objectClass], name = "GtkWidget")
  widgetCls.tags = @["GTK", "Widget"]
  widgetCls.isNimProxy = true
  widgetCls.nemoType = "GtkWidget"

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
  windowCls.nemoType = "GtkWindow"

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

  interp.globals[]["GtkWindow"] = windowCls.toValue()
  debug("Registered GtkWindow class")

  # Create Button class
  let buttonCls = newClass(superclasses = @[widgetCls], name = "GtkButton")
  buttonCls.tags = @["GTK", "Button"]
  buttonCls.isNimProxy = true
  buttonCls.nemoType = "GtkButton"

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
  boxCls.nemoType = "GtkBox"

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

  # Register Launcher class (derived from GtkWindow)
  let launcherCls = newClass(superclasses = @[windowCls], name = "Launcher")
  launcherCls.tags = @["GTK", "Window", "Launcher", "IDE"]
  launcherCls.isNimProxy = true
  launcherCls.nemoType = "Launcher"

  # Add Launcher class method - native new that creates a Launcher instance
  let launcherNewMethod = createCoreMethod("new")
  launcherNewMethod.nativeImpl = cast[pointer](launcherNewImpl)
  launcherNewMethod.hasInterpreterParam = true
  addMethodToClass(launcherCls, "new", launcherNewMethod, isClassMethod = true)

  interp.globals[]["Launcher"] = launcherCls.toValue()
  debug("Registered Launcher class")

  debug("GTK bridge initialization complete")

## Load Nemo-side GTK wrapper files
proc loadGtkWrapperFiles*(interp: var Interpreter, basePath: string = "") =
  ## Load the Nemo-side GTK wrapper classes from lib/nemo/gui/Gtk4/
  let libPath = if basePath.len > 0: basePath / "lib" / "nemo" / "gui" / "Gtk4" else: "lib" / "nemo" / "gui" / "Gtk4"

  debug("Loading GTK wrapper files from: ", libPath)

  let wrapperFiles = [
    "Widget.nemo",
    "Window.nemo",
    "Button.nemo",
    "Box.nemo"
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

## Load IDE tool files
proc loadIdeToolFiles*(interp: var Interpreter, basePath: string = "") =
  ## Load the IDE tool classes from lib/nemo/gui/Ide/
  let libPath = if basePath.len > 0: basePath / "lib" / "nemo" / "gui" / "Ide" else: "lib" / "nemo" / "gui" / "Ide"

  debug("Loading IDE tool files from: ", libPath)

  let toolFiles = [
    "Transcript.nemo",
    "Launcher.nemo"
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
  when defined(gtk4):
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
  let proxy = newGtkWindowProxy(window, addr(interp))

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
  obj.nimValue = cast[pointer](proxy)
  return obj.toValue()