import std/[strutils, tables]

# ============================================================================
# Symbol Table Management
# Handles symbol mangling and name resolution for code generation
# ============================================================================

type
  SymbolKind* = enum
    skClass          ## Class name
    skMethod         ## Method selector
    skSlot           ## Slot/instance variable
    skParameter      ## Method parameter
    skTemporary      ## Local temporary
    skGlobal         ## Global variable

  SymbolInfo* = object
    name*: string            ## Original name
    mangled*: string         ## Mangled identifier
    kind*: SymbolKind        ## Symbol type
    index*: int              ## Index (slot index, param index, etc.)
    class*: string       ## Owning class name (if applicable)

  SymbolTable* = ref object
    symbols*: Table[string, SymbolInfo]  ## Name -> info
    class*: string        ## Current class scope
    currentMethod*: string    ## Current method scope

proc newSymbolTable*(class = ""): SymbolTable =
  ## Create new symbol table
  result = SymbolTable(
    symbols: initTable[string, SymbolInfo](),
    class: class,
    currentMethod: ""
  )

proc mangleSelector*(selector: string): string =
  ## Convert selector to valid Nim identifier
  ## Examples: "at:put:" -> "nt_at_kput_k", "+" -> "nt_plus", "at" -> "nt_at"
  result = selector
  # First, escape any existing underscores to avoid collisions with our encoding
  result = result.replace("_", "_u")
  # Replace colons with _k to distinguish keyword selectors from unary
  result = result.replace(":", "_k")
  result = result.replace("-", "minus")
  result = result.replace("+", "plus")
  result = result.replace("*", "star")
  result = result.replace("/", "slash")
  result = result.replace("<", "lt")
  result = result.replace(">", "gt")
  result = result.replace("=", "eq")
  result = result.replace("~", "tilde")
  result = result.replace("@", "at")
  result = result.replace("|", "pipe")
  # Add nt_ prefix
  result = "nt_" & result

proc mangleClass*(name: string): string =
  ## Convert class name to valid Nim identifier
  result = "Class_" & name.replace(":", "_")

proc mangleSlot*(name: string): string =
  ## Convert slot name to valid Nim identifier
  result = name.replace(":", "_")

proc addSymbol*(table: var SymbolTable, info: SymbolInfo) =
  ## Add symbol to table
  table.symbols[info.name] = info

proc lookup*(table: SymbolTable, name: string): SymbolInfo =
  ## Look up symbol by name
  if name in table.symbols:
    return table.symbols[name]
  return SymbolInfo(name: name, mangled: name, kind: skGlobal, index: -1)

proc exists*(table: SymbolTable, name: string): bool =
  ## Check if symbol exists
  name in table.symbols

proc clearMethodScope*(table: var SymbolTable) =
  ## Clear method-specific symbols
  for name, info in table.symbols:
    if info.kind == skParameter or info.kind == skTemporary:
      table.symbols.del(name)
  table.currentMethod = ""

proc clearClassScope*(table: var SymbolTable) =
  ## Clear all scope-local symbols
  for name, info in table.symbols:
    if info.kind in {skSlot, skMethod}:
      table.symbols.del(name)
  table.class = ""
  table.clearMethodScope()
