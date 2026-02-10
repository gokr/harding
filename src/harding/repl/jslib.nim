#
# jslib.nim - Embedded Harding library files for JavaScript compilation
#
# This module uses staticRead to embed all library files at compile time,
# eliminating the need for file I/O in the browser environment.
#
# The library files are organized by category:
# - Core: Object, Boolean, Block, Number, String (loaded into globals)
# - Standard: Collections, SortedCollection, Interval, FileStream, Exception, TestCase (loaded into Standard)
#

import std/[tables, strutils, logging]
import ../core/types
import ../interpreter/vm
import ../interpreter/objects

# ============================================================================
# Embedded Library Files
# ============================================================================

# Core library files (loaded into globals via Harding load:)
const EmbeddedObjectHrd = staticRead("../../../lib/core/Object.hrd")
const EmbeddedBooleanHrd = staticRead("../../../lib/core/Boolean.hrd")
const EmbeddedBlockHrd = staticRead("../../../lib/core/Block.hrd")
const EmbeddedNumberHrd = staticRead("../../../lib/core/Number.hrd")
const EmbeddedStringHrd = staticRead("../../../lib/core/String.hrd")

# Standard library files (loaded into Standard Library)
const EmbeddedCollectionsHrd = staticRead("../../../lib/core/Collections.hrd")
const EmbeddedSortedCollectionHrd = staticRead("../../../lib/core/SortedCollection.hrd")
const EmbeddedIntervalHrd = staticRead("../../../lib/core/Interval.hrd")
const EmbeddedFileStreamHrd = staticRead("../../../lib/core/FileStream.hrd")
const EmbeddedExceptionHrd = staticRead("../../../lib/core/Exception.hrd")
const EmbeddedTestCaseHrd = staticRead("../../../lib/core/TestCase.hrd")

# Bootstrap code (entry point)
const EmbeddedBootstrapHrd = staticRead("../../../lib/core/Bootstrap.hrd")

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

  # Create Standard Library
  discard interp.doit("Standard := Library new.")

  # Load core files into globals (via Harding load: simulation)
  loadEmbeddedSource(interp, EmbeddedObjectHrd, "Object.hrd")
  loadEmbeddedSource(interp, EmbeddedBooleanHrd, "Boolean.hrd")
  loadEmbeddedSource(interp, EmbeddedBlockHrd, "Block.hrd")
  loadEmbeddedSource(interp, EmbeddedNumberHrd, "Number.hrd")
  loadEmbeddedSource(interp, EmbeddedStringHrd, "String.hrd")

  # Load standard library files into Standard
  loadEmbeddedSource(interp, EmbeddedCollectionsHrd, "Collections.hrd")
  loadEmbeddedSource(interp, EmbeddedSortedCollectionHrd, "SortedCollection.hrd")
  loadEmbeddedSource(interp, EmbeddedIntervalHrd, "Interval.hrd")
  loadEmbeddedSource(interp, EmbeddedFileStreamHrd, "FileStream.hrd")
  loadEmbeddedSource(interp, EmbeddedExceptionHrd, "Exception.hrd")
  loadEmbeddedSource(interp, EmbeddedTestCaseHrd, "TestCase.hrd")

  # Auto-import Standard for backward compatibility
  # Find Standard library instance and add to imported libraries
  if "Standard" in interp.globals[]:
    let standardVal = interp.globals[]["Standard"]
    if standardVal.kind == vkInstance and standardVal.instVal != nil:
      interp.importedLibraries.add(standardVal.instVal)
      debug("Auto-imported Standard library")

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

  # Set up FileStream class and Stdout instance
  let fileStreamCls = if "FileStream" in interp.globals[]:
                         let fsVal = interp.globals[]["FileStream"]
                         if fsVal.kind == vkClass: fsVal.classVal else: nil
                       else:
                         nil

  if fileStreamCls != nil:
    let stdoutInstance = fileStreamCls.newInstance()
    interp.globals[]["Stdout"] = stdoutInstance.toValue()
    debug("Created Stdout instance from FileStream class")

# ============================================================================
# JS-Specific Stdout Setup
# ============================================================================

proc setupJSStdout*(interp: var Interpreter) =
  ## Set up Stdout for JS environment
  ## FileStream methods use console.log via emit in objects.nim

  # Find FileStream class
  let fileStreamCls = if "FileStream" in interp.globals[]:
                         let fsVal = interp.globals[]["FileStream"]
                         if fsVal.kind == vkClass: fsVal.classVal else: nil
                       else:
                         nil

  if fileStreamCls != nil:
    # Create Stdout instance
    let stdoutInstance = fileStreamCls.newInstance()
    interp.globals[]["Stdout"] = stdoutInstance.toValue()
    debug("Created Stdout instance from FileStream class")
