import std/[tables]
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

var evalStatementsCallback*: EvalStatementsProc = nil

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

  debug("Installed Harding package: ", spec.name, " (", spec.version, ")")
  return true
