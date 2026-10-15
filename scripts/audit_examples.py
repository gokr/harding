#!/usr/bin/env python3
"""Run the example regression manifest: syntax, interpreter, native build and parity.

Known compiler failures remain visible and must match their recorded stage and
message. --strict fails on those too. Servers/libraries are syntax-only gates;
Selected website Markdown fences are extracted directly; historical proposals
and context-dependent documentation fragments are not standalone applications.
"""
import argparse
import collections
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
from typing import Any
from website_examples import snippets

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "examples" / "manifest.json"


def inventory(root=ROOT):
    return sorted(str(path.relative_to(root))
                  for directory in ("examples", "benchmark")
                  for path in (root / directory).rglob("*.hrd"))


def load_cases(root=ROOT):
    cases = json.loads((root / "examples" / "manifest.json").read_text())["cases"]
    paths = [case["path"] for case in cases if "snippet" not in case]
    website = snippets(root)
    covered = {(case["path"], case["snippet"]) for case in cases if "snippet" in case}
    if covered != set(website):
        raise ValueError(f"Website snippet coverage: unlisted={sorted(set(website) - covered)}, "
                         f"stale={sorted(covered - set(website))}")
    missing = set(inventory(root)) - set(paths)
    stale = set(paths) - set(inventory(root))
    if missing or stale:
        raise ValueError(f"Example manifest coverage: unlisted={sorted(missing)}, stale={sorted(stale)}")
    ids = [case["id"] for case in cases]
    if len(ids) != len(set(ids)):
        raise ValueError("Duplicate example case ids")
    for case in cases:
        if case.get("gate"):
            continue
        if not (root / case["stdout"]).is_file():
            raise ValueError(f"Missing expected stdout for {case['id']}")
        if case.get("known_failure", {}).get("stage") not in {None, "build", "native", "parity"}:
            raise ValueError(f"Invalid known failure stage: {case['id']}")
    return cases


def run(command, timeout, log):
    with subprocess.Popen(command, cwd=ROOT, stdin=subprocess.DEVNULL,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          start_new_session=True) as process:
        try:
            output, errors = process.communicate(timeout=timeout)
            code: int | str = process.returncode
        except subprocess.TimeoutExpired:
            # Granite spawns Nim/GCC: kill the group, not just its driver.
            os.killpg(process.pid, signal.SIGKILL)
            output, errors = process.communicate()
            code = "timeout"
    log.write_bytes(output)
    stderr = log.with_suffix(".stderr")
    stderr.write_bytes(errors)
    return {"exit": code, "stdout": str(log.relative_to(ROOT)),
            "stderr": str(stderr.relative_to(ROOT))}


def failure_status(case, stage, output):
    known = case.get("known_failure")
    if known and stage == known["stage"] and known["contains"] in output:
        return "known-compiler-failure"
    return f"{stage}-failure"


def contents(result):
    return "".join((ROOT / result[key]).read_text(errors="replace")
                   for key in ("stdout", "stderr"))


def execute(case, directory, syntax_binary, options):
    path = case["path"]
    record: dict[str, Any] = {"id": case["id"], "path": path}
    if "snippet" in case:
        extracted = directory / "snippet.hrd"
        extracted.write_text(snippets(ROOT)[(path, case["snippet"])])
        path = str(extracted)
        record["snippet"] = case["snippet"]
        record["extracted"] = str(extracted.relative_to(ROOT))
    syntax = run([str(syntax_binary), case.get("mode", "script"), path],
                 options.timeout, directory / "syntax.log")
    record["syntax"] = syntax
    if syntax["exit"] != 0:
        return dict(record, status="syntax-failure")
    if case.get("gate"):
        return dict(record, status="gated", reason=case["gate"])
    args = case.get("args", [])
    interpreter = run([str(ROOT / "harding"), path] + (["--"] + args if args else []),
                      case.get("timeout", options.timeout), directory / "interpreter.log")
    record["interpreter"] = interpreter
    if interpreter["exit"] != 0:
        return dict(record, status="interpreter-failure")
    expected = (ROOT / case["stdout"]).read_bytes()
    if (directory / "interpreter.log").read_bytes() != expected:
        return dict(record, status="stdout-regression")
    # Stderr is significant too; a new warning/error must not disappear in stdout parity.
    expected_errors = case.get("stderr", "").encode()
    if (directory / "interpreter.stderr").read_bytes() != expected_errors:
        return dict(record, status="stderr-regression")
    if options.interpreter_only:
        return dict(record, status="interpreter-pass")
    binary = directory / "program"
    built = run([str(ROOT / "granite"), "build", path, f"-d:{directory}", f"-o:{binary}"],
                options.build_timeout, directory / "build.log")
    record["build"] = built
    if built["exit"] != 0:
        return dict(record, status="build-failure" if built["exit"] == "timeout" else failure_status(case, "build", contents(built)))
    native = run([str(binary)] + args, case.get("timeout", options.timeout), directory / "native.log")
    record["native"] = native
    if native["exit"] != 0:
        return dict(record, status="native-failure" if native["exit"] == "timeout" else failure_status(case, "native", contents(native)))
    if (directory / "native.log").read_bytes() != expected or (directory / "native.stderr").read_bytes() != expected_errors:
        return dict(record, status=failure_status(case, "parity", contents(native)))
    return dict(record, status="unexpected-pass" if case.get("known_failure") else "parity-pass")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("cases", nargs="*", help="optional manifest ids or source paths")
    parser.add_argument("--timeout", type=int, default=60)
    parser.add_argument("--build-timeout", type=int, default=120)
    parser.add_argument("--interpreter-only", action="store_true")
    parser.add_argument("--strict", action="store_true", help="also fail on known compiler gaps")
    options = parser.parse_args()
    try:
        cases = load_cases()
    except (ValueError, KeyError) as error:
        parser.error(str(error))
    if options.cases:
        unknown = set(options.cases) - {value for case in cases for value in (case["id"], case["path"])}
        if unknown:
            parser.error(f"unknown examples: {sorted(unknown)}")
        cases = [case for case in cases if case["id"] in options.cases or case["path"] in options.cases]
    for executable in ["harding"] + ([] if options.interpreter_only else ["granite"]):
        if not (ROOT / executable).is_file():
            parser.error(f"Build ./{executable} before running this audit")
    artifact_root = ROOT / "build" / "example-audit"
    artifact_root.mkdir(parents=True, exist_ok=True)
    artifacts = Path(tempfile.mkdtemp(prefix="run-", dir=artifact_root))
    syntax_binary = artifacts / "parse-check"
    built = run(["nim", "c", f"-o:{syntax_binary}", "scripts/example_parse_check.nim"],
                options.build_timeout, artifacts / "parse-build.log")
    if built["exit"] != 0:
        raise SystemExit(f"Syntax checker build failed: {built}")
    records = []
    for case in cases:
        directory = artifacts / case["id"]
        directory.mkdir()
        record = execute(case, directory, syntax_binary, options)
        records.append(record)
        print(f"{record['status']:24} {case['id']} ({case['path']})", flush=True)
        (artifacts / "results.json").write_text(json.dumps(records, indent=2) + "\n")
    counts = collections.Counter(record["status"] for record in records)
    print(json.dumps(dict(counts), sort_keys=True))
    print(f"Artifacts: {artifacts.relative_to(ROOT)}")
    allowed = {"parity-pass", "interpreter-pass", "gated"}
    if not options.strict:
        allowed.add("known-compiler-failure")
    return any(record["status"] not in allowed for record in records)


if __name__ == "__main__":
    raise SystemExit(main())
