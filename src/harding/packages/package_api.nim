import std/[tables]
import ../core/types
import ../interpreter/vm

type
  HardingPackageSpec* = object
    ## Package descriptor for embedding Harding sources with Nim primitives.
    name*: string
    version*: string
    bootstrapPath*: string
    sources*: seq[tuple[path: string, source: string]]
    registerPrimitives*: proc(interp: var Interpreter) {.nimcall.}

proc ensurePackageSourceTable(interp: var Interpreter) =
  if interp.packageSources == nil:
    interp.packageSources = new(Table[string, string])
    interp.packageSources[] = initTable[string, string]()

proc addPackageSource*(interp: var Interpreter, path: string, source: string) =
  ## Register one embedded source file for subsequent `load:` calls.
  ensurePackageSourceTable(interp)
  interp.packageSources[][path] = source

proc hasPackageSource*(interp: Interpreter, path: string): bool =
  ## Check whether a virtual package source path is registered.
  if interp == nil or interp.packageSources == nil:
    return false
  path in interp.packageSources[]

proc installPackage*(interp: var Interpreter, spec: HardingPackageSpec): bool =
  ## Install a package by registering sources, evaluating bootstrap,
  ## and then binding Nim primitive implementations.
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

    let (_, err) = interp.evalStatements(interp.packageSources[][spec.bootstrapPath])
    if err.len > 0:
      warn("installPackage: bootstrap evaluation failed for package ", spec.name,
           ": ", err)
      return false

  if spec.registerPrimitives != nil:
    spec.registerPrimitives(interp)

  debug("Installed Harding package: ", spec.name, " (", spec.version, ")")
  return true
