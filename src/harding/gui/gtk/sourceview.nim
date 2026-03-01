## ============================================================================
## GtkSourceViewProxy - Source code editor widget wrapper
## ============================================================================

import std/[logging, tables]
import harding/core/types
import ./ffi
import ./widget
import ./textbuffer

type
  GtkSourceViewProxyObj* = object of GtkWidgetProxyObj

  GtkSourceViewProxy* = ref GtkSourceViewProxyObj

## Factory: Create new source view proxy
proc newGtkSourceViewProxy*(widget: GtkSourceView, interp: ptr Interpreter): GtkSourceViewProxy =
  result = GtkSourceViewProxy(
    widget: widget,
    interp: interp,
    signalHandlers: initTable[string, seq[SignalHandler]](),
    destroyed: false
  )
  proxyTable[cast[GtkWidget](widget)] = result

## Initialize GtkSourceView library (call once)
proc initSourceView*() =
  ## Initialize the source view library
  # Note: gtk_source_init() is only needed in some versions
  # The library initializes automatically when first used
  debug("GtkSourceView ready")

## Native class method: new
proc sourceViewNewImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Create a new source view with Harding syntax highlighting
  let widget = gtkSourceViewNew()
  discard newGtkSourceViewProxy(widget, addr(interp))

  # Configure the source view
  gtkSourceViewSetShowLineNumbers(widget, 1)
  gtkSourceViewSetHighlightCurrentLine(widget, 1)
  gtkSourceViewSetAutoIndent(widget, 1)
  gtkSourceViewSetIndentOnTab(widget, 1)
  gtkSourceViewSetTabWidth(widget, 2)

  # Set up syntax highlighting for Harding
  let langManager = gtkSourceLanguageManagerGetDefault()
  if langManager != nil:
    # Try to find the Harding language definition
    var hardingLang = gtkSourceLanguageManagerGetLanguage(langManager, "harding")

    # Get or create buffer and set language
    var buffer = gtkTextViewGetBuffer(cast[GtkTextView](widget))
    if buffer == nil:
      if hardingLang != nil:
        buffer = gtkSourceBufferNewWithLanguage(hardingLang)
        gtkSourceBufferSetHighlightSyntax(cast[GtkSourceBuffer](buffer), 1)
        debug("Created source buffer with Harding language")
      else:
        buffer = gtkSourceBufferNew(nil)
        debug("Created source buffer without language (Harding definition not found - install harding.lang to /usr/share/gtksourceview-5/language-specs/ or /usr/share/gtksourceview-4/language-specs/)")
      gtkTextViewSetBuffer(cast[GtkTextView](widget), buffer)
    else:
      # Cast buffer to source buffer and set language
      if hardingLang != nil:
        gtkSourceBufferSetLanguage(cast[GtkSourceBuffer](buffer), hardingLang)
        gtkSourceBufferSetHighlightSyntax(cast[GtkSourceBuffer](buffer), 1)
        debug("Set Harding language on existing buffer")

  var cls: Class = nil
  if "GtkSourceView" in interp.globals[]:
    let val = interp.globals[]["GtkSourceView"]
    if val.kind == vkClass:
      cls = val.classVal
  if cls == nil and "GtkWidget" in interp.globals[]:
    let val = interp.globals[]["GtkWidget"]
    if val.kind == vkClass:
      cls = val.classVal
  if cls == nil:
    cls = objectClass

  let obj = newInstance(cls)
  obj.isNimProxy = true
  storeInstanceWidget(obj, cast[GtkWidget](widget))
  obj.nimValue = cast[pointer](widget)
  return obj.toValue()

## Native instance method: getText:
proc sourceViewGetTextImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Get all text from the source view
  if not (self.isNimProxy and self.nimValue != nil):
    return nilValue()

  let widget = cast[GtkSourceView](self.nimValue)

  let buffer = gtkTextViewGetBuffer(cast[GtkTextView](widget))
  if buffer == nil:
    return "".toValue()

  # GtkTextIter is an opaque struct - allocate storage (256 bytes to be safe)
  var startIterStorage: array[256, byte]
  var endIterStorage: array[256, byte]
  let startIter = cast[GtkTextIter](addr(startIterStorage[0]))
  let endIter = cast[GtkTextIter](addr(endIterStorage[0]))

  gtkTextBufferGetStartIter(buffer, startIter)
  gtkTextBufferGetEndIter(buffer, endIter)

  let text = gtkTextBufferGetText(buffer, startIter, endIter, 1)
  if text == nil:
    return "".toValue()

  result = toValue($text)

## Native instance method: setText:
proc sourceViewSetTextImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Set text in the source view
  if args.len < 1 or args[0].kind != vkString:
    return nilValue()

  if not (self.isNimProxy and self.nimValue != nil):
    return nilValue()

  let widget = cast[GtkSourceView](self.nimValue)

  let buffer = gtkTextViewGetBuffer(cast[GtkTextView](widget))
  if buffer == nil:
    return nilValue()

  gtkTextBufferSetText(buffer, args[0].strVal.cstring, -1)

  debug("Set text in source view")

  nilValue()

## Native instance method: getSelectedText:
proc sourceViewGetSelectedTextImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Get selected text or current line if no selection
  debug("getSelectedTextImpl: ENTRY")
  if not (self.isNimProxy and self.nimValue != nil):
    debug("getSelectedTextImpl: Not a NimProxy or nimValue is nil")
    return nilValue()

  let widget = cast[GtkSourceView](self.nimValue)
  debug("getSelectedTextImpl: widget=", cast[int](widget))
  let buffer = gtkTextViewGetBuffer(cast[GtkTextView](widget))
  debug("getSelectedTextImpl: buffer=", cast[int](buffer))
  if buffer == nil:
    debug("getSelectedTextImpl: buffer is nil, returning empty")
    return "".toValue()

  # GtkTextIter is an opaque struct - allocate storage (256 bytes to be safe)
  var startIterStorage: array[256, byte]
  var endIterStorage: array[256, byte]
  let startIter = cast[GtkTextIter](addr(startIterStorage[0]))
  let endIter = cast[GtkTextIter](addr(endIterStorage[0]))

  debug("getSelectedTextImpl: About to get selection bounds")

  # Check if there's a selection using selection bounds
  let hasSelection = gtkTextBufferGetSelectionBounds(buffer, startIter, endIter)
  debug("getSelectedTextImpl: hasSelection=", hasSelection)

  if hasSelection == 0:
    # No selection, get current line
    debug("getSelectedTextImpl: No selection, getting current line")
    let insertMark = gtkTextBufferGetInsert(buffer)
    debug("getSelectedTextImpl: insertMark=", cast[int](insertMark))
    gtkTextBufferGetIterAtMark(buffer, startIter, insertMark)
    debug("getSelectedTextImpl: Got iter at mark")
    gtkTextIterSetLineOffset(startIter, 0)
    debug("getSelectedTextImpl: Set line offset")
    gtkTextBufferGetIterAtMark(buffer, endIter, insertMark)
    debug("getSelectedTextImpl: About to forward to line end")
    discard gtkTextIterForwardToLineEnd(endIter)
    debug("getSelectedTextImpl: Forwarded to line end")

  debug("getSelectedTextImpl: About to get text")
  let text = gtkTextBufferGetText(buffer, startIter, endIter, 1)
  debug("getSelectedTextImpl: text=", cast[int](text))
  if text == nil:
    debug("getSelectedTextImpl: text is nil, returning empty")
    return "".toValue()

  result = toValue($text)
  debug("getSelectedTextImpl: EXIT, result=", result.toString())

## Native instance method: showLineNumbers:
proc sourceViewShowLineNumbersImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Show or hide line numbers
  if args.len < 1 or args[0].kind != vkBool:
    return nilValue()

  if not (self.isNimProxy and self.nimValue != nil):
    return nilValue()

  let widget = cast[GtkSourceView](self.nimValue)
  gtkSourceViewSetShowLineNumbers(widget, if args[0].boolVal: 1 else: 0)
  return nilValue()

## Native instance method: setTabWidth:
proc sourceViewSetTabWidthImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Set tab width in spaces
  if args.len < 1 or args[0].kind != vkInt:
    return nilValue()

  if not (self.isNimProxy and self.nimValue != nil):
    return nilValue()

  let widget = cast[GtkSourceView](self.nimValue)
  gtkSourceViewSetTabWidth(widget, args[0].intVal.cuint)
  return nilValue()

## Native instance method: buffer
proc sourceViewBufferImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Get the text buffer from the source view
  if not (self.isNimProxy and self.nimValue != nil):
    return nilValue()

  let widget = cast[GtkSourceView](self.nimValue)
  let buffer = gtkTextViewGetBuffer(cast[GtkTextView](widget))
  if buffer == nil:
    return nilValue()

  # Return the existing GtkTextBuffer proxy for this buffer
  # First check if we already have a proxy for this buffer
  if "GtkTextBuffer" in interp.globals[]:
    let val = interp.globals[]["GtkTextBuffer"]
    if val.kind == vkClass:
      let cls = val.classVal
      let obj = newInstance(cls)
      obj.isNimProxy = true
      
      # Create or get the buffer proxy
      let proxy = newGtkTextBufferProxy(buffer, addr(interp))
      GC_ref(cast[ref RootObj](proxy))
      obj.nimValue = cast[pointer](proxy)
      return obj.toValue()

  return nilValue()
