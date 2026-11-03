"""Run the unmodified, pinned AWFY Python Bounce implementation."""
from pathlib import Path
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent / "upstream/benchmarks/Python"))
from bounce import Bounce  # noqa: E402


def main():
    benchmark = Bounce()
    result = benchmark.benchmark()
    if not benchmark.verify_result(result):
        raise RuntimeError(f"Bounce verification failed: {result}")
    print(result)


if __name__ == "__main__":
    main()
