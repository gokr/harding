## Shared helpers used by Granite-generated modules.
import std/tables
import ../core/types
import ./runtime

export types, runtime

# Runtime helpers for primitives

proc compiledLoopInt*(val: NodeValue): int =
  ## Convert NodeValue to integer for loop counters
  case val.kind
  of vkInt: return val.intVal
  of vkFloat: return int(val.floatVal)
  else: return 0

proc getArg*(args: seq[NodeValue], index: int, default: NodeValue = NodeValue(kind: vkNil)): NodeValue =
  ## Get argument at index with default fallback
  if index >= 0 and index < args.len:
    return args[index]
  return default

proc requireArg*(args: seq[NodeValue], index: int, kind: ValueKind): NodeValue =
  ## Get argument and require specific type
  if index < 0 or index >= args.len:
    raise newException(ValueError, "Missing argument at index " & $index)
  let arg = args[index]
  if arg.kind != kind:
    raise newException(ValueError, "Expected " & $kind & ", got " & $arg.kind)
  return arg

proc intArg*(args: seq[NodeValue], index: int): int =
  ## Get integer argument
  return requireArg(args, index, vkInt).intVal

proc floatArg*(args: seq[NodeValue], index: int): float64 =
  ## Get float argument (converts from int if needed)
  let arg = args[index]
  if arg.kind == vkInt:
    return float(arg.intVal)
  if arg.kind == vkFloat:
    return arg.floatVal
  raise newException(ValueError, "Expected numeric argument at index " & $index)

proc stringArg*(args: seq[NodeValue], index: int): string =
  ## Get string argument
  return requireArg(args, index, vkString).strVal

# I/O helper functions

proc nt_println*(value: NodeValue): NodeValue =
  ## Print value with newline
  echo value.toString()
  return value

proc nt_print*(value: NodeValue): NodeValue =
  ## Print value without newline
  stdout.write(value.toString())
  return value

proc nt_asString*(value: NodeValue): NodeValue =
  ## Convert value to string
  return NodeValue(kind: vkString, strVal: value.toString())

proc nt_comma*(a: NodeValue, b: NodeValue): NodeValue =
  ## String concatenation
  let aStr = a.toString()
  let bStr = b.toString()
  return NodeValue(kind: vkString, strVal: aStr & bStr)

# Collection access primitives

proc nt_at_k*(receiver: NodeValue, key: NodeValue): NodeValue =
  ## Collection access: receiver at: key
  ## Works for both Arrays (0-based indexing) and Tables
  if receiver.kind == vkArray and key.kind == vkInt:
    let idx = key.intVal
    if idx >= 0 and idx < receiver.arrayVal.len:
      return receiver.arrayVal[idx]
  elif receiver.kind == vkTable:
    if receiver.tableVal.hasKey(key):
      return receiver.tableVal[key]
  return NodeValue(kind: vkNil)

proc nt_at_kput_k*(receiver: NodeValue, key: NodeValue, value: NodeValue): NodeValue =
  ## Collection assignment: receiver at: key put: value
  ## Works for both Arrays (0-based indexing) and Tables
  if receiver.kind == vkArray and key.kind == vkInt:
    let idx = key.intVal
    if idx >= 0 and idx < receiver.arrayVal.len:
      var newArr = receiver
      newArr.arrayVal[idx] = value
      return newArr
    if idx == receiver.arrayVal.len:
      var newArr = receiver
      newArr.arrayVal.add(value)
      return newArr
  elif receiver.kind == vkTable:
    var newTbl = receiver
    newTbl.tableVal[key] = value
    return newTbl
  return receiver

# Array primitives

proc nt_size*(value: NodeValue): NodeValue =
  ## Collection or string size
  if value.kind == vkArray:
    return NodeValue(kind: vkInt, intVal: value.arrayVal.len)
  if value.kind == vkTable:
    return NodeValue(kind: vkInt, intVal: value.tableVal.len)
  if value.kind == vkString:
    return NodeValue(kind: vkInt, intVal: value.strVal.len)
  return NodeValue(kind: vkNil)

proc nt_last*(arr: NodeValue): NodeValue =
  ## Array last element
  if arr.kind == vkArray and arr.arrayVal.len > 0:
    return arr.arrayVal[^1]
  return NodeValue(kind: vkNil)

# Table primitives

proc nt_table_at*(tbl: NodeValue, key: NodeValue): NodeValue =
  ## Table access: table at: key
  if tbl.kind == vkTable:
    if tbl.tableVal.hasKey(key):
      return tbl.tableVal[key]
  return NodeValue(kind: vkNil)

proc nt_table_atput*(tbl: NodeValue, key: NodeValue, value: NodeValue): NodeValue =
  ## Table assignment: table at: key put: value
  if tbl.kind == vkTable:
    var newTbl = tbl
    newTbl.tableVal[key] = value
    return newTbl
  return tbl

proc nt_table_keys*(tbl: NodeValue): NodeValue =
  ## Table keys
  if tbl.kind == vkTable:
    var keys: seq[NodeValue] = @[]
    for key in tbl.tableVal.keys:
      keys.add(key)
    return NodeValue(kind: vkArray, arrayVal: keys)
  return NodeValue(kind: vkNil)

proc nt_table_size*(tbl: NodeValue): NodeValue =
  ## Table size
  if tbl.kind == vkTable:
    return NodeValue(kind: vkInt, intVal: tbl.tableVal.len)
  return NodeValue(kind: vkNil)

# Number primitives

proc nt_abs*(n: NodeValue): NodeValue =
  ## Absolute value
  if n.kind == vkInt:
    return NodeValue(kind: vkInt, intVal: abs(n.intVal))
  if n.kind == vkFloat:
    return NodeValue(kind: vkFloat, floatVal: abs(n.floatVal))
  return NodeValue(kind: vkNil)

proc nt_even*(n: NodeValue): NodeValue =
  ## Is even
  if n.kind == vkInt:
    return NodeValue(kind: vkBool, boolVal: n.intVal mod 2 == 0)
  return NodeValue(kind: vkNil)

proc nt_odd*(n: NodeValue): NodeValue =
  ## Is odd
  if n.kind == vkInt:
    return NodeValue(kind: vkBool, boolVal: n.intVal mod 2 != 0)
  return NodeValue(kind: vkNil)

proc nt_negated*(n: NodeValue): NodeValue =
  ## Negated value
  if n.kind == vkInt:
    return NodeValue(kind: vkInt, intVal: -n.intVal)
  if n.kind == vkFloat:
    return NodeValue(kind: vkFloat, floatVal: -n.floatVal)
  return NodeValue(kind: vkNil)

# Global variable support

var compiledGlobals = initTable[string, NodeValue]()

proc getGlobal*(name: string): NodeValue =
  ## Get global variable value
  if compiledGlobals.hasKey(name):
    return compiledGlobals[name]
  return NodeValue(kind: vkNil)

proc setGlobal*(name: string, value: NodeValue): NodeValue =
  ## Set global variable value
  compiledGlobals[name] = value
  return value


# Block Runtime Support
# =====================

# Exception type for non-local returns from blocks
type
  CompiledReturnTarget* = ref object
    active*: bool
  NonLocalReturnException* = object of CatchableError
    value*: NodeValue
    target*: CompiledReturnTarget

proc raiseNonLocalReturn*(target: CompiledReturnTarget, value: NodeValue): NodeValue =
  if target == nil or not target.active:
    # Surface this as a Harding BlockCannotReturn so application `on: Error do:`
    # handlers can catch it, matching the interpreter.
    discard raiseCompiledError(compiledErrorValue("BlockCannotReturn",
      "Block cannot return: home activation is no longer active"))
  raise (ref NonLocalReturnException)(value: value, target: target)

proc createBlock*(procPtr: pointer, paramCount: int, envPtr: pointer = nil): NodeValue =
  ## Create a block value wrapping a compiled procedure pointer
  ## Note: procPtr is cast to pointer inside this proc to avoid cast issues at call site
  var blk = BlockNode()
  blk.nativeImpl = procPtr
  blk.parameters = newSeq[string](paramCount)
  # Store env pointer in capturedEnv as a hack using a known key
  if envPtr != nil:
    blk.capturedEnv = initTable[string, MutableCell]()
    blk.capturedEnv["__env_ptr__"] = MutableCell(value: NodeValue(kind: vkInt, intVal: cast[int](envPtr)))
    blk.capturedEnvInitialized = true
  return NodeValue(kind: vkBlock, blockVal: blk)

# Template versions that handle the cast internally
template createBlock0*(procPtr: proc(): NodeValue {.cdecl.}, paramCount: int): NodeValue =
  createBlock(cast[pointer](procPtr), paramCount)

template createBlock1*(procPtr: proc(a: NodeValue): NodeValue {.cdecl.}, paramCount: int): NodeValue =
  createBlock(cast[pointer](procPtr), paramCount)

template createBlock2*(procPtr: proc(a, b: NodeValue): NodeValue {.cdecl.}, paramCount: int): NodeValue =
  createBlock(cast[pointer](procPtr), paramCount)

template createBlock3*(procPtr: proc(a, b, c: NodeValue): NodeValue {.cdecl.}, paramCount: int): NodeValue =
  createBlock(cast[pointer](procPtr), paramCount)

# Template versions with environment
template createBlockEnv0*(procPtr: proc(env: pointer): NodeValue {.cdecl.}, paramCount: int, envPtr: pointer): NodeValue =
  createBlock(cast[pointer](procPtr), paramCount, envPtr)

template createBlockEnv1*(procPtr: proc(env: pointer, a: NodeValue): NodeValue {.cdecl.}, paramCount: int, envPtr: pointer): NodeValue =
  createBlock(cast[pointer](procPtr), paramCount, envPtr)

template createBlockEnv2*(procPtr: proc(env: pointer, a, b: NodeValue): NodeValue {.cdecl.}, paramCount: int, envPtr: pointer): NodeValue =
  createBlock(cast[pointer](procPtr), paramCount, envPtr)

template createBlockEnv3*(procPtr: proc(env: pointer, a, b, c: NodeValue): NodeValue {.cdecl.}, paramCount: int, envPtr: pointer): NodeValue =
  createBlock(cast[pointer](procPtr), paramCount, envPtr)

template createBlockWithEnv*[T](procPtr: pointer, paramCount: int, env: T): NodeValue =
  ## Retain a managed closure environment for the lifetime of its block.
  block:
    let ownedEnv = env
    var blockValue = createBlock(procPtr, paramCount)
    blockValue.blockVal.compiledEnv = ownedEnv
    blockValue.blockVal.capturedEnv = initTable[string, MutableCell]()
    blockValue.blockVal.capturedEnv["__env_ptr__"] = MutableCell(
      value: NodeValue(kind: vkInt, intVal: cast[int](cast[pointer](ownedEnv))))
    blockValue.blockVal.capturedEnvInitialized = true
    blockValue


# Base Object Type
##################

type
  HardingObject* {.inheritable.} = object of RootObj
    className*: string
  HardingObjectRef* = ref HardingObject


# Control Flow Methods
######################

proc nt_whileTrue_k*(self: NodeValue, condition: BlockNode, body: BlockNode = nil): NodeValue {.cdecl, exportc.} =
  ## whileTrue: control structure
  ## Repeatedly evaluate condition and body while condition is true
  ##
  while true:
    let condResult = currentRuntime[].evalBlock(condition)
    if condResult.kind != vkBool or not condResult.boolVal:
      break

    if body != nil:
      discard currentRuntime[].evalBlock(body)

  return self

proc nt_whileFalse_k*(self: NodeValue, condition: BlockNode, body: BlockNode = nil): NodeValue {.cdecl, exportc.} =
  ## whileFalse: control structure
  ## Repeatedly evaluate condition and body while condition is false
  ##
  while true:
    let condResult = currentRuntime[].evalBlock(condition)
    if condResult.kind == vkBool and condResult.boolVal:
      break

    if body != nil:
      discard currentRuntime[].evalBlock(body)

  return self

proc nt_tableFrom*(entries: openArray[(NodeValue, NodeValue)]): NodeValue =
  ## Build a table value from literal key/value pairs. Nim's `{}` literal infers
  ## the wrong native key type, so generated modules call this instead.
  var built = initTable[NodeValue, NodeValue]()
  for (key, value) in entries:
    built[key] = value
  return NodeValue(kind: vkTable, tableVal: built)

proc nt_emptyTable*(): NodeValue =
  ## Empty table value with the correct key type.
  return NodeValue(kind: vkTable, tableVal: initTable[NodeValue, NodeValue]())

proc nt_ifTrue_kifFalse_k*(self: NodeValue, trueBlock: BlockNode, falseBlock: BlockNode): NodeValue {.cdecl, exportc.} =
  ## ifTrue:ifFalse: conditional
  ## Evaluates appropriate block based on boolean value
  ##
  if self.kind == vkBool:
    if self.boolVal:
      return currentRuntime[].evalBlock(trueBlock)
    else:
      return currentRuntime[].evalBlock(falseBlock)

  # Not a boolean - raise error
  return NodeValue(kind: vkNil)

proc nt_timesRepeat_k*(self: NodeValue, body: BlockNode): NodeValue {.cdecl, exportc.} =
  ## timesRepeat: control structure
  ## Evaluates block self times (if self is an integer)
  ##
  if self.kind != vkInt:
    return self

  let count = self.intVal
  for _ in 0..<count:
    discard currentRuntime[].evalBlock(body)

  return self


# Binary Operators
#################


proc nt_plus*(a: NodeValue, b: NodeValue): NodeValue {.cdecl, exportc.} =
  ## Binary operator: +
  ## Provides fast-path type specialization with dynamic fallback
  ##

  # Fast path: both operands are integers
  if a.kind == vkInt and b.kind == vkInt:
    return NodeValue(kind: vkInt, intVal: a.intVal + b.intVal)
  # Fast path: both operands are floats
  if a.kind == vkFloat and b.kind == vkFloat:
    return NodeValue(kind: vkFloat, floatVal: a.floatVal + b.floatVal)
  # Mixed int/float - promote to float
  if a.kind == vkInt and b.kind == vkFloat:
    return NodeValue(kind: vkFloat, floatVal: float(a.intVal) + b.floatVal)
  if a.kind == vkFloat and b.kind == vkInt:
    return NodeValue(kind: vkFloat, floatVal: a.floatVal + float(b.intVal))

  # Slow path: dynamic dispatch
  return sendMessage(currentRuntime[], a, "+", @[b])


proc nt_minus*(a: NodeValue, b: NodeValue): NodeValue {.cdecl, exportc.} =
  ## Binary operator: -
  ## Provides fast-path type specialization with dynamic fallback
  ##

  # Fast path: both operands are integers
  if a.kind == vkInt and b.kind == vkInt:
    return NodeValue(kind: vkInt, intVal: a.intVal - b.intVal)
  # Fast path: both operands are floats
  if a.kind == vkFloat and b.kind == vkFloat:
    return NodeValue(kind: vkFloat, floatVal: a.floatVal - b.floatVal)
  # Mixed int/float - promote to float
  if a.kind == vkInt and b.kind == vkFloat:
    return NodeValue(kind: vkFloat, floatVal: float(a.intVal) - b.floatVal)
  if a.kind == vkFloat and b.kind == vkInt:
    return NodeValue(kind: vkFloat, floatVal: a.floatVal - float(b.intVal))

  # Slow path: dynamic dispatch
  return sendMessage(currentRuntime[], a, "-", @[b])


proc nt_star*(a: NodeValue, b: NodeValue): NodeValue {.cdecl, exportc.} =
  ## Binary operator: *
  ## Provides fast-path type specialization with dynamic fallback
  ##

  # Fast path: both operands are integers
  if a.kind == vkInt and b.kind == vkInt:
    return NodeValue(kind: vkInt, intVal: a.intVal * b.intVal)
  # Fast path: both operands are floats
  if a.kind == vkFloat and b.kind == vkFloat:
    return NodeValue(kind: vkFloat, floatVal: a.floatVal * b.floatVal)
  # Mixed int/float - promote to float
  if a.kind == vkInt and b.kind == vkFloat:
    return NodeValue(kind: vkFloat, floatVal: float(a.intVal) * b.floatVal)
  if a.kind == vkFloat and b.kind == vkInt:
    return NodeValue(kind: vkFloat, floatVal: a.floatVal * float(b.intVal))

  # Slow path: dynamic dispatch
  return sendMessage(currentRuntime[], a, "*", @[b])


proc nt_slash*(a: NodeValue, b: NodeValue): NodeValue {.cdecl, exportc.} =
  ## Binary operator: /
  ## Provides fast-path type specialization with dynamic fallback
  ##

  # Fast path: both operands are integers
  if a.kind == vkInt and b.kind == vkInt:
    if b.intVal == 0:
      return raiseCompiledError(compiledErrorValue("DivisionByZero", "Integer division by zero"))
    return NodeValue(kind: vkFloat, floatVal: float(a.intVal) / float(b.intVal))
  # Fast path: both operands are floats
  if a.kind == vkFloat and b.kind == vkFloat:
    if b.floatVal == 0.0:
      return raiseCompiledError(compiledErrorValue("DivisionByZero", "Float division by zero"))
    return NodeValue(kind: vkFloat, floatVal: a.floatVal / b.floatVal)
  # Mixed int/float - promote to float
  if a.kind == vkInt and b.kind == vkFloat:
    if b.floatVal == 0.0:
      return raiseCompiledError(compiledErrorValue("DivisionByZero", "Float division by zero"))
    return NodeValue(kind: vkFloat, floatVal: float(a.intVal) / b.floatVal)
  if a.kind == vkFloat and b.kind == vkInt:
    if b.intVal == 0:
      return raiseCompiledError(compiledErrorValue("DivisionByZero", "Float division by zero"))
    return NodeValue(kind: vkFloat, floatVal: a.floatVal / float(b.intVal))

  # Slow path: dynamic dispatch
  return sendMessage(currentRuntime[], a, "/", @[b])


# Comparison Operators
#####################


proc nt_lt*(a: NodeValue, b: NodeValue): NodeValue {.cdecl, exportc.} =
  ## Comparison operator: <
  ## Provides fast-path type specialization with dynamic fallback
  ##

  # Fast path: integer comparison
  if a.kind == vkInt and b.kind == vkInt:
    return NodeValue(kind: vkBool, boolVal: a.intVal < b.intVal)
  # Fast path: float comparison
  if a.kind == vkFloat and b.kind == vkFloat:
    return NodeValue(kind: vkBool, boolVal: a.floatVal < b.floatVal)
  # Fast path: string comparison
  if a.kind == vkString and b.kind == vkString:
    return NodeValue(kind: vkBool, boolVal: a.strVal < b.strVal)
  # Fast path: bool comparison
  if a.kind == vkBool and b.kind == vkBool:
    return NodeValue(kind: vkBool, boolVal: a.boolVal < b.boolVal)

  # Slow path: dynamic dispatch
  return sendMessage(currentRuntime[], a, "<", @[b])


proc nt_lteq*(a: NodeValue, b: NodeValue): NodeValue {.cdecl, exportc.} =
  ## Comparison operator: <=
  ## Provides fast-path type specialization with dynamic fallback
  ##

  # Fast path: integer comparison
  if a.kind == vkInt and b.kind == vkInt:
    return NodeValue(kind: vkBool, boolVal: a.intVal <= b.intVal)
  # Fast path: float comparison
  if a.kind == vkFloat and b.kind == vkFloat:
    return NodeValue(kind: vkBool, boolVal: a.floatVal <= b.floatVal)
  # Fast path: string comparison
  if a.kind == vkString and b.kind == vkString:
    return NodeValue(kind: vkBool, boolVal: a.strVal <= b.strVal)
  # Fast path: bool comparison
  if a.kind == vkBool and b.kind == vkBool:
    return NodeValue(kind: vkBool, boolVal: a.boolVal <= b.boolVal)

  # Slow path: dynamic dispatch
  return sendMessage(currentRuntime[], a, "<=", @[b])


proc nt_gt*(a: NodeValue, b: NodeValue): NodeValue {.cdecl, exportc.} =
  ## Comparison operator: >
  ## Provides fast-path type specialization with dynamic fallback
  ##

  # Fast path: integer comparison
  if a.kind == vkInt and b.kind == vkInt:
    return NodeValue(kind: vkBool, boolVal: a.intVal > b.intVal)
  # Fast path: float comparison
  if a.kind == vkFloat and b.kind == vkFloat:
    return NodeValue(kind: vkBool, boolVal: a.floatVal > b.floatVal)
  # Fast path: string comparison
  if a.kind == vkString and b.kind == vkString:
    return NodeValue(kind: vkBool, boolVal: a.strVal > b.strVal)
  # Fast path: bool comparison
  if a.kind == vkBool and b.kind == vkBool:
    return NodeValue(kind: vkBool, boolVal: a.boolVal > b.boolVal)

  # Slow path: dynamic dispatch
  return sendMessage(currentRuntime[], a, ">", @[b])


proc nt_gteq*(a: NodeValue, b: NodeValue): NodeValue {.cdecl, exportc.} =
  ## Comparison operator: >=
  ## Provides fast-path type specialization with dynamic fallback
  ##

  # Fast path: integer comparison
  if a.kind == vkInt and b.kind == vkInt:
    return NodeValue(kind: vkBool, boolVal: a.intVal >= b.intVal)
  # Fast path: float comparison
  if a.kind == vkFloat and b.kind == vkFloat:
    return NodeValue(kind: vkBool, boolVal: a.floatVal >= b.floatVal)
  # Fast path: string comparison
  if a.kind == vkString and b.kind == vkString:
    return NodeValue(kind: vkBool, boolVal: a.strVal >= b.strVal)
  # Fast path: bool comparison
  if a.kind == vkBool and b.kind == vkBool:
    return NodeValue(kind: vkBool, boolVal: a.boolVal >= b.boolVal)

  # Slow path: dynamic dispatch
  return sendMessage(currentRuntime[], a, ">=", @[b])


proc nt_eq*(a: NodeValue, b: NodeValue): NodeValue {.cdecl, exportc.} =
  ## Comparison operator: =
  ## Provides fast-path type specialization with dynamic fallback
  ##

  # Fast path: integer comparison
  if a.kind == vkInt and b.kind == vkInt:
    return NodeValue(kind: vkBool, boolVal: a.intVal == b.intVal)
  # Fast path: float comparison
  if a.kind == vkFloat and b.kind == vkFloat:
    return NodeValue(kind: vkBool, boolVal: a.floatVal == b.floatVal)
  # Fast path: string comparison
  if a.kind == vkString and b.kind == vkString:
    return NodeValue(kind: vkBool, boolVal: a.strVal == b.strVal)
  # Fast path: bool comparison
  if a.kind == vkBool and b.kind == vkBool:
    return NodeValue(kind: vkBool, boolVal: a.boolVal == b.boolVal)

  # Slow path: dynamic dispatch
  return sendMessage(currentRuntime[], a, "=", @[b])


proc nt_eqeq*(a: NodeValue, b: NodeValue): NodeValue {.cdecl, exportc.} =
  ## Comparison operator: ==
  ## Provides fast-path type specialization with dynamic fallback
  ##

  # Fast path: integer comparison
  if a.kind == vkInt and b.kind == vkInt:
    return NodeValue(kind: vkBool, boolVal: a.intVal == b.intVal)
  # Fast path: float comparison
  if a.kind == vkFloat and b.kind == vkFloat:
    return NodeValue(kind: vkBool, boolVal: a.floatVal == b.floatVal)
  # Fast path: string comparison
  if a.kind == vkString and b.kind == vkString:
    return NodeValue(kind: vkBool, boolVal: a.strVal == b.strVal)
  # Fast path: bool comparison
  if a.kind == vkBool and b.kind == vkBool:
    return NodeValue(kind: vkBool, boolVal: a.boolVal == b.boolVal)

  # Slow path: dynamic dispatch
  return sendMessage(currentRuntime[], a, "==", @[b])


proc nt_tildeeq*(a: NodeValue, b: NodeValue): NodeValue {.cdecl, exportc.} =
  ## Comparison operator: ~=
  ## Provides fast-path type specialization with dynamic fallback
  ##

  # Fast path: integer comparison
  if a.kind == vkInt and b.kind == vkInt:
    return NodeValue(kind: vkBool, boolVal: a.intVal != b.intVal)
  # Fast path: float comparison
  if a.kind == vkFloat and b.kind == vkFloat:
    return NodeValue(kind: vkBool, boolVal: a.floatVal != b.floatVal)
  # Fast path: string comparison
  if a.kind == vkString and b.kind == vkString:
    return NodeValue(kind: vkBool, boolVal: a.strVal != b.strVal)
  # Fast path: bool comparison
  if a.kind == vkBool and b.kind == vkBool:
    return NodeValue(kind: vkBool, boolVal: a.boolVal != b.boolVal)

  # Slow path: dynamic dispatch
  return sendMessage(currentRuntime[], a, "~=", @[b])


# Integer Division and Modulo
#############################


proc nt_slashslash*(a: NodeValue, b: NodeValue): NodeValue {.cdecl, exportc.} =
  ## Binary operator: //
  ## Provides fast-path type specialization with dynamic fallback
  ##

  # Fast path: both operands are integers
  if a.kind == vkInt and b.kind == vkInt:
    if b.intVal == 0:
      return raiseCompiledError(compiledErrorValue("DivisionByZero", "Integer division by zero"))
    return NodeValue(kind: vkInt, intVal: a.intVal div b.intVal)

  # Slow path: dynamic dispatch
  return sendMessage(currentRuntime[], a, "//", @[b])


proc nt_backslash*(a: NodeValue, b: NodeValue): NodeValue {.cdecl, exportc.} =
  ## Binary operator: \
  ## Provides fast-path type specialization with dynamic fallback
  ##

  # Fast path: both operands are integers
  if a.kind == vkInt and b.kind == vkInt:
    if b.intVal == 0:
      return raiseCompiledError(compiledErrorValue("DivisionByZero", "Integer modulo by zero"))
    return NodeValue(kind: vkInt, intVal: a.intVal mod b.intVal)

  # Slow path: dynamic dispatch
  return sendMessage(currentRuntime[], a, "\\", @[b])


proc nt_percent*(a: NodeValue, b: NodeValue): NodeValue {.cdecl, exportc.} =
  ## Binary operator: %
  ## Provides fast-path type specialization with dynamic fallback
  ##

  # Fast path: both operands are integers
  if a.kind == vkInt and b.kind == vkInt:
    if b.intVal == 0:
      return raiseCompiledError(compiledErrorValue("DivisionByZero", "Integer modulo by zero"))
    return NodeValue(kind: vkInt, intVal: a.intVal mod b.intVal)

  # Slow path: dynamic dispatch
  return sendMessage(currentRuntime[], a, "%", @[b])


