## Test suite for tagged values (NaN boxing)

import std/unittest
import ../src/harding/core/tagged

suite "Tagged Value Tests":
  test "nil value":
    let v = nilValue()
    check isNil(v) == true
    check isInt(v) == false
    check isBool(v) == false
    check isHeapObject(v) == false

  test "integer values":
    let v = toValue(42)
    check isInt(v) == true
    check isNil(v) == false
    check asInt(v) == 42
    
  test "integer negative values":
    let v = toValue(-100)
    check isInt(v) == true
    check asInt(v) == -100
    
  test "integer zero":
    let v = toValue(0)
    check isInt(v) == true
    check asInt(v) == 0
    
  test "integer max value":
    let v = toValue(1073741823)  # 2^30 - 1
    check isInt(v) == true
    check asInt(v) == 1073741823
    
  test "integer min value":
    let v = toValue(-1073741824)  # -2^30
    check isInt(v) == true
    check asInt(v) == -1073741824

  test "boolean true":
    let v = toValue(true)
    check isBool(v) == true
    check isNil(v) == false
    check asBool(v) == true
    
  test "boolean false":
    let v = toValue(false)
    check isBool(v) == true
    check asBool(v) == false

  test "integer addition":
    let a = toValue(10)
    let b = toValue(20)
    let result = add(a, b)
    check isInt(result) == true
    check asInt(result) == 30
    
  test "integer subtraction":
    let a = toValue(50)
    let b = toValue(15)
    let result = sub(a, b)
    check asInt(result) == 35
    
  test "integer multiplication":
    let a = toValue(6)
    let b = toValue(7)
    let result = mul(a, b)
    check asInt(result) == 42
    
  test "integer division":
    let a = toValue(100)
    let b = toValue(10)
    let result = divInt(a, b)
    check asInt(result) == 10
    
  test "integer modulo":
    let a = toValue(17)
    let b = toValue(5)
    let result = modInt(a, b)
    check asInt(result) == 2

  test "integer equality":
    let a = toValue(42)
    let b = toValue(42)
    let c = toValue(99)
    check equals(a, b) == true
    check equals(a, c) == false
    
  test "nil equality":
    let a = nilValue()
    let b = nilValue()
    check equals(a, b) == true
    
  test "boolean equality":
    let t1 = toValue(true)
    let t2 = toValue(true)
    let f = toValue(false)
    check equals(t1, t2) == true
    check equals(t1, f) == false

  test "integer comparisons":
    let a = toValue(10)
    let b = toValue(20)
    check lessThan(a, b) == true
    check lessThan(b, a) == false
    check lessOrEqual(a, b) == true
    check greaterThan(b, a) == true
    check greaterOrEqual(b, a) == true

  test "toString for int":
    check toString(toValue(42)) == "42"
    check toString(toValue(-5)) == "-5"
    
  test "toString for nil":
    check toString(nilValue()) == "nil"
    
  test "toString for bool":
    check toString(toValue(true)) == "true"
    check toString(toValue(false)) == "false"

  test "hash consistency":
    let a = toValue(42)
    let b = toValue(42)
    check hash(a) == hash(b)

  test "heap object creation":
    var obj = HeapObject()
    let v = toValue(obj)
    check isHeapObject(v) == true
    check isInt(v) == false
    check asHeapObject(v) == obj
    
  test "nil heap object":
    let v = toValue(nil)
    check isNil(v) == true
    check isHeapObject(v) == false

  test "type errors":
    let i = toValue(42)
    let b = toValue(true)
    expect ValueError:
      discard asBool(i)
    expect ValueError:
      discard asInt(b)

when isMainModule:
  echo "Tagged value tests compiled successfully"
