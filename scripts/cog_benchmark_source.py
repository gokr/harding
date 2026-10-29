"""Mechanical Smalltalk spelling adapter for the two checked Harding benchmarks.

Generated source retains each benchmark's license notice.
This is intentionally not a general Harding compiler. Unsupported declarations
fail; each generated method is compiled by Squeak, then benchmark verification
checks results. Keep arithmetic bit helpers, worklists and cleanup unchanged.
"""
import re


def statements(source, smalltalk=False):
    # Preserve code structure while converting comments and string literals.
    output = []
    index = 0
    while index < len(source):
        character = source[index]
        if not smalltalk and character == '#' and not source.startswith('#(', index):
            index = source.find('\n', index)
            if index < 0:
                break
        elif not smalltalk and character == '"':
            index += 1
            value = ''
            while index < len(source) and source[index] != '"':
                if source[index] == '\\':
                    raise ValueError('Escaped strings are not supported by this benchmark adapter')
                value += source[index]
                index += 1
            if index == len(source):
                raise ValueError('Unclosed string')
            output.append("'" + value.replace("'", "''") + "'")
            index += 1
        else:
            output.append(character)
            index += 1
    text = ''.join(output).strip()
    # The benchmark driver lives outside the definitions; remove its script temps.
    text = re.sub(r'^\|[^|]*\|', '', text).strip()
    result = []
    start = depth = 0
    quoted = False
    index = 0
    while index < len(text):
        character = text[index]
        if character == "'":
            if quoted and index + 1 < len(text) and text[index + 1] == "'":
                index += 2
                continue
            quoted = not quoted
        if not quoted:
            if character in '[(':
                depth += 1
            elif character in '])':
                depth -= 1
            elif character == '.' and depth == 0:
                result.append(text[start:index].strip())
                start = index + 1
        index += 1
    if text[start:].strip():
        result.append(text[start:].strip())
    return result


ARRAY_ADAPTER = '''
Object subclass: #HBArray instanceVariableNames: 'storage' classVariableNames: '' poolDictionaries: '' category: 'HardingBench'.
HBArray compile: 'initialize storage := OrderedCollection new. ^self'.
HBArray class compile: 'new: count ^self new: count withAll: nil'.
HBArray class compile: 'new: count withAll: value | array | array := self new. count timesRepeat: [array add: value]. ^array'.
HBArray compile: 'add: value storage add: value'.
HBArray compile: 'size ^storage size'.
HBArray compile: 'at: index ^storage at: index + 1'.
HBArray compile: 'at: index put: value ^storage at: index + 1 put: value'.
HBArray compile: 'removeAt: index ^storage removeAt: index + 1'.
HBArray compile: 'do: callback storage do: callback'.
'''


def spelling(text):
    # Commas only occur as literal array separators in these two sources.
    text = re.sub(r'#\(([^()]*)\)', lambda m: '#(' + m[1].replace(',', ' ') + ')', text)
    # Outside quoted strings: <> is Smalltalk ~=; string append & is comma.
    parts = re.split(r"('(?:[^']|'')*')", text)
    return ''.join(part if index % 2 else part.replace('<>', '~=').replace('&', ',').replace('Array new', 'HBArray new')
                   for index, part in enumerate(parts))


def evaluate(code):
    return "Compiler evaluate: '" + code.replace("'", "''") + "'.\n"


def definitions(source):
    result = "Utilities authorInitials: 'HB'.\n"
    for statement in statements(ARRAY_ADAPTER, smalltalk=True):
        result += evaluate(statement)
    count = 0
    for statement in statements(source):
        if statement.startswith('repetitions :='):
            break
        cls = re.fullmatch(r'(\w+) := (\w+) derive(Public)?: #\(([^)]*)\)', statement)
        if cls:
            name, parent, public, slots = cls.groups()
            names = slots.replace(',', ' ').split()
            result += evaluate(f"{parent} subclass: #{name} instanceVariableNames: '{' '.join(names)}' classVariableNames: '' poolDictionaries: '' category: 'HardingBench'")
            if public:
                for slot in names:
                    result += evaluate(f"{name} compile: '{slot} ^{slot}'")
                    result += evaluate(f"{name} compile: '{slot}: aValue {slot} := aValue'")
        else:
            method = re.fullmatch(r'(\w+)( class)?>>([^\[]+)\[(.*)\]', statement, re.S)
            if method:
                name, side, header, body = method.groups()
                code = spelling(header.strip() + '\n' + body)
                result += evaluate(f"{name}{side or ''} compile: '" + code.replace("'", "''") + "'")
            else:
                global_assignment = re.match(r'([A-Z]\w*) :=', statement)
                if not global_assignment:
                    raise ValueError('Unsupported benchmark declaration: ' + statement[:100])
                name = global_assignment[1]
                result += f"Smalltalk at: #{name} put: nil.\n"
                result += evaluate(spelling(statement))
        count += 1
    if count < 30:
        raise ValueError('Incomplete benchmark declarations')
    return result


def driver(case, count, output, source):
    notice = ('GPL-2.0-or-later; Copyright 2008 the V8 project authors; Copyright 1996 John Maloney and Mario Wolczko. See DELTABLUE.txt and GPL-2.0.txt.'
              if case == 'deltablue' else 'BSD-3-Clause; Copyright 2006-2008 the V8 project authors. See RICHARDS.txt.')
    setup = '"Mechanically adapted benchmark. ' + notice + '"\n' + definitions(source)
    if case == 'richards':
        body = '''answer := solver benchmark.
answer verify.
(answer queueCount = 2322 and: [answer holdCount = 928]) ifFalse: [self error: 'Wrong Richards counters'].'''
    elif case == 'deltablue':
        body = '''answer := solver benchmark.
(answer - 223305) abs < 0.000001 ifFalse: [self error: 'Wrong DeltaBlue projection'].'''
    else:
        raise ValueError('Unsupported benchmark')
    solver = 'Richards' if case == 'richards' else 'DeltaBlue'
    code = f'''| solver answer done stream |
solver := {solver} new. done := 0.
{count} timesRepeat: [
{body}
done := done + 1].
stream := FileStream forceNewFileNamed: '{str(output).replace("'", "''")}'.
stream nextPutAll: done printString; close.
Smalltalk snapshot: false andQuit: true.'''
    return setup + evaluate(code)
