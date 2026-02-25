#!/bin/bash
echo "=== HARDING PERFORMANCE BASELINE ==="
echo "Date: $(date)"
echo ""

echo "1. Simple expression (3 + 4):"
time ./harding -e "3 + 4" 2>&1 | grep real

echo ""
echo "2. Small loop (10 timesRepeat):"
time ./harding -e "10 timesRepeat: [3 + 4]" 2>&1 | grep real

echo ""
echo "3. Medium loop (100 timesRepeat):"
time ./harding -e "100 timesRepeat: [3 + 4]" 2>&1 | grep real

echo ""
echo "4. Arithmetic intensive (1000 iterations):"
time ./harding -e "| sum | sum := 0. 1000 timesRepeat: [sum := sum + 1]" 2>&1 | grep real

echo ""
echo "5. Nested blocks (10 timesRepeat with inner 10 timesRepeat):"
time ./harding -e "10 timesRepeat: [10 timesRepeat: [3 + 4]]" 2>&1 | grep real
