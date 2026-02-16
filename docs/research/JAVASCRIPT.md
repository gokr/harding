# JavaScript Compilation for Harding

## Overview

This document describes the effort to compile the Harding interpreter to JavaScript using Nim's JS backend. The goal is to embed a working REPL in a web browser, allowing users to experiment with Harding without installing the native interpreter.

## Current Status

**Status**: Partially working - core primitives work, but library-defined methods fail.

### What Works

- **JavaScript build**: Successfully compiles to `website/dist/harding.js` (~74,000 lines)
- **Arithmetic**: `3 + 4`, `10 - 5`, `3 * 4`, `12 / 3` all return correct values
- **Comparisons**: `3 < 5`, `3 = 3`, `5 > 3` work correctly
- **Output**: `"Hello" println` outputs to console
- **Class introspection**: `3 class` returns `<class Integer>`
- **Module exports**: JavaScript can call `Harding.doit(code)` to evaluate Harding code

### What's Broken

- **String methods from library**: `"/Hello/" , "/World/"` fails with "Method not found: , on String"
- **Collection methods**: Array and Table methods defined in `.hrd` library files don't dispatch
- **Library-loaded methods**: Methods like `size`, `at:`, `indexOf:` defined in `String.hrd` aren't found

## Technical Implementation

### JS Primitive Dispatcher

Since function pointers don't work in JavaScript, we implemented a selector-based dispatch system:

```nim
# In src/harding/interpreter/vm.nim
when defined(js):
  proc dispatchPrimitive(interp: var Interpreter, receiver: Instance,
                        selector: string, args: seq[NodeValue]): NodeValue =
    case selector
    of "+": return plusImpl(receiver, args)
    of "-": return minusImpl(receiver, args)
    of ",": return stringConcatImpl(receiver, args)
    of "size": return sizeImpl(receiver, args)
    # ... etc
```

### Conditional Compilation

Pointer types had to be made conditional for JS builds:

```nim
# In src/harding/core/types.nim
when defined(js):
  nimValue*: int        # Dummy for JS
else:
  nimValue*: pointer    # Real pointer for native
```

### Embedded Libraries

Library files are embedded at compile time using `staticRead`:

```nim
# In src/harding/repl/jslib.nim
const EmbeddedObjectHrd = staticRead("../../../lib/core/Object.hrd")
const EmbeddedStringHrd = staticRead("../../../lib/core/String.hrd")
# ... etc
```

### JS Dispatch in VM

The stackless VM's message send handler tries JS dispatch before interpreted execution:

```nim
# In wfSendMessage handler
when defined(js):
  let primResult = dispatchPrimitive(interp, receiver, frame.selector, args)
  if primResult.kind != vkNil:
    interp.pushValue(primResult)
    return true
```

## Current Blocker

The fundamental issue is that methods defined in library files (`.hrd`) aren't dispatching correctly:

1. **Library files load**: The embedded `String.hrd` is evaluated during initialization
2. **Methods get registered**: `String>>, other` should add the `,` method to String
3. **Method lookup finds them**: The class's `allMethods` table contains the selector
4. **But dispatch fails**: The JS dispatch in `wfSendMessage` isn't reached, or returns nil

When you try `"/Hello/" , "/World/"`, the interpreter reports:
```
Method not found: , on String
```

Even though:
- The dispatch has `of ","` handler
- The dispatch has `of "primitiveConcat:"` alias
- The library file defines this method

The issue appears to be that methods loaded from library files have `nativeImpl = 0` (for JS), so `nativeImplIsSet()` returns false, but the JS dispatch after method lookup isn't being reached or isn't recognizing these as primitives.

## Files Modified

- `src/harding/core/types.nim` - Conditional pointer fields
- `src/harding/interpreter/vm.nim` - JS primitive dispatcher, stackless VM JS dispatch
- `src/harding/repl/hardingjs.nim` - JS entry point with exports
- `src/harding/repl/jslib.nim` - Embedded library loader
- `src/harding/parser/parser.nim` - Added `BinaryOpTokens` constant

## Building

```bash
# Build the JavaScript version
nim js -d:js -o:website/dist/harding.js src/harding/repl/hardingjs.nim

# Or use nimble task (if defined)
nimble js
```

## Testing with Node.js

```javascript
const vm = require('./website/dist/harding.js');

// Test arithmetic (works)
console.log(vm.doit('3 + 4'));        // "7"

// Test println (works)
vm.doit('"Hello" println');          // outputs: Hello

// Test string concat (broken)
console.log(vm.doit('"/a/" , "/b/"'));  // Error: Method not found: , on String
```

## Potential Solutions

1. **Ensure library methods dispatch**: Debug why the JS dispatch in `wfSendMessage` isn't reached for library-loaded methods

2. **Pre-register all primitives**: Instead of relying on library files, register all String/Array/Table primitives directly in `dispatchPrimitive` during `initCoreClasses`

3. **Separate native/JS method tables**: Have different method lookup paths for JS that don't check `nativeImpl` at all

4. **Compile-time method registration**: Use Nim macros to generate the dispatch table at compile time based on what's in the library files

## Resources

- Nim JavaScript backend documentation: https://nim-lang.org/docs/backends.html#backends-the-javascript-target
- Current JS build: `website/dist/harding.js` (when built)
- Test page: `website/index.html` (uses `website/dist/script.js`)
