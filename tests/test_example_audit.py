"""Regression checks for the example manifest runner (no engine builds needed)."""
import argparse
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
spec = importlib.util.spec_from_file_location("example_audit", ROOT / "scripts/audit_examples.py")
assert spec is not None and spec.loader is not None
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class ExampleAuditTests(unittest.TestCase):
    def setUp(self):
        (ROOT / "build").mkdir(exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(prefix="example-audit-test-", dir=ROOT / "build")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.directory = self.root / "artifacts"
        self.directory.mkdir()
        self.expected = self.root / "expected.stdout"
        self.expected.write_bytes(b"correct\n")
        self.case: dict[str, Any] = {"id": "sample", "path": "examples/sample.hrd", "stdout": "expected.stdout"}
        self.options = argparse.Namespace(timeout=1, build_timeout=1, interpreter_only=False)

    def execute(self, responses):
        def fake_run(command, timeout, log):
            code, stdout, stderr = responses.pop(0)
            log.write_bytes(stdout)
            log.with_suffix(".stderr").write_bytes(stderr)
            return {"exit": code, "stdout": str(log.relative_to(self.root)),
                    "stderr": str(log.with_suffix(".stderr").relative_to(self.root))}
        with patch.object(audit, "ROOT", self.root), patch.object(audit, "run", fake_run):
            return audit.execute(self.case, self.directory, self.root / "syntax", self.options)["status"]

    def test_success_requires_golden_output_and_both_engines(self):
        self.assertEqual(self.execute([(0, b"", b""), (0, b"correct\n", b""),
                                       (0, b"", b""), (0, b"correct\n", b"")]), "parity-pass")

    def test_matching_interpreter_failure_never_passes(self):
        self.assertEqual(self.execute([(0, b"", b""), (1, b"bad\n", b"")]), "interpreter-failure")

    def test_matching_changed_output_is_a_regression(self):
        self.assertEqual(self.execute([(0, b"", b""), (0, b"wrong\n", b"")]), "stdout-regression")

    def test_new_stderr_is_a_regression(self):
        self.assertEqual(self.execute([(0, b"", b""), (0, b"correct\n", b"warning\n")]), "stderr-regression")

    def test_known_failure_requires_stage_and_message(self):
        self.case["known_failure"] = {"stage": "native", "contains": "missing primitive"}
        prefix = [(0, b"", b""), (0, b"correct\n", b""), (0, b"", b"")]
        self.assertEqual(self.execute(prefix + [(1, b"", b"missing primitive")]), "known-compiler-failure")
        self.assertEqual(self.execute(prefix + [(1, b"", b"different bug")]), "native-failure")
        self.assertEqual(self.execute(prefix[:2] + [(1, b"missing primitive", b"")]), "build-failure")

    def test_timeout_is_not_a_known_failure(self):
        self.case["known_failure"] = {"stage": "native", "contains": "missing primitive"}
        responses = [(0, b"", b""), (0, b"correct\n", b""), (0, b"", b""),
                     ("timeout", b"missing primitive", b"")]
        self.assertEqual(self.execute(responses), "native-failure")

    def test_unexpected_success_requires_removing_the_known_gap(self):
        self.case["known_failure"] = {"stage": "native", "contains": "missing primitive"}
        self.assertEqual(self.execute([(0, b"", b""), (0, b"correct\n", b""),
                                       (0, b"", b""), (0, b"correct\n", b"")]), "unexpected-pass")

    def test_gate_does_not_hide_invalid_syntax(self):
        self.case["gate"] = "requires server"
        self.assertEqual(self.execute([(1, b"parse error", b"")]), "syntax-failure")
        self.assertEqual(self.execute([(0, b"", b"")]), "gated")

    def test_inventory_rejects_unlisted_sources(self):
        (self.root / "examples").mkdir()
        (self.root / "examples/sample.hrd").write_text('"hello" println')
        (self.root / "examples/manifest.json").write_text(json.dumps({"cases": []}))
        with self.assertRaisesRegex(ValueError, "unlisted"):
            audit.load_cases(self.root)

    def test_website_fences_are_extracted_without_copies(self):
        page = self.root / "website/content/docs.md"
        page.parent.mkdir(parents=True)
        page.write_text('### Demo\n```harding\n"hello" println\n```\n')
        self.assertEqual(audit.snippets(self.root)[("website/content/docs.md", "Demo")],
                         '"hello" println\n')
        page.write_text('### Demo\n```harding\n42 println\n```\n')
        self.assertEqual(audit.snippets(self.root)[("website/content/docs.md", "Demo")], '42 println\n')

    def test_snippet_execution_uses_extracted_source(self):
        page = self.root / "website/content/docs.md"
        page.parent.mkdir(parents=True)
        page.write_text('### Demo\n```harding\n42 println\n```\n')
        self.case.update(path="website/content/docs.md", snippet="Demo", gate="host context")
        self.assertEqual(self.execute([(0, b"", b"")]), "gated")
        self.assertEqual((self.directory / "snippet.hrd").read_text(), '42 println\n')

    def test_unlisted_website_fence_fails_coverage(self):
        (self.root / "examples").mkdir()
        (self.root / "examples/manifest.json").write_text(json.dumps({"cases": []}))
        page = self.root / "website/content/docs.md"
        page.parent.mkdir(parents=True)
        page.write_text('### Demo\n```harding\n42\n```\n')
        with self.assertRaisesRegex(ValueError, "Website snippet coverage"):
            audit.load_cases(self.root)

    def test_unclosed_and_duplicate_website_fences_fail(self):
        page = self.root / "website/content/docs.md"
        page.parent.mkdir(parents=True)
        page.write_text('### Demo\n```harding\n42\n')
        with self.assertRaisesRegex(ValueError, "Unclosed"):
            audit.snippets(self.root)
        page.write_text('### Demo\n```harding\n42\n```\n```harding\n43\n```\n')
        found = audit.snippets(self.root)
        self.assertEqual(found[("website/content/docs.md", "Demo")], '42\n')
        self.assertEqual(found[("website/content/docs.md", "Demo [2]")], '43\n')
        page.write_text('### Demo\n```harding\n42\n```\n```harding\n43\n```\n### Demo [2]\n```harding\n44\n```\n')
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            audit.snippets(self.root)

    def test_case_id_cannot_create_nested_or_parent_artifact_paths(self):
        (self.root / "examples").mkdir()
        source = self.root / "examples/sample.hrd"
        source.write_text('42 println')
        for unsafe in ["../escape", "nested/path", "", "a b"]:
            case = dict(self.case, id=unsafe, gate="test")
            (self.root / "examples/manifest.json").write_text(json.dumps({"cases": [case]}))
            with self.assertRaisesRegex(ValueError, "Unsafe example case id"):
                audit.load_cases(self.root)

    def test_process_timeout_is_reported(self):
        log = ROOT / "build" / Path(self.temporary.name).name / "timeout.log"
        result = audit.run([sys.executable, "-c", "import time; time.sleep(10)"], 0.1, log)
        self.assertEqual(result["exit"], "timeout")

    def test_process_stdout_and_stderr_are_separate(self):
        log = ROOT / "build" / Path(self.temporary.name).name / "process.log"
        result = audit.run([sys.executable, "-c", "import sys; print('out'); print('err', file=sys.stderr)"], 5, log)
        self.assertEqual(result["exit"], 0)
        self.assertEqual(log.read_bytes(), b"out\n")
        self.assertEqual(log.with_suffix(".stderr").read_bytes(), b"err\n")


if __name__ == "__main__":
    unittest.main()
