##
## primitives.nim - Nim primitive implementations for harding-echo
##
## This file implements the actual functionality behind the Harding primitives.

import std/[logging]
import harding/core/types
import harding/interpreter/objects

# Global counter (just for demonstration)
var echoCount: int = 0

proc primitiveEchoEchoImpl*(self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Echo back the message that was sent
  ## Primitive: primitiveEchoEcho:
  discard self
  
  if args.len < 1:
    return nilValue()
  
  let message = args[0].toString()
  echoCount += 1
  debug("Echo called with: ", message)
  
  return toValue(message)

proc primitiveEchoWithPrefixImpl*(self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Echo with a prefix
  ## Primitive: primitiveEchoWithPrefix:message:
  discard self
  
  if args.len < 2:
    return nilValue()
  
  let message = args[0].toString()
  let prefix = args[1].toString()
  echoCount += 1
  
  let result = prefix & message
  debug("Echo with prefix: ", result)
  
  return toValue(result)

proc primitiveEchoCountImpl*(self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Get the number of times echo was called
  ## Primitive: primitiveEchoCount
  discard self
  discard args
  
  return toValue(echoCount)

proc primitiveEchoResetImpl*(self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
  ## Reset the counter
  ## Primitive: primitiveEchoReset
  discard self
  discard args
  
  echoCount = 0
  return toValue(true)
