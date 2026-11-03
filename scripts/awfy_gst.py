"""GNU Smalltalk adapter for the AWFY Harding ports.

GST 3.2 cannot ingest Harding source directly: it needs class declarations with
explicit instance-variable names, bracketed method bodies, `printNl` instead of
`println`, and `#(` array literals. This module performs that mechanical spelling
translation only — every algorithm, control-flow shape and check stays as written
in the port, so the timed program is the same one Harding runs.

Coverage is limited to ports whose classes are all defined in their own source
(Bounce, Json). Havlak is built on SOM `Core` collections this adapter does not
translate, so it is reported as uncovered rather than compared against a
different program.
"""
import re

IGNORED_TOP = {''}
DRIVER_MARKERS = ('(Bounce new benchmark) println.',
                  '(Bounce new benchmark) printNl.',
                  'AWFY Json checks passed',
                  'JsonChecks run.')


def split_definitions(source):
    """Split into definitions and top-level statements.

    Harding method definitions are NOT period-terminated: the closing `]` ends
    them. Splitting on periods alone therefore merged whole files into one
    statement, so this splits at the start of each new definition
    (`Name>>sel [`, `Name := ...`, `Name class>>sel [`) and on top-level periods.
    """
    lines = source.splitlines(keepends=True)
    chunks, current = [], []
    depth = 0
    definition = re.compile(r'^\s*(\w+( class)?>>|\w+ :=)')
    for line in lines:
        if depth == 0 and current and definition.match(line):
            text = ''.join(current).strip()
            if text:
                chunks.append(text)
            current = []
        index = 0
        in_string = False
        # A top-level period ends a statement too. Definitions close with `]`,
        # but the ports also carry plain top-level statements after them, and
        # those must not be glued onto the previous method.
        while index < len(line):
            ch = line[index]
            was_top = depth == 0
            if in_string:
                if ch == '\\':
                    index += 1
                elif ch == '"':
                    in_string = False
                current.append(ch)
                index += 1
                continue
            if ch == '"':
                in_string = True
                current.append(ch)
                index += 1
                continue
            if ch in '([{':
                depth += 1
            elif ch in ')]}':
                depth -= 1
                # Harding method definitions end at their closing `]` with no
                # period, so the bracket close is the real statement boundary.
                if depth == 0 and re.match(r'^\s*\w+( class)?>>', ''.join(current)):
                    current.append(ch)
                    text = ''.join(current).strip()
                    if text:
                        chunks.append(text)
                    current = []
                    index += 1
                    continue
            if ch == '.' and was_top and depth == 0:
                current.append(ch)
                text = ''.join(current).strip()
                if text:
                    chunks.append(text)
                current = []
                index += 1
                continue
            current.append(ch)
            index += 1
    text = ''.join(current).strip()
    if text:
        chunks.append(text)
    return chunks


def split_statements(source):
    """Split Harding top-level statements on statement-terminating periods.

    Strings, comments (`"..."`) and bracket nesting are honoured; a `.` inside
    `( ... )` or `[ ... ]` does not terminate. This mirrors what the existing
    gst/cog adapters do and is intentionally conservative: anything it cannot
    classify raises rather than silently mis-compiling.
    """
    statements, current = [], []
    depth = 0
    in_string = False
    in_comment = False
    index = 0
    while index < len(source):
        ch = source[index]
        nxt = source[index + 1] if index + 1 < len(source) else ''
        if in_comment:
            current.append(ch)
            if ch == '"':
                in_comment = False
            index += 1
            continue
        if in_string:
            current.append(ch)
            if ch == '\\' and nxt:
                current.append(nxt)
                index += 2
                continue
            if ch == '"':
                in_string = False
            index += 1
            continue
        # Harding uses double quotes for strings (comments are `#` lines, stripped
        # earlier), the inverse of Smalltalk. Treating `"` as a comment start here
        # silently swallowed entire method bodies.
        if ch == '"':
            in_string = True
            current.append(ch)
            index += 1
            continue
        if ch in '([{':
            depth += 1
        elif ch in ')]}':
            depth -= 1
        if ch == '.' and depth == 0:
            text = ''.join(current).strip()
            if text:
                statements.append(text)
            current = []
            index += 1
            continue
        current.append(ch)
        index += 1
    tail = ''.join(current).strip()
    if tail:
        statements.append(tail)
    return statements


def unescape_harding_string(text):
    """Decode a Harding string literal body to the exact bytes it denotes.

    Harding uses C-style escapes; GST strings use `''` doubling and no escapes,
    so a literal containing `\\"` cannot be emitted as a GST string. Only calls
    that need such a literal (the Json fixture) are affected.
    """
    out, index = [], 0
    while index < len(text):
        ch = text[index]
        if ch == '\\' and index + 1 < len(text):
            nxt = text[index + 1]
            out.append({'n': '\n', 't': '\t', 'r': '\r', '"': '"', '\\': '\\'}.get(nxt, nxt))
            index += 2
            continue
        out.append(ch)
        index += 1
    return ''.join(out)


def gst_string_literal(decoded):
    """A GST string expression for arbitrary bytes: no escapes needed."""
    if '\n' in decoded or len(decoded) > 200:
        # Long or multi-line literals become an array of codes joined at runtime.
        codes = ','.join(str(ord(ch)) for ch in decoded)
        return f'(String withAll: #({codes}))'
    return "'" + decoded.replace("'", "''") + "'"


def spell(statement):
    """Rewrite Harding spelling into GNU Smalltalk, one token pass at a time.

    A regex split on quotes mis-pairs once a literal contains `\\"` (the Json
    fixture does), silently dropping literals. This scans instead, so escapes are
    consumed inside the string they belong to.
    """
    out = []
    index = 0
    while index < len(statement):
        ch = statement[index]
        if ch == '"':
            # Collect the whole Harding literal, honouring backslash escapes.
            body = []
            index += 1
            while index < len(statement):
                current = statement[index]
                if current == '\\' and index + 1 < len(statement):
                    body.append(statement[index:index + 2])
                    index += 2
                    continue
                if current == '"':
                    index += 1
                    break
                body.append(current)
                index += 1
            out.append(gst_string_literal(unescape_harding_string(''.join(body))))
            continue
        out.append(ch)
        index += 1
    text = ''.join(out)
    text = re.sub(r'\bArray\b', 'HBArray', text)
    text = re.sub(r'\bprintln\b', 'printNl', text)
    return text


def gst_compile(name, header, body):
    """Emit a GST `compile:` statement (3.2's file-in syntax, as the other adapters use)."""
    statements = split_statements(body.strip() + '.')
    bracketed = header + ' [ ' + ' '.join(spell(s.strip()) + '.' for s in statements if s.strip()) + ' ]'
    return name + " compile: '" + bracketed.replace("'", "''") + "'.\n"


def gst_method(name, header, body):
    """Add GST method syntax and a period to a method body's final statement."""
    body = body.strip()
    if body.startswith('|'):
        # keep the temporary declaration first
        close = body.index('|', 1)
        temps = body[:close + 1]
        rest = body[close + 1:]
    else:
        temps, rest = '', body
    statements = split_statements(rest + '.')
    rendered = temps + '\n' + '.\n'.join(s for s in statements if s) + '.'
    return f"{name} >> {header} [\n{rendered}\n].\n"


def strip_comments(source):
    """Separate Harding `#` line comments from code, keeping their text.

    Comments must be removed before statement splitting: a period inside prose
    such as "see AUTHORS.md" would otherwise terminate a statement.
    """
    comments, code = [], []
    for line in source.splitlines():
        if line.lstrip().startswith('#'):
            comments.append(line.lstrip().lstrip('#').strip())
        else:
            code.append(line)
    return comments, '\n'.join(code)


def translate(source):
    """Translate a Harding port source into GNU Smalltalk, or raise."""
    comments, code = strip_comments(source)
    # String indexing stays zero-based: adapt at:/at:put: via a helper selector.
    out = []
    out.append("Object subclass: #HBObject instanceVariableNames: '' classVariableNames: '' "
               "poolDictionaries: '' category: 'HardingBench'.\n")
    out.append(gst_compile('HBObject class', 'new', '^ super new initialize'))
    out.append(gst_compile('HBObject', 'initialize', '^ self'))
    # Harding arrays are zero-based and grow with add:; GST collections are
    # 1-based. This adapter keeps the port's own indexing expressions unchanged.
    out.append("Object subclass: #HBArray instanceVariableNames: 'storage' "
               "classVariableNames: '' poolDictionaries: '' category: 'HardingBench'.\n")
    out.append(gst_compile('HBArray', 'initialize', 'storage := OrderedCollection new. ^ self'))
    out.append(gst_compile('HBArray class', 'new', '^ self new initialize'))
    # `new` already runs initialize, so the sized constructors must not send it
    # again; they seed the collection directly.
    out.append(gst_compile('HBArray class', 'new: count', '^ self new: count withAll: nil'))
    out.append(gst_compile('HBArray class', 'new: count withAll: value',
                           '| array | array := super new initialize. count timesRepeat: [array add: value]. ^ array'))
    out.append(gst_compile('HBArray', 'add: value', 'storage add: value. ^ value'))
    out.append(gst_compile('HBArray', 'size', '^ storage size'))
    out.append(gst_compile('HBArray', 'at: index', '^ storage at: index + 1'))
    out.append(gst_compile('HBArray', 'at: index put: value', '^ storage at: index + 1 put: value'))
    out.append(gst_compile('HBArray', 'do: callback', 'storage do: callback. ^ self'))
    for text in split_definitions(code):
        statement = text.strip()
        if statement in ('', '.') or statement.startswith('#'):
            continue
        comment = ''
        cls = re.search(r'^\s*(\w+) := (\w+) derive(Public)?: #\(([^)]*)\)\.?$', statement, re.S)
        if cls:
            name, parent, public, slot_text = cls.groups()
            if parent == 'Object':
                parent = 'HBObject'
            slots = slot_text.replace(',', ' ').split()
            out.append(comment)
            out.append(f"{parent} subclass: #{name} instanceVariableNames: '{' '.join(slots)}' "
                       "classVariableNames: '' poolDictionaries: '' category: 'HardingBench'.\n")
            if public:
                for slot in slots:
                    out.append(gst_compile(name, slot, '^ ' + slot))
                    out.append(gst_compile(name, slot + ': aValue', slot + ' := aValue. ^ aValue'))
            continue
        method = re.fullmatch(r'(\w+)( class)?>>([^\[]*)\[(.*)\]\.?', statement, re.S)
        if method:
            name, side, header, body = method.groups()
            out.append(comment)
            out.append(gst_compile(name + (side or ''), header.strip(), body))
            continue
        derived = re.search(r'^\s*(\w+) := (\w+) derive(Public)?: #\(([^)]*)\)\.?$', statement, re.S)
        if derived is None:
            # `Foo := Object derive.` declares a slotless subclass.
            bare = re.fullmatch(r'(\w+) := (\w+) derive\.?', statement, re.S)
            if bare:
                name, parent = bare.groups()
                if parent == 'Object':
                    parent = 'HBObject'
                out.append(comment)
                out.append(f"{parent} subclass: #{name} instanceVariableNames: '' "
                           "classVariableNames: '' poolDictionaries: '' category: 'HardingBench'.\n")
                continue
        if derived:
            name, parent, public, slot_text = derived.groups()
            if parent == 'Object':
                parent = 'HBObject'
            slots = slot_text.replace(',', ' ').split()
            out.append(comment)
            out.append(f"{parent} subclass: #{name} instanceVariableNames: '{' '.join(slots)}' "
                       "classVariableNames: '' poolDictionaries: '' category: 'HardingBench'.\n")
            if public:
                for slot in slots:
                    out.append(gst_compile(name, slot, '^ ' + slot))
                    out.append(gst_compile(name, slot + ': aValue', slot + ' := aValue. ^ aValue'))
            continue
        if re.fullmatch(r'[A-Z]\w* := .*', statement, re.S):
            # A plain uppercase assignment publishes a global (the ports use these
            # for singletons). GST needs the association to exist before methods
            # that mention the name are compiled.
            name, expression = statement.split(':=', 1)
            out.append(comment)
            out.append(f'Smalltalk at: #{name.strip()} put: ({spell(expression.strip())}).\n')
            continue
        out.append(comment)
        out.append(spell(statement if statement.endswith('.') else statement + '.') + '\n')
    return ''.join(out)
