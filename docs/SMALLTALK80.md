# Nimtalk vs Smalltalk-80 Compatibility Assessment

This document compares Nimtalk's current implementation against the Smalltalk-80 standard library (based on the Xerox PARC Smalltalk-80, version 2, April 1, 1983).

## Overview

Nimtalk is a prototype-based Smalltalk dialect that compiles to Nim. While it captures much of the Smalltalk "feel" with message passing, blocks, and collection protocols, there are significant gaps compared to the full Smalltalk-80 class library.

## What's Already Implemented Well

### Core Collection Protocols
- **Iteration**: `do:`, `collect:`, `select:`, `reject:`, `detect:`, `detect:ifNone:`, `inject:into:`
- **Basic classes**: `Array`, `Table` (Dictionary), `Set`
- **Testing**: `includes:`, `isEmpty`, `notEmpty`, `anySatisfy:`, `allSatisfy:`

### Control Flow
- **Boolean**: `ifTrue:`, `ifFalse:`, `ifTrue:ifFalse:`, `and:`, `or:`, `not`
- **Blocks**: `value`, `value:`, `value:value:`, `value:value:value:`
- **Loops**: `whileTrue:`, `whileFalse:`, `repeat`, `repeat:`, `timesRepeat:`
- **Exceptions**: `on:do:`, `ensure:`, `ifError:`

### Object Primitives
- **Creation**: `derive`, `derive:`, `clone`
- **Properties**: `at:`, `at:put:`, `hasProperty:`, `properties`
- **Introspection**: `respondsTo:`, `methods`, `class`, `isKindOf:`
- **Identity**: `==` (identity), `=` (equality), `~~`, `~=`
- **Utility**: `yourself`, `initialize`, `error:`, `printString`, `asString`

## Key Gaps Compared to Smalltalk-80

### 1. Missing Collection Classes

Smalltalk-80 has a rich, hierarchical collection framework that Nimtalk lacks:

```
Object
  └── Collection (abstract)
       ├── Bag
       ├── Set
       │    └── Dictionary
       ├── MappedCollection
       └── SequenceableCollection (abstract)
            ├── ArrayedCollection (abstract)
            │    ├── Array
            │    ├── ByteArray
            │    ├── String
            │    ├── Text
            │    └── WordArray
            ├── OrderedCollection
            │    └── SortedCollection
            ├── LinkedList
            └── Interval
```

| Class | Purpose | Status |
|-------|---------|--------|
| `OrderedCollection` | Growable array with efficient add/remove at both ends | **Missing** |
| `SortedCollection` | Collection kept in sorted order via sort block | **Missing** |
| `Bag` | Unordered collection counting occurrences of equal objects | **Missing** |
| `Interval` | Represents arithmetic sequences (e.g., 1 to: 100 by: 2) | **Missing** |
| `LinkedList` | Doubly-linked list for efficient insertion/removal | **Missing** |

### 2. Missing Collection Methods

#### Array/SequenceableCollection

| Method | Description | Smalltalk-80 Category |
|--------|-------------|----------------------|
| `atAll:put:` | Set multiple indices to same value | accessing |
| `atAllPut:` | Set all elements to value | accessing |
| `indexOf:` / `indexOf:ifAbsent:` | Find element position | accessing |
| `indexOfSubCollection:startingAt:` | Find subsequence | accessing |
| `indexOfSubCollection:startingAt:ifAbsent:` | Find with default | accessing |
| `replaceFrom:to:with:` | Replace range with elements | accessing |
| `replaceFrom:to:with:startingAt:` | Replace from source | accessing |
| `reverseDo:` | Iterate in reverse | enumerating |
| `with:do:` | Iterate two collections in parallel | enumerating |
| `withIndexDo:` | Iterate with index (essential!) | enumerating |
| `findFirst:` | Find first matching index | enumerating |
| `findLast:` | Find last matching index | enumerating |
| `copyFrom:to:` | Extract sub-collection | copying |
| `copyWith:` | Copy adding element | copying |
| `copyWithout:` | Copy removing element | copying |
| `,` (comma) | Concatenate collections | copying |
| `first` / `last` | Access ends | accessing |

#### Collection (General)

| Method | Description |
|--------|-------------|
| `addAll:` | Add multiple elements |
| `remove:ifAbsent:` | Safe removal with block |
| `removeAll:` | Remove multiple elements |
| `removeAll:` | Remove all in collection |
| `occurrencesOf:` | Count matching elements |
| `asBag` | Convert to Bag |
| `asSet` | Convert to Set |
| `asOrderedCollection` | Convert to OrderedCollection |
| `asSortedCollection` | Convert to SortedCollection |
| `asSortedCollection:` | Convert with custom sort |
| `count:` | Count where block is true |
| `noneSatisfy:` | True if block never true |
| `sum` | Sum elements |
| `max` / `min` | Extremes |

#### Table (Dictionary)

| Method | Description |
|--------|-------------|
| `associationAt:` / `associationAt:ifAbsent:` | Get key-value pair |
| `associations` | Get all associations |
| `associationsDo:` | Iterate over associations |
| `keysDo:` | Iterate only keys |
| `valuesDo:` | Iterate only values |
| `at:ifAbsentPut:` | Get or create pattern |
| `at:ifPresent:` | Conditional access |
| `at:ifPresent:ifAbsent:` | Full conditional access |
| `includes:` | Check for value (not key) |
| `includesKey:` | Check for key (exists) |
| `includesAssociation:` | Check for association |
| `removeKey:ifAbsent:` | Safe key removal |
| `removeAssociation:` / `removeAssociation:ifAbsent:` | Remove by association |
| `add:` | Add an Association |
| `declare:from:` | Transfer from other dictionary |

### 3. Missing Magnitude/Number Methods

Smalltalk-80 uses `Magnitude` as an abstract superclass for comparable objects (Number, Character, String, Date, Time).

#### Magnitude Protocol

| Method | Description |
|--------|-------------|
| `<` | Less than |
| `<=` | Less than or equal |
| `>` | Greater than |
| `>=` | Greater than or equal |
| `between:and:` | Range check (very common idiom!) |
| `min:` | Minimum of two |
| `max:` | Maximum of two |
| `min:max:` | Clamp to range |

#### Number Extensions

| Method | Description |
|--------|-------------|
| `to:` | Create Interval (e.g., `1 to: 10`) |
| `to:by:` | Create Interval with step |
| `to:do:` | Iterate (Nimtalk has this) |
| `to:by:do:` | Iterate with step (Nimtalk has this) |
| `gcd:` | Greatest common divisor |
| `lcm:` | Least common multiple |
| `squared` | Square |
| `cubed` | Cube |
| `reciprocal` | 1/self |
| `sign` | -1, 0, or 1 |
| `strictlyPositive` | > 0 |
| `strictlyNegative` | < 0 |
| `isZero` | = 0 |
| `quo:` | Quotient (truncated division) |
| `rem:` | Remainder (truncated) |
| `//` | Floor division |
| `\\` | Modulo |
| `exp` | e raised to self |
| `ln` | Natural logarithm |
| `log:` | Logarithm to base |
| `raisedTo:` | Power (float exponent) |
| `raisedToInteger:` | Power (integer exponent) |
| `sin` / `cos` / `tan` | Trigonometry |
| `arcSin` / `arcCos` / `arcTan` | Inverse trig |
| `degreesToRadians` | Conversion |
| `radiansToDegrees` | Conversion |
| `random` | Random number |
| `asCharacter` | Convert to Character |
| `asDigit` | Convert to digit character |
| `asPoint` | Convert to Point (x@y) |

### 4. Missing String/Character Methods

#### String

| Method | Description |
|--------|-------------|
| `asNumber` | Parse as number |
| `asCamelCase` | Convert to camelCase |
| `asSnakeCase` | Convert to snake_case |
| `asKebabCase` | Convert to kebab-case |
| `findString:startingAt:` | Search with start position |
| `findTokens:` | Split by delimiters |
| `lineCount` | Count lines |
| `lines` | Split into lines |
| `withIndexDo:` | Iterate with position |
| `sameAs:` | Case-insensitive compare |
| `tr:from:to:` | Character translation |
| `expandMacros` | Template expansion |
| `match:` | Pattern matching |
| `includes:` | Check for substring |

#### Character (Distinct Type)

Smalltalk-80 treats `Character` as a distinct type from `String`. Single characters are not strings.

| Method | Description |
|--------|-------------|
| `asciiValue` | Get ASCII code |
| `asUppercase` / `asLowercase` | Case conversion |
| `asDigit` | Convert to digit value |
| `isAlpha` | Check if letter |
| `isDigit` | Check if digit |
| `isAlphaNumeric` | Check if letter or digit |
| `isSeparator` | Check if whitespace |
| `isVowel` | Check if vowel |
| `digitValue` | Parse digit |

### 5. Missing Stream Classes

Smalltalk-80 has extensive Stream support for I/O:

```
Object
  └── Stream (abstract)
       ├── PositionableStream (abstract)
       │    ├── ReadStream
       │    ├── WriteStream
       │    └── ReadWriteStream
       └── ExternalStream
            └── FileStream
```

#### Key Stream Methods

| Method | Description |
|--------|-------------|
| `next` | Read next element |
| `next:` | Read n elements |
| `nextPut:` | Write element |
| `nextPutAll:` | Write collection |
| `peek` | Look ahead without consuming |
| `atEnd` | Check if exhausted |
| `position` | Get current position |
| `position:` | Set position |
| `reset` | Go to beginning |
| `setToEnd` | Go to end |
| `skip:` | Skip n elements |
| `skipTo:` | Skip until element found |
| `contents` | Get all contents |
| `cr` / `tab` / `space` | Write formatting |
| `print:` | Write printString |
| `store:` | Write storeString |

### 6. Missing Object/Reflection Methods

| Method | Description |
|--------|-------------|
| `species` | Class for creating new instances (Array species -> Array) |
| `copy` | Shallow copy |
| `shallowCopy` | Explicit shallow copy |
| `deepCopy` | Deep copy |
| `postCopy` | Hook for copy customization |
| `hash` | Hash code for Dictionary/Set keys |
| `ifNil:` | Execute block if nil |
| `ifNotNil:` | Execute block if not nil |
| `ifNil:ifNotNil:` | Both branches |
| `isMemberOf:` | Exact class check |
| `perform:with:` | Dynamic dispatch with args |
| `perform:with:with:` | Dynamic dispatch with 2 args |
| `perform:withArguments:` | Dynamic dispatch with array |

### 7. Missing Date/Time Classes

Smalltalk-80 has `Date` and `Time` as subclasses of `Magnitude`:

#### Date

| Method | Description |
|--------|-------------|
| `today` | Today's date |
| `fromDays:` | Create from days since epoch |
| `dayOfWeek` | Day name |
| `dayOfWeekName` | Day name string |
| `dayOfMonth` | Day (1-31) |
| `dayOfYear` | Day (1-366) |
| `month` | Month (1-12) |
| `monthName` | Month name |
| `year` | Year |
| `daysInMonth` | Days in this month |
| `daysInYear` | Days in year |
| `isLeapYear` | Leap year check |
| `addDays:` | Date arithmetic |
| `subtractDays:` | Date arithmetic |
| `subtractDate:` | Days between dates |
| `printFormat:` | Formatting |

#### Time

| Method | Description |
|--------|-------------|
| `now` | Current time |
| `fromSeconds:` | Create from seconds |
| `hours` / `minutes` / `seconds` | Components |
| `milliseconds` | Milliseconds |
| `addTime:` | Time arithmetic |
| `subtractTime:` | Time arithmetic |

## Priority Recommendations

### High Priority (Essential for Smalltalk "Feel")

1. **`withIndexDo:`** on Array - Essential for indexed iteration
   ```smalltalk
   #('a' 'b' 'c') withIndexDo: [ :each :index |
     (index printString , ': ' , each) print ]
   ```

2. **`OrderedCollection`** - Growable arrays are fundamental
   - `add:`, `addFirst:`, `addLast:`, `addAll:`
   - `removeFirst`, `removeLast`, `remove:ifAbsent:`
   - Grows automatically, unlike fixed-size Array

3. **`at:ifAbsent:`** and **`at:ifAbsentPut:`** on Table
   ```smalltalk
   table at: key ifAbsent: [ default ].
   table at: key ifAbsentPut: [ computeValue ].
   ```

4. **`between:and:`** on Number - Very common Smalltalk idiom
   ```smalltalk
   (x between: 1 and: 10) ifTrue: [ ... ]
   ```

5. **`species`** - Required for Collection methods that create new collections
   - Ensures `collect:` returns same collection type

6. **`copyFrom:to:`** - Sub-collection extraction
   ```smalltalk
   array copyFrom: 2 to: 5
   ```

### Medium Priority

1. **`SortedCollection`** with configurable sort blocks
   ```smalltalk
   SortedCollection sortBlock: [ :a :b | a > b ]
   ```

2. **`Bag`** for counting occurrences
   ```smalltalk
   bag add: 'apple' withOccurrences: 3.
   bag occurrencesOf: 'apple'  "-> 3"
   ```

3. **`Interval`** to replace `to:do:` with collection iteration
   ```smalltalk
   (1 to: 10 by: 2) do: [ :i | i print ]
   (1 to: 10) select: [ :i | i even ]
   ```

4. **Stream hierarchy** for I/O
   - `ReadStream`, `WriteStream` on strings and arrays
   - `next`, `nextPut:`, `peek`, `atEnd`

5. **`with:do:`** for parallel iteration
   ```smalltalk
   arr1 with: arr2 do: [ :a :b | ... ]
   ```

6. **`hash`** method on Object
   - Required for proper Dictionary/Set operation

### Lower Priority

1. **Character as distinct type** - Currently use single-char strings
2. **Date/Time classes** - Can use Nim FFI initially
3. **Trigonometric and advanced math** - Can delegate to Nim
4. **String case conversion variants** - Modern convenience
5. **LinkedList** - Less commonly used
6. **MappedCollection** - View onto another collection

## Implementation Notes

### Prototype vs Class Model

Smalltalk-80 is class-based with metaclasses. Nimtalk is prototype-based. Some adaptations:

- `species` in Smalltalk returns a class; in Nimtalk it could return a prototype object
- Class methods become constructor methods on prototypes
- Instance variables become object properties

### Collection Creation Patterns

Smalltalk-80 uses class methods for creation:
```smalltalk
Array with: 1 with: 2 with: 3.
OrderedCollection new: 10.
```

Nimtalk can use:
```smalltalk
Array with: 1 with: 2 with: 3.
OrderedCollection new: 10.
#(1 2 3) asOrderedCollection.
```

### Nil Handling

Smalltalk-80 uses `nil` as the default value and has explicit nil testing:
```smalltalk
obj ifNil: [ ... ] ifNotNil: [ :val | ... ].
```

Nimtalk should add these for compatibility.

## References

- Smalltalk-80 sources: `../smalltalk-80-sources/assets/Smalltalk-80.sources`
- Blue Book: http://www.mirandabanda.org/bluebook/bluebook_imp_toc.html
- "Smalltalk-80: The Language and its Implementation" by Goldberg and Robson
