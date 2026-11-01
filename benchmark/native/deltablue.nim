# SPDX-License-Identifier: GPL-2.0-or-later
# Native Nim port of benchmark/deltablue.hrd (pinned Chromium Octane variant).
# Copyright 2008 the V8 project authors; Copyright 1996 John Maloney and Mario Wolczko.
# See ../licenses/DELTABLUE.txt and ../licenses/GPL-2.0.txt.
# LIFO worklists, strength mapping, ownership teardown and checks retained.
import std/[os, strutils, math]

type
  Variable = ref object
    value: float
    constraints: seq[Constraint]
    determinedBy: Constraint
    mark, walkStrength: int
    stay: bool
    name: string
  ConstraintKind = enum stayConstraint, editConstraint, equalityConstraint, scaleConstraint
  Constraint = ref object
    kind: ConstraintKind
    strength: int
    planner: Planner
    v1, v2, scale, offset: Variable
    direction: int
    satisfied: bool
  Planner = ref object
    currentMark: int
    variables: seq[Variable]
    owned: seq[Constraint]

const
  required = 0
  preferred = 2
  strongDefault = 3
  normal = 4
  weakest = 6

proc nextWeaker(strength: int): int =
  case strength
  of 0: 6
  of 1: 5
  of 2: 4
  of 3: 3
  of 4: 2
  of 5: 0
  else: -1

proc isUnary(constraint: Constraint): bool =
  constraint.kind in {stayConstraint, editConstraint}

proc isSatisfied(constraint: Constraint): bool =
  if constraint.isUnary(): constraint.satisfied else: constraint.direction != 0

proc output(constraint: Constraint): Variable =
  if constraint.isUnary(): constraint.v1
  elif constraint.direction == 1: constraint.v2
  else: constraint.v1

proc input(constraint: Constraint): Variable =
  if constraint.direction == 1: constraint.v1 else: constraint.v2

proc isInput(constraint: Constraint): bool = constraint.kind == editConstraint

proc variable(planner: Planner, name: string, value: float): Variable =
  result = Variable(name: name, value: value, stay: true, walkStrength: weakest)
  planner.variables.add(result)

proc newMark(planner: Planner): int =
  inc planner.currentMark
  planner.currentMark

proc removeConstraint(variable: Variable, constraint: Constraint) =
  var index = variable.constraints.high
  while index >= 0:
    if variable.constraints[index] == constraint: variable.constraints.delete(index)
    dec index
  if variable.determinedBy == constraint: variable.determinedBy = nil

proc markUnsatisfied(constraint: Constraint) =
  if constraint.isUnary(): constraint.satisfied = false
  else: constraint.direction = 0

proc removeFromGraph(constraint: Constraint) =
  if constraint.v1 != nil: constraint.v1.removeConstraint(constraint)
  if not constraint.isUnary() and constraint.v2 != nil: constraint.v2.removeConstraint(constraint)
  if constraint.kind == scaleConstraint:
    if constraint.scale != nil: constraint.scale.removeConstraint(constraint)
    if constraint.offset != nil: constraint.offset.removeConstraint(constraint)
  constraint.markUnsatisfied()

proc execute(constraint: Constraint) =
  case constraint.kind
  of stayConstraint, editConstraint: discard
  of equalityConstraint: constraint.output().value = constraint.input().value
  of scaleConstraint:
    if constraint.direction == 1:
      constraint.v2.value = constraint.v1.value * constraint.scale.value + constraint.offset.value
    else:
      constraint.v1.value = (constraint.v2.value - constraint.offset.value) / constraint.scale.value

proc recalculate(constraint: Constraint) =
  let outputVariable = constraint.output()
  if constraint.isUnary():
    outputVariable.walkStrength = constraint.strength
    outputVariable.stay = not constraint.isInput()
  else:
    let inputVariable = constraint.input()
    outputVariable.walkStrength = max(constraint.strength, inputVariable.walkStrength)
    outputVariable.stay = inputVariable.stay
    if constraint.kind == scaleConstraint:
      outputVariable.stay = outputVariable.stay and constraint.scale.stay and constraint.offset.stay
  if outputVariable.stay: constraint.execute()

proc chooseMethod(constraint: Constraint, mark: int) =
  if constraint.isUnary():
    constraint.satisfied = constraint.v1.mark != mark and constraint.strength < constraint.v1.walkStrength
    return
  let v1 = constraint.v1
  let v2 = constraint.v2
  if v1.mark == mark:
    constraint.direction = if v2.mark != mark and constraint.strength < v2.walkStrength: 1 else: 0
  if v2.mark == mark:
    constraint.direction = if v1.mark != mark and constraint.strength < v1.walkStrength: -1 else: 0
  if v1.walkStrength > v2.walkStrength:
    constraint.direction = if constraint.strength < v1.walkStrength: -1 else: 0
  else:
    constraint.direction = if constraint.strength < v2.walkStrength: 1 else: -1

proc markInputs(constraint: Constraint, mark: int) =
  if not constraint.isUnary():
    constraint.input().mark = mark
    if constraint.kind == scaleConstraint:
      constraint.scale.mark = mark
      constraint.offset.mark = mark

proc inputsKnown(constraint: Constraint, mark: int): bool =
  if constraint.isUnary(): return true
  let inputVariable = constraint.input()
  inputVariable.mark == mark or inputVariable.stay or inputVariable.determinedBy == nil

proc addConsuming(variable: Variable, collection: var seq[Constraint]) =
  let determining = variable.determinedBy
  var index = 0
  while index < variable.constraints.len:
    let constraint = variable.constraints[index]
    if constraint != determining and constraint.isSatisfied(): collection.add(constraint)
    inc index

proc incrementalRemove(planner: Planner, constraint: Constraint)

proc addPropagate(planner: Planner, constraint: Constraint, mark: int): bool =
  var todo = @[constraint]
  while todo.len > 0:
    let downstream = todo.pop()
    if downstream.output().mark == mark:
      planner.incrementalRemove(constraint)
      return false
    downstream.recalculate()
    addConsuming(downstream.output(), todo)
  true

proc satisfy(constraint: Constraint, mark: int): Constraint =
  constraint.chooseMethod(mark)
  if not constraint.isSatisfied():
    doAssert constraint.strength != required, "Could not satisfy a required constraint"
    return nil
  constraint.markInputs(mark)
  let outputVariable = constraint.output()
  result = outputVariable.determinedBy
  if result != nil: result.markUnsatisfied()
  outputVariable.determinedBy = constraint
  doAssert constraint.planner.addPropagate(constraint, mark), "Cycle encountered"
  outputVariable.mark = mark

proc incrementalAdd(planner: Planner, constraint: Constraint) =
  let mark = planner.newMark()
  var overridden = constraint.satisfy(mark)
  while overridden != nil: overridden = overridden.satisfy(mark)

proc removePropagateFrom(outputVariable: Variable): seq[Constraint] =
  outputVariable.determinedBy = nil
  outputVariable.walkStrength = weakest
  outputVariable.stay = true
  var todo = @[outputVariable]
  while todo.len > 0:
    let variable = todo.pop()
    var index = 0
    while index < variable.constraints.len:
      let constraint = variable.constraints[index]
      if not constraint.isSatisfied(): result.add(constraint)
      inc index
    let determining = variable.determinedBy
    index = 0
    while index < variable.constraints.len:
      let next = variable.constraints[index]
      if next != determining and next.isSatisfied():
        next.recalculate()
        todo.add(next.output())
      inc index

proc incrementalRemove(planner: Planner, constraint: Constraint) =
  let outputVariable = constraint.output()
  constraint.markUnsatisfied()
  constraint.removeFromGraph()
  let unsatisfied = removePropagateFrom(outputVariable)
  var level = required
  while true:
    for candidate in unsatisfied:
      if candidate.strength == level: planner.incrementalAdd(candidate)
    level = nextWeaker(level)
    if level == weakest: break

proc addConstraint(planner: Planner, kind: ConstraintKind, v1: Variable,
                   strength: int, v2: Variable = nil, scale: Variable = nil,
                   offset: Variable = nil): Constraint =
  result = Constraint(kind: kind, planner: planner, v1: v1, v2: v2,
    scale: scale, offset: offset, strength: strength)
  planner.owned.add(result)
  v1.constraints.add(result)
  if not result.isUnary(): v2.constraints.add(result)
  if kind == scaleConstraint:
    scale.constraints.add(result)
    offset.constraints.add(result)
  planner.incrementalAdd(result)

proc extractPlan(planner: Planner, constraints: seq[Constraint]): seq[Constraint] =
  var sources: seq[Constraint]
  for constraint in constraints:
    if constraint.isInput() and constraint.isSatisfied(): sources.add(constraint)
  let mark = planner.newMark()
  while sources.len > 0:
    let constraint = sources.pop()
    if constraint.output().mark != mark and constraint.inputsKnown(mark):
      result.add(constraint)
      constraint.output().mark = mark
      addConsuming(constraint.output(), sources)

proc execute(plan: seq[Constraint]) =
  for constraint in plan: constraint.execute()

proc change(planner: Planner, variable: Variable, value: float) =
  let edit = planner.addConstraint(editConstraint, variable, preferred)
  let plan = planner.extractPlan(@[edit])
  for iteration in 0..<10:
    variable.value = value
    plan.execute()
  if edit.isSatisfied(): planner.incrementalRemove(edit)
  else: edit.removeFromGraph()

proc dispose(planner: Planner) =
  for constraint in planner.owned:
    constraint.planner = nil
    constraint.v1 = nil
    constraint.v2 = nil
    constraint.scale = nil
    constraint.offset = nil
  for variable in planner.variables:
    variable.constraints = @[]
    variable.determinedBy = nil
  planner.owned = @[]
  planner.variables = @[]

proc chain(count: int): float =
  let planner = Planner()
  try:
    var previous, first, last: Variable
    for index in 0..count:
      let variable = planner.variable("v" & $index, 0)
      if previous != nil: discard planner.addConstraint(equalityConstraint, previous, required, variable)
      if index == 0: first = variable
      if index == count: last = variable
      previous = variable
    discard planner.addConstraint(stayConstraint, last, strongDefault)
    let edit = planner.addConstraint(editConstraint, first, preferred)
    let plan = planner.extractPlan(@[edit])
    for index in 0..<100:
      first.value = float(index)
      plan.execute()
      doAssert last.value == float(index)
    result = last.value
  finally:
    planner.dispose()

proc close(actual, expected: float) =
  doAssert abs(actual - expected) < 0.000001, "DeltaBlue projection differs"

proc projection(count: int): float =
  let planner = Planner()
  try:
    let scale = planner.variable("scale", 10)
    let offset = planner.variable("offset", 1000)
    var source, destination: Variable
    var destinations: seq[Variable]
    for index in 0..<count:
      source = planner.variable("src" & $index, float(index))
      destination = planner.variable("dst" & $index, float(index))
      destinations.add(destination)
      discard planner.addConstraint(stayConstraint, source, normal)
      discard planner.addConstraint(scaleConstraint, source, required, destination, scale, offset)
    planner.change(source, 17)
    close(destination.value, 1170)
    planner.change(destination, 1050)
    close(source.value, 5)
    planner.change(scale, 5)
    for index in 0..<count - 1: close(destinations[index].value, float(index * 5 + 1000))
    planner.change(offset, 2000)
    for index in 0..<count - 1: close(destinations[index].value, float(index * 5 + 2000))
    for destination in destinations: result += destination.value
  finally:
    planner.dispose()

proc benchmark*(): float =
  doAssert chain(100) == 99
  result = projection(100)
  close(result, 223305)

when isMainModule:
  let repetitions = if paramCount() > 0: parseInt(paramStr(1)) else: 1
  doAssert repetitions >= 0
  for iteration in 0..<repetitions: discard benchmark()
  echo "DeltaBlue runs=", repetitions, " verified"
