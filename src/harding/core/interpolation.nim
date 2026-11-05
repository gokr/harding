# ============================================================================
# String interpolation
# ============================================================================
#
# One implementation, shared by the interpreter and by Granite-compiled code, so
# `String>>interpolate:` cannot drift between engines.
#
# Grammar: `$name`, `$name::slot::nested`, `${expression}` or `$(expression)`,
# and `\$` for a literal dollar. Everything else is copied through unchanged.

proc isNameChar(c: char): bool =
  c in {'a'..'z', 'A'..'Z', '0'..'9', '_'}

proc interpolateText*(source: string,
                      resolve: proc (name: string, tail: seq[string],
                                     found: var bool): string): string =
  ## Replace `$` holes in `source`. `resolve` answers the display text for a
  ## hole and sets `found`; an unresolved hole is left as written.
  result = ""
  var position = 0
  while position < source.len:
    let ch = source[position]
    if ch == '\\' and position + 1 < source.len and source[position + 1] == '$':
      result.add('$')
      position += 2
      continue
    if ch == '$' and position + 1 < source.len:
      var cursor = position + 1
      var name = ""
      if source[cursor] == '{' or source[cursor] == '(':
        let opener = source[cursor]
        let closer = if opener == '{': '}' else: ')'
        inc cursor
        var depth = 1
        let start = cursor
        while cursor < source.len and depth > 0:
          if source[cursor] == opener:
            inc depth
          elif source[cursor] == closer:
            dec depth
            if depth == 0:
              break
          inc cursor
        name = source[start ..< cursor]
        if cursor < source.len:
          inc cursor
      else:
        let start = cursor
        while cursor < source.len and isNameChar(source[cursor]):
          inc cursor
        name = source[start ..< cursor]
      if name.len > 0:
        var tail: seq[string] = @[]
        while cursor + 1 < source.len and source[cursor] == ':' and source[cursor + 1] == ':':
          cursor += 2
          let start = cursor
          while cursor < source.len and isNameChar(source[cursor]):
            inc cursor
          if cursor == start:
            break
          tail.add(source[start ..< cursor])
        var found = false
        let shown = resolve(name, tail, found)
        if found:
          result.add(shown)
        else:
          result.add("$" & name)
        position = cursor
        continue
    result.add(ch)
    inc position
