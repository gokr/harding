# Tagged Value Implementation for Harding
# Simple tagging scheme using lower 3 bits

import std/[strutils, hashes]

# Forward declaration - defined in types.nim
type
  HeapObject* = ref object of RootObj
    class*: pointer

# The tagged value is just a 64-bit word
type
  Value* = distinct uint64

# Tag constants (lower 3 bits)
const
  TAG_HEAP* = 0u64      # 000 - HeapObject pointer (must be 8-byte aligned)
  TAG_INT* = 1u64       # 001 - 61-bit signed integer (shifted left 3)
  TAG_SPECIAL* = 2u64   # 010 - Special values (nil, true, false)
  # Tags 3-7 reserved for future use

  SPECIAL_NIL* = 0u64
  SPECIAL_TRUE* = 1u64
  SPECIAL_FALSE* = 2u64

  TAG_MASK* = 0x7u64
  POINTER_MASK* = not TAG_MASK  # Upper 61 bits for pointer
  PAYLOAD_MASK* = not TAG_MASK  # Upper 61 bits for payload

# ============================================================================
# Construction Functions
# ============================================================================

proc toValue*(obj: HeapObject): Value {.inline.} =
  ## Convert a heap object to a tagged value
  ## Requires: obj is 8-byte aligned (guaranteed by Nim's allocator)
  if obj == nil:
    return Value(SPECIAL_NIL shl 3 or TAG_SPECIAL)
  let ptrVal = cast[uint64](obj)
  # Verify alignment (should always pass with Nim's allocator)
  assert((ptrVal and TAG_MASK) == 0, "HeapObject not 8-byte aligned")
  Value(ptrVal or TAG_HEAP)

proc toValue*(i: int): Value {.inline.} =
  ## Convert an int to a tagged value (61-bit signed range)
  ## Range: -1152921504606846976 to 1152921504606846975
  let shifted = cast[uint64](i) shl 3
  Value(shifted or TAG_INT)

proc toValue*(b: bool): Value {.inline.} =
  ## Convert a bool to a tagged value
  let special = if b: SPECIAL_TRUE else: SPECIAL_FALSE
  Value((special shl 3) or TAG_SPECIAL)

proc nilValue*(): Value {.inline.} =
  ## Get the nil value
  Value((SPECIAL_NIL shl 3) or TAG_SPECIAL)

# ============================================================================
# Type Checking
# ============================================================================

proc getTag*(v: Value): uint64 {.inline.} =
  cast[uint64](v) and TAG_MASK

proc isHeapObject*(v: Value): bool {.inline.} =
  getTag(v) == TAG_HEAP

proc isInt*(v: Value): bool {.inline.} =
  getTag(v) == TAG_INT

proc isBool*(v: Value): bool {.inline.} =
  getTag(v) == TAG_SPECIAL and
  ((cast[uint64](v) shr 3) and 0xF) in [SPECIAL_TRUE, SPECIAL_FALSE]

proc isNil*(v: Value): bool {.inline.} =
  getTag(v) == TAG_SPECIAL and
  ((cast[uint64](v) shr 3) and 0xF) == SPECIAL_NIL

# ============================================================================
# Extraction Functions
# ============================================================================

proc asHeapObject*(v: Value): HeapObject {.inline.} =
  ## Extract heap object from tagged value
  if not isHeapObject(v):
    raise newException(ValueError, "Value is not a heap object, tag=" & $getTag(v))
  let ptrVal = cast[uint64](v) and POINTER_MASK
  cast[HeapObject](ptrVal)

proc asInt*(v: Value): int {.inline.} =
  ## Extract int from tagged value
  if not isInt(v):
    raise newException(ValueError, "Value is not an int, tag=" & $getTag(v))
  # Arithmetic shift right to preserve sign
  cast[int](cast[uint64](v)) shr 3

proc asBool*(v: Value): bool {.inline.} =
  ## Extract bool from tagged value
  if not isBool(v):
    raise newException(ValueError, "Value is not a bool, tag=" & $getTag(v))
  ((cast[uint64](v) shr 3) and 0xF) == SPECIAL_TRUE

# ============================================================================
# Arithmetic Operations (Fast Path)
# ============================================================================

proc add*(a, b: Value): Value {.inline.} =
  ## Fast integer addition (no allocation!)
  if isInt(a) and isInt(b):
    toValue(asInt(a) + asInt(b))
  else:
    raise newException(ValueError, "add: non-integer arguments")

proc sub*(a, b: Value): Value {.inline.} =
  ## Fast integer subtraction
  if isInt(a) and isInt(b):
    toValue(asInt(a) - asInt(b))
  else:
    raise newException(ValueError, "sub: non-integer arguments")

proc mul*(a, b: Value): Value {.inline.} =
  ## Fast integer multiplication
  if isInt(a) and isInt(b):
    toValue(asInt(a) * asInt(b))
  else:
    raise newException(ValueError, "mul: non-integer arguments")

proc divInt*(a, b: Value): Value {.inline.} =
  ## Fast integer division
  if isInt(a) and isInt(b):
    let divisor = asInt(b)
    if divisor == 0:
      raise newException(DivByZeroDefect, "Division by zero")
    toValue(asInt(a) div divisor)
  else:
    raise newException(ValueError, "divInt: non-integer arguments")

proc modInt*(a, b: Value): Value {.inline.} =
  ## Fast integer modulo
  if isInt(a) and isInt(b):
    let divisor = asInt(b)
    if divisor == 0:
      raise newException(DivByZeroDefect, "Division by zero")
    toValue(asInt(a) mod divisor)
  else:
    raise newException(ValueError, "modInt: non-integer arguments")

# ============================================================================
# Comparison Operations
# ============================================================================

proc equals*(a, b: Value): bool {.inline.} =
  ## Value equality (works for all types)
  cast[uint64](a) == cast[uint64](b)

proc lessThan*(a, b: Value): bool {.inline.} =
  ## Integer less-than comparison
  if isInt(a) and isInt(b):
    asInt(a) < asInt(b)
  else:
    raise newException(ValueError, "lessThan: non-integer arguments")

proc lessOrEqual*(a, b: Value): bool {.inline.} =
  ## Integer less-than-or-equal comparison
  if isInt(a) and isInt(b):
    asInt(a) <= asInt(b)
  else:
    raise newException(ValueError, "lessOrEqual: non-integer arguments")

proc greaterThan*(a, b: Value): bool {.inline.} =
  ## Integer greater-than comparison
  if isInt(a) and isInt(b):
    asInt(a) > asInt(b)
  else:
    raise newException(ValueError, "greaterThan: non-integer arguments")

proc greaterOrEqual*(a, b: Value): bool {.inline.} =
  ## Integer greater-than-or-equal comparison
  if isInt(a) and isInt(b):
    asInt(a) >= asInt(b)
  else:
    raise newException(ValueError, "greaterOrEqual: non-integer arguments")

# ============================================================================
# String Representation
# ============================================================================

proc toString*(v: Value): string =
  ## Convert value to string for debugging/display
  if isNil(v):
    "nil"
  elif isInt(v):
    $asInt(v)
  elif isBool(v):
    $asBool(v)
  elif isHeapObject(v):
    "<object>"
  else:
    "<unknown value: 0x" & toHex(cast[uint64](v)) & ">"

# ============================================================================
# Hash Support (for use as table keys)
# ============================================================================

proc hash*(v: Value): Hash {.inline.} =
  ## Hash a tagged value
  hash(cast[uint64](v))

# ============================================================================
# Debugging
# ============================================================================

proc dumpValue*(v: Value): string =
  ## Detailed dump for debugging
  let raw = cast[uint64](v)
  let tag = getTag(v)
  result = "Value(raw=0x" & toHex(raw) & ", tag=" & $tag & ")"
  if isInt(v):
    result &= " int=" & $asInt(v)
  elif isBool(v):
    result &= " bool=" & $asBool(v)
  elif isNil(v):
    result &= " nil"
  elif isHeapObject(v):
    result &= " heapObject"
  else:
    result &= " unknown"
