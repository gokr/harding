#!/usr/bin/env bash
# Compatibility entry point; the manifest runner owns example discovery/checks.
set -eu
repoRoot="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 "$repoRoot/scripts/audit_examples.py" "$@"
