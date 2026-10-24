import std/[os, json, tables, sets, strutils, algorithm]
import checksums/sha1
import ../core/types
import ../parser/parser

type
  FrozenEntry* = object
    name*, source*, digest*, tier*: string
    dependencies*, cases*: seq[string]
  FrozenPlan* = object
    entries*: Table[string, FrozenEntry]
    order*: seq[string]
    roots*: seq[string]
    manifestDigest*: string

proc fail(message: string) =
  raise newException(ValueError, "Frozen manifest: " & message)

proc stringList(node: JsonNode, field: string): seq[string] =
  if not node.hasKey(field) or node[field].kind != JArray:
    fail("missing array " & field)
  for item in node[field]:
    if item.kind != JString or item.getStr.len == 0:
      fail("invalid " & field & " item")
    if item.getStr in result: fail("duplicate " & field & " item: " & item.getStr)
    result.add(item.getStr)

proc globalReferences(node: Node, locals: HashSet[string], refs: var HashSet[string]) =
  if node == nil: return
  template visit(child: Node) = globalReferences(child, locals, refs)
  case node.kind
  of nkIdent:
    let name = node.IdentNode.name
    if name.len > 0 and name[0] in {'A'..'Z'} and name notin locals: refs.incl(name)
  of nkAssign:
    visit(node.AssignNode.expression)
  of nkMessage:
    visit(node.MessageNode.receiver)
    for arg in node.MessageNode.arguments: visit(arg)
  of nkBlock:
    var scope = locals
    for name in node.BlockNode.parameters & node.BlockNode.temporaries: scope.incl(name)
    for child in node.BlockNode.body: globalReferences(child, scope, refs)
  of nkLiteral:
    let value = node.LiteralNode.value
    if value.kind == vkBlock: visit(value.blockVal)
  of nkReturn: visit(node.ReturnNode.expression)
  of nkArray:
    for child in node.ArrayNode.elements: visit(child)
  of nkTable:
    for (key, value) in node.TableNode.entries:
      visit(key)
      visit(value)
  of nkCascade:
    visit(node.CascadeNode.receiver)
    for child in node.CascadeNode.messages: visit(child)
  of nkIf:
    visit(node.IfNode.condition)
    visit(node.IfNode.thenBranch)
    visit(node.IfNode.elseBranch)
  of nkWhile:
    visit(node.WhileNode.condition)
    visit(node.WhileNode.body)
  of nkNamedAccess:
    visit(node.NamedAccessNode.receiver)
    visit(node.NamedAccessNode.valueExpr)
  of nkSlotAccess: visit(node.SlotAccessNode.valueExpr)
  of nkSuperSend:
    for child in node.SuperSendNode.arguments: visit(child)
  of nkPrimitiveCall:
    for child in node.PrimitiveCallNode.arguments: visit(child)
  of nkPseudoVar: discard
  else: fail("unsupported AST in dependency analysis: " & $node.kind)

proc frozenReferences*(source: string): seq[string] =
  ## Conservative syntactic closure; dynamic perform/evaluate are not inferred.
  let (nodes, syntax) = parse(source)
  if syntax.hasError: fail(syntax.errorMsg)
  var refs = initHashSet[string]()
  for node in nodes: globalReferences(node, initHashSet[string](), refs)
  for name in refs: result.add(name)
  result.sort()

proc frozenToolchainDigest*(root: string): string =
  ## Include generated-program runtime sources, not just the compiler binary.
  var paths: seq[string]
  for path in walkDirRec(root / "src/harding"):
    if path.endsWith(".nim"): paths.add(relativePath(path, root))
  for name in ["config.nims", "harding.nimble"]:
    if fileExists(root / name): paths.add(name)
  paths.sort()
  var combined = ""
  for path in paths:
    combined.add(path.replace('\\', '/') & ":" & $secureHash(readFile(root / path)) & "\n")
  result = $secureHash(combined)

proc hasFrozenHeader(source: string): bool =
  for line in source.splitLines:
    let stripped = line.strip
    if stripped.len == 0: continue
    if not stripped.startsWith("#"): break
    if stripped == "# @frozen": return true

proc loadFrozenPlan*(manifestPath, root: string): FrozenPlan =
  ## Validate drift and declared dependency closure before any source execution.
  let raw = readFile(manifestPath)
  let document = parseJson(raw)
  if document.kind != JObject or document{"version"} == nil or
     document["version"].kind != JInt or document["version"].getInt != 1:
    fail("unsupported version")
  result.manifestDigest = $secureHash(raw)
  result.roots = stringList(document, "roots")
  if result.roots.len == 0: fail("empty roots")
  if not document.hasKey("classes") or document["classes"].kind != JArray:
    fail("missing classes")
  result.entries = initTable[string, FrozenEntry]()
  for item in document["classes"]:
    if item.kind != JObject: fail("class entry must be an object")
    for field in ["name", "source", "sha1", "tier"]:
      if item{field} == nil or item[field].kind != JString: fail("missing string " & field)
    let name = item{"name"}.getStr
    let entry = FrozenEntry(name: name, source: item{"source"}.getStr,
      digest: item{"sha1"}.getStr.toUpperAscii, tier: item{"tier"}.getStr,
      dependencies: stringList(item, "dependencies"), cases: stringList(item, "cases"))
    if name.len == 0 or name in result.entries: fail("missing/duplicate class " & name)
    if entry.tier notin ["generic", "counterpart"]: fail("unsupported tier for " & name)
    if entry.cases.len == 0: fail("no conformance cases for " & name)
    if entry.source.len == 0 or entry.source.isAbsolute or ".." in entry.source.split({'/', '\\'}):
      fail("unsafe source path for " & name)
    let path = root / entry.source
    if not fileExists(path): fail("missing source " & entry.source)
    let source = readFile(path)
    if ($secureHash(source)) != entry.digest: fail("source drift: " & entry.source)
    if entry.tier == "generic":
      if not hasFrozenHeader(source): fail("missing header # @frozen: " & entry.source)
      let declared = entry.dependencies & @[name]
      let references = frozenReferences(source)
      if name notin references: fail("generic source does not reference declared class " & name)
      for reference in references:
        if reference notin declared: fail(name & " has undeclared dependency " & reference)
    result.entries[name] = entry
  # Opted-in stdlib files must be inventoried rather than silently ignored.
  if dirExists(root / "lib"):
    for path in walkDirRec(root / "lib"):
      if path.endsWith(".hrd") and hasFrozenHeader(readFile(path)):
        let relative = relativePath(path, root).replace('\\', '/')
        var listed = false
        for entry in result.entries.values:
          if entry.source == relative and entry.tier == "generic": listed = true
        if not listed: fail("unlisted annotated source: " & relative)
  # Validate every declared dependency, including unused entries, before DFS.
  for name, entry in result.entries:
    for dependency in entry.dependencies:
      if dependency notin result.entries: fail(name & " depends on absent " & dependency)
  let entries = result.entries
  var visited = initHashSet[string]()
  var active = initHashSet[string]()
  var order: seq[string]
  proc visit(name: string) =
    if name notin entries: fail("unknown root " & name)
    if name in visited: return
    if name in active: return # Mutually recursive method dependencies form one closure.
    active.incl(name)
    for dependency in entries[name].dependencies: visit(dependency)
    active.excl(name)
    visited.incl(name)
    order.add(name)
  for name in result.roots: visit(name)
  if visited.len != result.entries.len: fail("stale entries outside root closure")
  result.order = order

proc frozenSources*(plan: FrozenPlan, root: string): string =
  ## Compose generic definitions once in dependency order; counterparts stay native.
  var emitted = initHashSet[string]()
  for name in plan.order:
    let entry = plan.entries[name]
    if entry.tier == "generic" and entry.source notin emitted:
      emitted.incl(entry.source)
      result.add(readFile(root / entry.source) & "\n")
