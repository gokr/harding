import std/strutils
import ../core/types
import ../compiler/context
import ../compiler/symbols

# ============================================================================
# Primitive Code Generation
# Handles <primitive> blocks with embedded Nim code
# ============================================================================

proc genPrimitiveMethod*(cls: ClassInfo, prim: PrimitiveNode,
                         selector: string, prototypeName: string = ""): string =
  ## Generate a method with primitive implementation
  let nimName = mangleSelector(selector)
  let clsPrefix = if cls != nil: mangleClass(cls.name) & "_" else: ""

  var output = "proc " & clsPrefix & nimName & "*(self: ref RuntimeObject"

  # Determine parameter count from selector and add parameters
  let paramCount = selector.count(':')
  for i in 0..<paramCount:
    output.add(", arg" & $i & ": NodeValue")

  output.add("): NodeValue {.cdecl, exportc.} =\n")
  output.add("  ## Compiled primitive method: " & selector & "\n")
  if prototypeName.len > 0:
    output.add("  ## Prototype: " & prototypeName & "\n")
  output.add("  ##\n")

  # Add the embedded Nim code
  if prim.nimCode.len > 0:
    output.add("  # Embedded primitive implementation\n")

    # Indent the primitive code
    for line in prim.nimCode.splitLines():
      if line.len > 0:
        output.add("  " & line.strip() & "\n")
      else:
        output.add("\n")

  else:
    output.add("  # No primitive implementation\n")

  # Add fallback (if any)
  if prim.fallback.len > 0:
    output.add("  # Smalltalk fallback (not used in compiled code)\n")
    output.add("  # Fallback nodes: " & $prim.fallback.len & "\n")

  output.add("\n\n")
  return output

proc genPrimitiveWrapper*(cls: ClassInfo, prim: PrimitiveNode,
                          selector: string): string =
  ## Generate a wrapper that calls the primitive with error handling
  let nimName = mangleSelector(selector)
  let clsPrefix = if cls != nil: mangleClass(cls.name) & "_" else: ""

  var output = "proc " & clsPrefix & nimName & "_safe*(self: ref RuntimeObject"

  let paramCount = selector.count(':')
  for i in 0..<paramCount:
    output.add(", arg" & $i & ": NodeValue")

  output.add("): NodeValue {.cdecl, exportc.} =\n")
  output.add("  ## Safe wrapper for primitive: " & selector & "\n")
  output.add("  ##\n")
  output.add("  try:\n")
  output.add("    return " & clsPrefix & nimName & "(self")

  for i in 0..<paramCount:
    output.add(", arg" & $i)

  output.add(")\n")
  output.add("  except Exception as e:\n")
  output.add("    # Fallback to dynamic dispatch\n")
  output.add("    var args: seq[NodeValue] = @[]\n")

  for i in 0..<paramCount:
    output.add("    args.add(arg" & $i & ")\n")

  output.add("    return sendMessage(runtime, self.toValue(), \"" & selector & "\", args)\n\n")

  return output

proc extractPrimitiveSelector*(prim: PrimitiveNode): string =
  ## Extract selector from primitive tag
  # Format: <primitive> or <primitive name="selector">
  let tag = prim.tag
  if tag.contains("name=\""):
    let start = tag.find("name=\"") + 6
    let endPos = tag.find("\"", start)
    if endPos > start:
      return tag[start..<endPos]
  return "unknown"
