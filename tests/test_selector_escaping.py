"""Execute selector escaping and Bounce with a private Granite compiler."""
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / 'build/selector-escaping'


class SelectorEscapingTest(unittest.TestCase):
    @staticmethod
    def build(label, command):
        run = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=240)
        (WORK / (label + '.log')).write_text(run.stdout + run.stderr)
        if run.returncode:
            raise AssertionError(f'{label}: {run.stdout}{run.stderr}')

    @classmethod
    def setUpClass(cls):
        WORK.mkdir(parents=True, exist_ok=True)
        cls.build('compiler', ['nim', 'c', '-p:external',
            '--nimcache:' + str(WORK / 'compiler-cache'),
            '-o:' + str(WORK / 'granite'), 'src/harding/compiler/granite.nim'])

    def test_emission(self):
        # Quotes are not lexical selectors: use synthetic ASTs for robustness.
        probe = WORK / 'selector_probe.nim'
        probe.write_text(r'''
import std/strutils
import ../../src/harding/core/types
import ../../src/harding/codegen/expression
let receiver = LiteralNode(value: NodeValue(kind: vkInt, intVal: 7))
let argument = LiteralNode(value: NodeValue(kind: vkInt, intVal: 3))
for selector in ["\\", "quote\"slash\\", "line\nreturn\rtab\t", "ordinary:"]:
  let quoted = "\"" & escapeNimString(selector) & "\""
  for mixed in [false, true]:
    for inMethod in [false, true]:
      let ctx = newGenContext(mixed = mixed)
      ctx.inMethod = inMethod
      let message = MessageNode(receiver: receiver, selector: selector, arguments: @[Node(argument)])
      if selector != "\\" or inMethod:
        doAssert quoted in genExpression(ctx, message)
      let cascade = CascadeNode(receiver: receiver, messages: @[Node(message)])
      doAssert quoted in genExpression(ctx, cascade)
      doAssert quoted in genStatement(ctx, cascade)
      let superSend = SuperSendNode(selector: selector, arguments: @[Node(argument)])
      doAssert quoted in genExpression(ctx, superSend)
      let primitive = PrimitiveCallNode(selector: selector, arguments: @[Node(argument)])
      doAssert quoted in genExpression(ctx, primitive)
      doAssert quoted in genStatement(ctx, primitive)
echo "selector emission passed"
''')
        self.build('probe', ['nim', 'c', '-r', '--nimcache:' + str(WORK / 'probe-cache'),
                            '-o:' + str(WORK / 'selector_probe'), str(probe)])

    def test_native_arc_orc(self):
        methods = WORK / 'modulo_methods.hrd'
        methods.write_text(r'''
ModuloProbe := Object derive: #().
ModuloProbe>>remainder: number [ ^ number \\ 3 ].
(ModuloProbe new remainder: 7) println.
(7 \\ 3) println.
(7 // 3) println.
''')
        cases = [('modulo_methods', methods, '1\n1\n2\n'),
                 ('modulo_repro', ROOT / 'benchmark/awfy/bounce/modulo_repro.hrd', '1\n'),
                 ('bounce', ROOT / 'benchmark/awfy/bounce/bounce.hrd', '1331\n')]
        for name, source, expected in cases:
            directory = WORK / name
            directory.mkdir(exist_ok=True)
            self.build(name + '-generate', [str(WORK / 'granite'), 'compile',
                str(source), '--dir:' + str(directory), '-o:' + name])
            for mm in ('arc', 'orc'):
                with self.subTest(case=name, mm=mm):
                    binary = directory / (name + '-' + mm)
                    self.build(name + '-' + mm, ['nim', 'c', '--mm:' + mm,
                        '--nimcache:' + str(directory / ('cache-' + mm)),
                        '-o:' + str(binary), str(directory / (name + '.nim'))])
                    run = subprocess.run([str(binary)], cwd=ROOT, capture_output=True,
                                         text=True, timeout=30)
                    self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
                    self.assertEqual(run.stderr, '')
                    self.assertEqual(run.stdout, expected)


if __name__ == '__main__':
    unittest.main()
