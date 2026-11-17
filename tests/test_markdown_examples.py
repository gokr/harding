"""Tests for Markdown fence discovery and execution policy."""
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('markdown_examples', ROOT / 'scripts/test_markdown_examples.py')
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)


class MarkdownExamplesTest(unittest.TestCase):
    def setUp(self):
        (ROOT / 'build').mkdir(exist_ok=True)
        self.tmp = tempfile.TemporaryDirectory(dir=ROOT / 'build')
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / 'sample.md'

    def test_fences_and_line_numbers(self):
        self.path.write_text('text\n```harding test=one stdout="ok\\n"\n1 println\n```\n~~~smalltalk\nfragment\n~~~\n')
        found = list(module.fences(self.path))
        self.assertEqual([f.line for f in found], [2, 5])
        self.assertEqual(found[0].body, '1 println\n')
        self.assertEqual(module.json.loads(module.HEADER.fullmatch(found[0].info).group(3)), 'ok\n')
        self.assertIsNone(module.HEADER.fullmatch(found[1].info))

    def test_unclosed_fence_rejected(self):
        self.path.write_text('```harding\n1\n')
        with self.assertRaisesRegex(ValueError, 'unclosed'):
            list(module.fences(self.path))

    def test_runner_checks_both_outputs(self):
        fence = module.Fence(self.path, 1, '', '1 println\n')
        with patch.object(module, 'command', side_effect=[('1\n', ''), ('', ''), ('wrong\n', '')]):
            with self.assertRaisesRegex(RuntimeError, 'Granite stdout'):
                module.run_case(fence, 'test', '1\n', Path('/harding'), Path('/granite'), 1)

    def test_interpreter_failure_stops_build(self):
        fence = module.Fence(self.path, 1, '', '')
        with patch.object(module, 'command', return_value=('wrong', '')) as command:
            with self.assertRaisesRegex(RuntimeError, 'interpreter stdout'):
                module.run_case(fence, 'test', 'right', Path('/harding'), Path('/granite'), 1)
            self.assertEqual(command.call_count, 1)


if __name__ == '__main__':
    unittest.main()
