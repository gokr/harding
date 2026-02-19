import std/[tables, strutils, sequtils, math, hashes, logging]
import ../core/types

# ============================================================================
# Platform-Specific Helpers
# ============================================================================

template setNativeImpl*(meth: BlockNode, impl: untyped) =
  ## Set native implementation for native builds
  meth.nativeImpl = cast[pointer](impl)

# ============================================================================
# Object System for Harding
# Class-based objects with delegation/inheritance
# ============================================================================
#
# DESIGN NOTE: Core Class Initialization
# --------------------------------------
# Core classes are created in TWO phases to avoid circular dependencies:
#
# Phase 1 - initCoreClasses() (in this file):
#   - Creates the class hierarchy (Root -> Object -> Integer/Float/String/Array/Table/Block)
#   - Registers class methods (new, derive:, selector:put:, etc.)
#   - Registers basic instance methods
#
# Phase 2 - initGlobals() (in vm.nim):
#   - Adds primitive methods that need evaluator context
#   - MUST reuse existing classes via: if arrayClass != nil: arrayCls = arrayClass
#
# IMPORTANT: hasInterpreterParam
# ------------------------------
# When registering native methods, the proc signature MUST match hasInterpreterParam:
#
#   hasInterpreterParam = false:
#     proc myMethod(self: Instance, args: seq[NodeValue]): NodeValue
#
#   hasInterpreterParam = true:
#     proc myMethod(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue
#
# MISMATCH causes calling convention errors (wrong return values, crashes).
# Use registerInstanceMethod/registerClassMethod templates for automatic detection.
#

# Forward declarations for core method implementations (exported for testing)
proc plusImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc minusImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc starImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc slashImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc sqrtImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc ltImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc gtImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc eqImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc leImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc geImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc neImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc intDivImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc backslashModuloImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc moduloImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc printStringImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc writeImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc writelineImpl*(self: Instance, args: seq[NodeValue]): NodeValue

# Collection primitives
# Note: arrayNewImpl is defined later in the file to avoid forward declaration issues
proc arraySizeImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc arrayAddImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc arrayRemoveAtImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc arrayIncludesImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc arrayReverseImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc arrayAtImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc arrayAtPutImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc arrayJoinImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc tableNewImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc tableKeysImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc tableIncludesKeyImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc tableRemoveKeyImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc tableAtImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc tableAtPutImpl*(self: Instance, args: seq[NodeValue]): NodeValue
# Set primitives (Instance-based)
proc primitiveSetNewImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc primitiveSetAddImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc primitiveSetRemoveImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc primitiveSetIncludesImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc primitiveSetSizeImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc primitiveSetUnionImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc primitiveSetIntersectionImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc primitiveSetDifferenceImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc primitiveSetKeysImpl*(self: Instance, args: seq[NodeValue]): NodeValue
# Library primitives (Instance-based)
proc libraryNewImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc libraryAtImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc libraryAtPutImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc libraryKeysImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc libraryIncludesKeyImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc libraryNameImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc libraryNameSetImpl*(self: Instance, args: seq[NodeValue]): NodeValue
# String primitives (Instance-based)
proc instStringConcatImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc instStringSizeImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc instStringAtImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc instStringFromToImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc instStringIndexOfImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc instStringIncludesSubStringImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc instStringReplaceWithImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc instStringUppercaseImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc instStringLowercaseImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc instStringTrimImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc instStringSplitImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc instStringAsIntegerImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc instStringAsSymbolImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc instStringRepeatImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc classImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc instIdentityImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc instanceCloneImpl*(self: Instance, args: seq[NodeValue]): NodeValue

# Class derivation methods
proc classDeriveWithAccessorsImpl*(self: Class, args: seq[NodeValue]): NodeValue
proc classDeriveGettersSettersImpl*(self: Class, args: seq[NodeValue]): NodeValue

# Slot accessors are implemented in vm.nim to avoid circular import

# ============================================================================
# Helper: Extract integer value from NodeValue or wrapped object
# ============================================================================

proc tryGetInt*(value: NodeValue): (bool, int) =
  ## Try to extract an integer from a NodeValue
  ## Returns (true, value) if successful, (false, 0) otherwise
  case value.kind
  of vkInt:
    return (true, value.intVal)
  of vkInstance:
    if value.instVal.kind == ikInt:
      return (true, value.instVal.intVal)
  else:
    discard
  return (false, 0)

proc tryGetFloat*(value: NodeValue): (bool, float) =
  ## Try to extract a float from a NodeValue
  ## Returns (true, value) if successful, (false, 0.0) otherwise
  case value.kind
  of vkFloat:
    return (true, value.floatVal)
  of vkInstance:
    if value.instVal.kind == ikFloat:
      return (true, value.instVal.floatVal)
    elif value.instVal.kind == ikInt:
      # Allow automatic promotion of integer to float
      return (true, value.instVal.intVal.float)
  of vkInt:
    # Allow automatic promotion of integer to float
    return (true, value.intVal.float)
  else:
    discard
  return (false, 0.0)

# ============================================================================
# Object System
# ============================================================================

# Forward declarations for class-based methods
proc classDeriveImpl*(self: Class, args: seq[NodeValue]): NodeValue
proc classDeriveParentsSlotsMethodsImpl*(self: Class, args: seq[NodeValue]): NodeValue
proc classDeriveParentsSlotsGettersSettersMethodsImpl*(self: Class, args: seq[NodeValue]): NodeValue
proc classNewImpl*(self: Class, args: seq[NodeValue]): NodeValue
proc classAddMethodImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue
proc classAddClassMethodImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue
proc classParentsImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc classSlotsImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc classGettersImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc classSettersImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc classMethodsImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc invalidateSubclasses*(cls: Class)
proc rebuildAllTables*(cls: Class)
proc registerPrimitivesOnObjectClass*(objCls: Class)
proc primitiveCloneImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc primitiveAtImpl*(self: Instance, args: seq[NodeValue]): NodeValue
proc primitiveAtPutImpl*(self: Instance, args: seq[NodeValue]): NodeValue

# Global true/false values for comparison operators
var trueValue*: NodeValue = NodeValue(kind: vkBool, boolVal: true)
var falseValue*: NodeValue = NodeValue(kind: vkBool, boolVal: false)

# Class caches for wrapped primitives (set by loadStdlib)
# These reference the new Class-based system
var booleanClassCache*: Class = nil
var trueClassCache*: Class = nil
var falseClassCache*: Class = nil
var numberClassCache*: Class = nil
var integerClassCache*: Class = nil
var stringClassCache*: Class = nil
var symbolClassCache*: Class = nil
var arrayClassCache*: Class = nil
var tableClassCache*: Class = nil
var blockClassCache*: Class = nil

# Scheduler-related classes (set by scheduler module)
var processClass*: Class = nil
var schedulerClass*: Class = nil

# Create a core method


proc createCoreMethod*(name: string): BlockNode =
  ## Create a method stub
  let blk = BlockNode()
  blk.parameters = if ':' in name:
                      name.split(':').filterIt(it.len > 0)
                    elif name in ["+", "-", "*", "/", "//", ">", "<", ">=", "<=", "=", "==", "!=", ",", "**"]:
                      # Binary operators take one argument (the receiver is implicit)
                      @["arg"]
                    else:
                      @[]
  blk.temporaries = @[]
  let placeholder: Node = LiteralNode(value: NodeValue(kind: vkNil))  # Placeholder
  blk.body = @[placeholder]
  blk.isMethod = true
  blk.nativeImpl = nil
  blk.capturedEnv = initTable[string, MutableCell]()
  blk.capturedEnvInitialized = true
  return blk

# Global namespace for storing "classes" and constants
var globals*: Table[string, NodeValue]

# Initialize global namespace
proc initGlobals*() =
  ## Initialize the globals table for storing classes and constants
  if globals.len == 0:
    globals = initTable[string, NodeValue]()

# Add a value to globals (typically a "class")
proc addGlobal*(name: string, value: NodeValue) =
  ## Add a global binding (e.g., Person := Object derive)
  globals[name] = value

# Get a value from globals
proc getGlobal*(name: string): NodeValue =
  ## Get a global binding, return nil if not found
  if globals.hasKey(name):
    return globals[name]
  else:
    return nilValue()

# Check if a global exists
proc hasGlobal*(name: string): bool =
  ## Check if a global binding exists
  return globals.hasKey(name)

# Remove a global
proc removeGlobal*(name: string) =
  ## Remove a global binding
  if globals.hasKey(name):
    globals.del(name)

# Get all global names
proc globalNames*(): seq[string] =
  ## Return all global names
  return toSeq(globals.keys)

# Forward declarations for primitive implementations (all Instance-based now)
proc doesNotUnderstandImpl*(self: Instance, args: seq[NodeValue]): NodeValue

# Build inheritance chain for a class (self first, then parents in DFS order)
proc inheritanceChain*(cls: Class): seq[Class] =
  result = @[cls]
  for parent in cls.superclasses:
    result.add(parent.inheritanceChain())

# Helper for NodeValue equality
proc valuesEqual*(a, b: NodeValue): bool =
  if a.kind != b.kind:
    return false
  case a.kind
  of vkInt: return a.intVal == b.intVal
  of vkFloat: return a.floatVal == b.floatVal
  of vkString: return a.strVal == b.strVal
  of vkSymbol: return a.symVal == b.symVal
  of vkBool: return a.boolVal == b.boolVal
  of vkNil: return true
  of vkBlock: return cast[int](a.blockVal) == cast[int](b.blockVal)
  of vkInstance: return unsafeAddr(a.instVal) == unsafeAddr(b.instVal)
  of vkArray:
    if a.arrayVal.len != b.arrayVal.len: return false
    for i in 0..<a.arrayVal.len:
      if not valuesEqual(a.arrayVal[i], b.arrayVal[i]): return false
    return true
  of vkTable:
    if a.tableVal.len != b.tableVal.len: return false
    for k, v in a.tableVal:
      if k notin b.tableVal or not valuesEqual(v, b.tableVal[k]): return false
    return true
  of vkClass: return unsafeAddr(a.classVal) == unsafeAddr(b.classVal)

# Helper to recursively rebuild all descendants
proc rebuildAllDescendants*(cls: Class) =
  ## Rebuild this class and all its descendants (in order: self first, then descendants)
  rebuildAllTables(cls)
  for subclass in cls.subclasses:
    rebuildAllDescendants(subclass)

# Forward declaration for slot access rewriter (defined below)
proc rewriteMethodForSlotAccess*(blk: BlockNode, cls: Class)

# Helper to add method to class
proc addMethodToClass*(cls: Class, selector: string, meth: BlockNode, isClassMethod: bool = false, deferRebuild: bool = false) =
  ## Add a method to a class (instance or class method)
  ## If deferRebuild is true, mark class as dirty instead of immediate rebuild
  ## Use deferRebuild=true when batch loading methods, then call finalizeClass() after
  # Mark block as a method so return (^) has correct semantics
  meth.isMethod = true
  meth.selector = selector  # Store the selector for later lookup
  if isClassMethod:
    cls.classMethods[selector] = meth
  else:
    cls.methods[selector] = meth
    # Rewrite slot accesses to use O(1) index instead of string lookup
    if cls.allSlotNames.len > 0:
      rewriteMethodForSlotAccess(meth, cls)

  # Bump version to invalidate inline caches referencing this class
  cls.version += 1

  # Mark as dirty for lazy rebuilding, or rebuild immediately
  if deferRebuild:
    cls.methodsDirty = true
    # Propagate dirty flag to all descendants
    for subclass in cls.subclasses:
      subclass.methodsDirty = true
  else:
    # Rebuild all method tables for this class and all descendants immediately
    rebuildAllDescendants(cls)

proc finalizeClass*(cls: Class) =
  ## Finalize a class after batch method loading - rebuilds method tables if dirty
  if cls.methodsDirty:
    rebuildAllDescendants(cls)
    cls.methodsDirty = false

proc rebuildAllMethodTables*() =
  ## Rebuild all method tables for all known classes
  ## Useful after batch loading or when explicit synchronization is needed
  ## Starts from root classes and rebuilds entire hierarchies
  if rootClass != nil:
    rebuildAllDescendants(rootClass)
  # Also rebuild Object hierarchy if different from Root
  if objectClass != nil and objectClass != rootClass:
    rebuildAllDescendants(objectClass)

# ============================================================================
# AST Rewriter for Slot Access
# Rewrites IdentNodes to SlotAccessNodes where name matches a class slot
# This enables O(1) slot access by integer index instead of string lookup
# ============================================================================

proc rewriteNodeForSlotAccess(node: Node, cls: Class, shadowedNames: seq[string]): Node =
  ## Recursively rewrite a node, replacing slot access patterns with SlotAccessNodes
  ## shadowedNames contains parameter and temporary names that shadow slots
  if node == nil:
    return nil

  case node.kind
  of nkIdent:
    # Check if this identifier is a slot name (and not shadowed)
    let ident = cast[IdentNode](node)
    debug("rewriteNode: nkIdent name=", ident.name)
    if ident.name notin shadowedNames:
      let idx = cls.getSlotIndex(ident.name)
      debug("rewriteNode: slot lookup for '", ident.name, "' = ", $idx)
      if idx >= 0:
        # Replace with SlotAccessNode for O(1) access
        debug("rewriteNode: replacing ident '", ident.name, "' with SlotAccessNode index=", $idx)
        return SlotAccessNode(
          slotName: ident.name,
          slotIndex: idx,
          isAssignment: false,
          valueExpr: nil
        )
    return node

  of nkAssign:
    # Check if assignment target is a slot name
    let assign = cast[AssignNode](node)
    debug("rewriteNode: nkAssign var=", assign.variable)
    if assign.variable notin shadowedNames:
      let idx = cls.getSlotIndex(assign.variable)
      debug("rewriteNode: slot lookup for assignment '", assign.variable, "' = ", $idx)
      if idx >= 0:
        # Replace with SlotAccessNode for O(1) slot write
        debug("rewriteNode: replacing assignment '", assign.variable, "' with SlotAccessNode index=", $idx)
        return SlotAccessNode(
          slotName: assign.variable,
          slotIndex: idx,
          isAssignment: true,
          valueExpr: rewriteNodeForSlotAccess(assign.expression, cls, shadowedNames)
        )
    # Not a slot - rewrite the expression part only
    assign.expression = rewriteNodeForSlotAccess(assign.expression, cls, shadowedNames)
    return assign

  of nkMessage:
    # Rewrite receiver and arguments
    let msg = cast[MessageNode](node)
    if msg.receiver != nil:
      msg.receiver = rewriteNodeForSlotAccess(msg.receiver, cls, shadowedNames)
    for i in 0..<msg.arguments.len:
      msg.arguments[i] = rewriteNodeForSlotAccess(msg.arguments[i], cls, shadowedNames)
    return msg

  of nkReturn:
    # Rewrite return expression
    let ret = cast[ReturnNode](node)
    if ret.expression != nil:
      ret.expression = rewriteNodeForSlotAccess(ret.expression, cls, shadowedNames)
    return ret

  of nkBlock:
    # Rewrite block body, but add block's parameters and temporaries to shadowed names
    let blk = cast[BlockNode](node)
    var newShadowed = shadowedNames
    for param in blk.parameters:
      newShadowed.add(param)
    for temp in blk.temporaries:
      newShadowed.add(temp)
    for i in 0..<blk.body.len:
      blk.body[i] = rewriteNodeForSlotAccess(blk.body[i], cls, newShadowed)
    return blk

  of nkCascade:
    # Rewrite cascade receiver and all messages
    let cascade = cast[CascadeNode](node)
    if cascade.receiver != nil:
      cascade.receiver = rewriteNodeForSlotAccess(cascade.receiver, cls, shadowedNames)
    for i in 0..<cascade.messages.len:
      let msg = cascade.messages[i]
      for j in 0..<msg.arguments.len:
        msg.arguments[j] = rewriteNodeForSlotAccess(msg.arguments[j], cls, shadowedNames)
    return cascade

  of nkPrimitiveCall:
    # Rewrite primitive arguments
    let prim = cast[PrimitiveCallNode](node)
    for i in 0..<prim.arguments.len:
      prim.arguments[i] = rewriteNodeForSlotAccess(prim.arguments[i], cls, shadowedNames)
    return prim

  of nkSuperSend:
    # Rewrite super send arguments
    let superNode = cast[SuperSendNode](node)
    for i in 0..<superNode.arguments.len:
      superNode.arguments[i] = rewriteNodeForSlotAccess(superNode.arguments[i], cls, shadowedNames)
    return superNode

  of nkArray:
    # Rewrite array elements
    let arr = cast[ArrayNode](node)
    for i in 0..<arr.elements.len:
      arr.elements[i] = rewriteNodeForSlotAccess(arr.elements[i], cls, shadowedNames)
    return arr

  of nkTable:
    # Rewrite table entries
    let tbl = cast[TableNode](node)
    for i in 0..<tbl.entries.len:
      let (key, value) = tbl.entries[i]
      tbl.entries[i] = (
        rewriteNodeForSlotAccess(key, cls, shadowedNames),
        rewriteNodeForSlotAccess(value, cls, shadowedNames)
      )
    return tbl

  else:
    # Other node types don't need rewriting (literals, pseudo-vars, etc.)
    return node

proc rewriteMethodForSlotAccess*(blk: BlockNode, cls: Class) =
  ## Rewrite a method's AST to use SlotAccessNodes for slot access
  ## Called when a method is installed on a class via selector:put:
  debug("rewriteMethodForSlotAccess: class=", cls.name, " slots=", $cls.allSlotNames)
  if cls.allSlotNames.len == 0:
    debug("rewriteMethodForSlotAccess: no slots, skipping")
    return  # No slots to optimize

  # Slots are optimized - shadowing is handled by the rewriting logic

  # Build initial shadowed names from method parameters and temporaries
  var shadowedNames: seq[string] = @[]
  for param in blk.parameters:
    shadowedNames.add(param)
  for temp in blk.temporaries:
    shadowedNames.add(temp)
  debug("rewriteMethodForSlotAccess: shadowedNames=", $shadowedNames)

  # Rewrite the method body
  for i in 0..<blk.body.len:
    blk.body[i] = rewriteNodeForSlotAccess(blk.body[i], cls, shadowedNames)
  debug("rewriteMethodForSlotAccess: done")

# ============================================================================
# Type-safe native method registration
# ============================================================================

template registerInstanceMethod*(cls: Class, selector: string, procName: typed) =
  ## Register an instance method with automatic hasInterpreterParam detection.
  ## The proc signature determines if interpreter param is needed:
  ##   proc(self: Instance, args: seq[NodeValue]) - no interpreter
  ##   proc(interp: var Interpreter, self: Instance, args: seq[NodeValue]) - with interpreter
  block:
    let meth = createCoreMethod(selector)
    meth.setNativeImpl(procName)
    # Auto-detect based on proc arity using type introspection
    when compiles(procName(default(Interpreter), default(Instance), default(seq[NodeValue]))):
      meth.hasInterpreterParam = true
    else:
      meth.hasInterpreterParam = false
    addMethodToClass(cls, selector, meth, isClassMethod = false)

template registerClassMethod*(cls: Class, selector: string, procName: typed) =
  ## Register a class method with automatic hasInterpreterParam detection.
  block:
    let meth = createCoreMethod(selector)
    meth.setNativeImpl(procName)
    when compiles(procName(default(Interpreter), default(Instance), default(seq[NodeValue]))):
      meth.hasInterpreterParam = true
    else:
      meth.hasInterpreterParam = false
    addMethodToClass(cls, selector, meth, isClassMethod = true)

# ============================================================================
# Array class method implementation (must be defined before initCoreClasses)
# ============================================================================
proc arrayNewImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Create new array (class method)
  var elements: seq[NodeValue] = @[]
  if args.len > 0:
    let (ok, val) = args[0].tryGetInt()
    if ok:
      for i in 0..<val:
        elements.add(nilValue())
  let inst = newArrayInstance(arrayClass, elements)
  return NodeValue(kind: vkInstance, instVal: inst)

# ============================================================================
# Core Classes Initialization
# ============================================================================

proc initCoreClasses*(): Class =
  ## Initialize the core class hierarchy:
  ##   Root (empty - for DNU proxies)
  ##     └── Object (core methods)
  ##           ├── Integer
  ##           ├── Float
  ##           ├── String
  ##           ├── Array
  ##           ├── Table
  ##           └── Block
  ##
  ## Methods are defined in .hrd files using <primitive selector> syntax.
  ## This procedure only creates the classes for bootstrapping.
  ##
  ## Returns objectClass for convenience.

  # Initialize symbol table and globals first
  initSymbolTable()
  initGlobals()

  # Create Root class (empty - for DNU proxies/wrappers)
  discard initRootClass()

  # Create Object class (inherits from Root)
  # Core bootstrap methods are registered here; other methods are in lib/core/Object.hrd
  if objectClass == nil:
    objectClass = initObjectClass()

    # Bootstrap methods needed for .hrd files to define other methods
    # selector:put: - for defining instance methods (used by >> syntax)
    let selectorPutMethod = createCoreMethod("selector:put:")
    selectorPutMethod.hasInterpreterParam = true
    selectorPutMethod.setNativeImpl(classAddMethodImpl)
    addMethodToClass(objectClass, "selector:put:", selectorPutMethod, isClassMethod = true)

    # classSelector:put: - for defining class methods (used by class>> syntax)
    let classSelectorPutMethod = createCoreMethod("classSelector:put:")
    classSelectorPutMethod.hasInterpreterParam = true
    classSelectorPutMethod.setNativeImpl(classAddClassMethodImpl)
    addMethodToClass(objectClass, "classSelector:put:", classSelectorPutMethod, isClassMethod = true)

    # derive: - create class with slots (no accessors, use deriveWithAccessors: for that)
    let deriveWithSlotsMethod = createCoreMethod("derive:")
    deriveWithSlotsMethod.setNativeImpl(classDeriveImpl)
    addMethodToClass(objectClass, "derive:", deriveWithSlotsMethod, isClassMethod = true)

    # deriveWithAccessors: - create class with slots and auto-generate accessors
    let deriveWithAccessorsMethod = createCoreMethod("deriveWithAccessors:")
    deriveWithAccessorsMethod.setNativeImpl(classDeriveWithAccessorsImpl)
    addMethodToClass(objectClass, "deriveWithAccessors:", deriveWithAccessorsMethod, isClassMethod = true)

    # derive:getters:setters: - create class with slots and selective accessor generation
    let deriveGettersSettersMethod = createCoreMethod("derive:getters:setters:")
    deriveGettersSettersMethod.setNativeImpl(classDeriveGettersSettersImpl)
    addMethodToClass(objectClass, "derive:getters:setters:", deriveGettersSettersMethod, isClassMethod = true)

    # derive - create class without slots
    let deriveMethod = createCoreMethod("derive")
    deriveMethod.setNativeImpl(classDeriveImpl)
    addMethodToClass(objectClass, "derive", deriveMethod, isClassMethod = true)

    # new - create instances (initialization is done via Harding code: ^self basicNew initialize)
    let newMethod = createCoreMethod("new")
    newMethod.setNativeImpl(classNewImpl)
    addMethodToClass(objectClass, "new", newMethod, isClassMethod = true)

    # Note: Instance methods (clone, at:, at:put:) are now defined in lib/core/Object.hrd
    # using <primitive> syntax. The primitive selectors are registered by
    # registerPrimitivesOnObjectClass() at the end of initCoreClasses().

    addGlobal("Object", NodeValue(kind: vkClass, classVal: objectClass))

  # Create Integer class
  # Methods are defined in lib/core/Integer.hrd using <primitive> syntax
  if integerClass == nil:
    integerClass = newClass(superclasses = @[objectClass], name = "Integer")
    integerClass.tags = @["Integer", "Number"]
    addGlobal("Integer", NodeValue(kind: vkClass, classVal: integerClass))

  # Create Float class
  # Methods are defined in lib/core/Float.hrd using <primitive> syntax
  if floatClass == nil:
    floatClass = newClass(superclasses = @[objectClass], name = "Float")
    floatClass.tags = @["Float", "Number"]
    addGlobal("Float", NodeValue(kind: vkClass, classVal: floatClass))

  # Create String class
  # Methods are defined in lib/core/String.hrd using <primitive> syntax
  if stringClass == nil:
    stringClass = newClass(superclasses = @[objectClass], name = "String")
    stringClass.tags = @["String"]
    addGlobal("String", NodeValue(kind: vkClass, classVal: stringClass))

  # Create Array class
  # Methods are defined in lib/core/Array.hrd using <primitive> syntax
  if arrayClass == nil:
    arrayClass = newClass(superclasses = @[objectClass], name = "Array")
    arrayClass.tags = @["Array", "Collection"]
    addGlobal("Array", NodeValue(kind: vkClass, classVal: arrayClass))

  # Create Table class
  # Methods are defined in lib/core/Table.hrd using <primitive> syntax
  if tableClass == nil:
    tableClass = newClass(superclasses = @[objectClass], name = "Table")
    tableClass.tags = @["Table", "Collection", "Dictionary"]
    addGlobal("Table", NodeValue(kind: vkClass, classVal: tableClass))

  # Create Library class (composition: ikObject with bindings Table slot)
  # Methods are defined in .hrd files using <primitive> syntax
  if libraryClass == nil:
    libraryClass = newClass(superclasses = @[objectClass],
                            slotNames = @["bindings", "imports", "name"],
                            name = "Library")
    libraryClass.tags = @["Library", "Namespace"]
    addGlobal("Library", NodeValue(kind: vkClass, classVal: libraryClass))

  # Create Set class (using a Table internally for element storage)
  # Methods are defined in lib/core/Collections.hrd using <primitive> syntax
  if setClass == nil:
    setClass = newClass(superclasses = @[objectClass], name = "Set")
    setClass.tags = @["Set", "Collection"]
    # Note: Set primitives like primitiveSetNew, primitiveSetAdd: etc.
    # are registered in vm.nim initGlobals() for use by Collections.hrd

  # Create Block class
  if blockClass == nil:
    blockClass = newClass(superclasses = @[objectClass], name = "Block")
    blockClass.tags = @["Block", "Closure"]

    addGlobal("Block", NodeValue(kind: vkClass, classVal: blockClass))

  # Create Boolean class (parent for True and False)
  if booleanClass == nil:
    booleanClass = newClass(superclasses = @[objectClass], name = "Boolean")
    booleanClass.tags = @["Boolean"]

    addGlobal("Boolean", NodeValue(kind: vkClass, classVal: booleanClass))

  # Also ensure the type module globals point to our classes
  types.objectClass = objectClass
  types.integerClass = integerClass
  types.floatClass = floatClass
  types.stringClass = stringClass
  types.arrayClass = arrayClass
  types.tableClass = tableClass
  types.blockClass = blockClass
  types.booleanClass = booleanClass
  types.libraryClass = libraryClass
  types.setClass = setClass

  # Register primitive methods for declarative primitive syntax
  # These are the internal primitive selectors that can be called via standard lookup
  registerPrimitivesOnObjectClass(objectClass)

  return objectClass

# ============================================================================
# Instance-based primitive implementations
# These are the actual implementations that core methods delegate to
# ============================================================================

proc plusImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Addition with automatic promotion to float for mixed types
  # Try integer addition first (most common case)
  let (intOk, intVal) = args[0].tryGetInt()
  if intOk and self.kind == ikInt:
    return toValue(self.intVal + intVal)

  # Handle mixed-type or float addition
  let (floatOk, floatVal) = args[0].tryGetFloat()
  if floatOk:
    if self.kind == ikFloat:
      return toValue(self.floatVal + floatVal)
    elif self.kind == ikInt:
      return toValue(self.intVal.float + floatVal)

proc minusImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Subtraction with automatic promotion to float for mixed types
  # Try integer subtraction first (most common case)
  let (intOk, intVal) = args[0].tryGetInt()
  if intOk and self.kind == ikInt:
    return toValue(self.intVal - intVal)

  # Handle mixed-type or float subtraction
  let (floatOk, floatVal) = args[0].tryGetFloat()
  if floatOk:
    if self.kind == ikFloat:
      return toValue(self.floatVal - floatVal)
    elif self.kind == ikInt:
      return toValue(self.intVal.float - floatVal)

proc starImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Multiplication with automatic promotion to float for mixed types
  # Try integer multiplication first (most common case)
  let (intOk, intVal) = args[0].tryGetInt()
  if intOk and self.kind == ikInt:
    return toValue(self.intVal * intVal)

  # Handle mixed-type or float multiplication
  let (floatOk, floatVal) = args[0].tryGetFloat()
  if floatOk:
    if self.kind == ikFloat:
      return toValue(self.floatVal * floatVal)
    elif self.kind == ikInt:
      return toValue(self.intVal.float * floatVal)

proc slashImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Division with automatic promotion to float
  # Division always returns float
  let (floatOk, floatVal) = args[0].tryGetFloat()
  if floatOk:
    if floatVal == 0.0: return nilValue()
    if self.kind == ikFloat:
      return toValue(self.floatVal / floatVal)
    elif self.kind == ikInt:
      return toValue(self.intVal.float / floatVal)

proc sqrtImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Square root
  if self.kind == ikInt:
    return toValue(sqrt(self.intVal.float))
  elif self.kind == ikFloat:
    return toValue(sqrt(self.floatVal))

proc ltImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Less than comparison with automatic promotion to float for mixed types
  # Try integer comparison first
  let (intOk, intVal) = args[0].tryGetInt()
  if self.kind == ikInt and intOk:
    return toValue(self.intVal < intVal)

  # Handle mixed-type or float comparison
  let (floatOk, floatVal) = args[0].tryGetFloat()
  if floatOk:
    if self.kind == ikFloat:
      return toValue(self.floatVal < floatVal)
    elif self.kind == ikInt:
      return toValue(self.intVal.float < floatVal)
  return falseValue

proc gtImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Greater than comparison with automatic promotion to float for mixed types
  # Try integer comparison first
  let (intOk, intVal) = args[0].tryGetInt()
  if self.kind == ikInt and intOk:
    return toValue(self.intVal > intVal)

  # Handle mixed-type or float comparison
  let (floatOk, floatVal) = args[0].tryGetFloat()
  if floatOk:
    if self.kind == ikFloat:
      return toValue(self.floatVal > floatVal)
    elif self.kind == ikInt:
      return toValue(self.intVal.float > floatVal)
  return falseValue

proc eqImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Equal comparison with automatic promotion to float for mixed types
  # Try integer comparison first
  let (intOk, intVal) = args[0].tryGetInt()
  if self.kind == ikInt and intOk:
    return toValue(self.intVal == intVal)

  # Handle mixed-type or float comparison
  let (floatOk, floatVal) = args[0].tryGetFloat()
  if floatOk:
    if self.kind == ikFloat:
      return toValue(self.floatVal == floatVal)
    elif self.kind == ikInt:
      return toValue(self.intVal.float == floatVal)
  return falseValue

proc leImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Less than or equal comparison with automatic promotion to float for mixed types
  # Try integer comparison first
  let (intOk, intVal) = args[0].tryGetInt()
  if self.kind == ikInt and intOk:
    return toValue(self.intVal <= intVal)

  # Handle mixed-type or float comparison
  let (floatOk, floatVal) = args[0].tryGetFloat()
  if floatOk:
    if self.kind == ikFloat:
      return toValue(self.floatVal <= floatVal)
    elif self.kind == ikInt:
      return toValue(self.intVal.float <= floatVal)
  return falseValue

proc geImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Greater than or equal comparison with automatic promotion to float for mixed types
  # Try integer comparison first
  let (intOk, intVal) = args[0].tryGetInt()
  if self.kind == ikInt and intOk:
    return toValue(self.intVal >= intVal)

  # Handle mixed-type or float comparison
  let (floatOk, floatVal) = args[0].tryGetFloat()
  if floatOk:
    if self.kind == ikFloat:
      return toValue(self.floatVal >= floatVal)
    elif self.kind == ikInt:
      return toValue(self.intVal.float >= floatVal)
  return falseValue

proc neImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Not equal comparison with automatic promotion to float for mixed types
  # Try integer comparison first
  let (intOk, intVal) = args[0].tryGetInt()
  if self.kind == ikInt and intOk:
    return toValue(self.intVal != intVal)

  # Handle mixed-type or float comparison
  let (floatOk, floatVal) = args[0].tryGetFloat()
  if floatOk:
    if self.kind == ikFloat:
      return toValue(self.floatVal != floatVal)
    elif self.kind == ikInt:
      return toValue(self.intVal.float != floatVal)
  return trueValue

proc intDivImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Integer division
  let (ok, val) = args[0].tryGetInt()
  if ok and self.kind == ikInt:
    if val == 0: return nilValue()
    return toValue(self.intVal div val)

proc moduloImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Modulo (backslash in Smalltalk)
  let (ok, val) = args[0].tryGetInt()
  if ok and self.kind == ikInt:
    if val == 0: return nilValue()
    return toValue(self.intVal mod val)

proc backslashModuloImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Modulo (backslash in Smalltalk) - alias for moduloImpl
  return moduloImpl(self, args)

proc modMethod*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Modulo with % operator
  let (ok, val) = args[0].tryGetInt()
  if ok and self.kind == ikInt:
    if val == 0: return nilValue()
    return toValue(self.intVal mod val)

proc classImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Return the receiver's class
  return NodeValue(kind: vkClass, classVal: self.class)

proc instIdentityImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Identity comparison - returns true only if same instance
  if args.len > 0:
    if args[0].kind == vkInstance:
      return toValue(self == args[0].instVal)
    # Symbols: two symbols with the same name are identical (value equality for same-class symbols)
    if args[0].kind == vkSymbol and self.kind == ikString and self.class == symbolClassCache:
      return toValue(self.strVal == args[0].symVal)
  return toValue(false)

proc doesNotUnderstandImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Handle unrecognized messages
  # For now, just return nil - could be enhanced to raise an error
  return nilValue()

proc writeImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Write output without newline
  if args.len > 0:
    let s = args[0].toString()
    stdout.write(s)
  return nilValue()

proc writelineImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Write output with newline
  if args.len > 0:
    echo(args[0].toString())
  else:
    echo()
  return nilValue()

proc printStringImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Convert to string representation
  case self.kind
  of ikInt: toValue($(self.intVal))
  of ikFloat: toValue($(self.floatVal))
  of ikString: toValue(self.strVal)
  of ikArray: toValue("#(" & $self.elements.len & ")")
  of ikTable: toValue("#{" & $self.entries.len & "}")
  of ikObject: toValue("<instance of " & self.class.name & ">")

proc classDeriveImpl*(self: Class, args: seq[NodeValue]): NodeValue =
  ## Create a new subclass with slot names
  ## Extract slot names first so newClass() can properly populate allSlotNames
  var slotNames: seq[string] = @[]
  if args.len > 0 and args[0].kind == vkInstance and args[0].instVal.kind == ikArray:
    let slotNameValues = args[0].instVal.elements
    for slot in slotNameValues:
      if slot.kind == vkSymbol:
        slotNames.add(slot.symVal)
  let className = if self.name.len > 0: self.name & "+Derived" else: "Anonymous"
  let newClass = newClass(superclasses = @[self], slotNames = slotNames, name = className)
  return NodeValue(kind: vkClass, classVal: newClass)

proc extractSlotNamesFromArray(arr: NodeValue): seq[string] =
  ## Extract slot names from an array NodeValue
  result = @[]
  if arr.kind == vkInstance and arr.instVal.kind == ikArray:
    for elem in arr.instVal.elements:
      if elem.kind == vkSymbol:
        result.add(elem.symVal)
      elif elem.kind == vkString:
        result.add(elem.strVal)

proc createGetterMethod*(cls: Class, slotName: string): BlockNode =
  ## Create a getter method for a slot: slotName [ ^slotName ]
  ## Uses SlotAccessNode for O(1) direct access
  let slotIndex = cls.getSlotIndex(slotName)
  if slotIndex < 0:
    return nil

  # Create SlotAccessNode for the slot read
  let slotAccess = SlotAccessNode(
    slotName: slotName,
    slotIndex: slotIndex,
    isAssignment: false,
    valueExpr: nil
  )

  # Create return node with the slot access
  let returnNode = ReturnNode(expression: cast[Node](slotAccess))

  # Create the method block
  let meth = BlockNode()
  meth.parameters = @[]
  meth.temporaries = @[]
  meth.body = @[cast[Node](returnNode)]
  meth.isMethod = true
  meth.nativeImpl = nil
  meth.capturedEnv = initTable[string, MutableCell]()
  meth.capturedEnvInitialized = true

  return meth

proc createSetterMethod*(cls: Class, slotName: string): BlockNode =
  ## Create a setter method for a slot: slotName: value [ slotName := value ]
  ## Uses SlotAccessNode for O(1) direct access
  let slotIndex = cls.getSlotIndex(slotName)
  if slotIndex < 0:
    return nil

  # Parameter name for the setter (e.g., "aValue" or just "value")
  let paramName = "aValue"

  # Create the parameter node as an IdentNode
  let paramNode = IdentNode(name: paramName)

  # Create SlotAccessNode for the slot assignment
  let slotAccess = SlotAccessNode(
    slotName: slotName,
    slotIndex: slotIndex,
    isAssignment: true,
    valueExpr: cast[Node](paramNode)
  )

  # Create the method block
  let meth = BlockNode()
  meth.parameters = @[paramName]
  meth.temporaries = @[]
  meth.body = @[cast[Node](slotAccess)]
  meth.isMethod = true
  meth.nativeImpl = nil
  meth.capturedEnv = initTable[string, MutableCell]()
  meth.capturedEnvInitialized = true

  return meth

proc classDeriveWithAccessorsImpl*(self: Class, args: seq[NodeValue]): NodeValue =
  ## Create a new subclass with slot names and auto-generate accessors
  ## args[0]: array of slot names
  ## Generates both getters and setters for each slot
  var slotNames: seq[string] = @[]
  if args.len > 0:
    slotNames = extractSlotNamesFromArray(args[0])

  let className = if self.name.len > 0: self.name & "+Derived" else: "Anonymous"
  let newCls = newClass(superclasses = @[self], slotNames = slotNames, name = className)

  # Generate getters and setters for each slot
  for slotName in slotNames:
    # Create and add getter: slotName
    let getter = createGetterMethod(newCls, slotName)
    if getter != nil:
      addMethodToClass(newCls, slotName, getter, isClassMethod = false)

    # Create and add setter: slotName:
    let setterName = slotName & ":"
    let setter = createSetterMethod(newCls, slotName)
    if setter != nil:
      addMethodToClass(newCls, setterName, setter, isClassMethod = false)

  return NodeValue(kind: vkClass, classVal: newCls)

proc classDeriveGettersSettersImpl*(self: Class, args: seq[NodeValue]): NodeValue =
  ## Create a new subclass with selective accessor generation
  ## args[0]: array of all slot names
  ## args[1]: array of slot names to generate getters for
  ## args[2]: array of slot names to generate setters for
  if args.len < 3:
    return nilValue()

  # Extract all slot names
  let allSlotNames = extractSlotNamesFromArray(args[0])

  # Extract getter slot names
  let getterSlotNames = extractSlotNamesFromArray(args[1])

  # Extract setter slot names
  let setterSlotNames = extractSlotNamesFromArray(args[2])

  let className = if self.name.len > 0: self.name & "+Derived" else: "Anonymous"
  let newCls = newClass(superclasses = @[self], slotNames = allSlotNames, name = className)

  # Generate getters for specified slots
  for slotName in getterSlotNames:
    let getter = createGetterMethod(newCls, slotName)
    if getter != nil:
      addMethodToClass(newCls, slotName, getter, isClassMethod = false)

  # Generate setters for specified slots
  for slotName in setterSlotNames:
    let setterName = slotName & ":"
    let setter = createSetterMethod(newCls, slotName)
    if setter != nil:
      addMethodToClass(newCls, setterName, setter, isClassMethod = false)

  return NodeValue(kind: vkClass, classVal: newCls)

proc classDeriveParentsSlotsMethodsImpl*(self: Class, args: seq[NodeValue]): NodeValue =
  ## Create a new class with multiple parents and define methods
  ## args[0]: parents array
  ## args[1]: slot names array
  ## args[2]: methods dictionary (optional)
  if args.len < 2:
    return nilValue()

  # Extract parents array
  var parents: seq[Class] = @[]
  if args[0].kind == vkInstance and args[0].instVal.kind == ikArray:
    for elem in args[0].instVal.elements:
      if elem.kind == vkClass:
        parents.add(elem.classVal)

  # If no parents provided, use self as the parent
  if parents.len == 0:
    parents.add(self)

  # Extract slot names
  var slotNames: seq[string] = @[]
  if args[1].kind == vkInstance and args[1].instVal.kind == ikArray:
    for elem in args[1].instVal.elements:
      if elem.kind == vkString or elem.kind == vkSymbol:
        let name = if elem.kind == vkString: elem.strVal else: elem.symVal
        if name.len > 0:
          slotNames.add(name)

  # Check type compatibility: first parent determines the instance type
  # All other parents must have the same or compatible instance type
  if parents.len > 1:
    # For now, the constraint is: all must have no conflicting slots
    # Slot name conflicts are already checked in newClass
    # More specific type checking could be added here in future
    discard

  # Create the new class
  # Note: we use self as base if parents array is empty
  let actualParents = if args[0].kind == vkNil: @[self] else: parents
  let className = if parents.len > 0 and parents[0].name.len > 0:
                    parents[0].name & "+Derived"
                  elif self.name.len > 0:
                    self.name & "+Derived"
                  else:
                    "Anonymous"
  let theClass = newClass(superclasses =actualParents, slotNames = slotNames, name = className)

  # Execute method block if provided (to define/override methods and resolve conflicts)
  # For now, skip block execution - it requires an interpreter context
  # This could be enhanced later to support true method definition in the block
  discard

  return NodeValue(kind: vkClass, classVal: theClass)

proc classDeriveParentsSlotsGettersSettersMethodsImpl*(self: Class, args: seq[NodeValue]): NodeValue =
  ## Create a new class with multiple parents, slots, selective getters/setters, and methods
  ## args[0]: slot names array (all slots)
  ## args[1]: parents array
  ## args[2]: slots array (extra slots)
  ## args[3]: getters array (slots to generate getters for)
  ## args[4]: setters array (slots to generate setters for)
  ## args[5]: methods dictionary (optional)
  if args.len < 5:
    return nilValue()

  # Extract slot names (from derive: parameter)
  var slotNames: seq[string] = @[]
  if args[0].kind == vkInstance and args[0].instVal.kind == ikArray:
    for elem in args[0].instVal.elements:
      if elem.kind == vkString or elem.kind == vkSymbol:
        let name = if elem.kind == vkString: elem.strVal else: elem.symVal
        if name.len > 0:
          slotNames.add(name)

  # Extract parents array
  var parents: seq[Class] = @[]
  if args[1].kind == vkInstance and args[1].instVal.kind == ikArray:
    for elem in args[1].instVal.elements:
      if elem.kind == vkClass:
        parents.add(elem.classVal)

  # If no parents provided, use self as the parent
  if parents.len == 0:
    parents.add(self)

  # Extract additional slot names (from slots: parameter)
  if args[2].kind == vkInstance and args[2].instVal.kind == ikArray:
    for elem in args[2].instVal.elements:
      if elem.kind == vkString or elem.kind == vkSymbol:
        let name = if elem.kind == vkString: elem.strVal else: elem.symVal
        if name.len > 0 and name notin slotNames:
          slotNames.add(name)

  # Extract getter slot names
  var getterSlotNames: seq[string] = @[]
  if args[3].kind == vkInstance and args[3].instVal.kind == ikArray:
    for elem in args[3].instVal.elements:
      if elem.kind == vkString or elem.kind == vkSymbol:
        let name = if elem.kind == vkString: elem.strVal else: elem.symVal
        if name.len > 0:
          getterSlotNames.add(name)

  # Extract setter slot names
  var setterSlotNames: seq[string] = @[]
  if args[4].kind == vkInstance and args[4].instVal.kind == ikArray:
    for elem in args[4].instVal.elements:
      if elem.kind == vkString or elem.kind == vkSymbol:
        let name = if elem.kind == vkString: elem.strVal else: elem.symVal
        if name.len > 0:
          setterSlotNames.add(name)

  # Create the new class
  let actualParents = if args[1].kind == vkNil: @[self] else: parents
  let className = if parents.len > 0 and parents[0].name.len > 0:
                    parents[0].name & "+Derived"
                  elif self.name.len > 0:
                    self.name & "+Derived"
                  else:
                    "Anonymous"
  let newClass = newClass(superclasses = actualParents, slotNames = slotNames, name = className)

  # Generate getters for specified slots
  for slotName in getterSlotNames:
    let getter = createGetterMethod(newClass, slotName)
    if getter != nil:
      addMethodToClass(newClass, slotName, getter, isClassMethod = false)

  # Generate setters for specified slots
  for slotName in setterSlotNames:
    let setterName = slotName & ":"
    let setter = createSetterMethod(newClass, slotName)
    if setter != nil:
      addMethodToClass(newClass, setterName, setter, isClassMethod = false)

  # Extract and add methods from dictionary if provided
  if args.len >= 6 and args[5].kind == vkInstance and args[5].instVal.kind == ikTable:
    let methodTable = args[5].instVal
    for key, value in methodTable.entries.pairs:
      if key.kind == vkSymbol and value.kind == vkBlock:
        let selector = key.symVal
        let meth = value.blockVal
        addMethodToClass(newClass, selector, meth, isClassMethod = false)

  return NodeValue(kind: vkClass, classVal: newClass)

proc classParentsImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Add parent classes to an existing class (cascade-style construction)
  ## args[0]: parents array
  if nimValueIsNil(self.nimValue):
    return nilValue()

  let cls = cast[ptr Class](self.nimValue)
  if args.len > 0 and args[0].kind == vkInstance and args[0].instVal.kind == ikArray:
    var parents: seq[Class] = @[]
    for elem in args[0].instVal.elements:
      if elem.kind == vkClass:
        parents.add(elem.classVal)

    # Add each parent to superclasses
    for parent in parents:
      if parent notin cls[].superclasses:
        cls[].superclasses.add(parent)
        invalidateSubclasses(cls[])
        rebuildAllTables(cls[])

  return NodeValue(kind: vkClass, classVal: cls[])

proc classSlotsImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Add slots to an existing class (cascade-style construction)
  ## Note: This creates a new class with the additional slots
  ## args[0]: slot names array
  if nimValueIsNil(self.nimValue):
    return nilValue()

  let cls = cast[ptr Class](self.nimValue)
  if args.len > 0 and args[0].kind == vkInstance and args[0].instVal.kind == ikArray:
    var extraSlotNames: seq[string] = @[]
    for elem in args[0].instVal.elements:
      if elem.kind == vkString or elem.kind == vkSymbol:
        let name = if elem.kind == vkString: elem.strVal else: elem.symVal
        if name.len > 0:
          extraSlotNames.add(name)

    # Create new slot names list combining existing and new
    var newSlotNames: seq[string] = @[]
    for slot in cls[].allSlotNames:
      newSlotNames.add(slot)
    for slot in extraSlotNames:
      if slot notin newSlotNames:
        newSlotNames.add(slot)

    # Rebuild class with new slot names (create a replacement class)
    let replacementClass = newClass(
      superclasses = cls[].superclasses,
      slotNames = newSlotNames,
      name = cls[].name
    )

    # Copy existing methods
    for selector, meth in cls[].methods.pairs:
      replacementClass.methods[selector] = meth
    for selector, meth in cls[].allMethods.pairs:
      replacementClass.allMethods[selector] = meth

    # For cascades, we update the nimValue pointer
    cast[ptr Class](self.nimValue)[] = replacementClass

    return NodeValue(kind: vkClass, classVal: replacementClass)

  return NodeValue(kind: vkClass, classVal: cls[])

proc classGettersImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Generate getter methods for specified slots (cascade-style construction)
  ## args[0]: slot names array
  if nimValueIsNil(self.nimValue):
    return nilValue()

  let cls = cast[ptr Class](self.nimValue)
  if args.len > 0 and args[0].kind == vkInstance and args[0].instVal.kind == ikArray:
    for elem in args[0].instVal.elements:
      if elem.kind == vkString or elem.kind == vkSymbol:
        let slotName = if elem.kind == vkString: elem.strVal else: elem.symVal
        let getter = createGetterMethod(cls[], slotName)
        if getter != nil:
          addMethodToClass(cls[], slotName, getter, isClassMethod = false)

  return NodeValue(kind: vkClass, classVal: cls[])

proc classSettersImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Generate setter methods for specified slots (cascade-style construction)
  ## args[0]: slot names array
  if nimValueIsNil(self.nimValue):
    return nilValue()

  let cls = cast[ptr Class](self.nimValue)
  if args.len > 0 and args[0].kind == vkInstance and args[0].instVal.kind == ikArray:
    for elem in args[0].instVal.elements:
      if elem.kind == vkString or elem.kind == vkSymbol:
        let slotName = if elem.kind == vkString: elem.strVal else: elem.symVal
        let setterName = slotName & ":"
        let setter = createSetterMethod(cls[], slotName)
        if setter != nil:
          addMethodToClass(cls[], setterName, setter, isClassMethod = false)

  return NodeValue(kind: vkClass, classVal: cls[])

proc classMethodsImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Add methods from a table literal (cascade-style construction)
  ## args[0]: methods table #{#selector -> [:arg|...], ...}
  if nimValueIsNil(self.nimValue):
    return nilValue()

  let cls = cast[ptr Class](self.nimValue)
  if args.len > 0 and args[0].kind == vkInstance and args[0].instVal.kind == ikTable:
    let methodTable = args[0].instVal
    for key, value in methodTable.entries.pairs:
      if key.kind == vkSymbol and value.kind == vkBlock:
        let selector = key.symVal
        let meth = value.blockVal
        addMethodToClass(cls[], selector, meth, isClassMethod = false)

  return NodeValue(kind: vkClass, classVal: cls[])

proc classNewImpl*(self: Class, args: seq[NodeValue]): NodeValue =
  ## Create a new instance of this class
  let inst = self.newInstance()
  return NodeValue(kind: vkInstance, instVal: inst)

proc classAddMethodImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Add an instance method to this class
  ## Returns self (the class) for method chaining
  if args.len >= 2:
    let selector = if args[0].kind == vkString: args[0].strVal
                   elif args[0].kind == vkSymbol: args[0].symVal
                   else: ""
    let meth: BlockNode = if args[1].kind == vkBlock: args[1].blockVal else: nil
    if selector.len > 0 and meth != nil:
      addMethodToClass(self.class, selector, meth, deferRebuild=interp.methodTableDeferRebuild)
  return self.class.toValue()

proc classAddClassMethodImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue =
  ## Add a class method to this class
  ## Returns self (the class) for method chaining
  if args.len >= 2:
    let selector = if args[0].kind == vkString: args[0].strVal
                   elif args[0].kind == vkSymbol: args[0].symVal
                   else: ""
    let meth: BlockNode = if args[1].kind == vkBlock: args[1].blockVal else: nil
    if selector.len > 0 and meth != nil:
      addMethodToClass(self.class, selector, meth, isClassMethod = true, deferRebuild=interp.methodTableDeferRebuild)
  return self.class.toValue()

proc sizeImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Get size of collections
  case self.kind
  of ikString: toValue(self.strVal.len)
  of ikArray: toValue(self.elements.len)
  of ikTable: toValue(self.entries.len)
  else: toValue(0)

proc atCollectionImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Get element at index (1-based for Smalltalk compatibility)
  case self.kind
  of ikString:
    let (ok, val) = args[0].tryGetInt()
    # Convert 1-based to 0-based
    if ok and val >= 1 and val <= self.strVal.len:
      return toValue($self.strVal[val - 1])
  of ikArray:
    let (ok, val) = args[0].tryGetInt()
    # Convert 1-based to 0-based
    if ok and val >= 1 and val <= self.elements.len:
      return self.elements[val - 1]
  of ikTable:
    let key = args[0]
    if key in self.entries:
      return self.entries[key]
  of ikObject:
    # Slot access for class-based objects
    if self.class != nil and args.len > 0:
      let slotName = if args[0].kind == vkString: args[0].strVal
                      elif args[0].kind == vkSymbol: args[0].symVal
                      else: ""
      if slotName.len > 0:
        for i, name in self.class.allSlotNames:
          if name == slotName and i < self.slots.len:
            return self.slots[i]
  else:
    discard
  return nilValue()

proc atCollectionPutImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Set element at index (1-based for Smalltalk compatibility)
  if args.len < 2: return nilValue()
  case self.kind
  of ikArray:
    let (ok, val) = args[0].tryGetInt()
    # Convert 1-based to 0-based
    if ok and val >= 1 and val <= self.elements.len:
      self.elements[val - 1] = args[1]
    return args[1]
  of ikTable:
    let key = args[0]
    self.entries[key] = args[1]
    return args[1]
  of ikObject:
    # Slot set for class-based objects
    if self.class != nil:
      let slotName = if args[0].kind == vkString: args[0].strVal
                      elif args[0].kind == vkSymbol: args[0].symVal
                      else: ""
      if slotName.len > 0:
        for i, name in self.class.allSlotNames:
          if name == slotName and i < self.slots.len:
            self.slots[i] = args[1]
            return args[1]
  else:
    discard
  return nilValue()

proc instStringConcatImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## String concatenation with auto-conversion using asString
  if self.kind == ikString:
    if args.len > 0:
      # Convert argument to string using toString (which handles all types)
      let otherStr = args[0].toString()
      return NodeValue(kind: vkInstance, instVal: newStringInstance(self.class, self.strVal & otherStr))
    else:
      return NodeValue(kind: vkInstance, instVal: newStringInstance(self.class, self.strVal))
  return NodeValue(kind: vkInstance, instVal: newStringInstance(self.class, ""))

proc instStringSizeImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## String size
  if self.kind == ikString:
    return toValue(self.strVal.len)
  return toValue(0)

proc instStringAtImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## String character at index (1-based)
  if self.kind == ikString and args.len > 0:
    let (ok, val) = args[0].tryGetInt()
    # Convert 1-based to 0-based
    if ok and val >= 1 and val <= self.strVal.len:
      return toValue($self.strVal[val - 1])
  return toValue("")

proc concatImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## String concatenation
  if self.kind == ikString and args.len > 0:
    let other = if args[0].kind == vkString: args[0].strVal
                elif args[0].kind == vkInstance and args[0].instVal.kind == ikString: args[0].instVal.strVal
                else: ""
    return NodeValue(kind: vkInstance, instVal: newStringInstance(self.class, self.strVal & other))
  return NodeValue(kind: vkInstance, instVal: newStringInstance(self.class, self.strVal))

proc instStringFromToImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Substring from:to: (1-based, inclusive)
  if self.kind == ikString and args.len >= 2:
    let (ok1, fromIdx) = args[0].tryGetInt()
    let (ok2, toIdx) = args[1].tryGetInt()
    let startIdx = fromIdx - 1
    let endIdx = toIdx - 1
    if ok1 and ok2 and startIdx >= 0 and endIdx < self.strVal.len and startIdx <= endIdx:
      return NodeValue(kind: vkInstance, instVal: newStringInstance(self.class, self.strVal[startIdx..endIdx]))
  return toValue("")

proc instStringIndexOfImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Index of substring
  if self.kind == ikString and args.len > 0:
    let sub = if args[0].kind == vkString: args[0].strVal
              elif args[0].kind == vkInstance and args[0].instVal.kind == ikString: args[0].instVal.strVal
              else: ""
    if sub.len > 0:
      let idx = self.strVal.find(sub) + 1  # 1-indexed
      return toValue(idx)
  return toValue(0)

proc instStringIncludesSubStringImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Check if includes substring
  if self.kind == ikString and args.len > 0:
    let sub = if args[0].kind == vkString: args[0].strVal
              elif args[0].kind == vkInstance and args[0].instVal.kind == ikString: args[0].instVal.strVal
              else: ""
    return toValue(sub in self.strVal)
  return toValue(false)

proc instStringReplaceWithImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Replace substring with another
  if self.kind == ikString and args.len >= 2:
    let old = if args[0].kind == vkString: args[0].strVal
              elif args[0].kind == vkInstance and args[0].instVal.kind == ikString: args[0].instVal.strVal
              else: ""
    let new = if args[1].kind == vkString: args[1].strVal
              elif args[1].kind == vkInstance and args[1].instVal.kind == ikString: args[1].instVal.strVal
              else: ""
    return NodeValue(kind: vkInstance, instVal: newStringInstance(self.class, self.strVal.replace(old, new)))
  return NodeValue(kind: vkInstance, instVal: newStringInstance(self.class, self.strVal))

proc instStringUppercaseImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Convert to uppercase
  if self.kind == ikString:
    return NodeValue(kind: vkInstance, instVal: newStringInstance(self.class, self.strVal.toUpperAscii()))
  return self.toValue()

proc instStringLowercaseImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Convert to lowercase
  if self.kind == ikString:
    return NodeValue(kind: vkInstance, instVal: newStringInstance(self.class, self.strVal.toLowerAscii()))
  return self.toValue()

proc instStringTrimImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Trim whitespace
  if self.kind == ikString:
    return NodeValue(kind: vkInstance, instVal: newStringInstance(self.class, strip(self.strVal)))
  return self.toValue()

proc instStringSplitImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Split string by delimiter
  if self.kind == ikString and args.len > 0:
    let delim = if args[0].kind == vkString: args[0].strVal
                elif args[0].kind == vkInstance and args[0].instVal.kind == ikString: args[0].instVal.strVal
                else: ""
    if delim.len > 0:
      let parts = self.strVal.split(delim)
      var elements: seq[NodeValue] = @[]
      for p in parts:
        elements.add(toValue(p))
      return NodeValue(kind: vkInstance, instVal: newArrayInstance(arrayClass, elements))
  return NodeValue(kind: vkInstance, instVal: newArrayInstance(arrayClass, @[]))

proc instStringAsIntegerImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Convert string to integer
  if self.kind == ikString:
    try:
      let val = parseInt(self.strVal)
      return toValue(val)
    except:
      discard
  return toValue(0)

proc instStringAsSymbolImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Convert string to symbol
  if self.kind == ikString:
    return toSymbol(self.strVal)
  return self.toValue()

proc instStringRepeatImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Repeat string n times (e.g., "ab" repeat: 3 -> "ababab")
  if self.kind == ikString and args.len > 0:
    let (ok, count) = args[0].tryGetInt()
    if ok and count > 0:
      var strResult = ""
      for i in 0..<count:
        strResult.add(self.strVal)
      return NodeValue(kind: vkInstance, instVal: newStringInstance(self.class, strResult))
    elif ok and count <= 0:
      return NodeValue(kind: vkInstance, instVal: newStringInstance(self.class, ""))
  return NodeValue(kind: vkInstance, instVal: newStringInstance(self.class, self.strVal))

# Array primitives
proc arraySizeImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Array size
  if self.kind == ikArray:
    return toValue(self.elements.len)
  return toValue(0)

proc arrayAddImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Add element to array
  let elemCount = if self.kind == ikArray: self.elements.len else: 0
  debug("arrayAddImpl: self.kind=", $self.kind, " ikArray=", $(self.kind == ikArray),
        " args.len=", $args.len, " elements.len=", $elemCount)
  if self.kind == ikArray and args.len > 0:
    self.elements.add(args[0])
    debug("arrayAddImpl: after add, elements.len=", $self.elements.len)
  return self.toValue()

proc arrayRemoveAtImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Remove element at index
  if self.kind == ikArray and args.len > 0:
    let (ok, val) = args[0].tryGetInt()
    if ok and val >= 0 and val < self.elements.len:
      self.elements.delete(val)
  return self.toValue()

proc arrayIncludesImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Check if array includes element
  if self.kind == ikArray and args.len > 0:
    for elem in self.elements:
      if valuesEqual(elem, args[0]):
        return toValue(true)
  return toValue(false)

proc arrayReverseImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Reverse array
  if self.kind == ikArray:
    for i in 0..<self.elements.len div 2:
      let temp = self.elements[i]
      self.elements[i] = self.elements[self.elements.len - 1 - i]
      self.elements[self.elements.len - 1 - i] = temp
  return self.toValue()

proc arrayAtImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Get element at index
  return atCollectionImpl(self, args)

proc arrayAtPutImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Set element at index
  return atCollectionPutImpl(self, args)

proc arrayJoinImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Join array elements with separator string
  if self.kind == ikArray:
    let sep = if args.len > 0 and args[0].kind == vkString: args[0].strVal
              elif args.len > 0 and args[0].kind == vkInstance and args[0].instVal.kind == ikString: args[0].instVal.strVal
              else: ""
    var joinResult = ""
    for i, elem in self.elements:
      if i > 0:
        joinResult.add(sep)
      joinResult.add(elem.toString())
    return NodeValue(kind: vkInstance, instVal: newStringInstance(stringClass, joinResult))
  return NodeValue(kind: vkInstance, instVal: newStringInstance(stringClass, ""))

# Table primitives
proc tableNewImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Create new table
  return NodeValue(kind: vkInstance, instVal: newTableInstance(tableClass, initTable[NodeValue, NodeValue]()))

proc tableKeysImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Get table keys as array
  if self.kind == ikTable:
    var elements: seq[NodeValue] = @[]
    for key in self.entries.keys():
      elements.add(key)
    return NodeValue(kind: vkInstance, instVal: newArrayInstance(arrayClass, elements))
  return NodeValue(kind: vkInstance, instVal: newArrayInstance(arrayClass, @[]))

proc tableIncludesKeyImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Check if table includes key
  if self.kind == ikTable and args.len > 0:
    return toValue(args[0] in self.entries)
  return toValue(false)

proc tableRemoveKeyImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Remove key from table
  if self.kind == ikTable and args.len > 0:
    let key = args[0]
    self.entries.del(key)
  return self.toValue()

proc tableAtImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Get table value by key
  return atCollectionImpl(self, args)

proc tableAtPutImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Set table value by key
  return atCollectionPutImpl(self, args)

# Library primitives (composition: delegates to bindings table in slot 0)

proc getLibraryBindings*(self: Instance): Instance =
  ## Get the bindings Table instance from a Library's slot 0
  if self.kind == ikObject and self.slots.len > 0:
    let bindingsVal = self.slots[0]
    if bindingsVal.kind == vkInstance and bindingsVal.instVal != nil and bindingsVal.instVal.kind == ikTable:
      return bindingsVal.instVal
  return nil

proc libraryNewImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Create a new Library instance with empty bindings table and imports array
  var inst = newInstance(libraryClass)
  inst.slots[0] = newTableInstance(tableClass, initTable[NodeValue, NodeValue]()).toValue()
  inst.slots[1] = newArrayInstance(arrayClass, @[]).toValue()
  inst.slots[2] = toValue("")
  return inst.toValue()

proc libraryAtImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Library at: - delegate to bindings table
  let bindings = getLibraryBindings(self)
  if bindings != nil and args.len > 0:
    return getTableValue(bindings, args[0])
  return nilValue()

proc libraryAtPutImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Library at:put: - delegate to bindings table
  let bindings = getLibraryBindings(self)
  if bindings != nil and args.len >= 2:
    setTableValue(bindings, args[0], args[1])
  return self.toValue()

proc libraryKeysImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Library keys - delegate to bindings table
  let bindings = getLibraryBindings(self)
  if bindings != nil:
    var elements: seq[NodeValue] = @[]
    for key in bindings.entries.keys():
      elements.add(key)
    return newArrayInstance(arrayClass, elements).toValue()
  return newArrayInstance(arrayClass, @[]).toValue()

proc libraryIncludesKeyImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Library includesKey: - delegate to bindings table
  let bindings = getLibraryBindings(self)
  if bindings != nil and args.len > 0:
    return toValue(args[0] in bindings.entries)
  return toValue(false)

proc libraryNameImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Library name - get the name slot (slot 2: [bindings, imports, name])
  if self.kind == ikObject and self.slots.len > 2:
    return self.slots[2]
  return nilValue()

proc libraryNameSetImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Library name: - set the name slot (slot 2: [bindings, imports, name])
  if self.kind == ikObject and self.slots.len > 2 and args.len > 0:
    self.slots[2] = args[0]
  return self.toValue()

proc libraryBindingsImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Library bindings - get the bindings slot (slot 0: [bindings, imports, name])
  ## Note: This is typically accessed via slot access (lib bindings), not via this primitive
  if self.kind == ikObject and self.slots.len > 0:
    return self.slots[0]
  return nilValue()

# Set primitives (storing elements in a table at slot 0)

proc getSetElements*(self: Instance): Instance =
  ## Get the elements Table instance from a Set's slot 0
  if self.kind == ikObject and self.slots.len > 0:
    let elementsVal = self.slots[0]
    if elementsVal.kind == vkInstance and elementsVal.instVal != nil and elementsVal.instVal.kind == ikTable:
      return elementsVal.instVal
  return nil

proc primitiveSetNewImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Create a new Set instance with empty table for elements
  if setClass == nil:
    return nilValue()
  var inst = newInstance(setClass)
  inst.slots = @[]
  inst.slots.add(newTableInstance(tableClass, initTable[NodeValue, NodeValue]()).toValue())
  return inst.toValue()

proc primitiveSetAddImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Add element to set
  let elements = getSetElements(self)
  if elements != nil and args.len > 0:
    elements.entries[args[0]] = toValue(true)
  return self.toValue()

proc primitiveSetRemoveImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Remove element from set
  let elements = getSetElements(self)
  if elements != nil and args.len > 0:
    elements.entries.del(args[0])
  return self.toValue()

proc primitiveSetIncludesImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Check if set includes element
  let elements = getSetElements(self)
  if elements != nil and args.len > 0:
    return toValue(args[0] in elements.entries)
  return toValue(false)

proc primitiveSetSizeImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Get set size
  let elements = getSetElements(self)
  if elements != nil:
    return toValue(elements.entries.len)
  return toValue(0)

proc primitiveSetUnionImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Return union of self and otherSet
  let selfElements = getSetElements(self)
  let otherElements = getSetElements(args[0].instVal)
  if selfElements == nil or otherElements == nil:
    return nilValue()
  var inst = newInstance(setClass)
  inst.slots = @[]
  var newEntries = initTable[NodeValue, NodeValue]()
  for key in selfElements.entries.keys():
    newEntries[key] = toValue(true)
  for key in otherElements.entries.keys():
    newEntries[key] = toValue(true)
  inst.slots.add(newTableInstance(tableClass, newEntries).toValue())
  return inst.toValue()

proc primitiveSetIntersectionImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Return intersection of self and otherSet
  let selfElements = getSetElements(self)
  let otherElements = getSetElements(args[0].instVal)
  if selfElements == nil or otherElements == nil:
    return nilValue()
  var inst = newInstance(setClass)
  inst.slots = @[]
  var newEntries = initTable[NodeValue, NodeValue]()
  for key in selfElements.entries.keys():
    if key in otherElements.entries:
      newEntries[key] = toValue(true)
  inst.slots.add(newTableInstance(tableClass, newEntries).toValue())
  return inst.toValue()

proc primitiveSetDifferenceImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Return difference (self - otherSet)
  let selfElements = getSetElements(self)
  let otherElements = getSetElements(args[0].instVal)
  if selfElements == nil or otherElements == nil:
    return nilValue()
  var inst = newInstance(setClass)
  inst.slots = @[]
  var newEntries = initTable[NodeValue, NodeValue]()
  for key in selfElements.entries.keys():
    if key notin otherElements.entries:
      newEntries[key] = toValue(true)
  inst.slots.add(newTableInstance(tableClass, newEntries).toValue())
  return inst.toValue()

proc primitiveSetKeysImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Get set elements as array
  let elements = getSetElements(self)
  if elements != nil:
    var keys: seq[NodeValue] = @[]
    for key in elements.entries.keys():
      keys.add(key)
    return NodeValue(kind: vkInstance, instVal: newArrayInstance(arrayClass, keys))
  return NodeValue(kind: vkInstance, instVal: newArrayInstance(arrayClass, @[]))

# Set>>do: requires interpreter to evaluate blocks
# Register this in vm.nim's initGlobals where other interpreter-dependent methods are registered

# ============================================================================
# Class method helpers
# ============================================================================

proc invalidateSubclasses*(cls: Class) =
  ## Invalidate cached method tables for all subclasses
  for subclass in cls.subclasses:
    subclass.methodsDirty = true
    subclass.version += 1
    invalidateSubclasses(subclass)

proc rebuildAllTables*(cls: Class) =
  ## Rebuild inherited method tables
  var allMethods = initTable[string, BlockNode]()
  var allClassMethods = initTable[string, BlockNode]()

  # For the class itself, use directly-defined methods only
  for sel, m in cls.methods:
    allMethods[sel] = m
  for sel, m in cls.classMethods:
    allClassMethods[sel] = m

  # For parent classes, use allMethods (includes what they inherited)
  # This ensures we pick up manually-added methods from tests
  for parent in cls.superclasses:
    for c in parent.inheritanceChain():
      for sel, m in c.allMethods:
        if sel notin allMethods:  # Don't override if already defined
          allMethods[sel] = m
      for sel, m in c.allClassMethods:
        if sel notin allClassMethods:
          allClassMethods[sel] = m

  # Also inherit slot names from parents
  var allSlotNames = cls.slotNames
  for parent in cls.superclasses:
    for slotName in parent.allSlotNames:
      if slotName notin allSlotNames:
        allSlotNames.add(slotName)
  cls.allSlotNames = allSlotNames
  cls.hasSlots = allSlotNames.len > 0

  cls.allMethods = allMethods
  cls.allClassMethods = allClassMethods

  # Bump version so inline caches see the rebuilt tables
  cls.version += 1

# ============================================================================
# Instance clone implementation (for new class-based system)
proc instanceCloneImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Clone an instance - creates a new instance with same class and copied slots
  case self.kind
  of ikObject:
    let clone = Instance(kind: ikObject, class: self.class)
    clone.slots = self.slots
    clone.isNimProxy = self.isNimProxy
    clone.nimValue = self.nimValue
    return NodeValue(kind: vkInstance, instVal: clone)
  of ikArray:
    let clone = Instance(kind: ikArray, class: self.class)
    clone.elements = self.elements  # Copy elements
    return NodeValue(kind: vkInstance, instVal: clone)
  of ikTable:
    let clone = Instance(kind: ikTable, class: self.class)
    clone.entries = self.entries  # Copy entries
    return NodeValue(kind: vkInstance, instVal: clone)
  of ikInt:
    return toValue(self.intVal)
  of ikFloat:
    return toValue(self.floatVal)
  of ikString:
    return toValue(self.strVal)

# ============================================================================
# Instance-based primitive wrapper functions
# These allow the new Instance-based system to support the primitive syntax
# ============================================================================

proc primitiveCloneImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Clone primitive for Instance - delegates to instanceCloneImpl
  return instanceCloneImpl(self, args)

proc primitiveAtImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Get slot value by name (for ikObject instances)
  if args.len == 0:
    return nilValue()
  if self.kind != ikObject or self.class == nil:
    return nilValue()
  let slotName = if args[0].kind == vkString: args[0].strVal
               elif args[0].kind == vkSymbol: args[0].symVal
               elif args[0].kind == vkInstance and args[0].instVal.kind == ikString: args[0].instVal.strVal
               else: ""
  let slotIdx = self.class.allSlotNames.find(slotName)
  if slotIdx >= 0 and slotIdx < self.slots.len:
    return self.slots[slotIdx]
  return nilValue()

proc primitiveAtPutImpl*(self: Instance, args: seq[NodeValue]): NodeValue =
  ## Set slot value by name (for ikObject instances)
  if args.len < 2:
    return self.toValue()
  if self.kind != ikObject or self.class == nil:
    return args[1]
  let slotName = if args[0].kind == vkString: args[0].strVal
               elif args[0].kind == vkSymbol: args[0].symVal
               elif args[0].kind == vkInstance and args[0].instVal.kind == ikString: args[0].instVal.strVal
               else: ""
  let slotIdx = self.class.allSlotNames.find(slotName)
  if slotIdx >= 0 and slotIdx < self.slots.len:
    self.slots[slotIdx] = args[1]
  return args[1]

# ============================================================================
# Register primitive method wrappers on Object class
# ============================================================================

proc registerPrimitivesOnObjectClass*(objCls: Class) =
  ## Register the internal primitive selector methods on Object class
  # These allow the declarative primitive syntax to work via standard lookup

  let primClone = createCoreMethod("primitiveClone")
  primClone.setNativeImpl(primitiveCloneImpl)
  addMethodToClass(objCls, "primitiveClone", primClone)

  # Note: primitiveAt: and primitiveAt:put: are registered on Table class in vm.nim
  # (not on Object as that would be inappropriate)
