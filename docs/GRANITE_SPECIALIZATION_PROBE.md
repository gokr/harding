# Specialization probe

## Purpose

Before building interprocedural native parameters/returns, measure the prize: how
many compiled-method dispatches a native-parameter variant could actually convert.
This is an attempt to avoid another multi-day slice with a 0% result.

## Running it

```sh
python3 scripts/probe_specialization.py      # builds each benchmark and reports
```

or by hand:

```sh
HARDING_SPEC_PROBE=1 ./program 30
```

The probe is opt-in (`HARDING_SPEC_PROBE=1`), records in thread-local state at
compiled dispatch, and prints one `SPECPROBE` line to stderr at process exit. It is
reached through `initRuntime`, so generated programs need no probe code. When the
variable is unset the only cost is an inline thread-local boolean test per
compiled dispatch.

## Classification

For each compiled dispatch it records whether the resolved target is defined

- on the receiver's **own** class — no inheritance ambiguity, the strongest
  candidate (this is *not* a rejection: an earlier version of the probe wrongly
  counted it as ineligible and reported 0%);
- on an ancestor, with exactly one compiled implementation on the receiver's path
  (unique), or more than one (shared).

For own-class and inherited-unique it additionally counts all-Integer arguments and
whether any argument is an Array/Table, since aggregate arguments are the cases a
native scalar signature cannot express cheaply.

## Result (30 passes, ARC release)

| Benchmark | compiled dispatches | own-class | own + all-Int + no aggregate | inherited-unique all-Int |
|---|---:|---:|---:|---:|
| Richards | 1,221,480 | 1,221,120 | **723,780 (59.3%)** | 0 |
| DeltaBlue | 1,735,657 | 1,154,467 | **896,520 (77.7%)** | 556,650 (96.8%) |
| Queens | 19,834 | 19,834 | 1 (0.0%) | 0 |

Per pass: ~24k eligible calls on Richards, ~30k on DeltaBlue.

Queens shows almost nothing here because its hot sends are already served by the
guarded direct-send helpers, which bypass this path entirely — so the probe is
measuring the remaining, unspecialized traffic.

## Interpretation

The eligible population is real and large: 59–78% of own-class dispatches carry
only Integer arguments. Each of those currently pays an argument `seq` allocation
plus boxing on entry and unboxing on use, which is the `newSeqPayload`/`eqcopy`
mass the profile shows.

It is **not** a 5x lever. Removing one sequence allocation and a handful of boxed
values from ~24–30k calls per pass is a plausible 10–20% on Richards and DeltaBlue,
not an order of magnitude. That is still the largest single identified opportunity
left, and it is the one that finally touches Richards, whose hot path is object
dispatch rather than builtin arithmetic.

Queens should not be expected to improve from this work at all.
