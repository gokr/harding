#
# breakpoints.nim - Breakpoint management for the Harding debugger
#
# Handles breakpoint table, resolution, and conditional breakpoints.
#

import std/[tables, hashes]
import ./protocol

# ============================================================================
# Breakpoint Manager
# ============================================================================

type
  BreakpointManager* = ref object
    nextId*: int
    breakpoints*: Table[int, Breakpoint]         # id -> breakpoint
    locationIndex*: Table[(string, int), int]     # (file, line) -> breakpoint id
    state*: DebuggerState

proc newBreakpointManager*(): BreakpointManager =
  ## Create a new breakpoint manager
  new(result)
  result.nextId = 1
  result.breakpoints = initTable[int, Breakpoint]()
  result.locationIndex = initTable[(string, int), int]()
  result.state = DebuggerState(
    enabled: true,
    connected: false,
    steppingMode: smNone,
    pauseRequested: false
  )

# ============================================================================
# Breakpoint CRUD Operations
# ============================================================================

proc addBreakpoint*(mgr: BreakpointManager, file: string, line: int,
                    condition: string = "", column: int = 0): Breakpoint =
  ## Add a new breakpoint
  let id = mgr.nextId
  mgr.nextId += 1

  result = Breakpoint(
    id: id,
    file: file,
    line: line,
    column: column,
    condition: condition,
    enabled: true,
    verified: false
  )

  mgr.breakpoints[id] = result
  mgr.locationIndex[(file, line)] = id
  mgr.state.breakpoints[(file, line)] = result

proc removeBreakpoint*(mgr: BreakpointManager, id: int): bool =
  ## Remove a breakpoint by ID
  if not mgr.breakpoints.hasKey(id):
    return false

  let bp = mgr.breakpoints[id]
  mgr.breakpoints.del(id)
  mgr.locationIndex.del((bp.file, bp.line))
  mgr.state.breakpoints.del((bp.file, bp.line))
  return true

proc removeBreakpoint*(mgr: BreakpointManager, file: string, line: int): bool =
  ## Remove a breakpoint by location
  if not mgr.locationIndex.hasKey((file, line)):
    return false

  let id = mgr.locationIndex[(file, line)]
  return mgr.removeBreakpoint(id)

proc clearAllBreakpoints*(mgr: BreakpointManager) =
  ## Remove all breakpoints
  mgr.breakpoints.clear()
  mgr.locationIndex.clear()
  mgr.state.breakpoints.clear()

proc clearBreakpointsInFile*(mgr: BreakpointManager, file: string) =
  ## Remove all breakpoints in a specific file
  var toRemove: seq[int] = @[]
  for id, bp in mgr.breakpoints:
    if bp.file == file:
      toRemove.add(id)
  for id in toRemove:
    discard mgr.removeBreakpoint(id)

# ============================================================================
# Breakpoint Queries
# ============================================================================

proc getBreakpoint*(mgr: BreakpointManager, id: int): Breakpoint =
  ## Get a breakpoint by ID
  if mgr.breakpoints.hasKey(id):
    return mgr.breakpoints[id]
  raise newException(KeyError, "Breakpoint not found: " & $id)

proc getBreakpoint*(mgr: BreakpointManager, file: string, line: int): Breakpoint =
  ## Get a breakpoint by location
  if mgr.locationIndex.hasKey((file, line)):
    let id = mgr.locationIndex[(file, line)]
    return mgr.breakpoints[id]
  raise newException(KeyError, "No breakpoint at " & file & ":" & $line)

proc hasBreakpoint*(mgr: BreakpointManager, file: string, line: int): bool =
  ## Check if a breakpoint exists at the given location
  return mgr.locationIndex.hasKey((file, line))

proc hasBreakpoint*(mgr: BreakpointManager, id: int): bool =
  ## Check if a breakpoint exists with the given ID
  return mgr.breakpoints.hasKey(id)

proc getAllBreakpoints*(mgr: BreakpointManager): seq[Breakpoint] =
  ## Get all breakpoints
  result = @[]
  for bp in mgr.breakpoints.values:
    result.add(bp)

proc getBreakpointsInFile*(mgr: BreakpointManager, file: string): seq[Breakpoint] =
  ## Get all breakpoints in a file
  result = @[]
  for bp in mgr.breakpoints.values:
    if bp.file == file:
      result.add(bp)

# ============================================================================
# Breakpoint State Management
# ============================================================================

proc setBreakpointEnabled*(mgr: BreakpointManager, id: int, enabled: bool): bool =
  ## Enable or disable a breakpoint
  if not mgr.breakpoints.hasKey(id):
    return false

  mgr.breakpoints[id].enabled = enabled
  let key = (mgr.breakpoints[id].file, mgr.breakpoints[id].line)
  if mgr.state.breakpoints.hasKey(key):
    mgr.state.breakpoints[key].enabled = enabled
  return true

proc setBreakpointCondition*(mgr: BreakpointManager, id: int, condition: string): bool =
  ## Set or change a breakpoint's condition
  if not mgr.breakpoints.hasKey(id):
    return false

  mgr.breakpoints[id].condition = condition
  let key = (mgr.breakpoints[id].file, mgr.breakpoints[id].line)
  if mgr.state.breakpoints.hasKey(key):
    mgr.state.breakpoints[key].condition = condition
  return true

proc verifyBreakpoint*(mgr: BreakpointManager, id: int): bool =
  ## Mark a breakpoint as verified (resolved to an actual location)
  if not mgr.breakpoints.hasKey(id):
    return false

  mgr.breakpoints[id].verified = true
  let key = (mgr.breakpoints[id].file, mgr.breakpoints[id].line)
  if mgr.state.breakpoints.hasKey(key):
    mgr.state.breakpoints[key].verified = true
  return true

# ============================================================================
# Breakpoint Resolution
# ============================================================================

proc resolveBreakpointLocation*(mgr: BreakpointManager, file: string, line: int): (string, int) =
  ## Resolve a breakpoint to the nearest valid location
  ## Returns (resolvedFile, resolvedLine)
  ## For now, just return the requested location
  ## In the future, this could map to actual AST node locations
  result = (file, line)

proc shouldBreakAt*(mgr: BreakpointManager, file: string, line: int,
                    evalCondition: proc(expr: string): bool = nil): bool =
  ## Check if execution should break at the given location
  if not mgr.locationIndex.hasKey((file, line)):
    return false

  let id = mgr.locationIndex[(file, line)]
  let bp = mgr.breakpoints[id]

  if not bp.enabled:
    return false

  # Check condition if present
  if bp.condition.len > 0 and evalCondition != nil:
    try:
      if not evalCondition(bp.condition):
        return false
    except:
      # If condition evaluation fails, break anyway
      return true

  return true

# ============================================================================
# Stepping State Management
# ============================================================================

proc setSteppingMode*(mgr: BreakpointManager, mode: SteppingMode, targetFrame: int = 0) =
  ## Set the current stepping mode
  mgr.state.steppingMode = mode
  mgr.state.stepTargetFrame = targetFrame

proc getSteppingMode*(mgr: BreakpointManager): SteppingMode =
  ## Get the current stepping mode
  return mgr.state.steppingMode

proc clearStepping*(mgr: BreakpointManager) =
  ## Clear stepping mode (resume normal execution)
  mgr.state.steppingMode = smNone
  mgr.state.stepTargetFrame = 0

proc requestPause*(mgr: BreakpointManager) =
  ## Request execution pause at next opportunity
  mgr.state.pauseRequested = true

proc clearPauseRequest*(mgr: BreakpointManager) =
  ## Clear pause request after handling
  mgr.state.pauseRequested = false

proc shouldPause*(mgr: BreakpointManager): bool =
  ## Check if a pause has been requested
  return mgr.state.pauseRequested

# ============================================================================
# Statistics
# ============================================================================

proc count*(mgr: BreakpointManager): int =
  ## Get total number of breakpoints
  return mgr.breakpoints.len

proc countVerified*(mgr: BreakpointManager): int =
  ## Get number of verified breakpoints
  result = 0
  for bp in mgr.breakpoints.values:
    if bp.verified:
      result += 1
