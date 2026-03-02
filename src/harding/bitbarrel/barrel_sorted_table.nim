## ============================================================================
## BitBarrel BarrelSortedTable
## Native implementation for BarrelSortedTable class - ordered persistent table
## ============================================================================

when defined(bitbarrel):
  import std/[tables, strutils]
  import ../core/types
  import ../interpreter/objects
  import ../interpreter/vm
  import ./client/client

  ## Forward declarations
  proc initBarrelSortedTableClass*(interp: var Interpreter)
  proc barrelSortedTableNewImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.}

  ## Native method implementations

  proc barrelSortedTableAtImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
    ## Get value at key: at: key
    if args.len < 1:
      return nilValue()

    let key = args[0].toString()

    if self.isNimProxy and self.nimValue != nil:
      let client = cast[ptr BitBarrelClient](self.nimValue)
      try:
        let value = client[].get(key)
        return value.toValue()
      except:
        return nilValue()

    nilValue()

  proc barrelSortedTableAtPutImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
    ## Set value at key: at:put: key value
    if args.len < 2:
      return self.toValue()

    let key = args[0].toString()
    let value = args[1].toString()

    if self.isNimProxy and self.nimValue != nil:
      let client = cast[ptr BitBarrelClient](self.nimValue)
      try:
        discard client[].set(key, value)
      except:
        discard

    self.toValue()

  proc barrelSortedTableKeysImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
    ## Get all keys as Array (in sorted order for critbit)
    if self.isNimProxy and self.nimValue != nil:
      let client = cast[ptr BitBarrelClient](self.nimValue)
      try:
        let keys = client[].listKeys()
        # Convert to Harding Array
        let arrClass = getArrayClass(interp)
        var result = newInstance(arrClass)
        for key in keys:
          result.elements.add(key.toValue())
        return result.toValue()
      except:
        discard

    nilValue()

  proc barrelSortedTableSizeImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
    ## Get number of entries
    if self.isNimProxy and self.nimValue != nil:
      let client = cast[ptr BitBarrelClient](self.nimValue)
      try:
        let count = client[].count()
        return count.toValue()
      except:
        discard

    0.toValue()

  proc barrelSortedTableRangeQueryImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
    ## Range query: rangeFrom:to:limit: startKey endKey limit
    if args.len < 2:
      return nilValue()

    let startKey = args[0].toString()
    let endKey = args[1].toString()
    var limit = 1000
    if args.len >= 3:
      limit = args[2].toInt()

    if self.isNimProxy and self.nimValue != nil:
      let client = cast[ptr BitBarrelClient](self.nimValue)
      try:
        let (pairs, _, _) = client[].rangeQuery(startKey, endKey, limit)
        # Convert to Harding Table
        let tableClass = getTableClass(interp)
        var result = newInstance(tableClass)
        for (key, value) in pairs:
          result.entries[key.toValue()] = value.toValue()
        return result.toValue()
      except:
        discard

    nilValue()

  proc barrelSortedTablePrefixQueryImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
    ## Prefix query: prefix:limit: prefix limit
    if args.len < 1:
      return nilValue()

    let prefix = args[0].toString()
    var limit = 1000
    if args.len >= 2:
      limit = args[1].toInt()

    if self.isNimProxy and self.nimValue != nil:
      let client = cast[ptr BitBarrelClient](self.nimValue)
      try:
        let (pairs, _, _) = client[].prefixQuery(prefix, limit)
        # Convert to Harding Table
        let tableClass = getTableClass(interp)
        var result = newInstance(tableClass)
        for (key, value) in pairs:
          result.entries[key.toValue()] = value.toValue()
        return result.toValue()
      except:
        discard

    nilValue()

  ## Implementation of new method
  proc barrelSortedTableNewImpl*(interp: var Interpreter, self: Instance, args: seq[NodeValue]): NodeValue {.nimcall.} =
    ## Create new BarrelSortedTable instance
    var cls: Class = nil
    if "BarrelSortedTable" in interp.globals[]:
      let val = interp.globals[]["BarrelSortedTable"]
      if val.kind == vkClass:
        cls = val.classVal
    if cls == nil:
      cls = objectClass

    let obj = newInstance(cls)
    obj.isNimProxy = true
    result = obj.toValue()

  ## Initialize BarrelSortedTable class
  proc initBarrelSortedTableClass*(interp: var Interpreter) =
    ## Initialize and register the BarrelSortedTable class

    var objectCls: Class = nil
    if "Object" in interp.globals[]:
      let val = interp.globals[]["Object"]
      if val.kind == vkClass:
        objectCls = val.classVal

    if objectCls == nil:
      warn("Object class not found, cannot create BarrelSortedTable class")
      return

    let sortedTableCls = newClass(superclasses = @[objectCls], name = "BarrelSortedTable")
    sortedTableCls.tags = @["BitBarrel", "Table", "Persistent", "Sorted", "Ordered"]
    sortedTableCls.isNimProxy = true
    sortedTableCls.hardingType = "BarrelSortedTable"

    let newMethod = createCoreMethod("new")
    newMethod.nativeImpl = cast[pointer](barrelSortedTableNewImpl)
    newMethod.hasInterpreterParam = true
    addMethodToClass(sortedTableCls, "new", newMethod, isClassMethod = true)

    let atMethod = createCoreMethod("at:")
    atMethod.nativeImpl = cast[pointer](barrelSortedTableAtImpl)
    atMethod.hasInterpreterParam = true
    addMethodToClass(sortedTableCls, "at:", atMethod)

    let atPutMethod = createCoreMethod("at:put:")
    atPutMethod.nativeImpl = cast[pointer](barrelSortedTableAtPutImpl)
    atPutMethod.hasInterpreterParam = true
    addMethodToClass(sortedTableCls, "at:put:", atPutMethod)

    let keysMethod = createCoreMethod("keys")
    keysMethod.nativeImpl = cast[pointer](barrelSortedTableKeysImpl)
    keysMethod.hasInterpreterParam = true
    addMethodToClass(sortedTableCls, "keys", keysMethod)

    let sizeMethod = createCoreMethod("size")
    sizeMethod.nativeImpl = cast[pointer](barrelSortedTableSizeImpl)
    sizeMethod.hasInterpreterParam = true
    addMethodToClass(sortedTableCls, "size", sizeMethod)

    let rangeQueryMethod = createCoreMethod("rangeFrom:to:limit:")
    rangeQueryMethod.nativeImpl = cast[pointer](barrelSortedTableRangeQueryImpl)
    rangeQueryMethod.hasInterpreterParam = true
    addMethodToClass(sortedTableCls, "rangeFrom:to:limit:", rangeQueryMethod)

    let prefixQueryMethod = createCoreMethod("prefix:limit:")
    prefixQueryMethod.nativeImpl = cast[pointer](barrelSortedTablePrefixQueryImpl)
    prefixQueryMethod.hasInterpreterParam = true
    addMethodToClass(sortedTableCls, "prefix:limit:", prefixQueryMethod)

    interp.globals[]["BarrelSortedTable"] = sortedTableCls.toValue()
    debug("Registered BarrelSortedTable class")

else:
  import ../core/types
  import ../interpreter/objects

  proc initBarrelSortedTableClass*(interp: var Interpreter) =
    debug("BarrelSortedTable class not available (compile with -d:bitbarrel)")
