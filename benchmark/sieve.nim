# Sieve of Eratosthenes Benchmark
# Ported from SOM benchmark suite (https://github.com/smarr/SOM)
# Expected result: 5133 primes below 50000

# Count primes using trial division
var primeCount = 0

var i = 2
while i <= 1000000:
  var isPrime = true

  # Test divisibility by checking divisors up to sqrt(i)
  var d = 2
  while d * d <= i:
    if i mod d == 0:
      isPrime = false
      d = i  # Exit loop using d = i (break)
    d = d + 1

  if isPrime:
    primeCount = primeCount + 1

  i = i + 1

echo primeCount
