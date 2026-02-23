#!/bin/bash
# Compare outputs between interpreter and compiled

cd /home/gokr/tankfeud/compiler-next

echo "=========================================="
echo "Output Comparison: Interpreter vs Compiled"
echo "=========================================="
echo ""

for file in examples/hello.hrd examples/arithmetic.hrd examples/fibonacci.hrd; do
    name=$(basename "$file" .hrd)
    echo "=== $name ==="
    
    echo "Interpreter output:"
    timeout 5 ./harding "$file" 2>&1 | head -5
    
    echo ""
    echo "Compiled output:"
    timeout 5 ./build/$name 2>&1 | head -5
    
    echo ""
    echo "---"
    echo ""
done
