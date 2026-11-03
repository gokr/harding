# Validation

Status: Json passes in the interpreter and natively under ARC and ORC.

- Interpreter ARC/ORC: full upstream fixture and all checks pass.
- Native ARC/ORC (Granite + `nim c`): all checks pass after the compiler/runtime
  fixes recorded below. `python3 tests/test_awfy_json.py` is the entry point.
- Matched upstream Python comparator passes.

## Gaps this port exposed (all fixed generically)

1. Selector strings were emitted unescaped; `\\` broke generated Nim
   (`tests/test_selector_escaping.py`).
2. A returning block stored through a slot got no non-local-return boundary, so
   `NonLocalReturnException` escaped (`tests/test_nested_nonlocal_codegen.py`).
3. Globals assigned inside a method body were not collected, so `JsonNULL` read
   back as a Symbol instead of the stored singleton.
4. Native `String>>from:to:` was missing (`tests/test_native_substring.py`).
5. Native `String>>at:` answered nil for every index instead of the byte or `""`.
6. Class objects raised MessageNotUnderstood for `=` instead of comparing
   identity, while user-defined `=` still had to win; pinned by the
   `equality_dynamic_dispatch` parity case.

## Known remaining limitation

Extensions to the built-in String class are not emitted into generated methods
(`blocker_string_override.hrd`). This port does not need them; it is recorded for
whoever does.

Products and logs stay under `build/awfy-json`; tests never overwrite root
compiler binaries.
