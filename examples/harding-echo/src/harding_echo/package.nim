##
## package.nim - Harding Echo Package registration
##
## This file registers the package with Harding and binds the primitives.

import std/[tables, os]
import harding/core/types
import harding/interpreter/objects
import harding/interpreter/vm
import harding/packages/package_api
import ./primitives

# Embed the .hrd source files using staticRead
const BootstrapHrd = staticRead("lib/echo/Bootstrap.hrd")
const EchoHrd = staticRead("lib/echo/Echo.hrd")

proc registerEchoPrimitives*(interp: var Interpreter) {.nimcall.} =
  ## Register all Echo package primitives with the interpreter
  
  # Find the Echo class in globals
  if "Echo" notin interp.globals[]:
    warn("Echo class not found in globals, skipping primitive registration")
    return
  
  let echoVal = interp.globals[]["Echo"]
  if echoVal.kind != vkClass:
    warn("Echo is not a class, skipping primitive registration")
    return
  
  let echoClass = echoVal.classVal
  
  # Register primitiveEchoEcho:
  let echoM = createCoreMethod("primitiveEchoEcho:")
  echoM.setNativeImpl(primitiveEchoEchoImpl)
  echoClass.classMethods["primitiveEchoEcho:"] = echoM
  echoClass.allClassMethods["primitiveEchoEcho:"] = echoM
  
  # Register primitiveEchoWithPrefix:message:
  let prefixM = createCoreMethod("primitiveEchoWithPrefix:message:")
  prefixM.setNativeImpl(primitiveEchoWithPrefixImpl)
  echoClass.classMethods["primitiveEchoWithPrefix:message:"] = prefixM
  echoClass.allClassMethods["primitiveEchoWithPrefix:message:"] = prefixM
  
  # Register primitiveEchoCount
  let countM = createCoreMethod("primitiveEchoCount")
  countM.setNativeImpl(primitiveEchoCountImpl)
  echoClass.classMethods["primitiveEchoCount"] = countM
  echoClass.allClassMethods["primitiveEchoCount"] = countM
  
  # Register primitiveEchoReset
  let resetM = createCoreMethod("primitiveEchoReset")
  resetM.setNativeImpl(primitiveEchoResetImpl)
  echoClass.classMethods["primitiveEchoReset"] = resetM
  echoClass.allClassMethods["primitiveEchoReset"] = resetM
  
  debug("Registered Echo package primitives")

proc installEchoPackage*(interp: var Interpreter): bool =
  ## Install the Echo package into the interpreter
  ##
  ## Usage:
  ##   var interp = newInterpreter()
  ##   initGlobals(interp)
  ##   loadStdlib(interp)
  ##   discard installEchoPackage(interp)
  
  let spec = HardingPackageSpec(
    name: "harding-echo",
    version: "0.1.0",
    bootstrapPath: "lib/echo/Bootstrap.hrd",
    sources: @[
      (path: "lib/echo/Bootstrap.hrd", source: BootstrapHrd),
      (path: "lib/echo/Echo.hrd", source: EchoHrd)
    ],
    registerPrimitives: registerEchoPrimitives
  )
  
  return installPackage(interp, spec)
