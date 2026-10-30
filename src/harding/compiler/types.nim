import std/[strutils]
import ../core/types

# ============================================================================
# Type System for Compiler
# Handles type constraints, type hints, and type inference
# ============================================================================

type
  TypeConstraint* = enum
    tcNone            ## No type constraint (dynamic)
    tcInt             ## Integer constraint
    tcFloat           ## Float constraint
    tcString          ## String constraint
    tcBool            ## Boolean constraint
    tcObject          ## Object reference
    tcBlock           ## Block/closure
    tcArray           ## Array of values
    tcTable           ## Hash table
    tcSymbol          ## Symbol payload (distinct from String)

proc toNimType*(constraint: TypeConstraint): string =
  ## Convert type constraint to Nim type name
  case constraint
  of tcNone: "NodeValue"
  of tcInt: "int"
  of tcFloat: "float64"
  of tcString, tcSymbol: "string"
  of tcBool: "bool"
  of tcObject, tcBlock, tcArray: "NodeValue"
  of tcTable: "Table[string, NodeValue]"

proc toValueKind*(constraint: TypeConstraint): string =
  ## Convert type constraint to ValueKind enum value
  case constraint
  of tcNone: "vkNone"
  of tcInt: "vkInt"
  of tcFloat: "vkFloat"
  of tcString: "vkString"
  of tcSymbol: "vkSymbol"
  of tcBool: "vkBool"
  of tcObject: "vkObject"
  of tcBlock: "vkBlock"
  of tcArray: "vkArray"
  of tcTable: "vkTable"

proc parseTypeHint*(hint: string): TypeConstraint =
  ## Parse type hint string to TypeConstraint
  case hint.toLowerAscii()
  of "int", "integer": tcInt
  of "float", "float64": tcFloat
  of "string", "str": tcString
  of "bool", "boolean": tcBool
  of "symbol": tcSymbol
  of "object", "obj": tcObject
  of "block", "closure": tcBlock
  of "array": tcArray
  of "table", "hash", "dict": tcTable
  else: tcNone

proc isNumeric*(constraint: TypeConstraint): bool =
  ## Check if type constraint is a numeric type
  constraint == tcInt or constraint == tcFloat

proc unifies*(a, b: TypeConstraint): bool =
  ## Check if two type constraints are compatible
  if a == tcNone or b == tcNone:
    return true
  if a == b:
    return true
  if isNumeric(a) and isNumeric(b):
    return false  ## Require explicit conversion for int<->float
  return false

proc constraintForNode*(kind: ValueKind): TypeConstraint =
  ## Infer type constraint from ValueKind
  case kind
  of vkInt: tcInt
  of vkFloat: tcFloat
  of vkString: tcString
  of vkBool: tcBool
  of vkBlock: tcBlock
  of vkArray: tcArray
  of vkTable: tcTable
  of vkClass: tcObject  # Class is treated as Object for now
  of vkInstance: tcObject  # Instance is treated as Object for now
  of vkSymbol: tcSymbol
  of vkNil: tcNone

const typeConstraintNames*: array[TypeConstraint, string] = [
  "None", "Int", "Float", "String", "Bool",
  "Object", "Block", "Array", "Table", "Symbol"
]

proc `$`*(constraint: TypeConstraint): string =
  typeConstraintNames[constraint]
