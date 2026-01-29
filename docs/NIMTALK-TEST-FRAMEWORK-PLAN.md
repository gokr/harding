# Nimtalk Unit Test Framework Plan

Based on sUnit (the original Smalltalk unit testing framework by Kent Beck)

## Overview

The Nimtalk test framework follows the xUnit family pattern established by sUnit. It provides a simple, consistent way to write and run tests entirely in Nimtalk code.

## Core Classes

### TestCase

The base class for all individual tests. Users subclass TestCase and implement test methods.

```smalltalk
MyTest := TestCase derive.

MyTest>>testAddition [
  self assert: 2 + 2 equals: 4
].

MyTest>>testStringConcat [
  self assert: ('Hello' , ' ' , 'World') equals: 'Hello World'
].
```

**Key Methods:**
- `assert:` - Fails if argument is false
- `assert:equals:` - Fails if two values are not equal (using `=`)
- `deny:` - Fails if argument is true (negated assert)
- `should:` - Takes a block, fails if block raises an error
- `should:raise:` - Takes a block and exception class, passes if block raises that exception

### TestSuite

A collection of tests that can be run together.

```smalltalk
suite := TestSuite new: 'My Test Suite'.
suite add: (MyTest selector: #testAddition).
suite add: (MyTest selector: #testStringConcat).

result := suite run.
"result passed, failed, errors counts available"
```

**Key Methods:**
- `add:` - Add a TestCase instance
- `addAll:` - Add all test methods from a class
- `run` - Execute all tests and return TestResult

### TestResult

Holds the results of running tests.

```smalltalk
result := myTest run.

result passedCount.   "Number of passed tests"
result failedCount.   "Number of failed tests"
result errorCount.    "Number of errors (unexpected exceptions)"
result totalCount.    "Total tests run"

result failures.  "Collection of failed assertions"
result errors.    "Collection of unexpected exceptions"
```

### TestRunner

Executes tests and reports results.

```smalltalk
runner := TestRunner new.
runner run: MyTest.           "Run all test methods in class"
runner runSuite: suite.       "Run a test suite"
runner runCategory: 'Core'.   "Run all tests in category"
```

## Assertion Methods Detail

### Basic Assertions

```smalltalk
self assert: condition.
  "Fails with generic message if condition is false"

self assert: condition description: 'Custom error message'.
  "Fails with custom message if condition is false"

self deny: condition.
  "Opposite of assert - fails if condition is true"
```

### Equality Assertions

```smalltalk
self assert: actual equals: expected.
  "Compare using =, fail with details if not equal"
  "Example: self assert: (3 + 4) equals: 7"

self deny: actual equals: expected.
  "Pass if values are not equal"
```

### Exception Assertions

```smalltalk
self should: [ 1 / 0 ].
  "Pass if block completes without error"
  "Fail if any exception is raised"

self should: [ 1 / 0 ] raise: DivisionByZero.
  "Pass if block raises specified exception"
  "Fail if no exception or different exception"

self shouldnt: [ 1 + 1 ] raise: Error.
  "Pass if block does NOT raise specified exception"
```

### Collection Assertions

```smalltalk
self assert: collection includes: element.
  "Pass if collection includes element"

self assert: collection isEmpty.
  "Pass if collection has no elements"

self assert: collection size equals: expectedSize.
  "Pass if collection size matches"
```

## Setup and Teardown

TestCase provides hooks for test preparation and cleanup:

```smalltalk
DatabaseTest := TestCase derive.

DatabaseTest>>setUp [
  "Called before EACH test method"
  db := Database new.
  db connect.
].

DatabaseTest>>tearDown [
  "Called after EACH test method, even if test failed"
  db disconnect.
].

DatabaseTest>>testQuery [
  self assert: (db query: 'SELECT 1') isNotNil
].

DatabaseTest>>testInsert [
  db insert: 'test'.
  self assert: (db count) > 0
].
"Both tests run with fresh db connection due to setUp/tearDown"
```

## Test Discovery

Tests can be discovered automatically:

```smalltalk
"Run all tests in a class"
TestRunner run: MyTestClass.

"Run all tests in multiple classes"
TestRunner runAll: #(MyTest YourTest TheirTest).

"Run tests matching pattern"
TestRunner runTestsMatching: 'test*Array*'.

"Run all tests in a package/category"
TestRunner runCategory: 'lib/core'.
```

## Test Organization with Categories

Tests can be organized into categories:

```smalltalk
ArrayTest := TestCase derive: #() category: 'Collections'.

ArrayTest>>testCreation category: 'Basic'.
ArrayTest>>testAdding category: 'Mutation'.
ArrayTest>>testIteration category: 'Enumeration'.
```

## Reporting Formats

The TestRunner supports multiple output formats:

```smalltalk
runner := TestRunner new.
runner format: 'simple'.     "One line per test: PASS/FAIL/ERROR"
runner format: 'progress'.   "Dots: . for pass, F for fail, E for error"
runner format: 'detailed'.   "Full test names with timing"
runner format: 'xml'.        "JUnit-compatible XML output"
runner format: 'tap'.        "Test Anything Protocol format"

runner run: MyTest.
```

## Example: Complete Test File

```smalltalk
#!/usr/bin/env ntalk
#
# test_array.nt - Array collection tests
#

ArrayTest := TestCase derive category: 'Collections-Tests'.

ArrayTest>>setUp [
  empty := Array new.
  numbers := Array new.
  numbers add: 1.
  numbers add: 2.
  numbers add: 3.
].

ArrayTest>>testNewCreatesEmptyArray [
  self assert: empty isEmpty.
  self assert: empty size equals: 0
].

ArrayTest>>testAddIncreasesSize [
  empty add: 'item'.
  self deny: empty isEmpty.
  self assert: empty size equals: 1
].

ArrayTest>>testFirstAndLast [
  self assert: numbers first equals: 1.
  self assert: numbers last equals: 3
].

ArrayTest>>testIncludes [
  self assert: numbers includes: 2.
  self deny: numbers includes: 99
].

ArrayTest>>testCollect [
  doubles := numbers collect: [ :n | n * 2 ].
  self assert: doubles size equals: 3.
  self assert: (doubles at: 0) equals: 2.
  self assert: (doubles at: 1) equals: 4.
  self assert: (doubles at: 2) equals: 6
].

ArrayTest>>testSelect [
  evens := numbers select: [ :n | n even ].
  self assert: evens size equals: 1.
  self assert: evens first equals: 2
].

ArrayTest>>testInject [
  sum := numbers inject: 0 into: [ :acc :n | acc + n ].
  self assert: sum equals: 6
].

ArrayTest>>testErrorHandling [
  "Test that proper error is raised"
  self should: [ Array new at: 100 ] raise: SubscriptOutOfBounds
].

"Run the tests"
runner := TestRunner new.
runner format: 'progress'.
runner run: ArrayTest.
```

## Implementation Notes

### Integration with Exception System

The test framework relies on the exception system (Phase 2):
- `assert:` raises TestFailure exception on failure
- `should:raise:` catches expected exceptions
- Unexpected exceptions become TestError

### Minimal Core Implementation

For initial implementation, we need:

1. **TestCase class** with:
   - `assert:`, `deny:`
   - `assert:equals:`
   - `should:`, `should:raise:`
   - `setUp`, `tearDown` hooks

2. **TestResult class** with:
   - Pass/fail/error counts
   - Collection of failure details

3. **TestRunner class** with:
   - `run:` method
   - Simple text output

Advanced features (TestSuite, categories, XML output) can be added later.

## Comparison with Other Frameworks

| Feature | sUnit (original) | Nimtalk Test | Notes |
|---------|------------------|--------------|-------|
| assert: | ✅ | ✅ | Basic assertion |
| assert:equals: | ✅ | ✅ | Equality check |
| deny: | ✅ | ✅ | Negated assertion |
| should:raise: | ✅ | ✅ | Exception testing |
| setUp/tearDown | ✅ | ✅ | Per-test hooks |
| TestSuite | ✅ | ✅ | Test collections |
| Categories | ✅ | ✅ | Organization |
| TestRunner | ✅ | ✅ | Execution |
| Mock objects | ❌ | Future | Can add later |
| Parameterized tests | ❌ | Future | Data-driven tests |

## Priority for Implementation

**Phase 1 (Core):**
- TestCase with assert:, deny:, assert:equals:
- TestResult with basic counting
- TestRunner with simple output

**Phase 2 (Complete):**
- should:, should:raise:
- setUp/tearDown
- TestSuite

**Phase 3 (Advanced):**
- Categories
- Multiple output formats
- Test discovery
