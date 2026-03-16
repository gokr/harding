## Activation Pool for Activation Record Recycling
## Reduces allocation pressure by reusing Activation objects.
##
## Only activations that have not been captured as homeActivation (for non-local
## returns) or stored in an ExceptionContext are pooled.  Captured activations
## have wasCaptured == true and are left to ARC's normal lifecycle.

import std/[tables]
import ../core/types

const
  InitialPoolSize = 64   # Pre-allocated activations on startup
  MaxPoolSize     = 512  # Maximum activations to keep in pool

type
  ActivationPool* = object
    activations: seq[Activation]
    acquiredCount: int
    totalAllocations: int
    totalReleases: int

var globalActivationPool*: ActivationPool

proc clearActivation*(act: Activation) =
  ## Reset all fields without deallocating the Table backing stores.
  ## After this call the activation is ready to be re-initialized.
  act.sender = nil
  act.receiver = nil
  act.currentMethod = nil
  act.definingObject = nil
  act.pc = 0
  act.locals.clear()
  act.indexedLocals.setLen(0)
  act.capturedVars.clear()
  act.returnValue = NodeValue(kind: vkNil)
  act.hasReturned = false
  act.nonLocalReturnTarget = nil
  act.isClassMethod = false
  act.wasCaptured = false
  act.blockHomeActivation = nil

proc initActivationPool*() =
  ## Pre-allocate the pool so the first burst of method calls does not hit
  ## the allocator.
  globalActivationPool.activations = newSeqOfCap[Activation](MaxPoolSize)
  for i in 0..<InitialPoolSize:
    globalActivationPool.activations.add(Activation())
  globalActivationPool.acquiredCount = 0
  globalActivationPool.totalAllocations = InitialPoolSize
  globalActivationPool.totalReleases = 0
  debug("Activation pool initialized with ", $InitialPoolSize, " activations")

proc acquireActivation*(): Activation =
  ## Borrow an activation from the pool (or allocate a fresh one).
  ## The caller is responsible for initialising all relevant fields.
  if globalActivationPool.activations.len > 0:
    result = globalActivationPool.activations.pop()
    globalActivationPool.acquiredCount += 1
  else:
    result = Activation()
    globalActivationPool.totalAllocations += 1
    globalActivationPool.acquiredCount += 1

proc releaseActivation*(act: Activation) =
  ## Return an activation to the pool for reuse.
  ## No-op if act is nil or was captured (wasCaptured == true).
  if act == nil or act.wasCaptured:
    return
  globalActivationPool.acquiredCount -= 1
  globalActivationPool.totalReleases += 1
  if globalActivationPool.activations.len < MaxPoolSize:
    clearActivation(act)
    globalActivationPool.activations.add(act)

proc getActivationPoolStats*(): tuple[available: int, inUse: int, totalAllocated: int, totalReleases: int] =
  result = (
    available: globalActivationPool.activations.len,
    inUse: globalActivationPool.acquiredCount,
    totalAllocated: globalActivationPool.totalAllocations,
    totalReleases: globalActivationPool.totalReleases
  )

# Initialize pool on module load
initActivationPool()
