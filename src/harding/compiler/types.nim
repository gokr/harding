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
