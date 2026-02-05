## ============================================================================
## GTK FFI Bindings for Nemo
## Supports both GTK3 and GTK4 via compile-time flag
## Use -d:gtk4 to compile with GTK4 support (default is GTK3)
## ============================================================================

when defined(gtk4):
  {.passl: "-lgtk-4 -lgio-2.0 -lgobject-2.0 -lglib-2.0".}
else:
  {.passl: "-lgtk-3 -lgio-2.0 -lgobject-2.0 -lglib-2.0".}

## Types
type
  GtkWidget* = pointer
  GtkWindow* = pointer
  GtkButton* = pointer
  GtkBox* = pointer
  GtkLabel* = pointer
  GtkApplication* = pointer
  GtkApplicationWindow* = pointer
  GApplication* = pointer
  GObject* = pointer
  GCallback* = pointer
  GClosureNotify* = pointer
  GtkMenuBar* = pointer
  GtkMenu* = pointer
  GtkMenuItem* = pointer
  GtkTextView* = pointer
  GtkTextBuffer* = pointer
  GtkTextIter* = pointer
  GtkScrolledWindow* = pointer

  GType* = csize_t
  GConnectFlags* = cint

const
  GCONNECTAFTER* = 1.GConnectFlags
  GCONNECTSWAPPED* = 2.GConnectFlags

when defined(gtk4):
  # GTK4 specific imports
  proc gtkWindowNew*(): GtkWindow {.cdecl, importc: "gtk_window_new".}
  proc gtkWindowSetChild*(window: GtkWindow, child: GtkWidget) {.cdecl, importc: "gtk_window_set_child".}
  proc gtkBoxAppend*(box: GtkBox, child: GtkWidget) {.cdecl, importc: "gtk_box_append".}
  proc gtkBoxPrepend*(box: GtkBox, child: GtkWidget) {.cdecl, importc: "gtk_box_prepend".}
  proc gtkWidgetAddCssClass*(widget: GtkWidget, cssClass: cstring) {.cdecl, importc: "gtk_widget_add_css_class".}
  proc gtkWidgetRemoveCssClass*(widget: GtkWidget, cssClass: cstring) {.cdecl, importc: "gtk_widget_remove_css_class".}
  proc gtkInit*() {.cdecl, importc: "gtk_init".}

  const
    GTKORIENTATIONHORIZONTAL* = 0.cint
    GTKORIENTATIONVERTICAL* = 1.cint

else:
  # GTK3 specific imports
  proc gtkWindowNew*(windowType: cint): GtkWindow {.cdecl, importc: "gtk_window_new".}
  proc gtkContainerAdd*(container: pointer, widget: GtkWidget) {.cdecl, importc: "gtk_container_add".}
  proc gtkBoxPackStart*(box: GtkBox, child: GtkWidget, expand: cint, fill: cint, padding: cuint) {.cdecl, importc: "gtk_box_pack_start".}
  proc gtkBoxPackEnd*(box: GtkBox, child: GtkWidget, expand: cint, fill: cint, padding: cuint) {.cdecl, importc: "gtk_box_pack_end".}

  const
    GTKWINDOWTOPLEVEL* = 0.cint
    GTKORIENTATIONHORIZONTAL* = 0.cint
    GTKORIENTATIONVERTICAL* = 1.cint

  proc gtkInit*(argc: pointer, argv: pointer) {.cdecl, importc: "gtk_init".}

# Common GTK functions (both versions)
proc gtkWindowSetTitle*(window: GtkWindow, title: cstring) {.cdecl, importc: "gtk_window_set_title".}
proc gtkWindowSetDefaultSize*(window: GtkWindow, width: cint, height: cint) {.cdecl, importc: "gtk_window_set_default_size".}
proc gtkWindowPresent*(window: GtkWindow) {.cdecl, importc: "gtk_window_present".}
proc gtkWindowClose*(window: GtkWindow) {.cdecl, importc: "gtk_window_close".}

# GTK Button
proc gtkButtonNew*(): GtkButton {.cdecl, importc: "gtk_button_new".}
proc gtkButtonNewWithLabel*(label: cstring): GtkButton {.cdecl, importc: "gtk_button_new_with_label".}
proc gtkButtonSetLabel*(button: GtkButton, label: cstring) {.cdecl, importc: "gtk_button_set_label".}
proc gtkButtonGetLabel*(button: GtkButton): cstring {.cdecl, importc: "gtk_button_get_label".}

# GTK Box
proc gtkBoxNew*(orientation: cint, spacing: cint): GtkBox {.cdecl, importc: "gtk_box_new".}
proc gtkBoxSetSpacing*(box: GtkBox, spacing: cint) {.cdecl, importc: "gtk_box_set_spacing".}

# GTK Label
proc gtkLabelNew*(text: cstring): GtkLabel {.cdecl, importc: "gtk_label_new".}
proc gtkLabelSetText*(label: GtkLabel, text: cstring) {.cdecl, importc: "gtk_label_set_text".}
proc gtkLabelGetText*(label: GtkLabel): cstring {.cdecl, importc: "gtk_label_get_text".}

# GTK Widget (base)
proc gtkWidgetShow*(widget: GtkWidget) {.cdecl, importc: "gtk_widget_show".}
proc gtkWidgetHide*(widget: GtkWidget) {.cdecl, importc: "gtk_widget_hide".}
proc gtkWidgetShowAll*(widget: GtkWidget) {.cdecl, importc: "gtk_widget_show_all".}
proc gtkWidgetSetSizeRequest*(widget: GtkWidget, width: cint, height: cint) {.cdecl, importc: "gtk_widget_set_size_request".}

# GObject signals
proc gSignalConnectData*(instance: GObject, detailedSignal: cstring, cHandler: GCallback,
                         data: pointer, destroyData: GClosureNotify, connectFlags: GConnectFlags): culong {.cdecl, importc: "g_signal_connect_data".}

proc gSignalEmit*(instance: GObject, signalId: cuint, detail: cuint) {.cdecl, importc: "g_signal_emit_by_name".}

# GTK Main Loop (GTK3 only)
when not defined(gtk4):
  proc gtkMain*() {.cdecl, importc: "gtk_main".}
  proc gtkMainQuit*() {.cdecl, importc: "gtk_main_quit".}
  proc gtkMainIterationDo*(blocking: cint): cint {.cdecl, importc: "gtk_main_iteration_do".}

# GTK4 Application support
type
  GApplicationFlags* = cint

when defined(gtk4):
  proc gtkApplicationNew*(applicationId: cstring, flags: GApplicationFlags): GtkApplication {.cdecl, importc: "gtk_application_new".}
  proc gApplicationRun*(app: GApplication, argc: cint, argv: pointer): cint {.cdecl, importc: "g_application_run".}
  proc gApplicationQuit*(app: GApplication) {.cdecl, importc: "g_application_quit".}
  proc gtkApplicationWindowNew*(app: GtkApplication): GtkWindow {.cdecl, importc: "gtk_application_window_new".}

  const
    GAPPLICATIONFLAGSNONE* = 0.GApplicationFlags

# GObject reference counting
proc gObjectRef*(obj: pointer): pointer {.cdecl, importc: "g_object_ref".}
proc gObjectUnref*(obj: pointer) {.cdecl, importc: "g_object_unref".}

# Helper for signal connection
proc gSignalConnect*(instance: GObject, signal: cstring, cHandler: GCallback, data: pointer): culong =
  gSignalConnectData(instance, signal, cHandler, data, nil, 0.GConnectFlags)

# Helper to initialize GTK (works with both versions)
when defined(gtk4):
  proc initGtk*() =
    gtkInit()
else:
  proc initGtk*() =
    gtkInit(nil, nil)

# GTK MenuBar, Menu, MenuItem (GTK3 only - not available in GTK4)
when not defined(gtk4):
  proc gtkMenuBarNew*(): GtkMenuBar {.cdecl, importc: "gtk_menu_bar_new".}
  proc gtkMenuNew*(): GtkMenu {.cdecl, importc: "gtk_menu_new".}
  proc gtkMenuPopupAtPointer*(menu: GtkMenu, triggerEvent: pointer) {.cdecl, importc: "gtk_menu_popup_at_pointer".}
  proc gtkMenuItemNew*(): GtkMenuItem {.cdecl, importc: "gtk_menu_item_new".}
  proc gtkMenuItemNewWithLabel*(label: cstring): GtkMenuItem {.cdecl, importc: "gtk_menu_item_new_with_label".}
  proc gtkShellAppend*(menuShell: pointer, child: GtkWidget) {.cdecl, importc: "gtk_shell_append".}

# GTK4 doesn't have GtkMenuBar/GtkMenu/GtkMenuItem
when defined(gtk4):
  # Stub implementations to allow compilation
  # In GTK4, menus are implemented using GMenuModel and GtkPopover
  # These use gtk_box_new and gtk_button_new as fallbacks with proper parameters
  proc gtkMenuBarNew*(): GtkMenuBar {.cdecl.} =
    cast[GtkMenuBar](gtkBoxNew(0.cint, 0.cint))  # Horizontal box, no spacing

  proc gtkMenuNew*(): GtkMenu {.cdecl.} =
    cast[GtkMenu](gtkBoxNew(1.cint, 0.cint))  # Vertical box, no spacing

  proc gtkMenuPopupAtPointer*(menu: GtkMenu, triggerEvent: pointer) {.cdecl.} =
    discard  # Stub for GTK4

  proc gtkMenuItemNew*(): GtkMenuItem {.cdecl.} =
    cast[GtkMenuItem](gtkButtonNew())

  proc gtkMenuItemNewWithLabel*(label: cstring): GtkMenuItem {.cdecl.} =
    cast[GtkMenuItem](gtkButtonNewWithLabel(label))

# TextView and TextBuffer
proc gtkTextViewNew*(): GtkTextView {.cdecl, importc: "gtk_text_view_new".}
proc gtkTextViewGetBuffer*(view: GtkTextView): GtkTextBuffer {.cdecl, importc: "gtk_text_view_get_buffer".}
proc gtkTextViewSetBuffer*(view: GtkTextView, buffer: GtkTextBuffer) {.cdecl, importc: "gtk_text_view_set_buffer".}

proc gtkTextBufferNew*(tagTable: pointer = nil): GtkTextBuffer {.cdecl, importc: "gtk_text_buffer_new".}
proc gtkTextBufferSetText*(buffer: GtkTextBuffer, text: cstring, len: cint = -1) {.cdecl, importc: "gtk_text_buffer_set_text".}
proc gtkTextBufferGetText*(buffer: GtkTextBuffer, start: GtkTextIter, endIter: GtkTextIter,
                          includeHidden: cint): cstring {.cdecl, importc: "gtk_text_buffer_get_text".}
proc gtkTextBufferGetStartIter*(buffer: GtkTextBuffer, iter: GtkTextIter) {.cdecl, importc: "gtk_text_buffer_get_start_iter".}
proc gtkTextBufferGetEndIter*(buffer: GtkTextBuffer, iter: GtkTextIter) {.cdecl, importc: "gtk_text_buffer_get_end_iter".}
proc gtkTextBufferInsertAtCursor*(buffer: GtkTextBuffer, text: cstring, len: cint = -1) {.cdecl, importc: "gtk_text_buffer_insert_at_cursor".}

# GtkTextIter operations
proc gtkTextIterGetOffset*(iter: GtkTextIter): cint {.cdecl, importc: "gtk_text_iter_get_offset".}
proc gtkTextBufferGetIterAtOffset*(buffer: GtkTextBuffer, iter: GtkTextIter, charOffset: cint) {.cdecl, importc: "gtk_text_buffer_get_iter_at_offset".}
proc gtkTextBufferDelete*(buffer: GtkTextBuffer, start: GtkTextIter, endIter: GtkTextIter) {.cdecl, importc: "gtk_text_buffer_delete".}

# ScrolledWindow (for wrapping TextView)
proc gtkScrolledWindowNew*(): GtkScrolledWindow {.cdecl, importc: "gtk_scrolled_window_new".}
when defined(gtk4):
  proc gtkScrolledWindowSetChild*(scrolled: GtkScrolledWindow, child: GtkWidget) {.cdecl, importc: "gtk_scrolled_window_set_child".}
  # GLib main loop iteration for GTK4 event processing
  proc gMainContextIteration*(context: pointer = nil, mayBlock: cint): cint {.cdecl, importc: "g_main_context_iteration".}
else:
  proc gtkContainerAdd*(container: pointer, widget: GtkWidget) {.cdecl, importc: "gtk_container_add".}
