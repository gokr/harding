# Nimtalk BNF Grammar

This document provides a formal BNF (Backus-Naur Form) grammar for the Nimtalk language, derived from the lexer (`src/nimtalk/parser/lexer.nim`) and parser (`src/nimtalk/parser/parser.nim`) implementations.

## Overview

Nimtalk uses a Smalltalk-style syntax with the following precedence (highest to lowest):
1. Primary expressions (literals, parentheses, blocks)
2. Unary messages (left-to-right)
3. Binary operators (left-to-right)
4. Keyword messages (single message, multiple parts)
5. Cascade (`;` - sends multiple messages to same receiver)

## Lexical Grammar

### Whitespace and Separators

```bnf
<whitespace>   ::= " " | "\t" | <comment>
<newline>      ::= "\n" | "\r" | "\r\n"
<separator>    ::= <newline> | "."
<comment>      ::= "#" <any-char-except-newline>* <newline>
```

### Identifiers and Keywords

```bnf
<identifier>   ::= <letter> <alphanumeric>*
<keyword>      ::= <identifier> ":" (<alphanumeric>+ ":")*
<letter>       ::= "a".."z" | "A".."Z"
<digit>        ::= "0".."9"
<alphanumeric> ::= <letter> | <digit>
```

Keywords are identifiers followed by a colon. Multi-part keywords like `at:put:` are parsed as a single token.

### Literals

```bnf
<literal>      ::= <integer> | <float> | <string> | <symbol> | <array> | <table> | <object>
                 | "true" | "false" | "nil" | "self" | "super"

<integer>      ::= "-"? <digit>+
<float>        ::= "-"? <digit>+ "." <digit>+ (<exponent>)?
                 | "-"? <digit>+ <exponent>
<exponent>     ::= ("e" | "E") ("+" | "-")? <digit>+

<string>       ::= "\"" <string-char>* "\""
                 (* Note: single quotes are reserved for future use *)
<string-char>  ::= <any-char-except-quote> | <escape-sequence>
<escape-seq>   ::= "\\n" | "\\t" | "\\r" | "\\\\" | "\\\""

<symbol>       ::= "#" <identifier>
                 | "#" <keyword>
                 | "#" "\"" <string-content> "\""   (* Symbol with spaces: #"symbol with spaces" *)
```

### Operators and Special Characters

```bnf
<operator>     ::= <binary-op> | <assign-op> | <return-op> | <method-def>
<binary-op>    ::= "+" | "-" | "*" | "/" | "//" | "\\" | "\\"
                 | "=" | "==" | "===" | "~="
                 | "<" | ">" | "<=" | ">="
                 | "," | "%" | "&" | "|"
<assign-op>    ::= ":="
<return-op>    ::= "^"
<method-def>   ::= ">>"
<arrow>        ::= "->"

<lparen>       ::= "("
<rparen>       ::= ")"
<lbracket>     ::= "["
<rbracket>     ::= "]"
<lbrace>       ::= "{"
<rbrace>       ::= "}"
<bar>          ::= "|"
<semicolon>    ::= ";"
<colon>        ::= ":"
<comma>        ::= ","
<period>       ::= "."
```

### Collection Literals

```bnf
<array-start>  ::= "#("
<table-start>  ::= "#{"
<object-start> ::= "{|"
```

### Primitives (Nim Code Embedding)

```bnf
<primitive-start> ::= "<primitive>" <any-char>* "</primitive>"
```

## Syntactic Grammar

### Program Structure

```bnf
<program>      ::= <statement>*
<statements>   ::= <statement> (<separator> <statement>)* <separator>?
```

### Statements

```bnf
<statement>    ::= <assignment>
                 | <return>
                 | <primitive>
                 | <expression>
                 | <method-definition>

<assignment>   ::= <identifier> ":=" <expression>

<return>       ::= "^" <expression>

<primitive>    ::= "<primitive>" <nim-code> "</primitive>" <fallback>?
<fallback>     ::= <statement>*
```

### Method Definitions

```bnf
<method-def>   ::= <receiver> ">>" <selector> <method-body>
<receiver>     ::= <expression>
                 | <expression> "class"   (* for class methods *)
<selector>     ::= <identifier>           (* unary selector *)
                 | <keyword> <param-name> (<keyword> <param-name>)*
                 | <binary-op> <param-name>
<param-name>   ::= <identifier>
<method-body>  ::= <block>
```

The `>>` syntax is syntactic sugar that transforms to: `Receiver selector:put: [body]`

### Expressions

```bnf
<expression>   ::= <primary> <message-chain>?

<message-chain> ::= <unary-chain> <binary-chain>? <keyword-msg>?
                  | <binary-chain> <keyword-msg>?
                  | <keyword-msg>
                  | <cascade>

<unary-chain>  ::= <unary-msg>+
<unary-msg>    ::= <identifier>   (* where first char is lowercase *)

<binary-chain> ::= <binary-op> <primary-unary> (<binary-op> <primary-unary>)*
<primary-unary> ::= <primary> <unary-msg>*

<keyword-msg>  ::= <keyword-segment>+
<keyword-seg>  ::= <keyword> <primary-unary>

<cascade>      ::= <expression> ";" <cascade-msg> (";" <cascade-msg>)*
<cascade-msg>  ::= <unary-msg>
                 | <binary-op> <expression>
                 | <keyword-msg>
```

### Primary Expressions

```bnf
<primary>      ::= <literal>
                 | <identifier>
                 | <pseudo-variable>
                 | <parenthesized>
                 | <block>
                 | <array-literal>
                 | <table-literal>
                 | <object-literal>
                 | <super-send>

<pseudo-var>   ::= "self" | "nil" | "true" | "false" | "super"

<parenthesized> ::= "(" <expression> ")"
```

### Blocks

```bnf
<block>        ::= "[" <block-params>? <block-temps>? <statements> "]"

<block-params> ::= ":" <identifier> (":" <identifier>)* "|"
                 | ":" <identifier> (":" <identifier>)*   (* Nimtalk-style: | optional *)

<block-temps>  ::= "|" <identifier>+ "|"
```

Block syntax variations:
- `[ code ]` - No parameters, no temporaries
- `[ :x | code ]` - One parameter
- `[ :x :y | code ]` - Multiple parameters
- `[ | temp1 temp2 | code ]` - Temporaries only
- `[ :x | temp1 | code ]` - Parameters and temporaries

### Collection Literals

```bnf
<array-literal> ::= "#(" <expression>* ")"

<table-literal> ::= "#{" <table-entry>* "}"
<table-entry>   ::= <expression> "->" <expression> ","?

<object-literal> ::= "{|" <object-slot>* "|}"
<object-slot>    ::= <identifier> ":" <expression>
```

### Super Sends

```bnf
<super-send>   ::= "super" <super-qualifier>? <message>
<super-qual>   ::= "<" <identifier> ">"
<message>      ::= <unary-msg> | <binary-op> <expression> | <keyword-msg>
```

Super sends support qualified syntax: `super<ParentClass> methodName`

## Precedence and Associativity

| Precedence | Construct | Associativity |
|------------|-----------|---------------|
| 1 (highest) | Primary expressions (literals, `()`, blocks) | - |
| 2 | Unary messages | Left-to-right |
| 3 | Binary operators | Left-to-right |
| 4 | Keyword messages | Right-to-left (single message) |
| 5 (lowest) | Cascade (`;`) | Left-to-right |

### Examples of Precedence

```smalltalk
# Unary before binary:
  obj foo + bar    → (obj foo) + bar

# Binary left-to-right:
  a + b * c        → (a + b) * c

# Keyword lowest:
  a + b at: c      → (a + b) at: c

# Cascade applies to result:
  obj foo; bar     → (obj foo); bar (both sent to obj)
```

## Complete Example Parse

```smalltalk
Point>>moveX: dx y: dy [
  x := x + dx.
  y := y + dy.
  ^ self
]
```

Parses as:
```
Message(
  receiver: Point
  selector: "selector:put:"
  arguments: [
    Literal(#moveX:y:)
    Block(
      parameters: ["dx", "dy"]
      body: [
        Assign("x", Message(Ident("x"), "+", [Ident("dx")]))
        Assign("y", Message(Ident("y"), "+", [Ident("dy")]))
        Return(PseudoVar("self"))
      ]
    )
  ]
)
```

## Token to Non-Terminal Mapping

| Token | BNF Non-Terminal |
|-------|------------------|
| `tkIdent` | `<identifier>` |
| `tkKeyword` | `<keyword>` |
| `tkInt` | `<integer>` |
| `tkFloat` | `<float>` |
| `tkString` | `<string>` |
| `tkSymbol` | `<symbol>` |
| `tkArrayStart` | `<array-start>` |
| `tkTableStart` | `<table-start>` |
| `tkObjectStart` | `<object-start>` |
| `tkAssign` | `":="` |
| `tkReturn` | `"^"` |
| `tkMethodDef` | `">>"` |
| `tkArrow` | `"->"` |
| `tkSeparator` | `<separator>` |
| `tkPeriod` | `"."` |
| `tkSpecial` (";", "\|", "{", "}") | `<semicolon>`, `<bar>`, etc. |

## Newline Handling and Statement Separation

Nimtalk takes a pragmatic approach to statement separation that differs from traditional Smalltalk:

### Statement Separators

```bnf
<separator>    ::= <newline> | "."
```

Both periods (`.`) and line endings act as statement separators:

```smalltalk
# Explicit periods (Smalltalk-style)
x := 1.
y := 2.

# Implicit line endings (Nimtalk-style)
x := 1
y := 2

# Mixed style
x := 1.
y := 2
z := 3.
```

### Multiline Keyword Messages

Keyword message chains can span multiple lines while forming a single statement:

```smalltalk
tags isNil
  ifTrue: [ ^ "Object" ]
  ifFalse: [ ^ tags first ]
```

This is parsed as: `tags isNil ifTrue: [...] ifFalse: [...]` - a single statement.

The parser recognizes that a line ending after a keyword argument does not terminate the statement if the next line continues the keyword message chain.

### Where Newlines Are NOT Allowed

| Construct | Multiline? | Example |
|-----------|-----------|---------|
| Binary operators | ❌ No | `x` followed by newline then `+ y` fails |
| Unary message chains | ❌ No | `obj` followed by newline then `msg` fails |
| Method selectors | ❌ No | `Class>>` followed by newline then `selector` fails |
| Keyword message chain | ✅ Yes | `obj msg1: a` followed by newline then `msg2: b` works |
| Statement separator | ✅ Yes | `x := 1` followed by newline then `y := 2` works |

### Examples

```smalltalk
# Valid - keyword message spans lines
result := dictionary
  at: #key
  ifAbsent: [ defaultValue ]

# Invalid - binary operator cannot span lines
result := x
  + y    # This will fail to parse

# Valid - block with temporaries can span lines
[ | temp1 temp2 |
  temp1 := 1.
  temp2 := 2
]
```

### Block Temporaries and Comments

Temporary variables must be declared at the beginning of a block, before any statements:

```smalltalk
# Valid
[ | temp1 temp2 |
  temp1 := 1.
  temp2 := 2
]

# Invalid - string literal before temporaries
[ "some string"
  | temp1 |
  temp1 := 1
]

# Valid - comment after temporaries
[ | temp1 |
  # some comment
  temp1 := 1
]
```

## Notes on Grammar Ambiguity

1. **Keywords vs Identifiers**: An identifier followed by `:` becomes a keyword token. The lexer handles this as a single token (e.g., `at:put:` is one keyword token, not three).

2. **Block Parameters**: The optional `|` in `[:x code]` vs `[:x | code]` is resolved by checking if the next token after parameters is `|` or not.

3. **Temporaries vs Parameters**: When both are present, the pattern is `[:p1 :p2 | t1 t2 | code]`. The parser distinguishes by counting `|` tokens.

4. **Super Send Detection**: The parser looks ahead after `super` to determine if it's a super send (followed by message selector) or just the pseudo-variable.

5. **Method Definition Parsing**: The `>>` token triggers method definition parsing, which expects a selector followed by a block.

6. **Newline as Separator vs Continuation**: The parser uses lookahead to determine if a newline should be a statement separator or if the statement continues (e.g., with another keyword segment).

## Relationship to Implementation

This grammar corresponds to:
- **Lexer**: `src/nimtalk/parser/lexer.nim` - Token production rules
- **Parser**: `src/nimtalk/parser/parser.nim` - Recursive descent implementation
- **AST Types**: `src/nimtalk/core/types.nim` - Node type definitions

The parser uses recursive descent with the following entry points:
- `parseExpression()` - Parses expressions with message chains
- `parsePrimary()` - Parses primary expressions
- `parseBlock()` - Parses block literals
- `parseStatement()` - Parses statements (assignment, return, expression)
- `parseMethodDefinition()` - Parses `>>` syntax
