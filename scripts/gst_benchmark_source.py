"""GNU Smalltalk spelling adapter for checked Harding benchmark definitions.

Uses the same zero-based OrderedCollection adapter as the Cog comparison;
retains arithmetic helpers, worklist order, graph teardown and source notices.
"""
import re
from cog_benchmark_source import ARRAY_ADAPTER, spelling, statements
from bench_compare import SQUEAK_OBJECTS


def compile_method(owner, code):
    # GNU Smalltalk 3.x compile: expects bracketed method syntax.
    if '\n' in code:
        header, body = code.split('\n', 1)
    else:
        # Array/Queens definitions have one-line methods; scan the selector and
        # its argument names, without consuming the first method-body token.
        tokens = code.split()
        end = 1
        if tokens[0].endswith(':'):
            end = 0
            while end < len(tokens) and tokens[end].endswith(':'): end += 2
        header, body = ' '.join(tokens[:end]), ' '.join(tokens[end:])
    body = body.replace('storage removeAt:', 'storage removeAtIndex:')
    bracketed = header + ' [ ' + body + ' ]'
    return owner + " compile: '" + bracketed.replace("'", "''") + "'.\n"


def adapt_smalltalk(statement):
    method = re.fullmatch(r"(\w+(?: class)?) compile: '((?:[^']|'')*)'", statement, re.S)
    if method:
        return compile_method(method[1], method[2].replace("''", "'"))
    return statement + '.\n'


def definitions(case, source):
    if case == 'queens':
        parts = statements(SQUEAK_OBJECTS, smalltalk=True)
        return ''.join(adapt_smalltalk(s) for s in parts if s.startswith(('Object subclass: #HBQueen', 'HBQueen')))
    # GST Object>>new does not send initialize, unlike Harding/Cog. Limit the
    # bootstrap to benchmark-owned classes; do not alter Object globally.
    output = "Object subclass: #HBObject instanceVariableNames: '' classVariableNames: '' poolDictionaries: '' category: 'HardingBench'.\n"
    output += compile_method('HBObject', 'initialize\n^self')
    output += compile_method('HBObject class', 'new\n^super new initialize')
    output += ''.join(adapt_smalltalk(s.replace('Object subclass: #HBArray', 'HBObject subclass: #HBArray'))
                      for s in statements(ARRAY_ADAPTER, smalltalk=True))
    # Install associations before compiling methods that reference strengths.
    # Otherwise GST can bind an undeclared uppercase name as a do-it temporary.
    for name in re.findall(r'^([A-Z]\w*) :=', source, re.M):
        if re.search(r'^' + name + r' := \w+ derive', source, re.M) is None:
            output += f'Smalltalk at: #{name} put: nil.\n'
    declarations = 0
    for statement in statements(source):
        if statement.startswith('repetitions :='): break
        cls = re.fullmatch(r'(\w+) := (\w+) derive(Public)?: #\(([^)]*)\)', statement)
        if cls:
            name, parent, public, slot_text = cls.groups()
            if parent == 'Object': parent = 'HBObject'
            slots = slot_text.replace(',', ' ').split()
            output += f"{parent} subclass: #{name} instanceVariableNames: '{' '.join(slots)}' classVariableNames: '' poolDictionaries: '' category: 'HardingBench'.\n"
            if public:
                for slot in slots:
                    output += compile_method(name, f'{slot}\n^{slot}')
                    output += compile_method(name, f'{slot}: aValue\n{slot} := aValue')
        else:
            method = re.fullmatch(r'(\w+)( class)?>>([^\[]+)\[(.*)\]', statement, re.S)
            if method:
                name, side, header, body = method.groups()
                output += compile_method(name + (side or ''), spelling(header.strip() + '\n' + body))
            elif re.match(r'[A-Z]\w* :=', statement):
                name, expression = statement.split(':=', 1)
                output += f'Smalltalk at: #{name.strip()} put: ({spelling(expression)}).\n'
            else: raise ValueError('Unsupported GNU Smalltalk declaration: ' + statement[:90])
        declarations += 1
    if declarations < 30: raise ValueError('incomplete definitions')
    return output


def driver(case, count, source):
    if count < 0: raise ValueError('negative repetitions')
    notices = '\n'.join('"' + line.replace('"', "'") + '"' for line in source.splitlines() if line.startswith('#'))
    solver = {'queens': 'HBQueens', 'richards': 'Richards', 'deltablue': 'DeltaBlue'}[case]
    verify = {
        'queens': "answer = 92 ifFalse: [self error: 'Wrong Queens result'].",
        'richards': "answer verify. (answer queueCount = 2322 and: [answer holdCount = 928]) ifFalse: [self error: 'Wrong Richards counters'].",
        'deltablue': "(answer - 223305) abs < 0.000001 ifFalse: [self error: 'Wrong DeltaBlue projection']."
    }[case]
    return '| solver answer done |\n' + notices + '\n' + definitions(case, source) + f'''
solver := {solver} new. done := 0.
{count} timesRepeat: [answer := solver benchmark. {verify} done := done + 1].
done printNl.
'''
