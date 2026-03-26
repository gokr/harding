import std/[tables, options]
import ../core/types

# Interpreter type is defined in core/types.nim, not vm.nim
# We use the Interpreter type from types.nim which has all the fields we need

type
  HardingPackageSpec* = object
    name*: string
    version*: string
    bootstrapPath*: string
    sources*: seq[tuple[path: string, source: string]]
    registerPrimitives*: proc(interp: var Interpreter) {.nimcall.}

# Callback for evalStatements - set by vm.nim to break circular dependency
type EvalStatementsProc* = proc(interp: var Interpreter, source: string): (seq[NodeValue], string) {.nimcall.}
type InstallThreadBridgeProc* = proc(interp: var Interpreter, channelGlobalName: string,
    pollProc: proc(): Option[NodeValue], workerSource: string): bool {.nimcall.}

var evalStatementsCallback*: EvalStatementsProc = nil
var installThreadBridgeCallback*: InstallThreadBridgeProc = nil

proc ensurePackageSourceTable(interp: var Interpreter) =
  if interp.packageSources == nil:
    interp.packageSources = new(Table[string, string])
    interp.packageSources[] = initTable[string, string]()

proc addPackageSource*(interp: var Interpreter, path: string, source: string) =
  ensurePackageSourceTable(interp)
  interp.packageSources[][path] = source

proc hasPackageSource*(interp: Interpreter, path: string): bool =
  if interp == nil or interp.packageSources == nil:
    return false
  path in interp.packageSources[]

proc rebindDeclarativePrimitives(interp: var Interpreter) =
  ## Rebind methods with declarative primitive syntax (<primitive ...>) to their
  ## native implementations after all primitives have been registered.
  if interp.globals == nil:
    return

  proc rebindMethodTable(cls: Class, methodTable: var Table[string, BlockNode],
                         allMethods: Table[string, BlockNode],
                         allClassMethods: Table[string, BlockNode]) =
    for selector, meth in methodTable.mpairs:
      discard selector
      if meth == nil or meth.primitiveSelector.len == 0 or meth.nativeImpl != nil:
        continue
      # Check both instance and class method tables for the primitive
      var primMethod: BlockNode = nil
      if meth.primitiveSelector in allMethods:
        primMethod = allMethods[meth.primitiveSelector]
        debug("Rebinding ", cls.name, ">>", selector, " from allMethods to ", meth.primitiveSelector)
      elif meth.primitiveSelector in allClassMethods:
        primMethod = allClassMethods[meth.primitiveSelector]
        debug("Rebinding ", cls.name, ">>", selector, " from allClassMethods to ", meth.primitiveSelector)
      else:
        if cls.name == "MysqlConnection":
          debug("Could not find primitive for MysqlConnection>>", selector, ": ", meth.primitiveSelector)
      
      if primMethod != nil and primMethod.nativeImpl != nil:
        meth.nativeImpl = primMethod.nativeImpl
        meth.nativeValueImpl = primMethod.nativeValueImpl
        meth.hasInterpreterParam = primMethod.hasInterpreterParam

  for _, value in interp.globals[].mpairs:
    if value.kind != vkClass or value.classVal == nil:
      continue
    var cls = value.classVal
    rebindMethodTable(cls, cls.methods, cls.allMethods, cls.allClassMethods)
    rebindMethodTable(cls, cls.classMethods, cls.allMethods, cls.allClassMethods)

proc installPackage*(interp: var Interpreter, spec: HardingPackageSpec): bool =
  if spec.name.len == 0:
    warn("installPackage: package name is empty")
    return false

  ensurePackageSourceTable(interp)
  for entry in spec.sources:
    interp.packageSources[][entry.path] = entry.source

  if spec.bootstrapPath.len > 0:
    if spec.bootstrapPath notin interp.packageSources[]:
      warn("installPackage: bootstrap source missing for package ", spec.name,
           " at path ", spec.bootstrapPath)
      return false

    if evalStatementsCallback != nil:
      let (_, err) = evalStatementsCallback(interp, interp.packageSources[][spec.bootstrapPath])
      if err.len > 0:
        warn("installPackage: bootstrap evaluation failed for package ", spec.name,
             ": ", err)
        return false
    else:
      warn("installPackage: evalStatements callback not set")
      return false

  if spec.registerPrimitives != nil:
    spec.registerPrimitives(interp)
    rebindDeclarativePrimitives(interp)

  debug("Installed Harding package: ", spec.name, " (", spec.version, ")")
  return true
