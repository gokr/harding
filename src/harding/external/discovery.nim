## ============================================================================
## External Library Discovery
## Handles registry loading, metadata parsing, and installed library discovery
## ============================================================================

import std/[os, strutils, json, tables, times, options]

type
  NimbleMetadata* = object
    version*: string
    description*: string
    author*: string
    requires*: seq[string]

  LibraryInfo* = object
    name*: string
    version*: string
    installedAt*: DateTime
    source*: string
    commit*: string
    description*: string
    author*: string
    requires*: seq[string]

  SimpleLibraryRegistry* = object
    version*: string
    libraries*: Table[string, string]

  CachedLibraryMetadata* = object
    url*: string
    version*: string
    description*: string
    author*: string
    requires*: seq[string]
    fetchedAt*: DateTime

  RegistryFullCache* = object
    version*: string
    updatedAt*: DateTime
    libraries*: Table[string, CachedLibraryMetadata]

const
  ExternalDir = "external"
  RegistryFile = "registry.json"
  RegistryFullFile = "registry-full.json"
  LibMetadataFile = ".harding-lib.json"

proc getExternalDir*(): string =
  ExternalDir

proc getRegistryPath*(): string =
  RegistryFile

proc getHardingHome*(): string =
  getEnv("HARDING_HOME", ".")

proc getRegistryCachePath*(): string =
  getHardingHome() / RegistryFullFile

proc loadSimpleRegistry*(): SimpleLibraryRegistry =
  result = SimpleLibraryRegistry(
    version: "1.0.0",
    libraries: initTable[string, string]()
  )

  if not fileExists(RegistryFile):
    return result

  try:
    let root = parseJson(readFile(RegistryFile))
    if root.hasKey("version"):
      result.version = root["version"].getStr()
    if root.hasKey("libraries"):
      for libName, libUrl in root["libraries"]:
        result.libraries[libName] = libUrl.getStr()
  except:
    discard

proc getLibraryUrl*(libName: string): string =
  let registry = loadSimpleRegistry()
  if registry.libraries.hasKey(libName):
    registry.libraries[libName]
  else:
    ""

proc listRegistryLibraries*(): seq[tuple[name: string, url: string]] =
  let registry = loadSimpleRegistry()
  for name, url in registry.libraries:
    result.add((name: name, url: url))

proc isLibraryInRegistry*(libName: string): bool =
  let registry = loadSimpleRegistry()
  registry.libraries.hasKey(libName)

proc parseNimbleFile*(nimblePath: string): NimbleMetadata =
  if not fileExists(nimblePath):
    return NimbleMetadata()

  try:
    for line in readFile(nimblePath).splitLines():
      let trimmed = line.strip()
      if trimmed.startsWith("version"):
        let parts = trimmed.split("=", 1)
        if parts.len == 2:
          result.version = parts[1].strip().strip(chars = {'"', '\''})
      elif trimmed.startsWith("description"):
        let parts = trimmed.split("=", 1)
        if parts.len == 2:
          result.description = parts[1].strip().strip(chars = {'"', '\''})
      elif trimmed.startsWith("author"):
        let parts = trimmed.split("=", 1)
        if parts.len == 2:
          result.author = parts[1].strip().strip(chars = {'"', '\''})
      elif trimmed.startsWith("requires "):
        let firstQuote = trimmed.find('"')
        if firstQuote >= 0:
          let secondQuote = trimmed.find('"', firstQuote + 1)
          if secondQuote > firstQuote:
            result.requires.add(trimmed[(firstQuote + 1) ..< secondQuote])
  except:
    discard

proc getNimbleMetadata*(libDir: string): NimbleMetadata =
  let nimblePath = libDir / (lastPathPart(libDir) & ".nimble")
  parseNimbleFile(nimblePath)

proc loadRegistryCache*(): RegistryFullCache =
  result = RegistryFullCache(
    version: "1.0.0",
    updatedAt: now().utc,
    libraries: initTable[string, CachedLibraryMetadata]()
  )

  let cachePath = getRegistryCachePath()
  if not fileExists(cachePath):
    return result

  try:
    let root = parseJson(readFile(cachePath))
    if root.hasKey("version"):
      result.version = root["version"].getStr()
    if root.hasKey("updatedAt"):
      result.updatedAt = parse(root["updatedAt"].getStr(), "yyyy-MM-dd'T'HH:mm:ss'Z'")
    if root.hasKey("libraries"):
      for libName, value in root["libraries"]:
        var item = CachedLibraryMetadata()
        if value.hasKey("url"):
          item.url = value["url"].getStr()
        if value.hasKey("version"):
          item.version = value["version"].getStr()
        if value.hasKey("description"):
          item.description = value["description"].getStr()
        if value.hasKey("author"):
          item.author = value["author"].getStr()
        if value.hasKey("requires"):
          for req in value["requires"]:
            item.requires.add(req.getStr())
        if value.hasKey("fetchedAt"):
          item.fetchedAt = parse(value["fetchedAt"].getStr(), "yyyy-MM-dd'T'HH:mm:ss'Z'")
        result.libraries[libName] = item
  except:
    discard

proc saveRegistryCache*(cache: RegistryFullCache) =
  let cachePath = getRegistryCachePath()
  let cacheDir = parentDir(cachePath)
  if cacheDir.len > 0 and not dirExists(cacheDir):
    createDir(cacheDir)

  var root = newJObject()
  root["version"] = %cache.version
  root["updatedAt"] = %cache.updatedAt.format("yyyy-MM-dd'T'HH:mm:ss'Z'")

  var libs = newJObject()
  for libName, item in cache.libraries:
    var node = newJObject()
    node["url"] = %item.url
    node["version"] = %item.version
    node["description"] = %item.description
    node["author"] = %item.author
    node["fetchedAt"] = %item.fetchedAt.format("yyyy-MM-dd'T'HH:mm:ss'Z'")
    var reqs = newJArray()
    for req in item.requires:
      reqs.add(%req)
    node["requires"] = reqs
    libs[libName] = node
  root["libraries"] = libs

  writeFile(cachePath, root.pretty())

proc cacheLibraryMetadata*(libName, url: string, meta: NimbleMetadata) =
  var cache = loadRegistryCache()
  cache.version = loadSimpleRegistry().version
  cache.updatedAt = now().utc
  cache.libraries[libName] = CachedLibraryMetadata(
    url: url,
    version: meta.version,
    description: meta.description,
    author: meta.author,
    requires: meta.requires,
    fetchedAt: now().utc
  )
  saveRegistryCache(cache)

proc getCachedLibraryMetadata*(libName: string): Option[CachedLibraryMetadata] =
  let cache = loadRegistryCache()
  if cache.libraries.hasKey(libName):
    some(cache.libraries[libName])
  else:
    none(CachedLibraryMetadata)

proc saveLibraryMetadata*(libDir: string, info: LibraryInfo) =
  let metadataPath = libDir / LibMetadataFile
  var root = newJObject()
  root["name"] = %info.name
  root["version"] = %info.version
  root["installedAt"] = %info.installedAt.format("yyyy-MM-dd'T'HH:mm:ss'Z'")
  root["source"] = %info.source
  root["commit"] = %info.commit
  root["description"] = %info.description
  root["author"] = %info.author
  var reqs = newJArray()
  for req in info.requires:
    reqs.add(%req)
  root["requires"] = reqs
  writeFile(metadataPath, root.pretty())

proc loadLibraryMetadata*(libDir: string): Option[LibraryInfo] =
  let metadataPath = libDir / LibMetadataFile
  if not fileExists(metadataPath):
    return none(LibraryInfo)

  try:
    let root = parseJson(readFile(metadataPath))
    var info = LibraryInfo(
      name: root["name"].getStr(),
      version: root["version"].getStr(),
      source: root["source"].getStr(),
      commit: root["commit"].getStr()
    )
    if root.hasKey("installedAt"):
      info.installedAt = parse(root["installedAt"].getStr(), "yyyy-MM-dd'T'HH:mm:ss'Z'")
    if root.hasKey("description"):
      info.description = root["description"].getStr()
    if root.hasKey("author"):
      info.author = root["author"].getStr()
    if root.hasKey("requires"):
      for req in root["requires"]:
        info.requires.add(req.getStr())

    let nimbleMeta = getNimbleMetadata(libDir)
    if info.version.len == 0 and nimbleMeta.version.len > 0:
      info.version = nimbleMeta.version
    if nimbleMeta.description.len > 0:
      info.description = nimbleMeta.description
    if nimbleMeta.author.len > 0:
      info.author = nimbleMeta.author
    if info.requires.len == 0 and nimbleMeta.requires.len > 0:
      info.requires = nimbleMeta.requires

    return some(info)
  except:
    none(LibraryInfo)

proc discoverInstalledLibraries*(): seq[LibraryInfo] =
  if not dirExists(ExternalDir):
    return @[]

  for entry in walkDir(ExternalDir):
    if entry.kind != pcDir:
      continue
    let metadataOpt = loadLibraryMetadata(entry.path)
    if metadataOpt.isSome:
      result.add(metadataOpt.get())

proc isLibraryInstalled*(libName: string): bool =
  let libDir = ExternalDir / libName
  dirExists(libDir) and fileExists(libDir / LibMetadataFile)

proc getInstalledLibrary*(libName: string): Option[LibraryInfo] =
  let libDir = ExternalDir / libName
  if not dirExists(libDir):
    return none(LibraryInfo)
  loadLibraryMetadata(libDir)

proc getLibraryCompileFlag*(libName: string): string =
  "-d:harding_" & libName

proc generateCompileFlags*(libs: seq[LibraryInfo]): string =
  var flags: seq[string] = @[]
  for lib in libs:
    flags.add(getLibraryCompileFlag(lib.name))
  flags.join(" ")

proc getLibraryModuleName*(libName: string): string =
  libName

proc getLibraryHardingName*(libName: string): string =
  if libName.len == 0:
    return ""
  $libName[0].toUpperAscii() & libName[1 .. ^1]
