#!/usr/bin/env python3
"""Validate a frozen closure, execute its declared parity cases, issue a drift receipt.

Receipts are local build evidence, not signatures or a security boundary. The
compiler checks them against the manifest, engine binaries and parity runner.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.sha1(Path(path).read_bytes()).hexdigest().upper()


def toolchain_digest(root):
    root = Path(root)
    paths = [path.relative_to(root) for path in (root / "src/harding").rglob("*.nim")]
    paths += [path.relative_to(root) for path in (root / "lib").rglob("*.hrd")]
    paths += [Path(name) for name in ("config.nims", "harding.nimble") if (root / name).is_file()]
    combined = "".join(path.as_posix() + ":" + digest(root / path) + "\n"
                       for path in sorted(paths))
    return hashlib.sha1(combined.encode()).hexdigest().upper()


def check(manifest, receipt, root=ROOT):
    root = Path(root).resolve()
    manifest = Path(manifest).resolve()
    receipt = Path(receipt).resolve()
    # Remove old success evidence before validation; a failed rerun cannot leave it usable.
    receipt.unlink(missing_ok=True)
    subprocess.run([str(root / "granite"), "freeze-check", str(manifest), str(root)],
                   cwd=root, check=True, timeout=60)
    before = {"manifestSha1": digest(manifest), "graniteSha1": digest(root / "granite"),
              "hardingSha1": digest(root / "harding"), "toolchainSha1": toolchain_digest(root),
              "runnerSha1": digest(root / "scripts/test_granite_parity.py")}
    source_hashes = {entry["source"]: digest(root / entry["source"])
                     for entry in json.loads(manifest.read_text())["classes"]}
    document = json.loads(manifest.read_text())
    cases = sorted({case for entry in document["classes"] for case in entry["cases"]})
    if not cases:
        raise ValueError("No conformance cases")
    subprocess.run([sys.executable, str(root / "scripts/test_granite_parity.py"),
                    "--timeout", "180", *cases], cwd=root, check=True, timeout=7200)
    receipt.parent.mkdir(parents=True, exist_ok=True)
    evidence = {
        "manifestSha1": digest(manifest),
        "graniteSha1": digest(root / "granite"),
        "hardingSha1": digest(root / "harding"),
        "runnerSha1": digest(root / "scripts/test_granite_parity.py"),
        "passedCases": cases,
    }
    evidence["toolchainSha1"] = toolchain_digest(root)
    if any(evidence[key] != value for key, value in before.items()) or any(
            digest(root / path) != value for path, value in source_hashes.items()):
        raise ValueError("Frozen inputs changed during conformance execution")
    receipt.write_text(json.dumps(evidence, indent=2) + "\n")
    return evidence


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--receipt", type=Path, required=True)
    args = parser.parse_args()
    try:
        check(args.manifest, args.receipt)
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        parser.exit(1, str(error) + "\n")


if __name__ == "__main__":
    main()
