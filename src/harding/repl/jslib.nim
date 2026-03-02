#
# jslib.nim - Embedded Harding library files for JavaScript compilation
#
# This module uses staticRead to embed all library files at compile time,
# eliminating the need for file I/O in the browser environment.
#
# The library files are organized by category:
# - Core: fundamental classes and mixins (loaded into globals)
# - Standard: extra collection and I/O classes (loaded into Standard)
# - Granite: compiler support classes (loaded into GraniteLib)
#

import std/[tables, strutils]
import ../core/types
import ../interpreter/vm
import ../interpreter/objects

# ============================================================================
# Embedded Library Files
# ============================================================================

# Core library files (loaded into globals)
const EmbeddedObjectHrd = staticRead("../../../lib/core/Object.hrd")
const EmbeddedBooleanHrd = staticRead("../../../lib/core/Boolean.hrd")
const EmbeddedTrueHrd = staticRead("../../../lib/core/True.hrd")
const EmbeddedFalseHrd = staticRead("../../../lib/core/False.hrd")
const EmbeddedUndefinedObjectHrd = staticRead("../../../lib/core/UndefinedObject.hrd")
const EmbeddedBlockHrd = staticRead("../../../lib/core/Block.hrd")
const EmbeddedLibraryHrd = staticRead("../../../lib/core/Library.hrd")
const EmbeddedNumberHrd = staticRead("../../../lib/core/Number.hrd")
const EmbeddedIntegerHrd = staticRead("../../../lib/core/Integer.hrd")
const EmbeddedFloatHrd = staticRead("../../../lib/core/Float.hrd")
const EmbeddedStringHrd = staticRead("../../../lib/core/String.hrd")
const EmbeddedSymbolHrd = staticRead("../../../lib/core/Symbol.hrd")
const EmbeddedArrayHrd = staticRead("../../../lib/core/Array.hrd")
const EmbeddedTableHrd = staticRead("../../../lib/core/Table.hrd")
const EmbeddedSetHrd = staticRead("../../../lib/core/Set.hrd")
const EmbeddedSystemHrd = staticRead("../../../lib/core/System.hrd")
const EmbeddedExceptionHrd = staticRead("../../../lib/core/Exception.hrd")
const EmbeddedErrorHrd = staticRead("../../../lib/core/Error.hrd")
const EmbeddedNotificationHrd = staticRead("../../../lib/core/Notification.hrd")
const EmbeddedMessageNotUnderstoodHrd = staticRead("../../../lib/core/MessageNotUnderstood.hrd")
const EmbeddedSubscriptOutOfBoundsHrd = staticRead("../../../lib/core/SubscriptOutOfBounds.hrd")
const EmbeddedDivisionByZeroHrd = staticRead("../../../lib/core/DivisionByZero.hrd")
const EmbeddedUnhandledErrorHrd = staticRead("../../../lib/core/UnhandledError.hrd")
const EmbeddedComparableHrd = staticRead("../../../lib/core/Comparable.hrd")
const EmbeddedIterableHrd = staticRead("../../../lib/core/Iterable.hrd")
const EmbeddedPrintableHrd = staticRead("../../../lib/core/Printable.hrd")
const EmbeddedSynchronizableHrd = staticRead("../../../lib/process/Synchronizable.hrd")

# Standard library files (loaded into Standard Library)
const EmbeddedSortedCollectionHrd = staticRead("../../../lib/standard/SortedCollection.hrd")
const EmbeddedIntervalHrd = staticRead("../../../lib/standard/Interval.hrd")
const EmbeddedFileHrd = staticRead("../../../lib/standard/File.hrd")
const EmbeddedFileStreamHrd = staticRead("../../../lib/standard/FileStream.hrd")
const EmbeddedTestCaseHrd = staticRead("../../../lib/standard/TestCase.hrd")

# Granite library files (loaded into GraniteLib)
const EmbeddedApplicationHrd = staticRead("../../../lib/granite/Application.hrd")
const EmbeddedGraniteHrd = staticRead("../../../lib/granite/Granite.hrd")

# ============================================================================
# Library Loading
# ============================================================================

proc loadEmbeddedSource(interp: var Interpreter, source, filename: string) =
  ## Load and evaluate an embedded source string
  debug("Loading embedded: ", filename)
  let (_, err) = interp.evalStatements(source)
  if err.len > 0:
    warn("Failed to load embedded ", filename, ": ", err)
  else:
    debug("Successfully loaded: ", filename)

proc loadEmbeddedStdlib*(interp: var Interpreter) =
  ## Load all embedded library files into the interpreter
  ## This replaces the file-based loadStdlib for JS environments

  # Load core files into globals
  loadEmbeddedSource(interp, EmbeddedObjectHrd, "Object.hrd")
  loadEmbeddedSource(interp, EmbeddedBooleanHrd, "Boolean.hrd")
  loadEmbeddedSource(interp, EmbeddedTrueHrd, "True.hrd")
  loadEmbeddedSource(interp, EmbeddedFalseHrd, "False.hrd")
  loadEmbeddedSource(interp, EmbeddedUndefinedObjectHrd, "UndefinedObject.hrd")
  loadEmbeddedSource(interp, EmbeddedBlockHrd, "Block.hrd")
  loadEmbeddedSource(interp, EmbeddedLibraryHrd, "Library.hrd")
  loadEmbeddedSource(interp, EmbeddedNumberHrd, "Number.hrd")
  loadEmbeddedSource(interp, EmbeddedIntegerHrd, "Integer.hrd")
  loadEmbeddedSource(interp, EmbeddedFloatHrd, "Float.hrd")
  loadEmbeddedSource(interp, EmbeddedStringHrd, "String.hrd")
  loadEmbeddedSource(interp, EmbeddedSymbolHrd, "Symbol.hrd")
  loadEmbeddedSource(interp, EmbeddedArrayHrd, "Array.hrd")
  loadEmbeddedSource(interp, EmbeddedTableHrd, "Table.hrd")
  loadEmbeddedSource(interp, EmbeddedSetHrd, "Set.hrd")
  loadEmbeddedSource(interp, EmbeddedSystemHrd, "System.hrd")
  loadEmbeddedSource(interp, EmbeddedExceptionHrd, "Exception.hrd")
  loadEmbeddedSource(interp, EmbeddedErrorHrd, "Error.hrd")
  loadEmbeddedSource(interp, EmbeddedNotificationHrd, "Notification.hrd")
  loadEmbeddedSource(interp, EmbeddedMessageNotUnderstoodHrd, "MessageNotUnderstood.hrd")
  loadEmbeddedSource(interp, EmbeddedSubscriptOutOfBoundsHrd, "SubscriptOutOfBounds.hrd")
  loadEmbeddedSource(interp, EmbeddedDivisionByZeroHrd, "DivisionByZero.hrd")
  loadEmbeddedSource(interp, EmbeddedUnhandledErrorHrd, "UnhandledError.hrd")
  loadEmbeddedSource(interp, EmbeddedComparableHrd, "Comparable.hrd")
  loadEmbeddedSource(interp, EmbeddedIterableHrd, "Iterable.hrd")
  loadEmbeddedSource(interp, EmbeddedPrintableHrd, "Printable.hrd")

  # Create Process library
  discard interp.doit("ProcessLibrary := Library new.")
  discard interp.doit("ProcessLibrary name: \"Process\".")
  loadEmbeddedSource(interp, EmbeddedSynchronizableHrd, "Synchronizable.hrd")
  discard interp.doit("ProcessLibrary at: \"Process\" put: Process.")
  discard interp.doit("ProcessLibrary at: \"Scheduler\" put: Scheduler.")
  discard interp.doit("ProcessLibrary at: \"Processor\" put: Processor.")
  discard interp.doit("ProcessLibrary at: \"Monitor\" put: Monitor.")
  discard interp.doit("ProcessLibrary at: \"Semaphore\" put: Semaphore.")
  discard interp.doit("ProcessLibrary at: \"SharedQueue\" put: SharedQueue.")

  # Create Standard Library
  discard interp.doit("Standard := Library new.")

  # Load standard library files into Standard
  loadEmbeddedSource(interp, EmbeddedSortedCollectionHrd, "SortedCollection.hrd")
  loadEmbeddedSource(interp, EmbeddedIntervalHrd, "Interval.hrd")
  loadEmbeddedSource(interp, EmbeddedFileHrd, "File.hrd")
  loadEmbeddedSource(interp, EmbeddedFileStreamHrd, "FileStream.hrd")
  loadEmbeddedSource(interp, EmbeddedTestCaseHrd, "TestCase.hrd")

  # Create Granite library
  discard interp.doit("GraniteLib := Library new.")
  loadEmbeddedSource(interp, EmbeddedApplicationHrd, "Application.hrd")
  loadEmbeddedSource(interp, EmbeddedGraniteHrd, "Granite.hrd")

  # Auto-import Standard for backward compatibility
  # Find Standard library instance and add to imported libraries
  if "Standard" in interp.globals[]:
    let standardVal = interp.globals[]["Standard"]
    if standardVal.kind == vkInstance and standardVal.instVal != nil:
      interp.importedLibraries.add(standardVal.instVal)
      debug("Auto-imported Standard library")

  if "ProcessLibrary" in interp.globals[]:
    let processVal = interp.globals[]["ProcessLibrary"]
    if processVal.kind == vkInstance and processVal.instVal != nil:
      interp.importedLibraries.add(processVal.instVal)
      debug("Auto-imported Process library")

  if "GraniteLib" in interp.globals[]:
    let graniteVal = interp.globals[]["GraniteLib"]
    if graniteVal.kind == vkInstance and graniteVal.instVal != nil:
      interp.importedLibraries.add(graniteVal.instVal)
      debug("Auto-imported GraniteLib library")

  # Set up class caches (similar to loadStdlib in vm.nim)
  if "Number" in interp.globals[]:
    let numVal = interp.globals[]["Number"]
    if numVal.kind == vkClass:
      numberClassCache = numVal.classVal
      debug("Set numberClassCache from Number global")

  if "Integer" in interp.globals[]:
    let intVal = interp.globals[]["Integer"]
    if intVal.kind == vkClass:
      integerClassCache = intVal.classVal
      debug("Set integerClassCache from Integer global")

  if "String" in interp.globals[]:
    let strVal = interp.globals[]["String"]
    if strVal.kind == vkClass:
      stringClassCache = strVal.classVal
      debug("Set stringClassCache from String global")

  if "Boolean" in interp.globals[]:
    let boolVal = interp.globals[]["Boolean"]
    if boolVal.kind == vkClass:
      booleanClassCache = boolVal.classVal
      debug("Set booleanClassCache from Boolean global")

  if "True" in interp.globals[]:
    let trueVal = interp.globals[]["True"]
    if trueVal.kind == vkClass:
      trueClassCache = trueVal.classVal
      debug("Set trueClassCache from True global")

  if "False" in interp.globals[]:
    let falseVal = interp.globals[]["False"]
    if falseVal.kind == vkClass:
      falseClassCache = falseVal.classVal
      debug("Set falseClassCache from False global")

  if "Block" in interp.globals[]:
    let blockVal = interp.globals[]["Block"]
    if blockVal.kind == vkClass:
      blockClassCache = blockVal.classVal
      debug("Set blockClassCache from Block global")

  if "Table" in interp.globals[]:
    let tableVal = interp.globals[]["Table"]
    if tableVal.kind == vkClass:
      tableClassCache = tableVal.classVal
      debug("Set tableClassCache from Table global")

  # Set up FileStream class and standard stream globals
  let fileStreamCls = if "FileStream" in interp.globals[]:
                         let fsVal = interp.globals[]["FileStream"]
                         if fsVal.kind == vkClass: fsVal.classVal else: nil
                       else:
                         nil

  if fileStreamCls != nil:
    let stdoutInstance = fileStreamCls.newInstance()
    let stderrInstance = fileStreamCls.newInstance()
    let stdinInstance = fileStreamCls.newInstance()
    interp.globals[]["Stdout"] = stdoutInstance.toValue()
    interp.globals[]["Stderr"] = stderrInstance.toValue()
    interp.globals[]["Stdin"] = stdinInstance.toValue()
    debug("Created Stdout instance from FileStream class")

# ============================================================================
# JS-Specific Stdout Setup
# ============================================================================

proc setupJSStdout*(interp: var Interpreter) =
  ## Set up standard stream globals for JS environment
  ## FileStream methods use console.log via emit in objects.nim

  # Find FileStream class
  let fileStreamCls = if "FileStream" in interp.globals[]:
                         let fsVal = interp.globals[]["FileStream"]
                         if fsVal.kind == vkClass: fsVal.classVal else: nil
                       else:
                         nil

  if fileStreamCls != nil:
    let stdoutInstance = fileStreamCls.newInstance()
    let stderrInstance = fileStreamCls.newInstance()
    let stdinInstance = fileStreamCls.newInstance()
    interp.globals[]["Stdout"] = stdoutInstance.toValue()
    interp.globals[]["Stderr"] = stderrInstance.toValue()
    interp.globals[]["Stdin"] = stdinInstance.toValue()
    debug("Created Stdin/Stdout/Stderr instances from FileStream class")
