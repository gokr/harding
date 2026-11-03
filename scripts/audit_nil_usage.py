#!/usr/bin/env python3
"""Classify every `nil` occurrence in Harding source by syntactic position.

Answers "where is nil actually used" rather than "how often does the word
appear". Each occurrence is assigned to the position it occupies, because the
answers differ sharply: a nil that is assigned to a slot is a normal absent
value, while a nil passed as an argument usually encodes an optional parameter.

Used by docs/NIL_AND_ABSENCE.md. Re-run it after any migration step; the counts
in that document are only meaningful for the revision they were taken at.

Usage:
    python3 scripts/audit_nil_usage.py                # summary
    python3 scripts/audit_nil_usage.py --by-area      # area x category table
    python3 scripts/audit_nil_usage.py --detail local # every local-assignment site

Note on classification: a plain `x := nil` cannot be told from a slot assignment
by syntax alone, so targets are checked against slots declared via `derive:` in
the same class. Targets that match neither a declared slot nor a lexically
visible local are reported as `unclassified` rather than guessed at.
"""

import argparse
import collections
import json
import pathlib
import re
import sys

AREAS = ["lib", "examples", "external", "benchmark", "tests"]
METHOD_HDR = re.compile(r"^\s*([A-Z][A-Za-z0-9_]*)\s*(class)?>>")
SLOT_DECL = re.compile(
    r"([A-Z][A-Za-z0-9_]*)\s*:=\s*\w+\s+derive(?:Public)?:?\s*#\(([^)]*)\)")


def strip_comment(line):
    """Drop a trailing # comment.

    Harding uses # for comments, for symbols (#foo, #(1, 2)) and for literal
    prefixes (json{...}), so a # only starts a comment when it is followed by
    whitespace or ends the line.
    """
    out, in_str, i = [], False, 0
    while i < len(line):
        ch = line[i]
        if ch == '"':
            in_str = not in_str
            out.append(ch)
        elif ch == "#" and not in_str:
            if i + 1 >= len(line) or line[i + 1] in " \t":
                break
            out.append(ch)
        else:
            out.append(ch)
        i += 1
    return "".join(out)


def declared_slots(root):
    """Slot names per class, from derive: declarations anywhere in the tree."""
    slots = collections.defaultdict(set)
    for f in root.rglob("*.hrd"):
        if "build/" in str(f):
            continue
        for line in f.read_text(errors="ignore").splitlines():
            m = SLOT_DECL.search(strip_comment(line))
            if not m:
                continue
            for name in m.group(2).split(","):
                name = name.strip()
                if name:
                    slots[m.group(1)].add(name)
    return slots


def classify(path, slots):
    """Yield one record per nil occurrence in one file."""
    lines = path.read_text(errors="ignore").splitlines()
    current_class, current_method = "", "(top-level)"
    locals_in_scope = set()

    for lineno, raw in enumerate(lines, start=1):
        if raw.strip().startswith("#"):
            continue
        code = strip_comment(raw)
        if not code.strip():
            continue

        hdr = METHOD_HDR.search(code)
        if hdr:
            current_class = hdr.group(1)
            after = code.split(">>", 1)[1]
            sel = re.match(r"\s*([A-Za-z0-9_]*(?::[A-Za-z0-9_]*:)*)", after)
            current_method = sel.group(1) if sel and sel.group(1) else "(unknown)"
            # Keyword selector parts are not locals; only `name:` in the header is.
            locals_in_scope = set(
                re.findall(r"([a-z][A-Za-z0-9_]*)\s*:(?!\=)", after))

        temps = re.match(r"^\s*\|\s*([^|]*)\|", code)
        if temps:
            locals_in_scope.update(temps.group(1).split())
        locals_in_scope.update(re.findall(r":([a-z][A-Za-z0-9_]*)\s*\|", code))

        if not re.search(r"\bnil\b", code):
            continue

        record = {
            "file": str(path),
            "line": lineno,
            "method": f"{current_class}>>{current_method}",
            "code": raw.strip(),
        }

        for m in re.finditer(r"([A-Za-z_][A-Za-z0-9_]*(?:::\w+)?)\s*:=\s*nil\b", code):
            target = m.group(1)
            base = target.split("::")[-1]
            if "::" in target:
                cat = "assign-slot-explicit"
            elif base in slots.get(current_class, set()):
                cat = "assign-slot"
            elif base in locals_in_scope:
                cat = "assign-local"
            elif current_method == "(top-level)":
                # An uppercase assignment at script level is a global, not a slot.
                cat = "assign-global"
            else:
                cat = "unclassified"
            yield dict(record, cat=cat, target=base)

        if re.search(r"\^\s*nil\b", code):
            yield dict(record, cat="return")

        for m in re.finditer(r"\bnil\b", code):
            before = code[: m.start()].rstrip()
            if re.search(r"(:=\s*|\^\s*)$", before):
                continue  # already counted above
            if re.search(r"([=~]=?)\s*$", before):
                yield dict(record, cat="compare")
            elif re.search(r"[:#]\s*$", before):
                yield dict(record, cat="keyword-argument")
            elif re.search(r"[(,]\s*$", before):
                yield dict(record, cat="literal-element")
            elif re.search(r"\[\s*$", before):
                yield dict(record, cat="block-result")
            elif before == "" or re.search(r"[A-Za-z0-9_)\]]\s*$", before):
                yield dict(record, cat="other-use")
            else:
                yield dict(record, cat="other-use")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", default=".", help="repository root (default: .)")
    ap.add_argument("--by-area", action="store_true", help="area x category table")
    ap.add_argument("--detail", metavar="CATEGORY",
                    help="list every occurrence in one category")
    ap.add_argument("--json", metavar="PATH", help="also write raw records here")
    args = ap.parse_args()

    root = pathlib.Path(args.root)
    if not (root / "lib").is_dir():
        sys.exit(f"not a Harding repository root: {root.resolve()}")

    slots = declared_slots(root)
    records = []
    for area in AREAS:
        for f in sorted((root / area).rglob("*.hrd")):
            if "build/" in str(f):
                continue
            for rec in classify(f, slots):
                records.append(dict(rec, area=area))

    if args.json:
        pathlib.Path(args.json).write_text(json.dumps(records, indent=1))

    if args.detail:
        chosen = [r for r in records if r["cat"] == args.detail]
        print(f"{len(chosen)} occurrence(s) of {args.detail}:")
        for r in chosen:
            print(f"  {r['file']}:{r['line']}  [{r['method']}]")
            print(f"      {r['code'][:100]}")
        return

    by_cat = collections.Counter(r["cat"] for r in records)
    files_by_cat = collections.defaultdict(set)
    for r in records:
        files_by_cat[r["cat"]].add(r["file"])

    print(f"nil occurrences: {len(records)}  in {len({r['file'] for r in records})} files\n")
    print(f"  {'position':24s} {'occ':>5s} {'files':>6s}")
    for cat, n in by_cat.most_common():
        print(f"  {cat:24s} {n:5d} {len(files_by_cat[cat]):6d}")

    if args.by_area:
        area_cat = collections.Counter((r["area"], r["cat"]) for r in records)
        cats = [c for c, _ in by_cat.most_common()]
        print(f"\n  {'area':10s} " + " ".join(f"{c[:12]:>12s}" for c in cats))
        for area in AREAS:
            if not any(r["area"] == area for r in records):
                continue
            print(f"  {area:10s} " + " ".join(
                f"{area_cat.get((area, c), 0):12d}" for c in cats))


if __name__ == "__main__":
    main()
