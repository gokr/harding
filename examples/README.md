# Harding examples

Examples are grouped by purpose, with no numbered filename prefixes:

| Directory | Contents |
|---|---|
| `language/` | Language basics, objects, inheritance, blocks, collections |
| `compiler/` | Granite entry points, closures and block benchmarks |
| `stdlib/` | Library-oriented demonstrations such as logging |
| `concurrency/` | Interpreter green-thread/scheduler examples |
| `web/` | HTTP servers, JSON APIs and Bona web applications |
| `integrations/` | BitBarrel and the host-loaded `harding-echo` package |
| `templates/` | Interpreter-hosted and Granite application templates |
| `expected/` | Reviewed stdout snapshots for runnable regression cases |

`../benchmark/` remains the home for algorithm/performance workloads. Historical
proposals remain under `../docs/research/`; they are not current runnable examples.

## Run an example

From the repository root:

```sh
./harding examples/language/hello.hrd
./harding examples/language/classes.hrd
./harding examples/language/collections.hrd
./granite build examples/compiler/compiled_blocks.hrd -d:build/blocks -o:build/blocks/demo
./build/blocks/demo
```

## Regression suite

```sh
nimble harding
nim c -p:external -o:granite src/harding/compiler/granite.nim
nimble testExamples
# Require every ungated example to succeed natively too:
nimble testExamplesStrict
```

`manifest.json` lists **every** `.hrd` file under `examples/` and `benchmark/`.
Unlisted new files and stale paths fail validation. The runner checks syntax in
script/library context, successful interpreter execution, checked-in stdout,
native build, successful native execution, and exact stdout/stderr parity.
Template cases include both empty and nonempty command-line arguments.

Known compiler failures are explicit, matched by stage and diagnostic, and reported
as `known-compiler-failure`, **not passes**. New failures, timeouts, changed expected
output, and unexpected successes fail the normal suite. `--strict` fails on known
gaps as well. Resolve a gap by fixing the compiler and removing its manifest entry,
not by changing correct source to avoid the feature.

```sh
python3 scripts/audit_examples.py examples/language/collections.hrd benchmark/permute.hrd
python3 scripts/audit_examples.py --interpreter-only
python3 -m unittest discover -s tests -p test_example_audit.py
```

All logs, generated sources, binaries and `results.json` stay in unique
`build/example-audit/run-*` directories. Executions and builds have time limits;
server/service inputs are never started automatically. `scripts/test_granite_examples.sh`
is a compatibility entry point for the same runner (the old shell flags are gone).

When changing an example intentionally, review its stdout file in `expected/` and
update it explicitly; the runner never rewrites snapshots. Empty-output benchmarks
are smoke checks only. The permutation, queens and towers outputs additionally
check their expected counts. See [the audit report](../docs/GRANITE_EXAMPLE_AUDIT.md)
for limits and remaining compiler gaps. Website/Markdown snippets are a separate
coverage stream; `tests/test_website_examples.nim` is interpreter-only.

## Host-loaded examples

Web/BitBarrel examples need their documented hosts/services and may write data.
Their manifest entries are syntax-only gates, not native execution successes.
`testExamples` also runs the Echo and interpreter-template host tests. They can
be run separately with `nimble testExampleHosts`. The Echo test command is:

```sh
nim c -p:src -p:external -p:examples/integrations/harding-echo/src \
  -o:build/example-echo-tests examples/integrations/harding-echo/tests/test_echo.nim
timeout 60 build/example-echo-tests
```
