=== RELEASE BUILD BASELINE ===

## Release Build (Sun Feb 15 10:42:21 PM CET 2026)

### Sieve (n=500)
Run 1:
real 0.34
Run 2:
real 0.44
Run 3:
real 0.49

### Queens
Run 1:
real 0.13
Run 2:
real 0.16
Run 3:
real 0.12

## Danger Build (Sun Feb 15 10:56:03 PM CET 2026)

### Sieve (n=500)
Run 1:
real 0.29
Run 2:
real 0.25
Run 3:
real 0.40

### Queens
Run 1:
real 0.10
Run 2:
real 0.10
Run 3:
real 0.10

## Summary

| Build | Sieve (avg) | Queens (avg) |
|-------|-------------|--------------|
| Debug | ~3.0s | ~1.0s |
| Release | ~0.4s | ~0.14s |
| Danger | ~0.4s | ~0.14s |
=== With Float Fast Path ===

## With Float Fast Path (Mon Feb 16 12:14:27 AM CET 2026)

### Sieve (n=500)
Run 1:
real 0.20
Run 2:
real 0.20
Run 3:
real 0.22

### Queens
Run 1:
real 0.07
Run 2:
real 0.07
Run 3:
real 0.09

## Summary Comparison

| Build | Sieve (avg) | Queens (avg) |
|-------|-------------|--------------|
| Original Release | ~0.4s | ~0.14s |
| With Float Fast Path | ~0.4s | ~0.14s |

## With Frame Pooling ($(date))

### Sieve (n=500)
Run 1: real 0.25
Run 2: real 0.25
Run 3: real 0.31

### Queens
Run 1: real 0.14
Run 2: real 0.10
Run 3: real 0.11

## Final Summary

| Build | Sieve (avg) | Queens (avg) | Improvement |
|-------|-------------|--------------|-------------|
| Debug | ~3.0s | ~1.0s | - |
| Original Release | ~0.4s | ~0.14s | baseline |
| With Frame Pooling | ~0.27s | ~0.12s | 32% / 14% |
