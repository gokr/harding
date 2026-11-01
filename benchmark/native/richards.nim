# Native Nim port of benchmark/richards.hrd (Chromium Octane reference).
# Copyright 2006-2008 the V8 project authors. BSD-3-Clause.
# See ../licenses/RICHARDS.txt. Arithmetic bit helpers and teardown retained.
import std/[os, strutils]

type
  Packet = ref object
    link: Packet
    identity, kind, datum: int
    data: array[4, int]
  TaskKind = enum idle, worker, handler, device
  Task = ref object
    link: Task
    identity, priority, state: int
    queue: Packet
    kind: TaskKind
    control, count, destination: int
    pending, workIn, deviceIn: Packet
  Scheduler = object
    queueCount, holdCount, currentId: int
    blocks: array[6, Task]
    list, current: Task

proc xor16(left, right: int): int =
  var a = left
  var b = right
  var place = 1
  while place < 65536:
    let abit = a - ((a div 2) * 2)
    let bbit = b - ((b div 2) * 2)
    if abit != bbit: result += place
    a = a div 2
    b = b div 2
    place *= 2

proc addTo(packet, queue: Packet): Packet =
  packet.link = nil
  if queue == nil: return packet
  var tail = queue
  var next = tail.link
  while next != nil:
    tail = next
    next = tail.link
  tail.link = packet
  queue

proc markRunnable(task: Task) =
  if (task.state - ((task.state div 2) * 2)) == 0: inc task.state

proc queue(scheduler: var Scheduler, packet: Packet): Task =
  let task = scheduler.blocks[packet.identity]
  if task == nil: return nil
  inc scheduler.queueCount
  packet.link = nil
  packet.identity = scheduler.currentId
  if task.queue == nil:
    task.queue = packet
    task.markRunnable()
    if task.priority > scheduler.current.priority: return task
  else:
    task.queue = packet.addTo(task.queue)
  scheduler.current

proc holdCurrent(scheduler: var Scheduler): Task =
  inc scheduler.holdCount
  if scheduler.current.state < 4: scheduler.current.state += 4
  scheduler.current.link

proc suspendCurrent(scheduler: var Scheduler): Task =
  if (scheduler.current.state - ((scheduler.current.state div 4) * 4)) < 2:
    scheduler.current.state += 2
  scheduler.current

proc release(scheduler: var Scheduler, identity: int): Task =
  let task = scheduler.blocks[identity]
  if task == nil: return nil
  if task.state >= 4: task.state -= 4
  if task.priority > scheduler.current.priority: task else: scheduler.current

proc run(task: Task, packet: Packet, scheduler: var Scheduler): Task =
  case task.kind
  of idle:
    dec task.count
    if task.count == 0: return scheduler.holdCurrent()
    if (task.control - ((task.control div 2) * 2)) == 0:
      task.control = task.control div 2
      return scheduler.release(4)
    task.control = xor16(task.control div 2, 53256)
    return scheduler.release(5)
  of device:
    if packet == nil:
      if task.pending == nil: return scheduler.suspendCurrent()
      let work = task.pending
      task.pending = nil
      return scheduler.queue(work)
    task.pending = packet
    return scheduler.holdCurrent()
  of worker:
    if packet == nil: return scheduler.suspendCurrent()
    task.destination = if task.destination == 2: 3 else: 2
    packet.identity = task.destination
    packet.datum = 0
    for index in 0..<4:
      inc task.count
      if task.count > 26: task.count = 1
      packet.data[index] = task.count
    return scheduler.queue(packet)
  of handler:
    if packet != nil:
      if packet.kind == 1: task.workIn = packet.addTo(task.workIn)
      else: task.deviceIn = packet.addTo(task.deviceIn)
    if task.workIn != nil:
      let count = task.workIn.datum
      if count < 4:
        if task.deviceIn != nil:
          let work = task.deviceIn
          task.deviceIn = work.link
          work.datum = task.workIn.data[count]
          task.workIn.datum = count + 1
          return scheduler.queue(work)
      else:
        let work = task.workIn
        task.workIn = work.link
        return scheduler.queue(work)
    return scheduler.suspendCurrent()

proc addTask(scheduler: var Scheduler, id, priority: int, queue: Packet, kind: TaskKind) =
  let task = Task(link: scheduler.list, identity: id, priority: priority,
    queue: queue, kind: kind, state: if queue == nil: 2 else: 3)
  scheduler.current = task
  scheduler.list = task
  scheduler.blocks[id] = task

proc benchmark*(): tuple[queued, held: int] =
  var scheduler: Scheduler
  scheduler.addTask(0, 0, nil, idle)
  scheduler.current.control = 1
  scheduler.current.count = 1000
  scheduler.current.state = 0
  var queue = Packet(identity: 1, kind: 1)
  queue = Packet(link: queue, identity: 1, kind: 1)
  scheduler.addTask(1, 1000, queue, worker)
  scheduler.current.destination = 2
  queue = Packet(identity: 4, kind: 0)
  queue = Packet(link: queue, identity: 4, kind: 0)
  queue = Packet(link: queue, identity: 4, kind: 0)
  scheduler.addTask(2, 2000, queue, handler)
  queue = Packet(identity: 5, kind: 0)
  queue = Packet(link: queue, identity: 5, kind: 0)
  queue = Packet(link: queue, identity: 5, kind: 0)
  scheduler.addTask(3, 3000, queue, handler)
  scheduler.addTask(4, 4000, nil, device)
  scheduler.addTask(5, 5000, nil, device)
  scheduler.current = scheduler.list
  while scheduler.current != nil:
    let task = scheduler.current
    if task.state >= 4 or task.state == 2:
      scheduler.current = task.link
    else:
      scheduler.currentId = task.identity
      var packet: Packet
      if task.state == 3:
        packet = task.queue
        task.queue = packet.link
        task.state = if task.queue == nil: 0 else: 1
      scheduler.current = task.run(packet, scheduler)
  result = (scheduler.queueCount, scheduler.holdCount)
  doAssert result == (2322, 928), "Richards counters differ"
  # Native variant embeds task-body state in the control block and passes the
  # scheduler by reference, so no task->scheduler reference cycle is created.
  scheduler.blocks = default(array[6, Task])
  scheduler.list = nil
  scheduler.current = nil

when isMainModule:
  let repetitions = if paramCount() > 0: parseInt(paramStr(1)) else: 1
  doAssert repetitions >= 0
  var queued, held = 0
  for iteration in 0..<repetitions:
    let counts = benchmark()
    queued += counts.queued
    held += counts.held
  echo "Richards queued=", queued, " held=", held
