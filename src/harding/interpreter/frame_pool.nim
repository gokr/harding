## Frame Pool for WorkFrame Recycling
## Reduces GC pressure by reusing WorkFrame objects

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

proc clearFrameRefs(frame: WorkFrame) {.inline.} =
  ## Clear only ref-type fields to allow ARC to collect them.
  ## Value-type fields (int, bool, enum) are left as-is since frame
  ## constructors will overwrite them.
  frame.node = nil
  frame.msgNode = nil
  frame.blockVal = nil
  frame.savedReceiver = nil
  frame.thenBlock = nil
  frame.elseBlock = nil
  frame.conditionBlock = nil
  frame.bodyBlock = nil
  frame.exceptionClass = nil
  frame.handlerBlock = nil
  frame.exceptionInstance = nil
  frame.protectedBlockForHandler = nil
  # Clear seqs (release their backing arrays)
  frame.blockArgs.setLen(0)
  frame.pendingArgs.setLen(0)
  frame.cascadeMessages.setLen(0)
  # Clear strings (release their backing memory)
  frame.selector = ""
  frame.pendingSelector = ""

proc initFramePool*() =
  ## Initialize the global frame pool with pre-allocated frames
  globalFramePool.frames = newSeqOfCap[WorkFrame](MaxPoolSize)
  for i in 0..<InitialPoolSize:
    globalFramePool.frames.add(WorkFrame())
  globalFramePool.acquiredCount = 0
  globalFramePool.totalAllocations = InitialPoolSize
  globalFramePool.totalReleases = 0
  debug("Frame pool initialized with ", $InitialPoolSize, " frames")

proc acquireFrame*(): WorkFrame {.inline.} =
  ## Acquire a frame from the pool, or allocate new if pool is empty.
  ## Ref fields are already cleared by releaseFrame; value fields will
  ## be set by the frame constructor.
  if globalFramePool.frames.len > 0:
    result = globalFramePool.frames.pop()
    globalFramePool.acquiredCount += 1
  else:
    result = WorkFrame()
    globalFramePool.totalAllocations += 1
    globalFramePool.acquiredCount += 1

proc releaseFrame*(frame: WorkFrame) =
  ## Release a frame back to the pool for reuse
  if frame == nil:
    return
  globalFramePool.acquiredCount -= 1
  globalFramePool.totalReleases += 1

  # Return to pool if not at max size, clearing refs first
  if globalFramePool.frames.len < MaxPoolSize:
    clearFrameRefs(frame)
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
