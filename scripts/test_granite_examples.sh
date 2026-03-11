#!/bin/bash

set -u

repoRoot="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
examplesDir="$repoRoot/examples"
tmpDir="${TMPDIR:-/tmp}/granite-example-parity"
keepTmp=0
runAll=0

declare -a requestedExamples=()
declare -a skipExamples=(
  "bitbarrel_demo.hrd"
  "mummyx_hello.hrd"
  "process_demo.hrd"
)

usage() {
  cat <<'EOF'
Usage: scripts/test_granite_examples.sh [options] [example ...]

Compare example behavior between ./harding and ./granite run.

Options:
  --all         Include examples that are skipped by default
  --keep-tmp    Keep captured outputs and diffs
  -h, --help    Show this help

Arguments:
  example       Example filename or path under examples/
EOF
}

normalizeExample() {
  local value="$1"
  value="${value##*/}"
  printf '%s\n' "$value"
}

inArray() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    if [[ "$item" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}

normalizeOutputFile() {
  local inputFile="$1"
  local outputFile="$2"

  python3 - "$inputFile" "$outputFile" <<'PY'
from pathlib import Path
import re
import sys

src = Path(sys.argv[1]).read_text(errors="replace").splitlines()
dst = []

for line in src:
    if (
        line.startswith("Compiling: ")
        or line.startswith("Generated: ")
        or line.startswith("Building: ")
        or line.startswith("Build successful: ")
        or line.startswith("Running: ")
        or line.startswith("Hint: ")
        or line.startswith("CC: ")
    ):
        continue
    if re.match(r"^.*/build/.*\bWarning:", line):
        continue
    if re.match(r"^.*/build/.*\bHint:", line):
        continue
    if re.match(r"^.*/build/.*\bError:", line):
        continue
    if re.match(r"^\d+ lines; .*\[SuccessX\]$", line):
        continue
    if re.match(r"^\.+$", line):
        continue
    dst.append(line)

Path(sys.argv[2]).write_text("\n".join(dst) + ("\n" if dst else ""))
PY
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)
      runAll=1
      ;;
    --keep-tmp)
      keepTmp=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      requestedExamples+=("$(normalizeExample "$1")")
      ;;
  esac
  shift
done

if [[ ! -x "$repoRoot/harding" ]]; then
  echo "Missing executable: $repoRoot/harding"
  echo "Build it with: nimble harding"
  exit 1
fi

if [[ ! -x "$repoRoot/granite" ]]; then
  echo "Missing executable: $repoRoot/granite"
  echo "Build it with: nim c -p:external -o:granite src/harding/compiler/granite.nim"
  exit 1
fi

mkdir -p "$tmpDir"
rm -f "$tmpDir"/*

declare -a examples=()
if [[ ${#requestedExamples[@]} -gt 0 ]]; then
  examples=("${requestedExamples[@]}")
else
  while IFS= read -r examplePath; do
    examples+=("$(basename "$examplePath")")
  done < <(printf '%s\n' "$examplesDir"/*.hrd | sort)
fi

passCount=0
failCount=0
skipCount=0

printf 'Granite example parity in %s\n\n' "$repoRoot"

for example in "${examples[@]}"; do
  examplePath="$examplesDir/$example"
  if [[ ! -f "$examplePath" ]]; then
    printf 'MISSING %s\n' "$example"
    failCount=$((failCount + 1))
    continue
  fi

  if [[ $runAll -eq 0 ]] && inArray "$example" "${skipExamples[@]}"; then
    printf 'SKIP   %s\n' "$example"
    skipCount=$((skipCount + 1))
    continue
  fi

  hardingOut="$tmpDir/${example%.hrd}.harding.out"
  graniteOut="$tmpDir/${example%.hrd}.granite.out"
  hardingNorm="$tmpDir/${example%.hrd}.harding.norm"
  graniteNorm="$tmpDir/${example%.hrd}.granite.norm"
  diffOut="$tmpDir/${example%.hrd}.diff"

  pushd "$repoRoot" >/dev/null || exit 1
  ./harding "$examplePath" >"$hardingOut" 2>&1
  hardingStatus=$?
  ./granite run "$examplePath" >"$graniteOut" 2>&1
  graniteStatus=$?
  popd >/dev/null || exit 1

  normalizeOutputFile "$hardingOut" "$hardingNorm"
  normalizeOutputFile "$graniteOut" "$graniteNorm"

  {
    printf 'harding exit: %s\n' "$hardingStatus"
    printf 'granite exit: %s\n' "$graniteStatus"
    printf '\n'
    diff -u "$hardingNorm" "$graniteNorm"
  } >"$diffOut" 2>&1
  diffStatus=$?

  if [[ $hardingStatus -eq $graniteStatus && $diffStatus -eq 0 ]]; then
    printf 'PASS   %s\n' "$example"
    passCount=$((passCount + 1))
    rm -f "$diffOut"
    if [[ $keepTmp -eq 0 ]]; then
      rm -f "$hardingOut" "$graniteOut" "$hardingNorm" "$graniteNorm"
    fi
  else
    printf 'FAIL   %s\n' "$example"
    printf '       diff: %s\n' "$diffOut"
    failCount=$((failCount + 1))
  fi
done

printf '\nPass: %d  Fail: %d  Skip: %d\n' "$passCount" "$failCount" "$skipCount"

if [[ $failCount -eq 0 && $keepTmp -eq 0 ]]; then
  rmdir "$tmpDir" 2>/dev/null || true
fi

if [[ $failCount -ne 0 ]]; then
  exit 1
fi
