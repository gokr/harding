## ============================================================================
## GTK4 Bridge Initialization
## Registers all GTK wrapper classes with Harding globals
## ============================================================================

import std/[os, tables]
import harding/core/types
import harding/interpreter/objects
import harding/interpreter/vm
import ./ffi
import ./widget
import ./window
import ./button
import ./entry
import ./box
import ./scrolledwindow
when defined(gtk3):
  import ./menubar
  import ./menu
  import ./menuitem
import ./textview
import ./textbuffer
import ./label
import ./sourceview
import ./eventcontroller
import ./alertdialog
import ./gesture
import ./popover
import ./paned
import ./listbox

## Forward declarations
proc initGtkBridge*(interp: var Interpreter)
proc loadGtkWrapperFiles*(interp: var Interpreter, basePath: string = "")
proc loadIdeToolFiles*(interp: var Interpreter, basePath: string = "")
proc setGtkApplication*(app: GtkApplication)
proc getGtkApplication*(): GtkApplication
proc setGtkDefaultIcon*(iconName: string): bool

## Global GTK application reference (for GTK4)
var gtkApp* {.global.}: GtkApplication = nil

proc setGtkApplication*(app: GtkApplication) =
  gtkApp = app

proc getGtkApplication*(): GtkApplication =
  gtkApp

## Register the getter with window module to avoid circular imports
## (window.nim is imported above, this sets up the forward reference)
setGtkApplicationGetter(getGtkApplication)

## Forward declaration for launcher new implementation
proc launcherNewImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.}

## Set the default application icon
proc setGtkDefaultIcon*(iconName: string): bool =
  ## Set the default application icon
  ##
  ## In GTK4: Sets the icon name to use from the icon theme (proper GTK4 approach)
  ## In GTK3: If iconName is a file path that exists, loads from file
  ##
  ## Returns true if successful
  when defined(gtk3):
    if fileExists(iconName):
      let result = gtkWindowSetDefaultIconFromFile(iconName.cstring)
      debug("Set default application icon from file: ", iconName, " result: ", result)
      return result != 0
    else:
      gtkWindowSetDefaultIconName(iconName.cstring)
      debug("Set default application icon name: ", iconName)
      return true
  else:
    gtkWindowSetDefaultIconName(iconName.cstring)
    debug("Set default application icon name: ", iconName)
    return true

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

  let widgetSetSizeRequestMethod = createCoreMethod("setSizeRequest:height:")
  widgetSetSizeRequestMethod.nativeImpl = cast[pointer](widgetSetSizeRequestImpl)
  widgetSetSizeRequestMethod.hasInterpreterParam = true
  addMethodToClass(widgetCls, "setSizeRequest:height:", widgetSetSizeRequestMethod)

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

  let widgetEmitSignalMethod = createCoreMethod("emitSignal:")
  widgetEmitSignalMethod.nativeImpl = cast[pointer](widgetEmitSignalImpl)
  widgetEmitSignalMethod.hasInterpreterParam = true
  addMethodToClass(widgetCls, "emitSignal:", widgetEmitSignalMethod)

  let widgetSetVexpandMethod = createCoreMethod("setVexpand:")
  widgetSetVexpandMethod.nativeImpl = cast[pointer](widgetSetVexpandImpl)
  widgetSetVexpandMethod.hasInterpreterParam = true
  addMethodToClass(widgetCls, "setVexpand:", widgetSetVexpandMethod)

  let widgetSetHexpandMethod = createCoreMethod("setHexpand:")
  widgetSetHexpandMethod.nativeImpl = cast[pointer](widgetSetHexpandImpl)
  widgetSetHexpandMethod.hasInterpreterParam = true
  addMethodToClass(widgetCls, "setHexpand:", widgetSetHexpandMethod)

  let widgetSetHalignStartMethod = createCoreMethod("setHalignStart")
  widgetSetHalignStartMethod.nativeImpl = cast[pointer](widgetSetHalignStartImpl)
  widgetSetHalignStartMethod.hasInterpreterParam = true
  addMethodToClass(widgetCls, "setHalignStart", widgetSetHalignStartMethod)

  let widgetSetTooltipTextMethod = createCoreMethod("setTooltipText:")
  widgetSetTooltipTextMethod.nativeImpl = cast[pointer](widgetSetTooltipTextImpl)
  widgetSetTooltipTextMethod.hasInterpreterParam = true
  addMethodToClass(widgetCls, "setTooltipText:", widgetSetTooltipTextMethod)

  let widgetMarginStartMethod = createCoreMethod("marginStart:")
  widgetMarginStartMethod.nativeImpl = cast[pointer](widgetMarginStartImpl)
  widgetMarginStartMethod.hasInterpreterParam = true
  addMethodToClass(widgetCls, "marginStart:", widgetMarginStartMethod)

  let widgetMarginEndMethod = createCoreMethod("marginEnd:")
  widgetMarginEndMethod.nativeImpl = cast[pointer](widgetMarginEndImpl)
  widgetMarginEndMethod.hasInterpreterParam = true
  addMethodToClass(widgetCls, "marginEnd:", widgetMarginEndMethod)

  let widgetMarginTopMethod = createCoreMethod("marginTop:")
  widgetMarginTopMethod.nativeImpl = cast[pointer](widgetMarginTopImpl)
  widgetMarginTopMethod.hasInterpreterParam = true
  addMethodToClass(widgetCls, "marginTop:", widgetMarginTopMethod)

  let widgetMarginBottomMethod = createCoreMethod("marginBottom:")
  widgetMarginBottomMethod.nativeImpl = cast[pointer](widgetMarginBottomImpl)
  widgetMarginBottomMethod.hasInterpreterParam = true
  addMethodToClass(widgetCls, "marginBottom:", widgetMarginBottomMethod)

  let widgetPumpEventsMethod = createCoreMethod("pumpEvents")
  widgetPumpEventsMethod.nativeImpl = cast[pointer](widgetPumpEventsImpl)
  widgetPumpEventsMethod.hasInterpreterParam = true
  addMethodToClass(widgetCls, "pumpEvents", widgetPumpEventsMethod, isClassMethod = true)

  let widgetPumpEventsCountMethod = createCoreMethod("pumpEvents:")
  widgetPumpEventsCountMethod.nativeImpl = cast[pointer](widgetPumpEventsImpl)
  widgetPumpEventsCountMethod.hasInterpreterParam = true
  addMethodToClass(widgetCls, "pumpEvents:", widgetPumpEventsCountMethod, isClassMethod = true)

  interp.globals[]["GtkWidget"] = widgetCls.toValue()
  debug("Registered GtkWidget class")

  # Create Window class
  let windowCls = newClass(superclasses = @[widgetCls], name = "GtkWindow")
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

  let windowSetIconNameMethod = createCoreMethod("iconName:")
  windowSetIconNameMethod.nativeImpl = cast[pointer](windowSetIconNameImpl)
  windowSetIconNameMethod.hasInterpreterParam = true
  addMethodToClass(windowCls, "iconName:", windowSetIconNameMethod)

  let windowSetIconFromFileMethod = createCoreMethod("iconFromFile:")
  windowSetIconFromFileMethod.nativeImpl = cast[pointer](windowSetIconFromFileImpl)
  windowSetIconFromFileMethod.hasInterpreterParam = true
  addMethodToClass(windowCls, "iconFromFile:", windowSetIconFromFileMethod)

  let windowSetWmClassMethod = createCoreMethod("setWmClass:")
  windowSetWmClassMethod.nativeImpl = cast[pointer](windowSetWmClassImpl)
  windowSetWmClassMethod.hasInterpreterParam = true
  addMethodToClass(windowCls, "setWmClass:", windowSetWmClassMethod)

  interp.globals[]["GtkWindow"] = windowCls.toValue()
  debug("Registered GtkWindow class")

  # Create Button class
  let buttonCls = newClass(superclasses = @[widgetCls], name = "GtkButton")
  buttonCls.isNimProxy = true
  buttonCls.hardingType = "GtkButton"

  # Add Button class methods
  let buttonNewMethod = createCoreMethod("new")
  buttonNewMethod.nativeImpl = cast[pointer](buttonNewImpl)
  buttonNewMethod.hasInterpreterParam = true
  addMethodToClass(buttonCls, "new", buttonNewMethod, isClassMethod = true)

  # Note: newLabel: class method is implemented in Harding (Button.hrd)

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

  let buttonIconNameMethod = createCoreMethod("iconName:")
  buttonIconNameMethod.nativeImpl = cast[pointer](buttonSetIconNameImpl)
  buttonIconNameMethod.hasInterpreterParam = true
  addMethodToClass(buttonCls, "iconName:", buttonIconNameMethod)

  let buttonLabelIconMethod = createCoreMethod("label:iconName:")
  buttonLabelIconMethod.nativeImpl = cast[pointer](buttonSetLabelAndIconImpl)
  buttonLabelIconMethod.hasInterpreterParam = true
  addMethodToClass(buttonCls, "label:iconName:", buttonLabelIconMethod)

  interp.globals[]["GtkButton"] = buttonCls.toValue()
  debug("Registered GtkButton class")

  # Create Entry class
  let entryCls = newClass(superclasses = @[widgetCls], name = "GtkEntry")
  entryCls.isNimProxy = true
  entryCls.hardingType = "GtkEntry"

  let entryNewMethod = createCoreMethod("new")
  entryNewMethod.nativeImpl = cast[pointer](entryNewImpl)
  entryNewMethod.hasInterpreterParam = true
  addMethodToClass(entryCls, "new", entryNewMethod, isClassMethod = true)

  let entryGetTextMethod = createCoreMethod("text")
  entryGetTextMethod.nativeImpl = cast[pointer](entryGetTextImpl)
  entryGetTextMethod.hasInterpreterParam = true
  addMethodToClass(entryCls, "text", entryGetTextMethod)

  let entrySetTextMethod = createCoreMethod("text:")
  entrySetTextMethod.nativeImpl = cast[pointer](entrySetTextImpl)
  entrySetTextMethod.hasInterpreterParam = true
  addMethodToClass(entryCls, "text:", entrySetTextMethod)

  let entryPlaceholderMethod = createCoreMethod("placeholderText:")
  entryPlaceholderMethod.nativeImpl = cast[pointer](entrySetPlaceholderTextImpl)
  entryPlaceholderMethod.hasInterpreterParam = true
  addMethodToClass(entryCls, "placeholderText:", entryPlaceholderMethod)

  interp.globals[]["GtkEntry"] = entryCls.toValue()
  debug("Registered GtkEntry class")

  # Create Box class
  let boxCls = newClass(superclasses = @[widgetCls], name = "GtkBox")
  boxCls.isNimProxy = true
  boxCls.hardingType = "GtkBox"

  # Add Box class methods
  let boxNewMethod = createCoreMethod("new")
  boxNewMethod.nativeImpl = cast[pointer](boxNewImpl)
  boxNewMethod.hasInterpreterParam = true
  addMethodToClass(boxCls, "new", boxNewMethod, isClassMethod = true)

  # Note: horizontal and vertical class methods are implemented in Harding (Box.hrd)
  # They use newOrientation:spacing: primitive

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

  # Create ScrolledWindow class (for scrollable containers)
  let scrolledWindowCls = newClass(superclasses = @[widgetCls], name = "GtkScrolledWindow")
  scrolledWindowCls.isNimProxy = true
  scrolledWindowCls.hardingType = "GtkScrolledWindow"

  # Add ScrolledWindow class methods
  let scrolledWindowNewMethod = createCoreMethod("new")
  scrolledWindowNewMethod.nativeImpl = cast[pointer](scrolledWindowNewImpl)
  scrolledWindowNewMethod.hasInterpreterParam = true
  addMethodToClass(scrolledWindowCls, "new", scrolledWindowNewMethod, isClassMethod = true)

  # Add ScrolledWindow instance methods
  let scrolledWindowSetChildMethod = createCoreMethod("setChild:")
  scrolledWindowSetChildMethod.nativeImpl = cast[pointer](scrolledWindowSetChildImpl)
  scrolledWindowSetChildMethod.hasInterpreterParam = true
  addMethodToClass(scrolledWindowCls, "setChild:", scrolledWindowSetChildMethod)

  interp.globals[]["GtkScrolledWindow"] = scrolledWindowCls.toValue()
  debug("Registered GtkScrolledWindow class")

  # Create Paned class (for split pane containers)
  let panedCls = newClass(superclasses = @[widgetCls], name = "GtkPaned")
  panedCls.isNimProxy = true
  panedCls.hardingType = "GtkPaned"

  # Add Paned class methods
  let panedNewMethod = createCoreMethod("new:")
  panedNewMethod.nativeImpl = cast[pointer](panedNewImpl)
  panedNewMethod.hasInterpreterParam = true
  addMethodToClass(panedCls, "new:", panedNewMethod, isClassMethod = true)

  # Note: horizontal and vertical class methods are implemented in Harding (Paned.hrd)

  # Add Paned instance methods
  let panedSetStartChildMethod = createCoreMethod("setStartChild:")
  panedSetStartChildMethod.nativeImpl = cast[pointer](panedSetStartChildImpl)
  panedSetStartChildMethod.hasInterpreterParam = true
  addMethodToClass(panedCls, "setStartChild:", panedSetStartChildMethod)

  let panedSetEndChildMethod = createCoreMethod("setEndChild:")
  panedSetEndChildMethod.nativeImpl = cast[pointer](panedSetEndChildImpl)
  panedSetEndChildMethod.hasInterpreterParam = true
  addMethodToClass(panedCls, "setEndChild:", panedSetEndChildMethod)

  let panedSetPositionMethod = createCoreMethod("setPosition:")
  panedSetPositionMethod.nativeImpl = cast[pointer](panedSetPositionImpl)
  panedSetPositionMethod.hasInterpreterParam = true
  addMethodToClass(panedCls, "setPosition:", panedSetPositionMethod)

  let panedSetShrinkStartChildMethod = createCoreMethod("setShrinkStartChild:")
  panedSetShrinkStartChildMethod.nativeImpl = cast[pointer](panedSetShrinkStartChildImpl)
  panedSetShrinkStartChildMethod.hasInterpreterParam = true
  addMethodToClass(panedCls, "setShrinkStartChild:", panedSetShrinkStartChildMethod)

  let panedSetShrinkEndChildMethod = createCoreMethod("setShrinkEndChild:")
  panedSetShrinkEndChildMethod.nativeImpl = cast[pointer](panedSetShrinkEndChildImpl)
  panedSetShrinkEndChildMethod.hasInterpreterParam = true
  addMethodToClass(panedCls, "setShrinkEndChild:", panedSetShrinkEndChildMethod)

  interp.globals[]["GtkPaned"] = panedCls.toValue()
  debug("Registered GtkPaned class")

  # Create ListBox class (for scrollable lists)
  let listBoxCls = newClass(superclasses = @[widgetCls], name = "GtkListBox")
  listBoxCls.isNimProxy = true
  listBoxCls.hardingType = "GtkListBox"

  # Add ListBox class methods
  let listBoxNewMethod = createCoreMethod("new")
  listBoxNewMethod.nativeImpl = cast[pointer](listBoxNewImpl)
  listBoxNewMethod.hasInterpreterParam = true
  addMethodToClass(listBoxCls, "new", listBoxNewMethod, isClassMethod = true)

  # Add ListBox instance methods
  let listBoxAppendMethod = createCoreMethod("append:")
  listBoxAppendMethod.nativeImpl = cast[pointer](listBoxAppendImpl)
  listBoxAppendMethod.hasInterpreterParam = true
  addMethodToClass(listBoxCls, "append:", listBoxAppendMethod)

  let listBoxPrependMethod = createCoreMethod("prepend:")
  listBoxPrependMethod.nativeImpl = cast[pointer](listBoxPrependImpl)
  listBoxPrependMethod.hasInterpreterParam = true
  addMethodToClass(listBoxCls, "prepend:", listBoxPrependMethod)

  let listBoxRemoveAllMethod = createCoreMethod("removeAll")
  listBoxRemoveAllMethod.nativeImpl = cast[pointer](listBoxRemoveAllImpl)
  listBoxRemoveAllMethod.hasInterpreterParam = true
  addMethodToClass(listBoxCls, "removeAll", listBoxRemoveAllMethod)

  let listBoxSetSelectionModeMethod = createCoreMethod("setSelectionMode:")
  listBoxSetSelectionModeMethod.nativeImpl = cast[pointer](listBoxSetSelectionModeImpl)
  listBoxSetSelectionModeMethod.hasInterpreterParam = true
  addMethodToClass(listBoxCls, "setSelectionMode:", listBoxSetSelectionModeMethod)

  let listBoxSelectedRowIndexMethod = createCoreMethod("selectedRowIndex")
  listBoxSelectedRowIndexMethod.nativeImpl = cast[pointer](listBoxGetSelectedRowIndexImpl)
  listBoxSelectedRowIndexMethod.hasInterpreterParam = true
  addMethodToClass(listBoxCls, "selectedRowIndex", listBoxSelectedRowIndexMethod)

  let listBoxSelectRowAtIndexMethod = createCoreMethod("selectRowAtIndex:")
  listBoxSelectRowAtIndexMethod.nativeImpl = cast[pointer](listBoxSelectRowAtIndexImpl)
  listBoxSelectRowAtIndexMethod.hasInterpreterParam = true
  addMethodToClass(listBoxCls, "selectRowAtIndex:", listBoxSelectRowAtIndexMethod)

  let listBoxRowIndexAtYMethod = createCoreMethod("rowIndexAtY:")
  listBoxRowIndexAtYMethod.nativeImpl = cast[pointer](listBoxGetRowIndexAtYImpl)
  listBoxRowIndexAtYMethod.hasInterpreterParam = true
  addMethodToClass(listBoxCls, "rowIndexAtY:", listBoxRowIndexAtYMethod)

  let listBoxOnRowSelectedMethod = createCoreMethod("onRowSelected:")
  listBoxOnRowSelectedMethod.nativeImpl = cast[pointer](listBoxOnRowSelectedImpl)
  listBoxOnRowSelectedMethod.hasInterpreterParam = true
  addMethodToClass(listBoxCls, "onRowSelected:", listBoxOnRowSelectedMethod)

  interp.globals[]["GtkListBox"] = listBoxCls.toValue()
  debug("Registered GtkListBox class")

  # Create Label class (for display widgets)
  let labelCls = newClass(superclasses = @[widgetCls], name = "GtkLabel")
  labelCls.isNimProxy = true
  labelCls.hardingType = "GtkLabel"

  # Add Label class methods
  let labelNewMethod = createCoreMethod("new")
  labelNewMethod.nativeImpl = cast[pointer](labelNewImpl)
  labelNewMethod.hasInterpreterParam = true
  addMethodToClass(labelCls, "new", labelNewMethod, isClassMethod = true)

  # Note: newLabel: class method is implemented in Harding (Label.hrd)

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
  textViewCls.isNimProxy = true
  textViewCls.hardingType = "GtkTextView"

  # Add TextView class methods
  let textViewNewMethod = createCoreMethod("new")
  textViewNewMethod.nativeImpl = cast[pointer](textViewNewImpl)
  textViewNewMethod.hasInterpreterParam = true
  addMethodToClass(textViewCls, "new", textViewNewMethod, isClassMethod = true)

  # Add TextView instance methods
  let textViewGetBufferMethod = createCoreMethod("getBuffer")
  textViewGetBufferMethod.nativeImpl = cast[pointer](textViewGetBufferImpl)
  textViewGetBufferMethod.hasInterpreterParam = true
  addMethodToClass(textViewCls, "getBuffer", textViewGetBufferMethod)

  let textViewSetBufferMethod = createCoreMethod("setBuffer:")
  textViewSetBufferMethod.nativeImpl = cast[pointer](textViewSetBufferImpl)
  textViewSetBufferMethod.hasInterpreterParam = true
  addMethodToClass(textViewCls, "setBuffer:", textViewSetBufferMethod)

  let textViewGetTextMethod = createCoreMethod("getText")
  textViewGetTextMethod.nativeImpl = cast[pointer](textViewGetTextImpl)
  textViewGetTextMethod.hasInterpreterParam = true
  addMethodToClass(textViewCls, "getText", textViewGetTextMethod)

  let textViewSetTextMethod = createCoreMethod("setText:")
  textViewSetTextMethod.nativeImpl = cast[pointer](textViewSetTextImpl)
  textViewSetTextMethod.hasInterpreterParam = true
  addMethodToClass(textViewCls, "setText:", textViewSetTextMethod)

  let textViewInsertTextAtMethod = createCoreMethod("insertText:at:")
  textViewInsertTextAtMethod.nativeImpl = cast[pointer](textViewInsertTextAtImpl)
  textViewInsertTextAtMethod.hasInterpreterParam = true
  addMethodToClass(textViewCls, "insertText:at:", textViewInsertTextAtMethod)

  let textViewInsertTextAtEndMethod = createCoreMethod("insertTextAtEnd:")
  textViewInsertTextAtEndMethod.nativeImpl = cast[pointer](textViewInsertTextAtEndImpl)
  textViewInsertTextAtEndMethod.hasInterpreterParam = true
  addMethodToClass(textViewCls, "insertTextAtEnd:", textViewInsertTextAtEndMethod)

  let textViewSelectRangeFromToMethod = createCoreMethod("selectRangeFrom:to:")
  textViewSelectRangeFromToMethod.nativeImpl = cast[pointer](textViewSelectRangeFromToImpl)
  textViewSelectRangeFromToMethod.hasInterpreterParam = true
  addMethodToClass(textViewCls, "selectRangeFrom:to:", textViewSelectRangeFromToMethod)

  let textViewInsertTextAtSelectedEndMethod = createCoreMethod("insertTextAtSelectedEnd:")
  textViewInsertTextAtSelectedEndMethod.nativeImpl = cast[pointer](textViewInsertTextAtSelectedEndImpl)
  textViewInsertTextAtSelectedEndMethod.hasInterpreterParam = true
  addMethodToClass(textViewCls, "insertTextAtSelectedEnd:", textViewInsertTextAtSelectedEndMethod)

  let textViewGetSelectionEndMethod = createCoreMethod("getSelectionEnd")
  textViewGetSelectionEndMethod.nativeImpl = cast[pointer](textViewGetSelectionEndImpl)
  textViewGetSelectionEndMethod.hasInterpreterParam = true
  addMethodToClass(textViewCls, "getSelectionEnd", textViewGetSelectionEndMethod)
  let textViewGetCurrentLineEndMethod = createCoreMethod("getCurrentLineEnd")
  textViewGetCurrentLineEndMethod.nativeImpl = cast[pointer](textViewGetCurrentLineEndImpl)
  textViewGetCurrentLineEndMethod.hasInterpreterParam = true
  addMethodToClass(textViewCls, "getCurrentLineEnd", textViewGetCurrentLineEndMethod)

  let textViewScrollToEndMethod = createCoreMethod("scrollToEnd")
  textViewScrollToEndMethod.nativeImpl = cast[pointer](textViewScrollToEndImpl)
  textViewScrollToEndMethod.hasInterpreterParam = true
  addMethodToClass(textViewCls, "scrollToEnd", textViewScrollToEndMethod)

  let textViewSetEditableMethod = createCoreMethod("editable:")
  textViewSetEditableMethod.nativeImpl = cast[pointer](textViewSetEditableImpl)
  textViewSetEditableMethod.hasInterpreterParam = true
  addMethodToClass(textViewCls, "editable:", textViewSetEditableMethod)

  interp.globals[]["GtkTextView"] = textViewCls.toValue()
  debug("Registered GtkTextView class")

  # Create GtkSourceView class (for source code editing with syntax highlighting)
  # Inherits from GtkTextView so it gets the text manipulation methods
  let sourceViewCls = newClass(superclasses = @[textViewCls], name = "GtkSourceView")
  sourceViewCls.isNimProxy = true
  sourceViewCls.hardingType = "GtkSourceView"

  # Add SourceView class methods
  let sourceViewNewMethod = createCoreMethod("new")
  sourceViewNewMethod.nativeImpl = cast[pointer](sourceViewNewImpl)
  sourceViewNewMethod.hasInterpreterParam = true
  addMethodToClass(sourceViewCls, "new", sourceViewNewMethod, isClassMethod = true)

  # Add SourceView instance methods
  let sourceViewGetTextMethod = createCoreMethod("getText")
  sourceViewGetTextMethod.nativeImpl = cast[pointer](sourceViewGetTextImpl)
  sourceViewGetTextMethod.hasInterpreterParam = true
  addMethodToClass(sourceViewCls, "getText", sourceViewGetTextMethod)

  let sourceViewSetTextMethod = createCoreMethod("setText:")
  sourceViewSetTextMethod.nativeImpl = cast[pointer](sourceViewSetTextImpl)
  sourceViewSetTextMethod.hasInterpreterParam = true
  addMethodToClass(sourceViewCls, "setText:", sourceViewSetTextMethod)

  let sourceViewGetSelectedTextMethod = createCoreMethod("getSelectedText")
  let funcPtr = cast[pointer](sourceViewGetSelectedTextImpl)
  debug("Registering getSelectedTextImpl, funcPtr=", cast[int](funcPtr))
  sourceViewGetSelectedTextMethod.nativeImpl = funcPtr
  sourceViewGetSelectedTextMethod.hasInterpreterParam = true
  addMethodToClass(sourceViewCls, "getSelectedText", sourceViewGetSelectedTextMethod)

  let sourceViewShowLineNumbersMethod = createCoreMethod("showLineNumbers:")
  sourceViewShowLineNumbersMethod.nativeImpl = cast[pointer](sourceViewShowLineNumbersImpl)
  sourceViewShowLineNumbersMethod.hasInterpreterParam = true
  addMethodToClass(sourceViewCls, "showLineNumbers:", sourceViewShowLineNumbersMethod)

  let sourceViewSetTabWidthMethod = createCoreMethod("setTabWidth:")
  sourceViewSetTabWidthMethod.nativeImpl = cast[pointer](sourceViewSetTabWidthImpl)
  sourceViewSetTabWidthMethod.hasInterpreterParam = true
  addMethodToClass(sourceViewCls, "setTabWidth:", sourceViewSetTabWidthMethod)

  let sourceViewBufferMethod = createCoreMethod("buffer")
  sourceViewBufferMethod.nativeImpl = cast[pointer](sourceViewBufferImpl)
  sourceViewBufferMethod.hasInterpreterParam = true
  addMethodToClass(sourceViewCls, "buffer", sourceViewBufferMethod)

  interp.globals[]["GtkSourceView"] = sourceViewCls.toValue()
  debug("Registered GtkSourceView class")

  # Create GtkEventController class for keyboard handling
  let eventControllerCls = newClass(superclasses = @[objectClass], name = "GtkEventController")
  eventControllerCls.isNimProxy = true
  eventControllerCls.hardingType = "GtkEventController"

  # Add EventController class methods for GDK key constants
  let eventControllerGetGdkKeyMethod = createCoreMethod("getGdkKey:")
  eventControllerGetGdkKeyMethod.nativeImpl = cast[pointer](eventControllerGetGdkKeyImpl)
  eventControllerGetGdkKeyMethod.hasInterpreterParam = true
  addMethodToClass(eventControllerCls, "getGdkKey:", eventControllerGetGdkKeyMethod, isClassMethod = true)

  let eventControllerGetControlMaskMethod = createCoreMethod("getControlMask")
  eventControllerGetControlMaskMethod.nativeImpl = cast[pointer](eventControllerGetControlMaskImpl)
  eventControllerGetControlMaskMethod.hasInterpreterParam = true
  addMethodToClass(eventControllerCls, "getControlMask", eventControllerGetControlMaskMethod, isClassMethod = true)

  # Add EventController methods to GtkWidget class (since controllers are installed on widgets)
  let widgetInstallKeyControllerMethod = createCoreMethod("installKeyController")
  widgetInstallKeyControllerMethod.nativeImpl = cast[pointer](widgetInstallKeyControllerImpl)
  widgetInstallKeyControllerMethod.hasInterpreterParam = true
  addMethodToClass(widgetCls, "installKeyController", widgetInstallKeyControllerMethod)

  let widgetOnKeyModifiersDoMethod = createCoreMethod("onKey:modifiers:do:")
  widgetOnKeyModifiersDoMethod.nativeImpl = cast[pointer](widgetOnKeyModifiersDoImpl)
  widgetOnKeyModifiersDoMethod.hasInterpreterParam = true
  addMethodToClass(widgetCls, "onKey:modifiers:do:", widgetOnKeyModifiersDoMethod)

  interp.globals[]["GtkEventController"] = eventControllerCls.toValue()
  debug("Registered GtkEventController class")

  # Create TextBuffer class (for TextView text storage)
  let textBufferCls = newClass(superclasses = @[objectClass], name = "GtkTextBuffer")
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

  let textBufferGetTextMethod = createCoreMethod("getText")
  textBufferGetTextMethod.nativeImpl = cast[pointer](textBufferGetTextImpl)
  textBufferGetTextMethod.hasInterpreterParam = true
  addMethodToClass(textBufferCls, "getText", textBufferGetTextMethod)

  let textBufferInsertAtMethod = createCoreMethod("insert:at:")
  textBufferInsertAtMethod.nativeImpl = cast[pointer](textBufferInsertAtImpl)
  textBufferInsertAtMethod.hasInterpreterParam = true
  addMethodToClass(textBufferCls, "insert:at:", textBufferInsertAtMethod)

  let textBufferDeleteToMethod = createCoreMethod("delete:to:")
  textBufferDeleteToMethod.nativeImpl = cast[pointer](textBufferDeleteToImpl)
  textBufferDeleteToMethod.hasInterpreterParam = true
  addMethodToClass(textBufferCls, "delete:to:", textBufferDeleteToMethod)

  let textBufferChangedMethod = createCoreMethod("changed:")
  textBufferChangedMethod.nativeImpl = cast[pointer](textBufferChangedImpl)
  textBufferChangedMethod.hasInterpreterParam = true
  addMethodToClass(textBufferCls, "changed:", textBufferChangedMethod)

  interp.globals[]["GtkTextBuffer"] = textBufferCls.toValue()
  debug("Registered GtkTextBuffer class")

  when not defined(gtk3):
    # Create AlertDialog class (GTK4 only)
    let alertDialogCls = newClass(superclasses = @[objectClass], name = "GtkAlertDialog")
    alertDialogCls.isNimProxy = true
    alertDialogCls.hardingType = "GtkAlertDialog"

    # Add AlertDialog class methods
    let alertDialogShowMethod = createCoreMethod("showAlertDialog:message:onResponse:")
    alertDialogShowMethod.nativeImpl = cast[pointer](alertDialogShowImpl)
    alertDialogShowMethod.hasInterpreterParam = true
    addMethodToClass(alertDialogCls, "showAlertDialog:message:onResponse:", alertDialogShowMethod, isClassMethod = true)

    let alertDialogConfirmMethod = createCoreMethod("showConfirmDialog:message:onYes:onNo:")
    alertDialogConfirmMethod.nativeImpl = cast[pointer](alertDialogConfirmImpl)
    alertDialogConfirmMethod.hasInterpreterParam = true
    addMethodToClass(alertDialogCls, "showConfirmDialog:message:onYes:onNo:", alertDialogConfirmMethod, isClassMethod = true)

    interp.globals[]["GtkAlertDialog"] = alertDialogCls.toValue()
    debug("Registered GtkAlertDialog class")

    # Create GtkPopover class (GTK4 only) - custom popover with button content
    let popoverCls = newClass(superclasses = @[widgetCls], name = "GtkPopover")
    popoverCls.isNimProxy = true
    popoverCls.hardingType = "GtkPopover"

    # Add Popover class methods
    let popoverNewMethod = createCoreMethod("new:")
    popoverNewMethod.nativeImpl = cast[pointer](popoverNewImpl)
    popoverNewMethod.hasInterpreterParam = true
    addMethodToClass(popoverCls, "new:", popoverNewMethod, isClassMethod = true)

    # Add Popover instance methods
    let popoverAddItemDoMethod = createCoreMethod("addItem:do:")
    popoverAddItemDoMethod.nativeImpl = cast[pointer](popoverAddItemDoImpl)
    popoverAddItemDoMethod.hasInterpreterParam = true
    addMethodToClass(popoverCls, "addItem:do:", popoverAddItemDoMethod)

    let popoverPopupAtXYMethod = createCoreMethod("popupAtX:y:")
    popoverPopupAtXYMethod.nativeImpl = cast[pointer](popoverPopupAtXYImpl)
    popoverPopupAtXYMethod.hasInterpreterParam = true
    addMethodToClass(popoverCls, "popupAtX:y:", popoverPopupAtXYMethod)

    let popoverPopupMethod = createCoreMethod("popup")
    popoverPopupMethod.nativeImpl = cast[pointer](popoverPopupImpl)
    popoverPopupMethod.hasInterpreterParam = true
    addMethodToClass(popoverCls, "popup", popoverPopupMethod)

    let popoverClearMethod = createCoreMethod("clear")
    popoverClearMethod.nativeImpl = cast[pointer](popoverClearImpl)
    popoverClearMethod.hasInterpreterParam = true
    addMethodToClass(popoverCls, "clear", popoverClearMethod)

    let popoverAddSeparatorMethod = createCoreMethod("addSeparator")
    popoverAddSeparatorMethod.nativeImpl = cast[pointer](popoverAddSeparatorImpl)
    popoverAddSeparatorMethod.hasInterpreterParam = true
    addMethodToClass(popoverCls, "addSeparator", popoverAddSeparatorMethod)

    interp.globals[]["GtkPopover"] = popoverCls.toValue()
    debug("Registered GtkPopover class")

    # Register gesture click method on GtkWidget (GTK4 only)
    let widgetOnRightClickMethod = createCoreMethod("onRightClick:")
    widgetOnRightClickMethod.nativeImpl = cast[pointer](widgetOnRightClickImpl)
    widgetOnRightClickMethod.hasInterpreterParam = true
    addMethodToClass(widgetCls, "onRightClick:", widgetOnRightClickMethod)

    debug("Registered onRightClick: method on GtkWidget")

  when defined(gtk3):
    # Create MenuItem class (GTK3 only)
    let menuItemCls = newClass(superclasses = @[widgetCls], name = "GtkMenuItem")
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
  let launcherCls = newClass(superclasses = @[windowCls], slotNames = @["windows", "nextWorkspaceId"], name = "Launcher")
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
  ## Load the Harding-side GTK wrapper classes from lib/gui/gtk4/
  let libPath = if basePath.len > 0:
    basePath / "lib" / "gui" / "gtk4"
  elif interp.hardingHome.len > 0:
    interp.hardingHome / "lib" / "gui" / "gtk4"
  else:
    "lib" / "gui" / "gtk4"

  debug("Loading GTK wrapper files from: ", libPath)

  let wrapperFiles = [
    "Widget.hrd",
    "Window.hrd",
    "Button.hrd",
    "Box.hrd",
    "Paned.hrd",
    "ListBox.hrd",
    "ScrolledWindow.hrd",
    "Label.hrd",
    "TextView.hrd",
    "TextBuffer.hrd",
    "SourceView.hrd",
    "EventController.hrd",
    "ContextMenu.hrd"
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
        error("Failed to load ", filepath, ": ", err)
        error("Bona cannot start due to errors loading GTK wrappers. Please fix the errors above.")
        quit(1)
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
          error("Failed to load ", filepath, ": ", err)
          error("Bona cannot start due to errors loading GTK3 wrappers. Please fix the errors above.")
          quit(1)
        else:
          debug("Successfully loaded: ", filepath)
      else:
        debug("GTK wrapper file not found (optional): ", filepath)

## Load IDE tool files
proc loadIdeToolFiles*(interp: var Interpreter, basePath: string = "") =
  ## Load the IDE tool classes from lib/gui/bona/
  let libPath = if basePath.len > 0:
    basePath / "lib" / "gui" / "bona"
  elif interp.hardingHome.len > 0:
    interp.hardingHome / "lib" / "gui" / "bona"
  else:
    "lib" / "gui" / "bona"

  debug("Loading IDE tool files from: ", libPath)

  let toolFiles = [
    "Catalog.hrd",
    "BrowserModel.hrd",
    "InspectorModel.hrd",
    "BuilderModel.hrd",
    "BrowserPane.hrd",
    "Browser.hrd",
    "Inspector.hrd",
    "Transcript.hrd",
    "Workspace.hrd",
    "Launcher.hrd",
    "Builder.hrd"
  ]

  for filename in toolFiles:
    let filepath = libPath / filename
    if fileExists(filepath):
      debug("Loading IDE tool: ", filepath)
      let source = readFile(filepath)
      let (_, err) = interp.evalStatements(source)
      if err.len > 0:
        error("Failed to load ", filepath, ": ", err)
        error("Bona cannot start due to errors loading IDE tools. Please fix the errors above.")
        quit(1)
      else:
        debug("Successfully loaded: ", filepath)
    else:
      debug("IDE tool file not found (optional): ", filepath)

## Launcher new implementation - separated to avoid closure capture issues
proc launcherNewImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
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
