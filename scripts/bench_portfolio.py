#!/usr/bin/env python3
"""Compare release engines on the checked portfolio showcase (build first)."""
import argparse
import json
from pathlib import Path
import statistics
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def expected(count):
    values = [350000 * (100 + shock) // 100
              + 200000 * (100 - int(shock / 2)) // 100 + 50000
              for shock in range(-10, 11)]
    checksum = sum(values) * (count // 21) + sum(values[:count % 21])
    worst = min([600000] + values[:min(count, 21)])
    return ('equity\ntrue\ndemonstration rejection\ntrue\n'
            + json.dumps([2, count, 600000, checksum, worst], separators=(',', ':')) + '\n').encode()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--scenarios', type=int, default=20000)
    parser.add_argument('--trials', type=int, default=5)
    parser.add_argument('--timeout', type=int, default=180)
    args = parser.parse_args()
    if args.scenarios < 1 or args.trials < 1:
        parser.error('scenarios and trials must be positive')
    base = ROOT / 'build/portfolio-stress'
    base.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='timings-', dir=base))
    engines = {
        'interpreter': [str(ROOT / 'harding'), 'examples/compiler/portfolio_stress.hrd', '--'],
        'granite': [str(base / 'portfolio')],
    }
    rows = {name: {'work_ms': [], 'baseline_ms': []} for name in engines}
    # Alternate order to reduce systematic warm-cache/order bias.
    for trial in range(args.trials):
        for name in list(engines)[::1 if trial % 2 == 0 else -1]:
            for label, count in [('work', args.scenarios), ('baseline', 0)]:
                start = time.perf_counter_ns()
                run = subprocess.run(engines[name] + [str(count)], cwd=ROOT,
                                     capture_output=True, timeout=args.timeout)
                elapsed = (time.perf_counter_ns() - start) / 1e6
                stem = work / f'{name}-{trial}-{label}'
                stem.with_suffix('.stdout').write_bytes(run.stdout)
                stem.with_suffix('.stderr').write_bytes(run.stderr)
                if run.returncode or run.stderr or run.stdout != expected(count):
                    raise RuntimeError(f'Incorrect result: {stem}')
                rows[name][label + '_ms'].append(elapsed)
    for name, row in rows.items():
        row['median_work_ms'] = statistics.median(row['work_ms'])
        row['median_baseline_ms'] = statistics.median(row['baseline_ms'])
        row['net_ms'] = row['median_work_ms'] - row['median_baseline_ms']
        print(f"{name}: {row['median_work_ms']:.3f} ms total; "
              f"{row['median_baseline_ms']:.3f} ms zero-scenario baseline; "
              f"{row['net_ms']:.3f} ms net")
    total_ratio = rows['interpreter']['median_work_ms'] / rows['granite']['median_work_ms']
    print(f'Total elapsed ratio: {total_ratio:.2f}x')
    print('Baseline subtraction is approximate, especially for short native runs.')
    (work / 'results.json').write_text(json.dumps({'scenarios': args.scenarios,
        'trials': args.trials, 'engines': rows, 'total_ratio': total_ratio}, indent=2) + '\n')
    print(f'Artifacts: {work.relative_to(ROOT)}')


if __name__ == '__main__':
    main()
