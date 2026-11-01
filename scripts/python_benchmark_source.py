"""Restricted source-to-source adapter for the three checked Harding benchmarks.

Emits ordinary Python classes/methods and Python control flow, not a VM or a
message-send interpreter. Unsupported syntax/selectors fail. Generated sources
retain the original notices and must pass workload verification before timing.
"""
import ast
import re

TOKEN = re.compile(r'\s+|"(?:[^"\\]|\\.)*"|:=|>>|<=|>=|<>|==|//|[A-Za-z_]\w*:?|\d+(?:\.\d+)?|[^\s]')


class Parser:
    def __init__(self, source):
        self.tokens = [t for t in TOKEN.findall(source) if not t.isspace()]
        self.pos = 0

    def peek(self):
        return self.tokens[self.pos] if self.pos < len(self.tokens) else ''

    def pop(self, expected=None):
        token = self.peek()
        if not token:
            raise ValueError('unexpected end of source')
        if expected is not None and token != expected:
            raise ValueError(f'expected {expected!r}, got {token!r} at {self.pos}')
        self.pos += 1
        return token

    def body(self, end=''):
        temps, body = [], []
        if self.peek() == '|':
            self.pop()
            while self.peek() != '|': temps.append(self.pop())
            self.pop('|')
        while self.peek() != end:
            if not self.peek(): raise ValueError('unclosed body')
            if self.peek() == '^':
                self.pop(); body.append(('return', self.expr()))
            elif self.pos + 1 < len(self.tokens) and self.tokens[self.pos + 1] == ':=':
                name = self.pop(); self.pop(':='); body.append(('assign', name, self.expr()))
            else: body.append(('expr', self.expr()))
            if self.peek() == '.': self.pop()
            elif self.peek() != end: raise ValueError('missing statement separator: ' + self.peek())
        return temps, body

    def atom(self):
        token = self.pop()
        if token == '(':
            expr = self.expr(); self.pop(')'); return expr
        if token == '[':
            params = []
            while self.peek() == ':': self.pop(); params.append(self.pop())
            if params: self.pop('|')
            temps, body = self.body(']'); self.pop(']')
            return ('block', params, temps, body)
        if token == '-': return ('send', ('literal', 0), '-', [self.atom()])
        if token.startswith('"'): return ('literal', ast.literal_eval(token))
        if re.fullmatch(r'\d+(\.\d+)?', token): return ('literal', ast.literal_eval(token))
        if re.fullmatch(r'[A-Za-z_]\w*', token): return ('name', token)
        raise ValueError('unsupported atom ' + token)

    def unary(self):
        expr = self.atom()
        while re.fullmatch(r'[A-Za-z_]\w*', self.peek()):
            selector = self.pop(); expr = ('send', expr, selector, [])
        return expr

    def binary(self):
        expr = self.unary()
        while self.peek() in ['+', '-', '*', '/', '//', '<', '>', '<=', '>=', '=', '==', '<>', '|', '&']:
            op = self.pop(); expr = ('send', expr, op, [self.unary()])
        return expr

    def expr(self):
        expr = self.binary()
        if re.fullmatch(r'[A-Za-z_]\w*:', self.peek()):
            selector, args = '', []
            while re.fullmatch(r'[A-Za-z_]\w*:', self.peek()):
                selector += self.pop(); args.append(self.binary())
            expr = ('send', expr, selector, args)
        return expr


def selector_name(selector):
    return selector.replace(':', '_')


class Generator:
    def __init__(self, slots, locals_):
        self.slots, self.locals = slots, set(locals_)
        self.lines = []
        self.depth = 1
        self.counter = 0

    def emit(self, line):
        self.lines.append('    ' * self.depth + line)

    def name(self, name):
        if name in self.locals: return 'local_' + name
        if name == 'self': return 'self'
        if name == 'super': return 'super()'
        if name in ['nil', 'true', 'false']: return {'nil': 'None', 'true': 'True', 'false': 'False'}[name]
        if name in self.slots: return 'self._slot_' + name
        return name

    def block(self, node):
        if node[0] != 'block': raise ValueError('literal block required')
        params, temps, body = node[1:]
        # Benchmark blocks do not escape and their explicit locals do not
        # shadow enclosing variables; emit ordinary Python control flow.
        saved = self.locals.copy()
        self.locals.update(params + temps)
        for name in temps: self.emit(self.name(name) + ' = None')
        if not body: self.emit('pass')
        for statement in body: self.statement(statement)
        self.locals = saved

    def expr(self, node):
        tag = node[0]
        if tag == 'literal': return repr(node[1])
        if tag == 'name': return self.name(node[1])
        if tag != 'send': raise ValueError('block used as a value')
        receiver, selector, args = node[1:]
        if selector in ['ifTrue:', 'ifFalse:', 'ifTrue:ifFalse:', 'whileTrue:', 'ensure:', 'timesRepeat:', 'do:']:
            # These benchmark sends occur as statements, not value expressions.
            raise ValueError('statement control flow in value position: ' + selector)
        if selector in ['and:', 'or:']:
            if args[0][0] != 'block' or len(args[0][3]) != 1 or args[0][3][0][0] != 'expr':
                raise ValueError('short circuit requires one expression')
            return '(' + self.expr(receiver) + (' and ' if selector == 'and:' else ' or ') + self.expr(args[0][3][0][1]) + ')'
        recv = self.expr(receiver)
        vals = [self.expr(a) for a in args]
        if selector in ['+', '-', '*', '/', '//', '<', '>', '<=', '>=', '=', '==', '<>', '|', '&']:
            op = {'=': '==', '==': 'is', '<>': '!=', '|': '|', '&': '+'}.get(selector, selector)
            # Harding & is string concatenation; both operands are strings here.
            return f'({recv} {op} {vals[0]})'
        if selector == 'new':
            if recv == 'Array': return '[]'
            return recv + '()'
        if recv == 'Array' and selector == 'new:withAll:': return f'([{vals[1]}] * {vals[0]})'
        if selector == 'isNil': return f'({recv} is None)'
        if selector == 'notNil': return f'({recv} is not None)'
        if selector == 'not': return f'(not {recv})'
        if selector == 'abs': return f'abs({recv})'
        if selector == 'printString': return f'str({recv})'
        if selector == 'size': return f'len({recv})' if recv not in ['self'] else f'{recv}.size()'
        if selector == 'at:': return f'{recv}[{vals[0]}]'
        if selector == 'at:put:': return f'_put({recv}, {vals[0]}, {vals[1]})'
        if selector == 'add:': return f'{recv}.append({vals[0]})'
        if selector == 'removeAt:': return f'{recv}.pop({vals[0]})'
        if recv == 'Error' and selector == 'signal:': return f'_error({vals[0]})'
        return f'{recv}.{selector_name(selector)}({", ".join(vals)})'

    def statement(self, node):
        tag = node[0]
        if tag == 'assign': self.emit(self.name(node[1]) + ' = ' + self.expr(node[2])); return
        if tag == 'return': self.emit('return ' + self.expr(node[1])); return
        expr = node[1]
        if expr[0] == 'send':
            receiver, selector, args = expr[1:]
            if selector in ['ifTrue:', 'ifFalse:', 'ifTrue:ifFalse:']:
                cond = self.expr(receiver)
                self.emit('if ' + ('not ' if selector == 'ifFalse:' else '') + cond + ':')
                self.depth += 1; self.block(args[0]); self.depth -= 1
                if len(args) == 2:
                    self.emit('else:'); self.depth += 1; self.block(args[1]); self.depth -= 1
                return
            if selector == 'whileTrue:':
                if receiver[0] != 'block': raise ValueError('while requires block')
                # Multi-statement conditions are evaluated every iteration.
                self.emit('while True:'); self.depth += 1
                body = receiver[3]
                for stmt in body[:-1]: self.statement(stmt)
                if body[-1][0] != 'expr': raise ValueError('condition must end in expression')
                self.emit('if not (' + self.expr(body[-1][1]) + '): break')
                self.block(args[0]); self.depth -= 1; return
            if selector == 'ensure:':
                self.emit('try:'); self.depth += 1; self.block(receiver); self.depth -= 1
                self.emit('finally:'); self.depth += 1; self.block(args[0]); self.depth -= 1; return
            if selector == 'timesRepeat:':
                self.counter += 1
                self.emit(f'for _repeat{self.counter} in range({self.expr(receiver)}):')
                self.depth += 1; self.block(args[0]); self.depth -= 1; return
            if selector == 'do:':
                block = args[0]
                if block[0] != 'block' or len(block[1]) != 1: raise ValueError('do: arity')
                saved = self.locals.copy(); self.locals.update(block[1])
                self.emit(f'for {self.name(block[1][0])} in {self.expr(receiver)}:')
                self.depth += 1; self.block(block); self.depth -= 1; self.locals = saved; return
        self.emit(self.expr(expr))


def definitions(source):
    # Unlike the Smalltalk adapter, preserve Python strings with the tokenizer.
    source = re.sub(r'^\s*#.*$', '', source, flags=re.M)
    source = re.sub(r'^\s*\|[^|]*\|', '', source)
    tokens = Parser(source)
    classes, methods, globals_ = {}, {}, []
    while tokens.peek():
        if tokens.peek() == 'repetitions' or tokens.peek() == 'solver': break
        name = tokens.pop()
        if tokens.peek() in ['class', '>>']:
            side = tokens.peek() == 'class'
            if side: tokens.pop()
            tokens.pop('>>')
            header, params = '', []
            if tokens.peek().endswith(':'):
                while tokens.peek().endswith(':'): header += tokens.pop(); params.append(tokens.pop())
            else: header = tokens.pop()
            tokens.pop('['); temps, body = tokens.body(']'); tokens.pop(']')
            methods.setdefault(name, []).append((header, params, temps, body, side))
        else:
            tokens.pop(':=')
            if tokens.pos + 1 < len(tokens.tokens) and tokens.tokens[tokens.pos + 1] in ['derive:', 'derivePublic:']:
                parent, derive = tokens.pop(), tokens.pop(); tokens.pop('#'); tokens.pop('(')
                slots = []
                while tokens.peek() != ')':
                    if tokens.peek() == ',': tokens.pop()
                    else: slots.append(tokens.pop())
                tokens.pop(')')
                classes[name] = (parent, slots, derive == 'derivePublic:')
            else:
                expr = tokens.expr(); globals_.append((name, expr))
        if tokens.peek() == '.': tokens.pop()
    output = ['# Generated restricted Python port; same algorithm and workload as Harding.',
              'def _put(array, index, value):', '    array[index] = value', '    return value',
              'def _error(message):', '    raise RuntimeError(message)', '']
    all_slots = {}
    for name, (parent, slots, public) in classes.items():
        inherited = all_slots.get(parent, [])
        all_slots[name] = inherited + slots
        output += [f'class {name}({parent if parent != "Object" else "object"}):', '    def __init__(self):']
        for slot in all_slots[name]: output.append(f'        self._slot_{slot} = None')
        output.append('        self.initialize()')
        # Prefix storage names so fields and explicit methods cannot collide.
        # Public slot sends use ordinary accessor calls, as in the Cog port.
        output += ['    def initialize(self):', '        pass'] if parent == 'Object' else []
        for header, params, temps, body, side in methods.get(name, []):
            if side: output.append('    @classmethod')
            output.append(f'    def {selector_name(header)}(self' + ''.join(', local_' + p for p in params) + '):')
            g = Generator(all_slots[name], params + temps); g.depth = 2
            for temp in temps: g.emit(g.name(temp) + ' = None')
            for stmt in body: g.statement(stmt)
            g.emit('return self')
            output += g.lines
        if public:
            for slot in slots:
                output += [f'    def get_{slot}(self):', f'        return self._slot_{slot}',
                           f'    def {slot}_(self, value):', f'        self._slot_{slot} = value', '        return value']
        if name == 'DBCollection':
            output += ['    def __len__(self):', '        return self.size()',
                       '    def __getitem__(self, index):', '        return self.at_(index)',
                       '    def append(self, value):', '        return self.add_(value)']
        output.append('')
    for name, expr in globals_:
        output.append(name + ' = ' + Generator([], []).expr(expr))
    text = '\n'.join(output) + '\n'
    # Public slot reads become get_slot(), avoiding field/method collisions.
    getters = {slot for _, slots, public in classes.values() if public for slot in slots}
    for slot in getters:
        text = re.sub(r'\.' + slot + r'\(\)', '.get_' + slot + '()', text)
    return text


def driver(case, count, source):
    if count < 0: raise ValueError('negative repetitions')
    notices = '\n'.join('# ' + line for line in source.splitlines() if line.startswith('#'))
    code = notices + '\n' + definitions(source)
    if case == 'richards':
        body = '''answer = Richards().benchmark()
    assert (answer.get_queueCount(), answer.get_holdCount()) == (2322, 928)
    queued += answer.get_queueCount()
    held += answer.get_holdCount()'''
        code += 'queued = held = 0\n'
    elif case == 'deltablue': body = 'answer = DeltaBlue().benchmark()\n    assert abs(answer - 223305) < 0.000001'
    elif case == 'queens': body = 'answer = Queens().benchmark()\n    assert answer == 92'
    else: raise ValueError(case)
    code += f'for _pass in range({count}):\n    ' + body + '\n'
    code += f'print({count})\n'
    return code
