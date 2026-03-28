#!/usr/bin/env nim

import std/[times, algorithm, strformat, json, sequtils]
import ../src/harding/core/types
import ../src/harding/interpreter/vm

type
  Address = object
    street: string
    city: string
    region: string
    postalCode: string
    country: string

  Customer = object
    id: int
    name: string
    email: string
    vip: bool
    tags: seq[string]
    address: Address

  OrderItem = object
    sku: string
    title: string
    qty: int
    price: float
    taxable: bool
    discounts: seq[float]

  OrderPayload = object
    orderId: int
    status: string
    customer: Customer
    items: seq[OrderItem]
    notes: seq[string]
    subtotal: float
    tax: float
    total: float
    paid: bool

proc median(values: seq[float]): float =
  var sortedVals = values
  sortedVals.sort()
  let mid = sortedVals.len div 2
  if sortedVals.len mod 2 == 0:
    return (sortedVals[mid - 1] + sortedVals[mid]) / 2.0
  sortedVals[mid]

proc writeJsonString(buf: var string, s: string) =
  buf.add '"'
  for c in s:
    case c
    of '"': buf.add("\\\"")
    of '\\': buf.add("\\\\")
    of '\b': buf.add("\\b")
    of '\f': buf.add("\\f")
    of '\n': buf.add("\\n")
    of '\r': buf.add("\\r")
    of '\t': buf.add("\\t")
    else: buf.add(c)
  buf.add '"'

proc writeJsonBool(buf: var string, v: bool) =
  if v:
    buf.add("true")
  else:
    buf.add("false")

proc writeJsonFloat(buf: var string, v: float) =
  buf.add($(%v))

proc writeAddress(buf: var string, value: Address) =
  buf.add('{')
  buf.add("\"street\":")
  writeJsonString(buf, value.street)
  buf.add(",\"city\":")
  writeJsonString(buf, value.city)
  buf.add(",\"region\":")
  writeJsonString(buf, value.region)
  buf.add(",\"postalCode\":")
  writeJsonString(buf, value.postalCode)
  buf.add(",\"country\":")
  writeJsonString(buf, value.country)
  buf.add('}')

proc writeCustomer(buf: var string, value: Customer) =
  buf.add('{')
  buf.add("\"id\":")
  buf.add($value.id)
  buf.add(",\"name\":")
  writeJsonString(buf, value.name)
  buf.add(",\"email\":")
  writeJsonString(buf, value.email)
  buf.add(",\"vip\":")
  writeJsonBool(buf, value.vip)
  buf.add(",\"tags\":[")
  for i, tag in value.tags:
    if i > 0:
      buf.add(',')
    writeJsonString(buf, tag)
  buf.add("],\"address\":")
  writeAddress(buf, value.address)
  buf.add('}')

proc writeOrderItem(buf: var string, value: OrderItem) =
  buf.add('{')
  buf.add("\"sku\":")
  writeJsonString(buf, value.sku)
  buf.add(",\"title\":")
  writeJsonString(buf, value.title)
  buf.add(",\"qty\":")
  buf.add($value.qty)
  buf.add(",\"price\":")
  writeJsonFloat(buf, value.price)
  buf.add(",\"taxable\":")
  writeJsonBool(buf, value.taxable)
  buf.add(",\"discounts\":[")
  for i, discount in value.discounts:
    if i > 0:
      buf.add(',')
    writeJsonFloat(buf, discount)
  buf.add("]}")

proc toJsonDirect(value: OrderPayload): string =
  var buf = newStringOfCap(512)
  buf.add('{')
  buf.add("\"orderId\":")
  buf.add($value.orderId)
  buf.add(",\"status\":")
  writeJsonString(buf, value.status)
  buf.add(",\"customer\":")
  writeCustomer(buf, value.customer)
  buf.add(",\"items\":[")
  for i, item in value.items:
    if i > 0:
      buf.add(',')
    writeOrderItem(buf, item)
  buf.add("],\"notes\":[")
  for i, note in value.notes:
    if i > 0:
      buf.add(',')
    writeJsonString(buf, note)
  buf.add("],\"subtotal\":")
  writeJsonFloat(buf, value.subtotal)
  buf.add(",\"tax\":")
  writeJsonFloat(buf, value.tax)
  buf.add(",\"total\":")
  writeJsonFloat(buf, value.total)
  buf.add(",\"paid\":")
  writeJsonBool(buf, value.paid)
  buf.add('}')
  buf

proc toJsonStd(value: OrderPayload): string =
  $(%*{
    "orderId": value.orderId,
    "status": value.status,
    "customer": {
      "id": value.customer.id,
      "name": value.customer.name,
      "email": value.customer.email,
      "vip": value.customer.vip,
      "tags": value.customer.tags,
      "address": {
        "street": value.customer.address.street,
        "city": value.customer.address.city,
        "region": value.customer.address.region,
        "postalCode": value.customer.address.postalCode,
        "country": value.customer.address.country
      }
    },
    "items": value.items.mapIt(%*{
      "sku": it.sku,
      "title": it.title,
      "qty": it.qty,
      "price": it.price,
      "taxable": it.taxable,
      "discounts": it.discounts
    }),
    "notes": value.notes,
    "subtotal": value.subtotal,
    "tax": value.tax,
    "total": value.total,
    "paid": value.paid
  })

proc samplePayload(): OrderPayload =
  result = OrderPayload(
    orderId: 1001,
    status: "processing",
    customer: Customer(
      id: 7,
      name: "Alice Example",
      email: "alice@example.com",
      vip: true,
      tags: @["newsletter", "priority", "beta"],
      address: Address(
        street: "123 River Road",
        city: "Portland",
        region: "OR",
        postalCode: "97205",
        country: "US"
      )
    ),
    items: @[
      OrderItem(sku: "RKT-01", title: "Rocket Skates", qty: 2, price: 129.95, taxable: true, discounts: @[10.0, 5.5]),
      OrderItem(sku: "ANV-02", title: "Travel Anvil", qty: 1, price: 349.0, taxable: true, discounts: @[25.0]),
      OrderItem(sku: "MAP-03", title: "Desert Map", qty: 4, price: 7.5, taxable: false, discounts: @[])
    ],
    notes: @["leave at front desk", "fragile", "gift wrap"],
    subtotal: 646.4,
    tax: 51.71,
    total: 698.11,
    paid: false
  )

proc newJsonInterp(): Interpreter =
  result = newInterpreter()
  initGlobals(result)
  initSymbolTable()
  loadStdlib(result)
  let setup = result.evalStatements("""
    Payload := #{
      "orderId" -> 1001,
      "status" -> "processing",
      "customer" -> #{
        "id" -> 7,
        "name" -> "Alice Example",
        "email" -> "alice@example.com",
        "vip" -> true,
        "tags" -> #("newsletter", "priority", "beta"),
        "address" -> #{
          "street" -> "123 River Road",
          "city" -> "Portland",
          "region" -> "OR",
          "postalCode" -> "97205",
          "country" -> "US"
        }
      },
      "items" -> #(
        #{"sku" -> "RKT-01", "title" -> "Rocket Skates", "qty" -> 2, "price" -> 129.95, "taxable" -> true, "discounts" -> #(10.0, 5.5)}
        #{"sku" -> "ANV-02", "title" -> "Travel Anvil", "qty" -> 1, "price" -> 349.0, "taxable" -> true, "discounts" -> #(25.0)}
        #{"sku" -> "MAP-03", "title" -> "Desert Map", "qty" -> 4, "price" -> 7.5, "taxable" -> false, "discounts" -> #()}
      ),
      "notes" -> #("leave at front desk", "fragile", "gift wrap"),
      "subtotal" -> 646.4,
      "tax" -> 51.71,
      "total" -> 698.11,
      "paid" -> false
    }.
  """)
  if setup[1].len > 0:
    raise newException(ValueError, "Setup failed: " & setup[1])

proc runHardingCase(iterations: int, runs: int = 5): float =
  let code = fmt("""
    I := 0.
    [I < {iterations}] whileTrue: [
      Output := Json stringify: Payload.
      I := I + 1
    ].
    Result := Output size
  """)
  var samples: seq[float] = @[]
  for _ in 0..<runs:
    var interp = newJsonInterp()
    let start = cpuTime()
    let runResult = interp.evalStatements(code)
    let elapsed = (cpuTime() - start) * 1000.0
    if runResult[1].len > 0:
      raise newException(ValueError, "Harding case failed: " & runResult[1])
    samples.add(elapsed)

  let med = median(samples)
  var best = samples[0]
  var worst = samples[0]
  for value in samples:
    if value < best:
      best = value
    if value > worst:
      worst = value
  let name = "Harding Json stringify"
  echo fmt("{name:>24}: median {med:>8.2f} ms (best {best:>8.2f}, worst {worst:>8.2f})")
  med

proc runNimCase(name: string, iterations: int, runs: int, fn: proc()) =
  var samples: seq[float] = @[]
  for _ in 0..<runs:
    let start = cpuTime()
    for _ in 0..<iterations:
      fn()
    let elapsed = (cpuTime() - start) * 1000.0
    samples.add(elapsed)

  let med = median(samples)
  var best = samples[0]
  var worst = samples[0]
  for value in samples:
    if value < best:
      best = value
    if value > worst:
      worst = value
  echo fmt("{name:>24}: median {med:>8.2f} ms (best {best:>8.2f}, worst {worst:>8.2f})")

when isMainModule:
  let payload = samplePayload()
  let iterations = 5000
  let runs = 5

  let directSample = toJsonDirect(payload)
  let stdSample = toJsonStd(payload)
  doAssert directSample.len > 0
  doAssert stdSample.len > 0

  echo "Harding JSON stringify benchmark"
  echo "==============================="
  echo fmt("Iterations per run: {iterations}")
  echo fmt("Runs: {runs}")
  echo fmt("Pure Nim direct JSON size: {directSample.len} bytes")
  echo fmt("Pure Nim std/json size:    {stdSample.len} bytes")
  echo ""

  discard runHardingCase(iterations, runs)
  runNimCase("Nim direct writer", iterations, runs, proc() = discard toJsonDirect(payload))
  runNimCase("Nim std/json", iterations, runs, proc() = discard toJsonStd(payload))
