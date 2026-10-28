import std/unittest
import ../src/harding/core/types
import ../src/harding/interpreter/vm
import ./stdlib_test_support

var interp = newSharedStdlibInterpreter()

proc evaluate(source: string): NodeValue =
  let (value, error) = interp.doit(source)
  doAssert error.len == 0, error
  value

suite "Lexical scope isolation":
  test "main temporaries exist before their first assignment is captured":
    discard evaluate("""
      Harding main: [| total read |
        read := [total].
        total := 42.
        LexMainAnswer := read value
      ]
    """)
    check evaluate("LexMainAnswer").intVal == 42

  test "nested unassigned block temporaries have independent capture cells":
    let value = evaluate("""
      LexForward := Array new.
      2 timesRepeat: [| pending reader |
        reader := [pending].
        pending := LexForward size + 10.
        LexForward add: reader
      ].
      LexResults := Array new.
      LexResults add: ((LexForward at: 0) value).
      LexResults add: ((LexForward at: 1) value).
      LexResults
    """)
    check value.toString() == "#(10 11)"

  test "control-flow slot reads and writes ignore caller locals":
    let value = evaluate("""
      LexBox := Object derivePublic: #(payload).
      LexBox>>sample [true ifTrue: [^payload]. ^nil].
      LexBox>>mutate [true ifTrue: [payload := 9]. ^self payload].
      LexCaller := Object derive: #().
      LexCaller>>sampleFrom: target [| payload | payload := 77. ^target sample].
      LexCaller>>mutateFrom: target [| payload | payload := 77. target mutate. ^payload].
      LexTarget := LexBox new.
      LexTarget payload: 5.
      LexRead := LexCaller new sampleFrom: LexTarget.
      LexCallerLocal := LexCaller new mutateFrom: LexTarget.
      LexResults := Array new.
      LexResults add: LexRead. LexResults add: LexCallerLocal. LexResults add: LexTarget payload.
      LexResults
    """)
    check value.toString() == "#(5 77 9)"

  test "nil slots and ordinary methods do not expose caller temporaries":
    let value = evaluate("""
      LexPlain := Object derivePublic: #(stored).
      LexPlain>>sample [^stored].
      LexPlain>>conditional [true ifTrue: [^stored]. ^1].
      LexPlain>>setStored [true ifTrue: [stored := 12]].
      LexCaller>>plainFrom: target [| stored | stored := 77. ^target sample].
      LexCaller>>nilFrom: target [| stored | stored := 77. ^target conditional].
      LexFresh := LexPlain new.
      #((LexCaller new plainFrom: LexFresh), (LexCaller new nilFrom: LexFresh))
    """)
    check value.toString() == "#(nil nil)"

  test "unbound reads cannot see a caller and writes stay in the callee":
    let value = evaluate("""
      LexUnbound := Object derive: #().
      LexUnbound>>sample [^callerOnly].
      LexUnbound>>mutate [callerOnly := 9].
      LexCaller>>unboundFrom: target [| callerOnly | callerOnly := 77. ^target sample].
      LexCaller>>isolatedFrom: target [| callerOnly | callerOnly := 77. target mutate. ^callerOnly].
      #((LexCaller new unboundFrom: LexUnbound new), (LexCaller new isolatedFrom: LexUnbound new))
    """)
    check value.toString() == "#(nil 77)"

  test "nested control flow shares lexical cells without caller scope":
    let value = evaluate("""
      LexClosure := Object derive: #().
      LexClosure>>make [| count callbacks |
        count := 0. callbacks := Array new.
        [count < 3] whileTrue: [| item |
          item := count.
          true ifTrue: [callbacks add: [count := count + 1. item]].
          count := count + 1
        ].
        callbacks add: [count]. ^callbacks
      ].
      LexPair := LexClosure new make.
      LexResults := Array new.
      LexResults add: ((LexPair at: 0) value).
      LexResults add: ((LexPair at: 2) value).
      LexResults add: ((LexPair at: 3) value).
      LexResults
    """)
    check value.toString() == "#(0 2 5)"

  test "an escaped block uses its defining locals instead of invoking method locals":
    let value = evaluate("""
      LexClosure>>makeCounter [| count | count := 10. ^[true ifTrue: [count := count + 1]. count]].
      LexCaller>>invoke: callback [| count values | count := 77. values := Array new.
        values add: callback value. values add: count. ^values].
      LexCounter := LexClosure new makeCounter.
      #((LexCaller new invoke: LexCounter), (LexCaller new invoke: LexCounter))
    """)
    check value.toString() == "#(#(11 77) #(12 77))"
