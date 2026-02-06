## Explicit Stack AST Interpreter for Nemo
##
## This module implements an iterative AST interpreter using an explicit work queue
## instead of recursive Nim procedure calls. This enables:
## 1. True cooperative multitasking (yield within statements)
## 2. Stack reification (thisContext accessible from Nemo)
## 3. No Nim stack overflow on deep recursion
## 4. Easier debugging and profiling

import std/[tables, logging]
import ../core/types
import ../parser/[lexer, parser]
import ./activation
import ./objects
import ./evaluator

type
  VMStatus* = enum
    vmRunning     # Normal execution
    vmYielded     # Processor yielded, can be resumed
    vmCompleted   # Execution finished
    vmError       # Error occurred

  VMResult* = object
    status*: VMStatus
    value*: NodeValue
    error*: string

# Work frame constructors
proc newEvalFrame*(node: Node): WorkFrame =
  WorkFrame(kind: wfEvalNode, node: node)

proc newSendMessageFrame*(selector: string, argCount: int): WorkFrame =
  WorkFrame(kind: wfSendMessage, selector: selector, argCount: argCount)

proc newAfterReceiverFrame*(selector: string, args: seq[Node]): WorkFrame =
  WorkFrame(kind: wfAfterReceiver, pendingSelector: selector, pendingArgs: args, currentArgIndex: 0)

proc newAfterArgFrame*(selector: string, args: seq[Node], currentIndex: int): WorkFrame =
  WorkFrame(kind: wfAfterArg, pendingSelector: selector, pendingArgs: args, currentArgIndex: currentIndex)

proc newApplyBlockFrame*(blockVal: BlockNode, argCount: int): WorkFrame =
  WorkFrame(kind: wfApplyBlock, blockVal: blockVal, argCount: argCount)

proc newReturnValueFrame*(value: NodeValue): WorkFrame =
  WorkFrame(kind: wfReturnValue, returnValue: value)

proc newCascadeFrame*(messages: seq[MessageNode], receiver: NodeValue): WorkFrame =
  WorkFrame(kind: wfCascade, cascadeMessages: messages, cascadeReceiver: receiver)

proc newPopActivationFrame*(savedReceiver: Instance, isBlock: bool = false, evalStackDepth: int = 0): WorkFrame =
  WorkFrame(kind: wfPopActivation, savedReceiver: savedReceiver, isBlockActivation: isBlock, savedEvalStackDepth: evalStackDepth)

proc newIfBranchFrame*(condResult: bool, thenBlock, elseBlock: BlockNode): WorkFrame =
  ## Create a work frame for conditional branch (ifTrue:, ifFalse:)
  WorkFrame(kind: wfIfBranch, conditionResult: condResult, thenBlock: thenBlock, elseBlock: elseBlock)

proc newWhileLoopFrame*(loopKind: bool, conditionBlock, bodyBlock: BlockNode, loopState: LoopState): WorkFrame =
  ## Create a work frame for while loop (whileTrue:, whileFalse:)
  WorkFrame(kind: wfWhileLoop, loopKind: loopKind, conditionBlock: conditionBlock, bodyBlock: bodyBlock, loopState: loopState)

# Stack operations
proc pushWorkFrame*(interp: var Interpreter, frame: WorkFrame) =
  interp.workQueue.add(frame)

proc popWorkFrame*(interp: var Interpreter): WorkFrame =
  if interp.workQueue.len == 0:
    raise newException(ValueError, "Work queue underflow")
  result = interp.workQueue.pop()

proc hasWorkFrames*(interp: Interpreter): bool =
  interp.workQueue.len > 0

proc pushValue*(interp: var Interpreter, value: NodeValue) =
  debug("VM: pushValue ", value.toString(), " (stack len will be ", interp.evalStack.len + 1, ")")
  interp.evalStack.add(value)

proc popValue*(interp: var Interpreter): NodeValue =
  if interp.evalStack.len == 0:
    raise newException(ValueError, "Eval stack underflow")
  result = interp.evalStack.pop()
  debug("VM: popValue ", result.toString(), " (stack len now ", interp.evalStack.len, ")")

proc peekValue*(interp: Interpreter): NodeValue =
  if interp.evalStack.len == 0:
    raise newException(ValueError, "Eval stack empty")
  interp.evalStack[^1]

proc popValues*(interp: var Interpreter, count: int): seq[NodeValue] =
  ## Pop multiple values in reverse order (first argument was pushed first)
  result = newSeq[NodeValue](count)
  for i in countdown(count - 1, 0):
    result[i] = interp.popValue()

# Clear VM state
proc clearVMState*(interp: var Interpreter) =
  interp.workQueue.setLen(0)
  interp.evalStack.setLen(0)

# Handle evaluation of simple nodes (Phase 2)
proc handleEvalNode(interp: var Interpreter, frame: WorkFrame): bool =
  ## Handle wfEvalNode work frame. Returns true if processing should continue.
  let node = frame.node
  if node == nil:
    interp.pushValue(nilValue())
    return true

  case node.kind
  of nkLiteral:
    let lit = cast[LiteralNode](node)
    interp.pushValue(lit.value)
    return true

  of nkIdent:
    let ident = cast[IdentNode](node)
    let value = lookupVariable(interp, ident.name)
    interp.pushValue(value)
    return true

  of nkPseudoVar:
    let pseudo = cast[PseudoVarNode](node)
    case pseudo.name
    of "self":
      if interp.currentReceiver == nil:
        interp.pushValue(nilValue())
      # For class methods, self should return the Class object
      # We track this via activation.isClassMethod rather than structural checks
      elif interp.currentActivation != nil and interp.currentActivation.isClassMethod:
        interp.pushValue(interp.currentReceiver.class.toValue())
      else:
        interp.pushValue(interp.currentReceiver.toValue().unwrap())
    of "nil":
      interp.pushValue(nilValue())
    of "true":
      interp.pushValue(trueValue)
    of "false":
      interp.pushValue(falseValue)
    of "super":
      if interp.currentReceiver != nil:
        interp.pushValue(interp.currentReceiver.toValue().unwrap())
      else:
        interp.pushValue(nilValue())
    else:
      interp.pushValue(nilValue())
    return true

  of nkBlock:
    # Block literal - create a copy and capture environment
    let origBlock = cast[BlockNode](node)
    let blockNode = BlockNode(
      parameters: origBlock.parameters,
      temporaries: origBlock.temporaries,
      body: origBlock.body,
      isMethod: origBlock.isMethod,
      capturedEnv: initTable[string, MutableCell](),
      capturedEnvInitialized: true,
      homeActivation: interp.currentActivation
    )
    captureEnvironment(interp, blockNode)
    interp.pushValue(NodeValue(kind: vkBlock, blockVal: blockNode))
    return true

  of nkAssign:
    # Variable assignment: evaluate expression, then assign
    let assign = cast[AssignNode](node)
    # Push continuation frame to handle assignment after expression is evaluated
    interp.pushWorkFrame(WorkFrame(
      kind: wfAfterArg,  # Reuse for assignment continuation
      pendingSelector: "__assign__",  # Internal marker for assignment (not a valid selector)
      pendingArgs: @[],
      currentArgIndex: 0
    ))
    # Extend frame with variable name (store in selector field)
    interp.workQueue[^1].selector = assign.variable
    # Evaluate expression
    interp.pushWorkFrame(newEvalFrame(assign.expression))
    return true

  of nkSlotAccess:
    # Slot access - O(1) direct instance variable access by index
    let slotNode = cast[SlotAccessNode](node)
    if interp.currentReceiver != nil and interp.currentReceiver.kind == ikObject:
      let inst = interp.currentReceiver
      if slotNode.slotIndex >= 0 and slotNode.slotIndex < inst.slots.len:
        if slotNode.isAssignment:
          # Assignment: need to evaluate valueExpr first
          if slotNode.valueExpr != nil:
            # Push continuation to handle slot assignment
            interp.pushWorkFrame(WorkFrame(
              kind: wfAfterArg,
              pendingSelector: ":=",
              currentArgIndex: slotNode.slotIndex
            ))
            interp.pushWorkFrame(newEvalFrame(slotNode.valueExpr))
            return true
          else:
            interp.pushValue(nilValue())
            return true
        else:
          # Read slot value
          interp.pushValue(inst.slots[slotNode.slotIndex])
          return true
    interp.pushValue(nilValue())
    return true

  of nkMessage:
    # Message send - will be implemented in Phase 3
    # For now, push placeholder frames
    let msg = cast[MessageNode](node)

    # First evaluate receiver (or use self if nil)
    if msg.receiver != nil:
      interp.pushWorkFrame(newAfterReceiverFrame(msg.selector, msg.arguments))
      interp.pushWorkFrame(newEvalFrame(msg.receiver))
    else:
      # Implicit self as receiver
      if interp.currentReceiver == nil:
        interp.pushValue(nilValue())
      else:
        interp.pushValue(interp.currentReceiver.toValue().unwrap())
      # Now handle arguments
      if msg.arguments.len == 0:
        interp.pushWorkFrame(newSendMessageFrame(msg.selector, 0))
      else:
        interp.pushWorkFrame(newAfterArgFrame(msg.selector, msg.arguments, 0))
        interp.pushWorkFrame(newEvalFrame(msg.arguments[0]))
    return true

  of nkReturn:
    # Return - evaluate expression and push return frame
    let ret = cast[ReturnNode](node)
    if ret.expression != nil:
      # Push placeholder with vkNil (NOT nilValue() which may be vkInstance)
      # This signals to wfReturnValue to pop the value from the stack
      interp.pushWorkFrame(WorkFrame(kind: wfReturnValue, returnValue: NodeValue(kind: vkNil)))
      interp.pushWorkFrame(newEvalFrame(ret.expression))
    else:
      # Return self
      if interp.currentReceiver != nil:
        interp.pushWorkFrame(newReturnValueFrame(interp.currentReceiver.toValue().unwrap()))
      else:
        interp.pushWorkFrame(WorkFrame(kind: wfReturnValue, returnValue: NodeValue(kind: vkNil)))
    return true

  of nkArray:
    # Array literal - evaluate elements
    let arr = cast[ArrayNode](node)
    if arr.elements.len == 0:
      if arrayClass != nil:
        interp.pushValue(newArrayInstance(arrayClass, @[]).toValue())
      else:
        interp.pushValue(NodeValue(kind: vkArray, arrayVal: @[]))
    else:
      # Push build-array frame first (will execute last)
      interp.pushWorkFrame(WorkFrame(kind: wfBuildArray, argCount: arr.elements.len))
      # Push element evaluation frames in reverse order
      for i in countdown(arr.elements.len - 1, 0):
        let elem = arr.elements[i]
        # Handle special cases for array literals (symbols, keywords)
        if elem.kind == nkIdent:
          let ident = cast[IdentNode](elem)
          case ident.name
          of "true":
            interp.pushWorkFrame(WorkFrame(kind: wfEvalNode, node: PseudoVarNode(name: "true")))
          of "false":
            interp.pushWorkFrame(WorkFrame(kind: wfEvalNode, node: PseudoVarNode(name: "false")))
          of "nil":
            interp.pushWorkFrame(WorkFrame(kind: wfEvalNode, node: PseudoVarNode(name: "nil")))
          else:
            # Bare identifier in array literal is treated as symbol
            interp.pushWorkFrame(WorkFrame(kind: wfEvalNode, node: LiteralNode(value: getSymbol(ident.name))))
        else:
          interp.pushWorkFrame(newEvalFrame(elem))
    return true

  of nkTable:
    # Table literal - evaluate key-value pairs and build table
    let tab = cast[TableNode](node)
    if tab.entries.len == 0:
      if tableClass != nil:
        interp.pushValue(newTableInstance(tableClass, initTable[NodeValue, NodeValue]()).toValue())
      else:
        interp.pushValue(NodeValue(kind: vkTable, tableVal: initTable[NodeValue, NodeValue]()))
    else:
      # Push build-table frame first (will execute last)
      interp.pushWorkFrame(WorkFrame(kind: wfBuildTable, argCount: tab.entries.len * 2))
      # Push key-value evaluation frames in reverse order (values first, then keys)
      for i in countdown(tab.entries.len - 1, 0):
        let entry = tab.entries[i]
        interp.pushWorkFrame(newEvalFrame(entry.value))  # Value
        interp.pushWorkFrame(newEvalFrame(entry.key))    # Key
    return true

  of nkCascade:
    # Cascade messages - evaluate receiver once, then send each message to same receiver
    let cascade = cast[CascadeNode](node)
    if cascade.messages.len == 0:
      # No messages, just evaluate receiver
      interp.pushWorkFrame(newEvalFrame(cascade.receiver))
    else:
      # Push cascade continuation frame to handle multiple messages
      interp.pushWorkFrame(newCascadeFrame(cascade.messages, nilValue()))
      # Evaluate receiver first
      interp.pushWorkFrame(newEvalFrame(cascade.receiver))
    return true

  of nkSuperSend:
    # Super send - lookup method in parent class
    let superNode = cast[SuperSendNode](node)

    if interp.currentReceiver == nil:
      raise newException(ValueError, "super send with no current receiver")

    # Get the defining class from the current activation
    var definingClass: Class = nil
    if interp.currentActivation != nil and interp.currentActivation.definingObject != nil:
      definingClass = interp.currentActivation.definingObject
    else:
      definingClass = interp.currentReceiver.class

    if definingClass == nil:
      raise newException(ValueError, "super send with no defining class")

    # Determine which parent to look in
    var targetParent: Class = nil
    if superNode.explicitParent.len > 0:
      # Qualified super<Parent>: find specific parent by name
      for parent in definingClass.superclasses:
        if parent.name == superNode.explicitParent:
          targetParent = parent
          break
      if targetParent == nil:
        raise newException(ValueError, "Parent class '" & superNode.explicitParent & "' not found in inheritance chain")
    else:
      # Unqualified super: use first parent of the defining class
      if definingClass.superclasses.len == 0:
        raise newException(ValueError, "super send in class with no parents")
      targetParent = definingClass.superclasses[0]

    # Look up method in target parent's allMethods
    let methodBlock = lookupInstanceMethod(targetParent, superNode.selector)
    if methodBlock == nil:
      raise newException(ValueError, "Method '" & superNode.selector & "' not found in super class " & targetParent.name)

    # Push self as receiver for super send
    interp.pushValue(interp.currentReceiver.toValue().unwrap())

    # Evaluate arguments and send message
    if superNode.arguments.len == 0:
      # No arguments - create send frame directly, passing targetParent as definingClass
      # We need a special frame for super sends to pass the defining class
      interp.pushWorkFrame(WorkFrame(
        kind: wfSendMessage,
        selector: superNode.selector,
        argCount: 0,
        pendingSelector: targetParent.name  # Store target class name here for super lookup
      ))
    else:
      # Push after-arg frame that will handle super send with targetParent
      interp.pushWorkFrame(WorkFrame(
        kind: wfAfterArg,
        pendingSelector: "__super_send__",
        pendingArgs: @[],
        currentArgIndex: 0,
        selector: superNode.selector & "|" & targetParent.name  # Combined selector|targetParent
      ))
      interp.pushWorkFrame(newEvalFrame(superNode.arguments[0]))
    return true

  of nkObjectLiteral:
    # Object literal - create new Table instance with properties
    let objLit = cast[ObjectLiteralNode](node)
    if objLit.properties.len == 0:
      # Empty object literal
      if tableClass != nil:
        interp.pushValue(newTableInstance(tableClass, initTable[NodeValue, NodeValue]()).toValue())
      else:
        interp.pushValue(NodeValue(kind: vkTable, tableVal: initTable[NodeValue, NodeValue]()))
    else:
      # Push build-object-literal frame (reuses wfBuildTable with string keys)
      interp.pushWorkFrame(WorkFrame(kind: wfBuildTable, argCount: objLit.properties.len * 2))
      # Push property value evaluations in reverse order
      for i in countdown(objLit.properties.len - 1, 0):
        let prop = objLit.properties[i]
        # Property name as string value
        interp.pushWorkFrame(WorkFrame(kind: wfEvalNode, node: LiteralNode(value: toValue(prop.name))))
        interp.pushWorkFrame(newEvalFrame(prop.value))
    return true

  of nkPrimitive:
    # Primitive - evaluate fallback
    let prim = cast[PrimitiveNode](node)
    if prim.fallback.len > 0:
      # Evaluate fallback statements
      for i in countdown(prim.fallback.len - 1, 0):
        if i < prim.fallback.len - 1:
          # Pop intermediate results (only keep last)
          interp.pushWorkFrame(WorkFrame(kind: wfAfterArg, pendingSelector: "discard"))
        interp.pushWorkFrame(newEvalFrame(prim.fallback[i]))
    else:
      interp.pushValue(nilValue())
    return true

  of nkPrimitiveCall:
    # Primitive call - dispatch via standard method lookup on currentReceiver
    let primCall = cast[PrimitiveCallNode](node)
    debug("VM: Primitive call #", primCall.selector, " with ", primCall.arguments.len, " args")

    # Push currentReceiver as the receiver
    if interp.currentReceiver != nil:
      interp.pushValue(interp.currentReceiver.toValue().unwrap())
    else:
      interp.pushValue(nilValue())

    # Use the same continuation mechanism as message sends
    if primCall.arguments.len > 0:
      interp.pushWorkFrame(newAfterReceiverFrame(primCall.selector, primCall.arguments))
    else:
      interp.pushWorkFrame(newSendMessageFrame(primCall.selector, 0))
    return true

# Handle continuation frames (what to do after subexpression)
proc handleContinuation(interp: var Interpreter, frame: WorkFrame): bool =
  case frame.kind
  of wfAfterReceiver:
    # Receiver is on stack, now evaluate arguments
    if frame.pendingArgs.len == 0:
      # No arguments - send message now
      interp.pushWorkFrame(newSendMessageFrame(frame.pendingSelector, 0))
    else:
      # Evaluate first argument
      interp.pushWorkFrame(newAfterArgFrame(frame.pendingSelector, frame.pendingArgs, 0))
      interp.pushWorkFrame(newEvalFrame(frame.pendingArgs[0]))
    return true

  of wfAfterArg:
    # Special case: assignment continuation
    if frame.pendingSelector == "__assign__":
      let value = interp.popValue()
      setVariable(interp, frame.selector, value)
      interp.pushValue(value)
      return true

    # Special case: slot assignment continuation
    if frame.pendingSelector == ":=":
      let value = interp.popValue()
      if interp.currentReceiver != nil and interp.currentReceiver.kind == ikObject:
        let slotIndex = frame.currentArgIndex
        if slotIndex >= 0 and slotIndex < interp.currentReceiver.slots.len:
          interp.currentReceiver.slots[slotIndex] = value
      interp.pushValue(value)
      return true

    # Special case: discard continuation (for primitive fallback)
    if frame.pendingSelector == "discard":
      discard interp.popValue()
      return true

    # Argument evaluated, check if more
    let nextIndex = frame.currentArgIndex + 1
    if nextIndex < frame.pendingArgs.len:
      # More arguments to evaluate
      interp.pushWorkFrame(newAfterArgFrame(frame.pendingSelector, frame.pendingArgs, nextIndex))
      interp.pushWorkFrame(newEvalFrame(frame.pendingArgs[nextIndex]))
    else:
      # All arguments evaluated - send message
      interp.pushWorkFrame(newSendMessageFrame(frame.pendingSelector, frame.pendingArgs.len))
    return true

  of wfSendMessage:
    # Pop args and receiver, send message
    let args = interp.popValues(frame.argCount)
    let receiverVal = interp.popValue()

    # Handle block invocation
    if receiverVal.kind == vkBlock:
      case frame.selector
      of "value", "value:", "value:value:", "value:value:value:", "value:value:value:value:":
        interp.pushWorkFrame(newApplyBlockFrame(receiverVal.blockVal, args.len))
        # Push args back for block application
        for arg in args:
          interp.pushValue(arg)
        return true
      else:
        discard  # Fall through to regular dispatch

    # Convert receiver to Instance for method lookup
    var receiver: Instance
    case receiverVal.kind
    of vkInstance:
      receiver = receiverVal.instVal
    of vkInt:
      receiver = newIntInstance(integerClass, receiverVal.intVal)
    of vkFloat:
      receiver = newFloatInstance(floatClass, receiverVal.floatVal)
    of vkString:
      receiver = newStringInstance(stringClass, receiverVal.strVal)
    of vkBool:
      # Boolean - create ikObject instance with nimValue
      let p = cast[pointer](alloc(sizeof(bool)))
      cast[ptr bool](p)[] = receiverVal.boolVal
      var boolInst: Instance
      new(boolInst)
      boolInst.kind = ikObject
      boolInst.class = if receiverVal.boolVal: trueClassCache else: falseClassCache
      boolInst.slots = @[]
      boolInst.isNimProxy = true
      boolInst.nimValue = p
      receiver = boolInst
    of vkNil:
      receiver = nilInstance
    of vkArray:
      receiver = newArrayInstance(arrayClass, receiverVal.arrayVal)
    of vkTable:
      receiver = newTableInstance(tableClass, receiverVal.tableVal)
    of vkClass:
      # Class method lookup
      let cls = receiverVal.classVal
      let lookup = evaluator.lookupClassMethod(cls, frame.selector)
      if lookup.found:
        let currentMethod = lookup.currentMethod

        # Handle native class methods
        if currentMethod.nativeImpl != nil:
          let savedReceiver = interp.currentReceiver
          try:
            var resultVal: NodeValue
            if currentMethod.hasInterpreterParam:
              # Native method with interpreter - needs class receiver wrapper
              let classReceiver = Instance(kind: ikObject, class: cls, slots: @[], isNimProxy: false, nimValue: nil)
              type NativeProcWithInterp = proc(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.}
              let nativeProc = cast[NativeProcWithInterp](currentMethod.nativeImpl)
              resultVal = nativeProc(interp, classReceiver, args)
            else:
              # Direct class method without interpreter param
              type ClassMethodProc = proc(self: Class, args: seq[NodeValue]): NodeValue {.nimcall.}
              let nativeProc = cast[ClassMethodProc](currentMethod.nativeImpl)
              resultVal = nativeProc(cls, args)
            interp.pushValue(resultVal)
          finally:
            interp.currentReceiver = savedReceiver
          return true

        # Interpreted class method - create activation with class wrapper as receiver
        let classReceiver = Instance(kind: ikObject, class: cls, slots: @[], isNimProxy: false, nimValue: nil)

        # Check parameter count
        if currentMethod.parameters.len != args.len:
          raise newException(ValueError,
            "Wrong number of arguments: expected " & $currentMethod.parameters.len &
            ", got " & $args.len)

        # Create activation (isClassMethod = true for class methods)
        let activation = newActivation(currentMethod, classReceiver, interp.currentActivation, lookup.definingClass, isClassMethod = true)

        # Bind parameters
        for i in 0..<currentMethod.parameters.len:
          activation.locals[currentMethod.parameters[i]] = args[i]

        # Save current receiver
        let savedReceiver = interp.currentReceiver

        # Push activation
        interp.activationStack.add(activation)
        interp.currentActivation = activation
        interp.currentReceiver = classReceiver

        # Set home activation for methods
        if currentMethod.isMethod:
          currentMethod.homeActivation = activation

        # Push pop-activation frame (save eval stack depth for return unwinding)
        interp.pushWorkFrame(newPopActivationFrame(savedReceiver, isBlock = false, evalStackDepth = interp.evalStack.len))

        # Push method body
        if currentMethod.body.len > 0:
          for i in countdown(currentMethod.body.len - 1, 0):
            if i < currentMethod.body.len - 1:
              interp.pushWorkFrame(WorkFrame(kind: wfAfterArg, pendingSelector: "discard"))
            interp.pushWorkFrame(newEvalFrame(currentMethod.body[i]))
        else:
          interp.pushValue(nilValue())

        return true
      else:
        raise newException(ValueError, "Class method not found: " & frame.selector)
    of vkBlock:
      # Create Block instance with the BlockNode stored in nimValue
      var blockInst: Instance
      new(blockInst)
      blockInst.kind = ikObject
      blockInst.class = blockClass
      blockInst.slots = @[]
      blockInst.isNimProxy = false
      blockInst.nimValue = cast[pointer](receiverVal.blockVal)
      receiver = blockInst
    of vkSymbol:
      receiver = newStringInstance(stringClass, receiverVal.symVal)

    # Special stackless handling for control flow primitives
    if receiver.isNimProxy and receiver.kind == ikObject and receiver.class != nil:
      # Boolean ifTrue:/ifFalse: - use stackless work frames
      if (receiver.class == trueClassCache or receiver.class == falseClassCache) and args.len > 0 and args[0].kind == vkBlock:
        case frame.selector
        of "ifTrue:":
          let boolVal = cast[ptr bool](receiver.nimValue)[]
          if boolVal:
            # True - execute then block
            interp.pushWorkFrame(newIfBranchFrame(true, args[0].blockVal, nil))
          else:
            # False - push nil result
            interp.pushValue(nilValue())
          return true
        of "ifFalse:":
          let boolVal = cast[ptr bool](receiver.nimValue)[]
          if not boolVal:
            # False - execute then block (the block passed to ifFalse:)
            interp.pushWorkFrame(newIfBranchFrame(true, args[0].blockVal, nil))
          else:
            # True - push nil result
            interp.pushValue(nilValue())
          return true
        else:
          discard  # Fall through to regular method dispatch

    # Special stackless handling for block whileTrue:/whileFalse:
    if receiver.kind == ikObject and receiver.class == blockClass and not receiver.isNimProxy and args.len > 0 and args[0].kind == vkBlock:
      let conditionBlock = cast[BlockNode](receiver.nimValue)
      let bodyBlock = args[0].blockVal
      case frame.selector
      of "whileTrue:":
        # Evaluate condition first, then body if true
        interp.pushWorkFrame(newWhileLoopFrame(true, conditionBlock, bodyBlock, lsEvaluateCondition))
        return true
      of "whileFalse:":
        # Evaluate condition first, then body if false
        interp.pushWorkFrame(newWhileLoopFrame(false, conditionBlock, bodyBlock, lsEvaluateCondition))
        return true
      else:
        discard  # Fall through to regular method dispatch

    if receiver == nil:
      raise newException(ValueError, "Cannot send message to nil receiver")

    # Look up method
    debug("VM: Looking up method '", frame.selector, "' on ", (if receiver.class != nil: receiver.class.name else: "nil"))
    let lookup = lookupMethod(interp, receiver, frame.selector)
    if not lookup.found:
      raise newException(ValueError, "Method not found: " & frame.selector & " on " &
        (if receiver.class != nil: receiver.class.name else: "unknown"))

    # Check for native implementation
    let currentMethod = lookup.currentMethod
    debug("VM: Found method '", frame.selector, "', native=", currentMethod.nativeImpl != nil)
    if currentMethod.nativeImpl != nil:
      # Call native method
      debug("VM: Calling native method '", frame.selector, "'")
      let savedReceiver = interp.currentReceiver
      try:
        var resultVal: NodeValue
        if currentMethod.hasInterpreterParam:
          debug("VM: Native method has interpreter param")
          type NativeProcWithInterp = proc(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.}
          let nativeProc = cast[NativeProcWithInterp](currentMethod.nativeImpl)
          resultVal = nativeProc(interp, receiver, args)
          debug("VM: Native method returned: ", resultVal.toString())
        else:
          type NativeProc = proc(self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.}
          let nativeProc = cast[NativeProc](currentMethod.nativeImpl)
          resultVal = nativeProc(receiver, args)
        interp.pushValue(resultVal)
      finally:
        interp.currentReceiver = savedReceiver
      return true

    # Interpreted method - create activation and execute body
    debug("VM: Executing interpreted method '", frame.selector, "' with ", args.len, " args, body has ", currentMethod.body.len, " statements")

    # Check parameter count
    if currentMethod.parameters.len != args.len:
      raise newException(ValueError,
        "Wrong number of arguments: expected " & $currentMethod.parameters.len &
        ", got " & $args.len)

    # Create activation
    let activation = newActivation(currentMethod, receiver, interp.currentActivation, lookup.definingClass)

    # Bind parameters
    for i in 0..<currentMethod.parameters.len:
      activation.locals[currentMethod.parameters[i]] = args[i]

    # Save current receiver to restore after method completes
    let savedReceiver = interp.currentReceiver

    # Push activation
    interp.activationStack.add(activation)
    interp.currentActivation = activation
    interp.currentReceiver = receiver

    # Set home activation for methods
    if currentMethod.isMethod:
      currentMethod.homeActivation = activation

    # Push pop-activation frame FIRST (will execute LAST after body completes)
    interp.pushWorkFrame(newPopActivationFrame(savedReceiver, isBlock = false, evalStackDepth = interp.evalStack.len))

    # Push method body statements in reverse order
    if currentMethod.body.len > 0:
      for i in countdown(currentMethod.body.len - 1, 0):
        if i < currentMethod.body.len - 1:
          # Pop intermediate results (keep only last statement's result)
          interp.pushWorkFrame(WorkFrame(kind: wfAfterArg, pendingSelector: "discard"))
        interp.pushWorkFrame(newEvalFrame(currentMethod.body[i]))
    else:
      # Empty body returns nil
      interp.pushValue(nilValue())

    return true

  of wfApplyBlock:
    # Apply block with args on stack
    let args = interp.popValues(frame.argCount)
    let blockNode = frame.blockVal

    # Check argument count
    if blockNode.parameters.len != args.len:
      raise newException(ValueError,
        "Wrong number of arguments to block: expected " & $blockNode.parameters.len &
        ", got " & $args.len)

    # Block's home activation determines 'self'
    let blockHome = blockNode.homeActivation
    let blockReceiver = if blockHome != nil and blockHome.receiver != nil:
                          blockHome.receiver
                        else:
                          interp.currentReceiver

    # Create activation
    let activation = newActivation(blockNode, blockReceiver, interp.currentActivation)

    # Bind captured environment
    if blockNode.capturedEnvInitialized and blockNode.capturedEnv.len > 0:
      for name, cell in blockNode.capturedEnv:
        activation.locals[name] = cell.value

    # Bind parameters
    for i in 0..<blockNode.parameters.len:
      activation.locals[blockNode.parameters[i]] = args[i]

    # Initialize temporaries
    for tempName in blockNode.temporaries:
      activation.locals[tempName] = nilValue()

    # Save current receiver to restore after block completes
    let savedReceiver = interp.currentReceiver

    # Push activation
    interp.activationStack.add(activation)
    interp.currentActivation = activation
    interp.currentReceiver = blockReceiver

    # Push pop-activation frame FIRST (will execute LAST after body completes)
    # Store the block in the frame so we can save captured vars back
    var popFrame = newPopActivationFrame(savedReceiver, isBlock = true, evalStackDepth = interp.evalStack.len)
    popFrame.blockVal = blockNode
    interp.pushWorkFrame(popFrame)

    # Push block body statements in reverse order
    if blockNode.body.len > 0:
      for i in countdown(blockNode.body.len - 1, 0):
        if i < blockNode.body.len - 1:
          interp.pushWorkFrame(WorkFrame(kind: wfAfterArg, pendingSelector: "discard"))
        interp.pushWorkFrame(newEvalFrame(blockNode.body[i]))
    else:
      # Empty body returns nil
      interp.pushValue(nilValue())

    return true

  of wfPopActivation:
    # Pop activation after method/block body completes
    # The result value is on top of the eval stack
    debug("VM: wfPopActivation, evalStack.len=", interp.evalStack.len)
    let resultValue = if interp.evalStack.len > 0:
                        interp.popValue()
                      else:
                        nilValue()
    debug("VM: wfPopActivation resultValue=", resultValue.toString())

    # For blocks, save captured variables back to their cells
    if frame.isBlockActivation and frame.blockVal != nil:
      let blockNode = frame.blockVal
      if blockNode.capturedEnvInitialized and blockNode.capturedEnv.len > 0:
        let activation = interp.currentActivation
        if activation != nil:
          for name, cell in blockNode.capturedEnv:
            if name in activation.locals:
              cell.value = activation.locals[name]

    # Check for non-local return
    if interp.currentActivation != nil and interp.currentActivation.hasReturned:
      # Non-local return - propagate the return value
      let returnVal = interp.currentActivation.returnValue

      # Pop the activation
      discard interp.activationStack.pop()
      if interp.activationStack.len > 0:
        interp.currentActivation = interp.activationStack[^1]
        interp.currentReceiver = interp.currentActivation.receiver
      else:
        interp.currentActivation = nil
        interp.currentReceiver = frame.savedReceiver

      interp.pushValue(returnVal.unwrap())
    else:
      # Normal completion - pop activation and push result
      discard interp.activationStack.pop()
      if interp.activationStack.len > 0:
        interp.currentActivation = interp.activationStack[^1]
        interp.currentReceiver = interp.currentActivation.receiver
      else:
        interp.currentActivation = nil
        interp.currentReceiver = frame.savedReceiver

      interp.pushValue(resultValue.unwrap())

    return true

  of wfReturnValue:
    # Handle return (^ expression) - must unwind work queue to target activation
    let value = if frame.returnValue.kind != vkNil:
                  frame.returnValue
                else:
                  interp.popValue()
    let returnVal = value.unwrap()

    # Find target activation for the return
    # For blocks, target is homeActivation (the enclosing method)
    # For methods, target is the current activation
    var targetActivation: Activation = nil
    if interp.currentActivation != nil and interp.currentActivation.currentMethod != nil:
      let currentMethod = interp.currentActivation.currentMethod
      if not currentMethod.isMethod and currentMethod.homeActivation != nil:
        targetActivation = currentMethod.homeActivation
      else:
        targetActivation = interp.currentActivation

    if targetActivation == nil:
      # No target - just push value (shouldn't happen in well-formed code)
      interp.pushValue(returnVal)
      return true

    # Unwind: pop work frames until we find and process the wfPopActivation
    # for the target activation. For each intermediate wfPopActivation (blocks),
    # pop the corresponding activation from the activation stack.
    debug("VM: wfReturnValue unwinding to target activation")
    var found = false
    var targetEvalStackDepth = 0
    while interp.workQueue.len > 0 and not found:
      let wf = interp.workQueue.pop()
      if wf.kind == wfPopActivation:
        # Save captured vars for blocks
        if wf.isBlockActivation and wf.blockVal != nil:
          let blockNode = wf.blockVal
          if blockNode.capturedEnvInitialized and blockNode.capturedEnv.len > 0:
            let act = interp.currentActivation
            if act != nil:
              for name, cell in blockNode.capturedEnv:
                if name in act.locals:
                  cell.value = act.locals[name]

        # Check if the current activation is the target
        if interp.currentActivation == targetActivation:
          # Save the eval stack depth to restore to
          targetEvalStackDepth = wf.savedEvalStackDepth

          # Pop the target activation
          discard interp.activationStack.pop()
          if interp.activationStack.len > 0:
            interp.currentActivation = interp.activationStack[^1]
            interp.currentReceiver = interp.currentActivation.receiver
          else:
            interp.currentActivation = nil
            interp.currentReceiver = wf.savedReceiver
          found = true
        else:
          # Pop intermediate activation (block)
          if interp.activationStack.len > 0:
            discard interp.activationStack.pop()
            if interp.activationStack.len > 0:
              interp.currentActivation = interp.activationStack[^1]
              interp.currentReceiver = interp.currentActivation.receiver

    # Restore eval stack to the depth before the target activation was pushed
    if interp.evalStack.len > targetEvalStackDepth:
      interp.evalStack.setLen(targetEvalStackDepth)
    interp.pushValue(returnVal)
    return true

  of wfCascade:
    # Cascade - receiver is on stack, send each message to same receiver
    let receiverVal = interp.peekValue()  # Keep receiver on stack for next message
    let messages = frame.cascadeMessages

    if messages.len == 0:
      # No messages to send, just leave receiver on stack as result
      return true

    # Pop the receiver for processing (we'll push results back)
    discard interp.popValue()

    # Save original receiver and set cascade receiver
    let savedReceiver = interp.currentReceiver

    # Convert receiverVal to Instance
    var receiver: Instance
    case receiverVal.kind
    of vkInstance:
      receiver = receiverVal.instVal
    of vkInt:
      receiver = newIntInstance(integerClass, receiverVal.intVal)
    of vkFloat:
      receiver = newFloatInstance(floatClass, receiverVal.floatVal)
    of vkString:
      receiver = newStringInstance(stringClass, receiverVal.strVal)
    of vkArray:
      receiver = newArrayInstance(arrayClass, receiverVal.arrayVal)
    of vkTable:
      receiver = newTableInstance(tableClass, receiverVal.tableVal)
    of vkBool:
      let p = cast[pointer](alloc(sizeof(bool)))
      cast[ptr bool](p)[] = receiverVal.boolVal
      var boolInst: Instance
      new(boolInst)
      boolInst.kind = ikObject
      boolInst.class = if receiverVal.boolVal: trueClassCache else: falseClassCache
      boolInst.slots = @[]
      boolInst.isNimProxy = true
      boolInst.nimValue = p
      receiver = boolInst
    of vkBlock:
      var blockInst: Instance
      new(blockInst)
      blockInst.kind = ikObject
      blockInst.class = blockClass
      blockInst.slots = @[]
      blockInst.isNimProxy = false
      blockInst.nimValue = cast[pointer](receiverVal.blockVal)
      receiver = blockInst
    else:
      raise newException(ValueError, "Cascade to unsupported value kind: " & $receiverVal.kind)

    # Set current receiver for message sends
    interp.currentReceiver = receiver

    # For now, handle single message (push result) or loop for all messages
    # To properly handle multiple messages without recursion, we need to:
    # 1. Push frames for each message in reverse order
    # 2. Each message will leave its result on stack
    # 3. Only keep the last result

    if messages.len == 1:
      # Single message - just send it
      let msg = messages[0]
      interp.pushWorkFrame(WorkFrame(
        kind: wfAfterReceiver,
        pendingSelector: msg.selector,
        pendingArgs: msg.arguments,
        currentArgIndex: 0
      ))
      interp.pushValue(receiverVal)  # Push receiver back for the message send
    else:
      # Multiple messages - push them in reverse order with cascade continuation
      # Push a final frame to restore receiver and keep only last result
      interp.pushWorkFrame(WorkFrame(kind: wfRestoreReceiver, savedReceiver: savedReceiver))

      # Push all message frames in reverse order
      for i in countdown(messages.len - 1, 0):
        let msg = messages[i]
        if i == messages.len - 1:
          # Last message - keep its result
          interp.pushWorkFrame(WorkFrame(
            kind: wfCascadeMessage,
            pendingSelector: msg.selector,
            pendingArgs: msg.arguments,
            currentArgIndex: 0,
            cascadeReceiver: receiverVal  # Store receiver for this message
          ))
        else:
          # Intermediate message - discard result, keep receiver
          interp.pushWorkFrame(WorkFrame(
            kind: wfCascadeMessageDiscard,
            pendingSelector: msg.selector,
            pendingArgs: msg.arguments,
            currentArgIndex: 0,
            cascadeReceiver: receiverVal
          ))

    return true

  of wfBuildArray:
    # Build array from N values on stack
    let count = frame.argCount
    var elements = newSeq[NodeValue](count)
    # Pop in reverse order to maintain original order
    for i in countdown(count - 1, 0):
      elements[i] = interp.popValue()
    if arrayClass != nil:
      interp.pushValue(newArrayInstance(arrayClass, elements).toValue())
    else:
      interp.pushValue(NodeValue(kind: vkArray, arrayVal: elements))
    return true

  of wfBuildTable:
    # Build table from key-value pairs on stack
    # Stack has: ... key1 value1 key2 value2 ... (in reverse order of pushing)
    # We need to pop values in pairs and build the table
    let pairCount = frame.argCount div 2
    var entries = initTable[NodeValue, NodeValue]()
    for i in 0..<pairCount:
      let value = interp.popValue()
      let key = interp.popValue()
      entries[key] = value
    if tableClass != nil:
      interp.pushValue(newTableInstance(tableClass, entries).toValue())
    else:
      interp.pushValue(NodeValue(kind: vkTable, tableVal: entries))
    return true

  of wfCascadeMessage, wfCascadeMessageDiscard:
    # Send a message in a cascade - receiver is stored in cascadeReceiver
    let receiverVal = frame.cascadeReceiver

    # Convert receiver to Instance
    var receiver: Instance
    case receiverVal.kind
    of vkInstance:
      receiver = receiverVal.instVal
    of vkInt:
      receiver = newIntInstance(integerClass, receiverVal.intVal)
    of vkFloat:
      receiver = newFloatInstance(floatClass, receiverVal.floatVal)
    of vkString:
      receiver = newStringInstance(stringClass, receiverVal.strVal)
    of vkArray:
      receiver = newArrayInstance(arrayClass, receiverVal.arrayVal)
    of vkTable:
      receiver = newTableInstance(tableClass, receiverVal.tableVal)
    of vkBool:
      let p = cast[pointer](alloc(sizeof(bool)))
      cast[ptr bool](p)[] = receiverVal.boolVal
      var boolInst: Instance
      new(boolInst)
      boolInst.kind = ikObject
      boolInst.class = if receiverVal.boolVal: trueClassCache else: falseClassCache
      boolInst.slots = @[]
      boolInst.isNimProxy = true
      boolInst.nimValue = p
      receiver = boolInst
    of vkBlock:
      var blockInst: Instance
      new(blockInst)
      blockInst.kind = ikObject
      blockInst.class = blockClass
      blockInst.slots = @[]
      blockInst.isNimProxy = false
      blockInst.nimValue = cast[pointer](receiverVal.blockVal)
      receiver = blockInst
    else:
      raise newException(ValueError, "Cascade to unsupported value kind: " & $receiverVal.kind)

    # Set current receiver
    interp.currentReceiver = receiver

    # Push receiver value for message send
    interp.pushValue(receiverVal)

    # Now handle arguments and send message
    if frame.pendingArgs.len == 0:
      interp.pushWorkFrame(newSendMessageFrame(frame.pendingSelector, 0))
    else:
      interp.pushWorkFrame(newAfterArgFrame(frame.pendingSelector, frame.pendingArgs, 0))
      interp.pushWorkFrame(newEvalFrame(frame.pendingArgs[0]))
    return true

  of wfRestoreReceiver:
    # Restore original receiver after cascade completes
    interp.currentReceiver = frame.savedReceiver
    return true

  of wfIfBranch:
    # Handle conditional branch (ifTrue: or ifFalse:)
    if frame.conditionResult:
      # Condition is true - execute then block
      interp.pushWorkFrame(newApplyBlockFrame(frame.thenBlock, 0))
    elif frame.elseBlock != nil:
      # Condition is false - execute else block
      interp.pushWorkFrame(newApplyBlockFrame(frame.elseBlock, 0))
    else:
      # No else block - return nil
      interp.pushValue(nilValue())
    return true

  of wfWhileLoop:
    # Handle while loop (whileTrue: or whileFalse:)
    case frame.loopState
    of lsEvaluateCondition:
      # Push frame to check condition after it's evaluated
      interp.pushWorkFrame(WorkFrame(kind: wfWhileLoop, loopKind: frame.loopKind,
                                      conditionBlock: frame.conditionBlock,
                                      bodyBlock: frame.bodyBlock,
                                      loopState: lsCheckCondition))
      interp.pushWorkFrame(newApplyBlockFrame(frame.conditionBlock, 0))
      return true
    of lsCheckCondition:
      # Check the condition result on the stack
      let conditionResult = interp.peekValue()
      let condBool = conditionResult.isTruthy()
      let shouldContinue = if frame.loopKind: condBool else: not condBool
      discard interp.popValue()  # Clean up condition result
      if shouldContinue:
        # Continue loop - execute body
        interp.pushWorkFrame(WorkFrame(kind: wfWhileLoop, loopKind: frame.loopKind,
                                        conditionBlock: frame.conditionBlock,
                                        bodyBlock: frame.bodyBlock,
                                        loopState: lsExecuteBody))
        interp.pushWorkFrame(newApplyBlockFrame(frame.bodyBlock, 0))
      else:
        # Loop done - push nil result
        interp.pushValue(nilValue())
      return true
    of lsExecuteBody:
      # Transition to lsLoopBody state (will be used after body completes)
      interp.pushWorkFrame(WorkFrame(kind: wfWhileLoop, loopKind: frame.loopKind,
                                      conditionBlock: frame.conditionBlock,
                                      bodyBlock: frame.bodyBlock,
                                      loopState: lsLoopBody))
      return true
    of lsLoopBody:
      # Body completed - discard body result and loop back to condition
      discard interp.popValue()
      interp.pushWorkFrame(WorkFrame(kind: wfWhileLoop, loopKind: frame.loopKind,
                                      conditionBlock: frame.conditionBlock,
                                      bodyBlock: frame.bodyBlock,
                                      loopState: lsEvaluateCondition))
      return true
    of lsDone:
      return true

  of wfEvalNode:
    # Should not reach here - wfEvalNode is handled in handleEvalNode
    return handleEvalNode(interp, frame)

# Main execution loop
proc runASTInterpreter*(interp: var Interpreter): VMResult =
  ## Main execution loop for the explicit stack AST interpreter
  ## Returns when:
  ## - Work queue is empty (vmCompleted)
  ## - Processor yields (vmYielded)
  ## - Error occurs (vmError)

  while interp.hasWorkFrames():
    # Check for yield
    if interp.shouldYield:
      interp.shouldYield = false
      return VMResult(status: vmYielded, value: interp.peekValue())

    let frame = interp.popWorkFrame()
    debug("VM: Processing frame kind=", frame.kind)

    try:
      let shouldContinue = case frame.kind
        of wfEvalNode:
          handleEvalNode(interp, frame)
        else:
          handleContinuation(interp, frame)

      if not shouldContinue:
        break
    except ValueError as e:
      return VMResult(status: vmError, error: e.msg)
    except Exception as e:
      return VMResult(status: vmError, error: "VM error: " & e.msg)

  # Execution complete
  let resultValue = if interp.evalStack.len > 0:
                      interp.evalStack[^1]
                    else:
                      nilValue()

  return VMResult(status: vmCompleted, value: resultValue)

# Entry point to evaluate an expression using the new VM
proc evalWithVM*(interp: var Interpreter, node: Node): NodeValue =
  ## Evaluate an expression using the explicit stack VM
  ## Handles re-entrancy by saving/restoring VM state for nested calls
  if node == nil:
    return nilValue()

  # Save current VM state for re-entrancy support
  let savedWorkQueue = interp.workQueue
  let savedEvalStack = interp.evalStack

  # Initialize fresh VM state for this evaluation
  interp.workQueue = @[newEvalFrame(node)]
  interp.evalStack = @[]

  # Run the VM
  let vmResult = interp.runASTInterpreter()

  # Get result before restoring state
  let resultValue = case vmResult.status
    of vmCompleted, vmYielded:
      vmResult.value
    of vmError:
      raise newException(ValueError, vmResult.error)
    of vmRunning:
      nilValue()

  # Restore previous VM state
  interp.workQueue = savedWorkQueue
  interp.evalStack = savedEvalStack

  return resultValue

proc doitStackless*(interp: var Interpreter, source: string, dumpAst = false): (NodeValue, string) =
  ## Parse and evaluate source code using the stackless VM
  let tokens = lex(source)
  var parser = initParser(tokens)
  let nodes = parser.parseStatements()

  if parser.hasError:
    return (nilValue(), "Parse error: " & parser.errorMsg)

  if nodes.len == 0:
    return (nilValue(), "No expression to evaluate")

  # Dump AST if requested
  if dumpAst:
    echo "AST:"
    for node in nodes:
      echo printAST(node)

  # Evaluate all nodes using stackless VM, return last result
  try:
    var lastResult = nilValue()
    for node in nodes:
      lastResult = interp.evalWithVM(node)
    interp.lastResult = lastResult
    return (lastResult, "")
  except ValueError:
    raise
  except EvalError as e:
    return (nilValue(), "Runtime error: " & e.msg)
  except Exception as e:
    return (nilValue(), "Error: " & e.msg)

proc evalStatementsStackless*(interp: var Interpreter, source: string): (seq[NodeValue], string) =
  ## Parse and evaluate multiple statements using the stackless VM
  let tokens = lex(source)
  var parser = initParser(tokens)
  let nodes = parser.parseStatements()

  if parser.hasError:
    return (@[], "Parse error: " & parser.errorMsg)

  var results = newSeq[NodeValue]()

  try:
    for node in nodes:
      let evalResult = interp.evalWithVM(node)
      results.add(evalResult)
    return (results, "")
  except ValueError:
    raise
  except EvalError as e:
    return (@[], "Runtime error: " & e.msg)
  except Exception as e:
    return (@[], "Error: " & e.msg)

proc evalForProcess*(interp: var Interpreter, node: Node): (NodeValue, VMStatus) =
  ## Evaluate a node for a process, preserving VM state across yields.
  ## This is used by the scheduler to execute one statement at a time,
  ## allowing proper yield/resume semantics.
  ##
  ## If node is nil and work queue has pending frames, continues from work queue.
  ## If node is not nil and work queue is empty, pushes node onto work queue.
  ##
  ## Returns (value, status) where status indicates if the VM yielded,
  ## completed, or encountered an error.
  if node == nil and interp.workQueue.len == 0:
    return (nilValue(), vmCompleted)

  # If work queue is empty, push the new node
  if interp.workQueue.len == 0:
    interp.workQueue.add(newEvalFrame(node))
  # If work queue has pending work (resuming from yield), continue execution
  # without pushing a new frame

  # Run the VM (continues from where it left off if resuming)
  let vmResult = interp.runASTInterpreter()

  return (vmResult.value, vmResult.status)
