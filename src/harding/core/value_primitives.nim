import std/[strutils, math]
import ../interpreter/objects
import ./types
import ./string_conversion

proc primitiveArraySize*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  ## Shared value ABI for interpreted and compiled primitive calls.
  case self.kind
  of vkArray: toValue(self.arrayVal.len)
  of vkInstance:
    if self.instVal != nil and self.instVal.kind == ikArray:
      toValue(self.instVal.elements.len)
    else: toValue(0)
  else: toValue(0)

proc primitiveAsInteger*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  var source = ""
  case self.kind
  of vkString: source = self.strVal
  of vkSymbol: source = self.symVal
  of vkInstance:
    if self.instVal != nil and self.instVal.kind == ikString:
      source = self.instVal.strVal
  else: discard
  stringAsInteger(source)

proc primitiveAsFloat*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  case self.kind
  of vkString: stringAsFloat(self.strVal)
  of vkSymbol: stringAsFloat(self.symVal)
  of vkInstance:
    if self.instVal != nil and self.instVal.kind == ikString:
      stringAsFloat(self.instVal.strVal)
    else: nilValue()
  else: nilValue()

proc primitiveStringSizeValueImpl*(self: NodeValue, argsUnused: seq[NodeValue]): NodeValue =
  discard argsUnused
  case self.kind
  of vkString:
    return NodeValue(kind: vkInt, intVal: self.strVal.len)
  of vkSymbol:
    return NodeValue(kind: vkInt, intVal: self.symVal.len)
  of vkInstance:
    if self.instVal != nil and self.instVal.kind == ikString:
      return NodeValue(kind: vkInt, intVal: self.instVal.strVal.len)
  else:
    discard
  return nilValue()

proc primitiveStringConcatValueImpl*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len == 0:
    case self.kind
    of vkString:
      return self
    of vkSymbol:
      return NodeValue(kind: vkString, strVal: self.symVal)
    of vkInstance:
      if self.instVal != nil and self.instVal.kind == ikString:
        return NodeValue(kind: vkString, strVal: self.instVal.strVal)
    else:
      discard
    return NodeValue(kind: vkString, strVal: "")

  let rhs = args[0].toString()
  case self.kind
  of vkString:
    return NodeValue(kind: vkString, strVal: self.strVal & rhs)
  of vkSymbol:
    return NodeValue(kind: vkString, strVal: self.symVal & rhs)
  of vkInstance:
    if self.instVal != nil and self.instVal.kind == ikString:
      return NodeValue(kind: vkString, strVal: self.instVal.strVal & rhs)
  else:
    discard
  return NodeValue(kind: vkString, strVal: rhs)

proc primitiveStringAtValueImpl*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len == 0:
    return toValue("")

  let (ok, idx) = args[0].tryGetInt()
  if not ok or idx < 0:
    return toValue("")

  var source = ""
  case self.kind
  of vkString:
    source = self.strVal
  of vkSymbol:
    source = self.symVal
  of vkInstance:
    if self.instVal != nil and self.instVal.kind == ikString:
      source = self.instVal.strVal
  else:
    discard

  if idx >= source.len:
    return toValue("")
  return toValue($source[idx])

proc tryExtractString*(val: NodeValue, outStr: var string): bool =
  case val.kind
  of vkString:
    outStr = val.strVal
    return true
  of vkSymbol:
    outStr = val.symVal
    return true
  of vkInstance:
    if val.instVal != nil and val.instVal.kind == ikString:
      outStr = val.instVal.strVal
      return true
  else:
    discard
  return false

proc primitiveStringLowercaseValueImpl*(self: NodeValue, argsUnused: seq[NodeValue]): NodeValue =
  discard argsUnused
  var source = ""
  if tryExtractString(self, source):
    return toValue(source.toLowerAscii())
  return toValue("")

proc primitiveStringUppercaseValueImpl*(self: NodeValue, argsUnused: seq[NodeValue]): NodeValue =
  discard argsUnused
  var source = ""
  if tryExtractString(self, source):
    return toValue(source.toUpperAscii())
  return toValue("")

proc primitiveStringTrimValueImpl*(self: NodeValue, argsUnused: seq[NodeValue]): NodeValue =
  discard argsUnused
  var source = ""
  if tryExtractString(self, source):
    return toValue(strip(source))
  return toValue("")

proc primitiveStringSplitValueImpl*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len == 0:
    return NodeValue(kind: vkArray, arrayVal: @[])

  var source = ""
  if not tryExtractString(self, source):
    return NodeValue(kind: vkArray, arrayVal: @[])

  var delim = ""
  if not tryExtractString(args[0], delim):
    delim = ""
  if delim.len == 0:
    return NodeValue(kind: vkArray, arrayVal: @[])

  let parts = source.split(delim)
  var elements: seq[NodeValue] = @[]
  for part in parts:
    elements.add(toValue(part))
  return NodeValue(kind: vkArray, arrayVal: elements)

proc primitiveStringFromToValueImpl*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len < 2:
    return toValue("")

  var source = ""
  if not tryExtractString(self, source):
    return toValue("")

  let (ok1, fromIdx) = args[0].tryGetInt()
  let (ok2, toIdx) = args[1].tryGetInt()
  if ok1 and ok2 and fromIdx >= 0 and toIdx < source.len and fromIdx <= toIdx:
    return toValue(source[fromIdx..toIdx])
  return toValue("")

proc primitiveStringIndexOfValueImpl*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len == 0:
    return toValue(-1)

  var source = ""
  if not tryExtractString(self, source):
    return toValue(-1)

  var needle = ""
  if not tryExtractString(args[0], needle):
    return toValue(-1)
  if needle.len == 0:
    return toValue(-1)

  return toValue(source.find(needle))

proc primitiveStringIncludesSubStringValueImpl*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len == 0:
    return falseValue

  var source = ""
  if not tryExtractString(self, source):
    return falseValue

  var needle = ""
  if not tryExtractString(args[0], needle):
    return falseValue
  return toValue(needle in source)

proc primitiveStringReplaceWithValueImpl*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len < 2:
    var source = ""
    if tryExtractString(self, source):
      return toValue(source)
    return toValue("")

  var source = ""
  if not tryExtractString(self, source):
    return toValue("")

  var oldPart = ""
  var newPart = ""
  if not tryExtractString(args[0], oldPart):
    oldPart = ""
  if not tryExtractString(args[1], newPart):
    newPart = ""
  return toValue(source.replace(oldPart, newPart))

proc primitiveStringAsSymbolValueImpl*(self: NodeValue, argsUnused: seq[NodeValue]): NodeValue =
  discard argsUnused
  var source = ""
  if tryExtractString(self, source):
    return toSymbol(source)
  return self

proc primitiveStringRepeatValueImpl*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len == 0:
    var source = ""
    if tryExtractString(self, source):
      return toValue(source)
    return toValue("")

  var source = ""
  if not tryExtractString(self, source):
    return toValue("")

  let (ok, count) = args[0].tryGetInt()
  if not ok or count <= 0:
    return toValue("")

  var resultStr = ""
  for _ in 0..<count:
    resultStr.add(source)
  return toValue(resultStr)

proc primitiveSqrtValueImpl*(self: NodeValue, argsUnused: seq[NodeValue]): NodeValue =
  discard argsUnused
  let (ok, val) = self.tryGetFloat()
  if ok:
    return toValue(sqrt(val))
  return nilValue()

proc primitivePrintStringValueImpl*(self: NodeValue, argsUnused: seq[NodeValue]): NodeValue =
  discard argsUnused
  case self.kind
  of vkString:
    return self
  of vkSymbol:
    return NodeValue(kind: vkString, strVal: "#" & self.symVal)
  else:
    return NodeValue(kind: vkString, strVal: self.toString())

proc primitivePlusValueImpl*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len == 0:
    return nilValue()
  let (intOk, intVal) = args[0].tryGetInt()
  if self.kind == vkInt and intOk:
    return toValue(self.intVal + intVal)

  let (lhsOk, lhsFloat) = self.tryGetFloat()
  let (rhsOk, rhsFloat) = args[0].tryGetFloat()
  if lhsOk and rhsOk:
    return toValue(lhsFloat + rhsFloat)
  return nilValue()

proc primitiveMinusValueImpl*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len == 0:
    return nilValue()
  let (intOk, intVal) = args[0].tryGetInt()
  if self.kind == vkInt and intOk:
    return toValue(self.intVal - intVal)

  let (lhsOk, lhsFloat) = self.tryGetFloat()
  let (rhsOk, rhsFloat) = args[0].tryGetFloat()
  if lhsOk and rhsOk:
    return toValue(lhsFloat - rhsFloat)
  return nilValue()

proc primitiveTimesValueImpl*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len == 0:
    return nilValue()
  let (intOk, intVal) = args[0].tryGetInt()
  if self.kind == vkInt and intOk:
    return toValue(self.intVal * intVal)

  let (lhsOk, lhsFloat) = self.tryGetFloat()
  let (rhsOk, rhsFloat) = args[0].tryGetFloat()
  if lhsOk and rhsOk:
    return toValue(lhsFloat * rhsFloat)
  return nilValue()

proc primitiveLtValueImpl*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len == 0:
    return falseValue
  let (intOk, intVal) = args[0].tryGetInt()
  if self.kind == vkInt and intOk:
    return toValue(self.intVal < intVal)

  let (lhsOk, lhsFloat) = self.tryGetFloat()
  let (rhsOk, rhsFloat) = args[0].tryGetFloat()
  if lhsOk and rhsOk:
    return toValue(lhsFloat < rhsFloat)
  return falseValue

proc primitiveGtValueImpl*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len == 0:
    return falseValue
  let (intOk, intVal) = args[0].tryGetInt()
  if self.kind == vkInt and intOk:
    return toValue(self.intVal > intVal)

  let (lhsOk, lhsFloat) = self.tryGetFloat()
  let (rhsOk, rhsFloat) = args[0].tryGetFloat()
  if lhsOk and rhsOk:
    return toValue(lhsFloat > rhsFloat)
  return falseValue

proc primitiveEqValueImpl*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len == 0:
    return falseValue
  let (intOk, intVal) = args[0].tryGetInt()
  if self.kind == vkInt and intOk:
    return toValue(self.intVal == intVal)

  let (lhsOk, lhsFloat) = self.tryGetFloat()
  let (rhsOk, rhsFloat) = args[0].tryGetFloat()
  if lhsOk and rhsOk:
    return toValue(lhsFloat == rhsFloat)
  return falseValue

proc primitiveLeValueImpl*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len == 0:
    return falseValue
  let (intOk, intVal) = args[0].tryGetInt()
  if self.kind == vkInt and intOk:
    return toValue(self.intVal <= intVal)

  let (lhsOk, lhsFloat) = self.tryGetFloat()
  let (rhsOk, rhsFloat) = args[0].tryGetFloat()
  if lhsOk and rhsOk:
    return toValue(lhsFloat <= rhsFloat)
  return falseValue

proc primitiveGeValueImpl*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len == 0:
    return falseValue
  let (intOk, intVal) = args[0].tryGetInt()
  if self.kind == vkInt and intOk:
    return toValue(self.intVal >= intVal)

  let (lhsOk, lhsFloat) = self.tryGetFloat()
  let (rhsOk, rhsFloat) = args[0].tryGetFloat()
  if lhsOk and rhsOk:
    return toValue(lhsFloat >= rhsFloat)
  return falseValue

proc primitiveNeValueImpl*(self: NodeValue, args: seq[NodeValue]): NodeValue =
  if args.len == 0:
    return trueValue
  let (intOk, intVal) = args[0].tryGetInt()
  if self.kind == vkInt and intOk:
    return toValue(self.intVal != intVal)

  let (lhsOk, lhsFloat) = self.tryGetFloat()
  let (rhsOk, rhsFloat) = args[0].tryGetFloat()
  if lhsOk and rhsOk:
    return toValue(lhsFloat != rhsFloat)
  return trueValue
