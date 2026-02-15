## Frame Pool for WorkFrame Recycling
## Reduces GC pressure by reusing WorkFrame objects

import std/[logging, strutils]
import ../core/types

const
  InitialPoolSize = 256  # Initial number of frames to pre-allocate
  MaxPoolSize = 4096     # Maximum frames to keep in pool

type
  WorkFramePool* = object
    ## Pool of reusable WorkFrame objects
    frames: seq[WorkFrame]  # Available frames in pool
    acquiredCount: int      # Number of frames currently in use
    totalAllocations: int   # Total allocations since start
    totalReleases: int      # Total releases back to pool

var globalFramePool: WorkFramePool

proc initFramePool*() =
  ## Initialize the global frame pool with pre-allocated frames
  globalFramePool.frames = newSeqOfCap[WorkFrame](MaxPoolSize)
  for i in 0..<InitialPoolSize:
    globalFramePool.frames.add(WorkFrame())
  globalFramePool.acquiredCount = 0
  globalFramePool.totalAllocations = InitialPoolSize
  globalFramePool.totalReleases = 0
  debug("Frame pool initialized with ", $InitialPoolSize, " frames")

proc clearFrame*(frame: WorkFrame) =
  ## Clear all fields of a frame to prevent stale data
  if frame == nil:
    return
  frame.node = nil
  frame.selector = ""
  frame.argCount = 0
  frame.msgNode = nil
  frame.isClassMethod = false
  frame.blockVal = nil
  frame.blockArgs = @[]
  frame.pendingSelector = ""
  frame.pendingArgs = @[]
  frame.currentArgIndex = 0
  frame.returnValue = NodeValue(kind: vkNil)
  frame.cascadeMessages = @[]
  frame.cascadeReceiver = NodeValue(kind: vkNil)
  frame.savedReceiver = nil
  frame.isBlockActivation = false
  frame.savedEvalStackDepth = 0
  frame.conditionResult = false
  frame.thenBlock = nil
  frame.elseBlock = nil
  frame.loopKind = false
  frame.conditionBlock = nil
  frame.bodyBlock = nil
  frame.loopState = lsEvaluateCondition
  frame.exceptionClass = nil
  frame.handlerBlock = nil
  frame.exceptionInstance = nil

proc acquireFrame*(): WorkFrame =
  ## Acquire a frame from the pool, or allocate new if pool is empty
  if globalFramePool.frames.len > 0:
    result = globalFramePool.frames.pop()
    clearFrame(result)
    globalFramePool.acquiredCount += 1
  else:
    # Pool is empty, allocate new frame
    result = WorkFrame()
    globalFramePool.totalAllocations += 1
    globalFramePool.acquiredCount += 1

proc releaseFrame*(frame: WorkFrame) =
  ## Release a frame back to the pool for reuse
  if frame == nil:
    return
  globalFramePool.acquiredCount -= 1
  globalFramePool.totalReleases += 1

  # Return to pool if not at max size
  if globalFramePool.frames.len < MaxPoolSize:
    globalFramePool.frames.add(frame)

proc getFramePoolStats*(): tuple[available: int, inUse: int, totalAllocated: int, totalReleases: int] =
  ## Get current frame pool statistics
  result = (
    available: globalFramePool.frames.len,
    inUse: globalFramePool.acquiredCount,
    totalAllocated: globalFramePool.totalAllocations,
    totalReleases: globalFramePool.totalReleases
  )

# Initialize pool on module load
initFramePool()
