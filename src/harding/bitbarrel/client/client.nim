## BitBarrel Network Client
##
## WebSocket client library for BitBarrel network operations using the
## whisky WebSocket library (https://github.com/gokr/whisky).

import std/[locks, tables, strformat, net, strutils, json, times]
import whisky
import protocol

type
  ServerInfo* = object
    ## Server information from handshake
    versionMajor*: int
    versionMinor*: int
    serverId*: string
    availablePlugins*: seq[string]

  BitBarrelClient* = object
    ## Client for BitBarrel network operations
    ##
    ## Manages a single WebSocket connection to a BitBarrel server
    ## and provides a high-level API for barrel and key-value operations
    host*: string
    port*: Port
    ws: WebSocket
    wsUrl: string
    connected*: bool
    seqCounter*: uint32
    currentBarrel*: string
    pending*: Table[uint32, Response]
    lock: Lock
    token*: string             ## JWT authentication token (if any, default: "")
    subscriptions*: Table[string, bool]  ## Track active subscriptions
    onMessage*: proc(event: PubSubEvent) {.closure, gcsafe.}  ## Pub/sub message handler
    serverInfo*: ServerInfo    ## Server information from handshake

  ClientConfig* = object
    ## Configuration for BitBarrel client connections
    host*: string              ## Server host (default: "localhost")
    port*: Port                ## Server port (default: 9876)
    connectTimeout*: int       ## Connection timeout in ms (default: 5000)
    requestTimeout*: int       ## Request timeout in ms (default: 3000)
    token*: string             ## JWT authentication token (optional, default: "")

  ClientError* = object of CatchableError
    ## Raised when client operations fail

  TraverseOptions* = object
    ## Options for reference traversal operations
    includeFullData*: bool    ## Return full values or just paths
    extractArrays*: bool      ## Extract array elements individually
    firstOnly*: bool          ## Stop after first result

  BarrelMode* = enum
    ## Index mode for a barrel
    bmHash       ## Hash table index with O(1) lookups (default)
    bmCritBit    ## CritBit tree for ordered keys and range queries

const
  DefaultHost* = "localhost"
  DefaultPort* = 9876.Port
  DefaultConnectTimeout* = 5000
  DefaultRequestTimeout* = 3000

proc defaultConfig*(): ClientConfig =
  ## Returns default client configuration
  ClientConfig(
    host: DefaultHost,
    port: DefaultPort,
    connectTimeout: DefaultConnectTimeout,
    requestTimeout: DefaultRequestTimeout,
    token: ""
  )

proc newClient*(config: ClientConfig): BitBarrelClient =
  ## Create a new BitBarrel client with configuration
  ##
  ## **Example:**
  ## ```nim
  ## var config = ClientConfig(
  ##   host: "localhost",
  ##   port: 9876.Port,
  ##   connectTimeout: 5000,
  ##   token: "eyJhbGciOiJIUzI1NiJ9..."
  ## )
  ## var client = newClient(config)
  ## ```
  let url = if config.token.len > 0:
              fmt"ws://{config.host}:{config.port}/ws?token={config.token}"
            else:
              fmt"ws://{config.host}:{config.port}/ws"
  result = BitBarrelClient(
    host: config.host,
    port: config.port,
    wsUrl: url,
    connected: false,
    seqCounter: 0,
    currentBarrel: "",
    pending: initTable[uint32, Response](),
    token: config.token,
    subscriptions: initTable[string, bool](),
    serverInfo: ServerInfo(
      versionMajor: 0,
      versionMinor: 0,
      serverId: "",
      availablePlugins: @[]
    )
  )
  initLock(result.lock)

proc newClient*(host: string = DefaultHost, port: Port = DefaultPort): BitBarrelClient =
  ## Create client with default config
  ##
  ## **Example:**
  ## ```nim
  ## # Create with defaults (localhost:9876)
  ## var client = newClient()
  ##
  ## # Create with custom host
  ## var client2 = newClient("192.168.1.100", 8080.Port)
  ## ```
  newClient(ClientConfig(host: host, port: port,
                         connectTimeout: DefaultConnectTimeout,
                         requestTimeout: DefaultRequestTimeout,
                         token: ""))

proc newClient*(host: string, port: Port, token: string): BitBarrelClient =
  ## Create a new BitBarrel client with JWT token authentication
  ##
  ## **Example:**
  ## ```nim
  ## var client = newClient("localhost", 9876.Port, "eyJhbGciOiJIUzI1NiJ9...")
  ## client.connect()
  ## ```
  newClient(ClientConfig(
    host: host,
    port: port,
    connectTimeout: DefaultConnectTimeout,
    requestTimeout: DefaultRequestTimeout,
    token: token
  ))

proc isConnected*(client: BitBarrelClient): bool =
  ## Check if client is connected
  client.connected

proc connect*(client: var BitBarrelClient) =
  ## Connect to the server
  ##
  ## Performs WebSocket handshake with the BitBarrel server.
  ## Raises ClientError if connection fails.
  ##
  ## **Example:**
  ## ```nim
  ## var client = newClient("localhost", 9876.Port)
  ## client.connect()  # Explicit connect
  ## ```
  if client.connected:
    return  # Already connected

  let url = fmt"ws://{client.host}:{client.port}/ws"
  try:
    client.ws = newWebSocket(url)

    # Wait for binary handshake message (protocol v1.1+)
    const maxAttempts = 50  # 50 * 100ms = 5 seconds
    var attempts = 0

    while attempts < maxAttempts:
      let msg = client.ws.receiveMessage(timeout = 100)
      if msg.isSome():
        let m = msg.get()
        if m.kind == BinaryMessage:
          try:
            let handshake = protocol.decodeHandshake(m.data)
            client.serverInfo = ServerInfo(
              versionMajor: int(handshake.versionMajor),
              versionMinor: int(handshake.versionMinor),
              serverId: handshake.serverId,
              availablePlugins: handshake.plugins
            )
            client.connected = true
            return
          except CatchableError:
            # Not a valid handshake, might be old server
            discard
        elif m.kind == TextMessage and m.data.contains("Connected to BitBarrel"):
          # Fallback for v1.0 servers
          client.serverInfo = ServerInfo(
            versionMajor: 1,
            versionMinor: 0,
            serverId: "",
            availablePlugins: @[]
          )
          client.connected = true
          return

      inc attempts
    raise newException(ClientError, "No handshake message received from server")

  except CatchableError as e:
    raise newException(ClientError, fmt"Failed to connect: {e.msg}")

proc close*(client: var BitBarrelClient) {.raises: [].} =
  ## Close connection to the server
  ##
  ## **Example:**
  ## ```nim
  ## var client = newClient()
  ## client.connect()
  ## # ... do work ...
  ## client.close()
  ## ```
  if client.connected:
    try:
      client.ws.close()
    except:
      discard
    client.connected = false
    client.currentBarrel = ""

proc receiveMessages*(client: var BitBarrelClient, timeoutMs: int = 100) =
  ## Receive and process pending pub/sub messages
  ##
  ## This is called automatically by sendAndWait, but can also be
  ## called manually to process pub/sub events while idle.
  ##
  ## **Example:**
  ## ```nim
  ## # Wait for messages to arrive
  ## sleep(100)
  ## client.receiveMessages(500)  # Process any pending events
  ## ```
  if not client.connected:
    return

  try:
    let msg = client.ws.receiveMessage(timeout = timeoutMs)
    if msg.isSome() and msg.get().kind == BinaryMessage:
      let data = msg.get().data

      # Check if this is a pub/sub event (command 0xFF)
      if isPubSubEvent(data):
        try:
          let event = decodePubSubEvent(data)
          if client.onMessage != nil:
            client.onMessage(event)
        except CatchableError as e:
          echo "Error handling pub/sub event: ", e.msg
  except CatchableError:
    # Timeout or other error - ignore
    discard

proc sendAndWait*(client: var BitBarrelClient, req: Request, preserveSeq: bool = false,
                   timeoutMs: int = 3000): Response =
  ## Send request and wait for response
  ##
  ## Also processes pub/sub events while waiting.
  ## Thread-safe: uses lock to prevent concurrent access.
  ## Raises ClientError on timeout or communication error.
  ## If preserveSeq is true, uses req.seq instead of generating a new one.
  ## timeoutMs: Maximum time to wait for response (default: 3000ms)
  withLock client.lock:
    var mutableReq = req
    if not preserveSeq:
      mutableReq.seq = client.seqCounter
      client.seqCounter += 1

    try:
      # Send request as binary frame
      let encodedReq = encodeRequest(mutableReq)
      when defined(debug):
        echo &"sendAndWait: seq={mutableReq.seq} command={mutableReq.command} timeout={timeoutMs}"
      client.ws.send(encodedReq, kind = BinaryMessage)

      # Wait for response
      var attempts = 0
      const pollTimeout = 100  # 100ms per poll
      let maxAttempts = timeoutMs div pollTimeout

      while attempts < maxAttempts:
        let msg = client.ws.receiveMessage(timeout = pollTimeout)
        if msg.isSome() and msg.get().kind == BinaryMessage:
          let data = msg.get().data

          # Check if this is a pub/sub event (command 0xFF)
          if isPubSubEvent(data):
            # Decode and handle pub/sub event
            try:
              let event = decodePubSubEvent(data)
              # Call onMessage callback if set
              if client.onMessage != nil:
                client.onMessage(event)
            except CatchableError as e:
              # Log error but continue waiting for response
              echo "Error handling pub/sub event: ", e.msg
            # Continue waiting for our response
            inc attempts
            continue

          # Regular response
          let resp = decodeResponse(data)
          when defined(debug):
            echo &"sendAndWait: received response seq={resp.seq} status={resp.status}"
          if resp.seq == mutableReq.seq:
            when defined(debug):
              echo &"sendAndWait: matched seq={resp.seq}"
            return resp

        inc attempts

      raise newException(ClientError, "Response timeout")

    except ClientError:
      raise
    except CatchableError as e:
      raise newException(ClientError, fmt"Communication error: {e.msg}")

# Barrel management operations

proc createBarrel*(client: var BitBarrelClient, name: string, config: string = ""): bool =
  ## Create a new barrel on the server
  ##
  ## Returns true if successful, false if barrel already exists.
  ##
  ## **Example:**
  ## ```nim
  ## var client = newClient()
  ## client.connect()
  ## discard client.createBarrel("mydb")
  ## discard client.createBarrel("ordered", """{"mode": "bmCritBit"}""")
  ## ```
  if not client.connected:
    client.connect()

  let req = Request(command: cmdCreateBarrel, key: name, value: config)
  let resp = client.sendAndWait(req)
  return resp.status == statusOk

proc createBarrel*(client: var BitBarrelClient, name: string, mode: BarrelMode): bool =
  ## Create a new barrel on the server with specified mode
  ##
  ## Returns true if successful, false if barrel already exists.
  ##
  ## **Example:**
  ## ```nim
  ## var client = newClient()
  ## client.connect()
  ## discard client.createBarrel("mydb", bmHash)
  ## discard client.createBarrel("ordered", bmCritBit)
  ## ```
  let config = case mode
    of bmHash: """{"mode": "hash"}"""
    of bmCritBit: """{"mode": "critbit"}"""
  client.createBarrel(name, config)

proc openBarrel*(client: var BitBarrelClient, name: string): bool =
  ## Open an existing barrel on the server
  ##
  ## Returns true if successful, false if barrel not found.
  ##
  ## **Example:**
  ## ```nim
  ## var client = newClient()
  ## client.connect()
  ## discard client.openBarrel("existing_db")
  ## ```
  if not client.connected:
    client.connect()

  let req = Request(command: cmdOpenBarrel, key: name)
  let resp = client.sendAndWait(req)
  return resp.status == statusOk

proc useBarrel*(client: var BitBarrelClient, name: string): bool =
  ## Set current barrel for this client session
  ##
  ## All key-value operations will use the selected barrel.
  ## Returns true if successful, false if barrel not found.
  ##
  ## **Example:**
  ## ```nim
  ## var client = newClient()
  ## client.connect()
  ## discard client.createBarrel("mydb")
  ## discard client.useBarrel("mydb")
  ## discard client.set("key", "value")
  ## ```
  if not client.connected:
    client.connect()

  let req = Request(command: cmdUseBarrel, key: name)
  let resp = client.sendAndWait(req)
  if resp.status == statusOk:
    client.currentBarrel = name
    return true
  return false

proc closeBarrel*(client: var BitBarrelClient): bool =
  ## Close the current barrel
  ##
  ## Returns true if successful, false if no barrel was selected.
  ##
  ## **Example:**
  ## ```nim
  ## var client = newClient()
  ## client.connect()
  ## discard client.useBarrel("mydb")
  ## discard client.closeBarrel()
  ## ```
  if not client.connected:
    return false

  let req = Request(command: cmdCloseBarrel)
  let resp = client.sendAndWait(req)
  if resp.status == statusOk:
    client.currentBarrel = ""
    return true
  return false

proc listBarrels*(client: var BitBarrelClient): seq[string] =
  ## List all available barrels on the server
  ##
  ## **Example:**
  ## ```nim
  ## var client = newClient()
  ## client.connect()
  ## let barrels = client.listBarrels()
  ## for name in barrels:
  ##   echo name
  ## ```
  if not client.connected:
    client.connect()

  let req = Request(command: cmdListBarrels)
  let resp = client.sendAndWait(req)
  if resp.status == statusOk and resp.value.len > 0:
    return resp.value.split(',')
  return @[]

proc dropBarrel*(client: var BitBarrelClient, name: string): bool =
  ## Delete a barrel and all its data
  ##
  ## Returns true if successful, false if barrel not found.
  ##
  ## **Example:**
  ## ```nim
  ## var client = newClient()
  ## client.connect()
  ## discard client.createBarrel("temp")
  ## discard client.dropBarrel("temp")
  ## ```
  if not client.connected:
    client.connect()

  let req = Request(command: cmdDropBarrel, key: name)
  let resp = client.sendAndWait(req)
  if resp.status == statusOk:
    if name == client.currentBarrel:
      client.currentBarrel = ""
    return true
  return false

proc getBarrelConfig*(client: var BitBarrelClient, name: string): string =
  ## Get the configuration for a barrel
  ##
  ## Returns the barrel configuration as a JSON string.
  ## Raises ClientError if barrel not found.
  ##
  ## **Example:**
  ## ```nim
  ## var client = newClient()
  ## client.connect()
  ## discard client.createBarrel("mydb", """{"mode": "critbit"}""")
  ## let config = client.getBarrelConfig("mydb")
  ## echo config  # {"mode": "critbit"}
  ## ```
  if not client.connected:
    client.connect()

  let req = Request(command: cmdGetBarrelConfig, key: name)
  let resp = client.sendAndWait(req)

  if resp.status == statusBarrelNotFound:
    raise newException(ClientError, fmt"Barrel not found: {name}")
  elif resp.status != statusOk:
    raise newException(ClientError, fmt"Get barrel config failed: {resp.status}")

  return resp.value

proc setBarrelConfig*(client: var BitBarrelClient, name: string, config: string): bool =
  ## Set the configuration for a barrel
  ##
  ## Returns true if successful.
  ## Raises ClientError if barrel not found.
  ##
  ## **Example:**
  ## ```nim
  ## var client = newClient()
  ## client.connect()
  ## discard client.createBarrel("mydb")
  ## discard client.setBarrelConfig("mydb", """{"autoCompact": false}""")
  ## ```
  if not client.connected:
    client.connect()

  let req = Request(command: cmdSetBarrelConfig, key: name, value: config)
  let resp = client.sendAndWait(req)

  if resp.status == statusBarrelNotFound:
    raise newException(ClientError, fmt"Barrel not found: {name}")
  elif resp.status != statusOk:
    raise newException(ClientError, fmt"Set barrel config failed: {resp.status}")

  return true

# Key-value operations (require current barrel)

proc get*(client: var BitBarrelClient, key: string): string =
  ## Get value by key
  ##
  ## Raises ClientError if no barrel is selected or key is not found.
  ##
  ## **Example:**
  ## ```nim
  ## var client = newClient()
  ## client.connect()
  ## discard client.createBarrel("mydb")
  ## discard client.useBarrel("mydb")
  ## discard client.set("user:1", "Alice")
  ## let value = client.get("user:1")  # Returns "Alice"
  ## ```
  if client.currentBarrel.len == 0:
    raise newException(ClientError, "No barrel selected. Call useBarrel() first.")

  if not client.connected:
    client.connect()

  let req = Request(command: cmdGet, key: key)
  let resp = client.sendAndWait(req)

  if resp.status == statusNotFound:
    raise newException(ClientError, fmt"Key not found: {key}")
  elif resp.status != statusOk:
    raise newException(ClientError, fmt"GET failed: {resp.status}")

  return resp.value

proc getOrDefault*(client: var BitBarrelClient, key: string, default: string = ""): string =
  ## Get value by key, returning default if not found
  ##
  ## **Example:**
  ## ```nim
  ## let value = client.getOrDefault("missing", "default_value")
  ## ```
  try:
    return client.get(key)
  except ClientError:
    return default

proc set*(client: var BitBarrelClient, key, value: string): bool =
  ## Set key-value pair
  ##
  ## Raises ClientError if no barrel is selected.
  ## Returns true if successful.
  ##
  ## **Example:**
  ## ```nim
  ## var client = newClient()
  ## client.connect()
  ## discard client.createBarrel("mydb")
  ## discard client.useBarrel("mydb")
  ## discard client.set("user:1", "Alice")
  ## ```
  if client.currentBarrel.len == 0:
    raise newException(ClientError, "No barrel selected. Call useBarrel() first.")

  if not client.connected:
    client.connect()

  let req = Request(command: cmdSet, key: key, value: value)
  let resp = client.sendAndWait(req)
  return resp.status == statusOk

proc delete*(client: var BitBarrelClient, key: string): bool =
  ## Delete a key
  ##
  ## Raises ClientError if no barrel is selected.
  ## Returns true if successful.
  ##
  ## **Example:**
  ## ```nim
  ## discard client.set("temp", "data")
  ## discard client.delete("temp")
  ## echo client.exists("temp")  # false
  ## ```
  if client.currentBarrel.len == 0:
    raise newException(ClientError, "No barrel selected. Call useBarrel() first.")

  if not client.connected:
    client.connect()

  let req = Request(command: cmdDelete, key: key)
  let resp = client.sendAndWait(req)
  return resp.status == statusOk

proc setMany*(client: var BitBarrelClient, pairs: openArray[(string, string)]): int =
  ## Set multiple key-value pairs using batch protocol
  ## Returns number of successful sets
  if client.currentBarrel.len == 0:
    raise newException(ClientError, "No barrel selected. Call useBarrel() first.")

  if not client.connected:
    client.connect()

  # Create and encode batch set request
  let batchPairs = @pairs
  let reqSeq = client.seqCounter
  let batchReq = BatchSetRequest(seq: reqSeq, pairs: batchPairs)
  # Note: The batch request has its own seq, but we need to preserve reqSeq for the outer request
  # The batchReq.seq is used for the batch response to correlate with the batch request

  # Calculate timeout: base timeout (30000ms) + 50ms per item
  let timeoutMs = 30000 + (pairs.len * 50)

  let req = Request(command: cmdBatchSet, value: encodeBatchSetRequest(batchReq), seq: reqSeq)
  let resp = client.sendAndWait(req, preserveSeq = true, timeoutMs = timeoutMs)
  client.seqCounter += 1  # Increment after using this sequence number

  if resp.status == statusOk and resp.value.len > 0:
    # Decode batch response
    try:
      let batchResp = decodeBatchSetResponse(resp.value)
      # Count successful operations
      var successCount = 0
      for status in batchResp.statuses:
        if status == uint8(ord(statusOk)):
          successCount += 1
      return successCount
    except CatchableError as e:
      raise newException(ClientError, "Failed to decode batch set response: " & e.msg)
  else:
    # Handle error
    if resp.status == statusNoBarrel:
      raise newException(ClientError, "No barrel selected")
    elif resp.status == statusUnauthorized:
      raise newException(ClientError, "Unauthorized: write access required")
    elif resp.status == statusBarrelNotFound:
      raise newException(ClientError, "Barrel not found")
    else:
      raise newException(ClientError, "Batch set failed: " & resp.value)

proc getMany*(client: var BitBarrelClient, keys: openArray[string]): seq[(string, string)] =
  ## Get multiple key-value pairs using batch protocol
  ## Returns seq of (key, value) for found keys
  if client.currentBarrel.len == 0:
    raise newException(ClientError, "No barrel selected. Call useBarrel() first.")

  if not client.connected:
    client.connect()

  # Create and encode batch get request
  let batchKeys = @keys
  let reqSeq = client.seqCounter
  let batchReq = BatchGetRequest(seq: reqSeq, keys: batchKeys)

  # Calculate timeout: base timeout (30000ms) + 50ms per item
  let timeoutMs = 30000 + (keys.len * 50)

  let req = Request(command: cmdBatchGet, value: encodeBatchGetRequest(batchReq), seq: reqSeq)
  let resp = client.sendAndWait(req, preserveSeq = true, timeoutMs = timeoutMs)
  client.seqCounter += 1  # Increment after using this sequence number

  if resp.status == statusOk and resp.value.len > 0:
    # Decode batch response
    try:
      let batchResp = decodeBatchGetResponse(resp.value)
      result = @[]

      # Collect found items
      for i, item in batchResp.results:
        if item.status == uint8(ord(statusOk)):
          result.add((batchReq.keys[i], item.value))

      return result
    except CatchableError as e:
      raise newException(ClientError, "Failed to decode batch get response: " & e.msg)
  else:
    # Handle error
    if resp.status == statusNoBarrel:
      raise newException(ClientError, "No barrel selected")
    elif resp.status == statusUnauthorized:
      raise newException(ClientError, "Unauthorized: read access required")
    elif resp.status == statusBarrelNotFound:
      raise newException(ClientError, "Barrel not found")
    else:
      raise newException(ClientError, "Batch get failed: " & resp.value)

proc deleteMany*(client: var BitBarrelClient, keys: openArray[string]): int =
  ## Delete multiple keys using batch protocol
  ## Returns number of successful deletions
  if client.currentBarrel.len == 0:
    raise newException(ClientError, "No barrel selected. Call useBarrel() first.")

  if not client.connected:
    client.connect()

  # Create and encode batch delete request
  let batchKeys = @keys
  let reqSeq = client.seqCounter
  let batchReq = BatchDeleteRequest(seq: reqSeq, keys: batchKeys)

  # Calculate timeout: base timeout (30000ms) + 50ms per item
  let timeoutMs = 30000 + (keys.len * 50)

  let req = Request(command: cmdBatchDelete, value: encodeBatchDeleteRequest(batchReq), seq: reqSeq)
  let resp = client.sendAndWait(req, preserveSeq = true, timeoutMs = timeoutMs)
  client.seqCounter += 1  # Increment after using this sequence number

  if resp.status == statusOk and resp.value.len > 0:
    # Decode batch response
    try:
      let batchResp = decodeBatchDeleteResponse(resp.value)
      # Count successful operations
      var successCount = 0
      for status in batchResp.statuses:
        if status == uint8(ord(statusOk)):
          successCount += 1
      return successCount
    except CatchableError as e:
      raise newException(ClientError, "Failed to decode batch delete response: " & e.msg)
  else:
    # Handle error
    if resp.status == statusNoBarrel:
      raise newException(ClientError, "No barrel selected")
    elif resp.status == statusUnauthorized:
      raise newException(ClientError, "Unauthorized: write access required")
    elif resp.status == statusBarrelNotFound:
      raise newException(ClientError, "Barrel not found")
    else:
      raise newException(ClientError, "Batch delete failed: " & resp.value)

proc exists*(client: var BitBarrelClient, key: string): bool =
  ## Check if key exists
  ##
  ## Raises ClientError if no barrel is selected.
  ##
  ## **Example:**
  ## ```nim
  ## discard client.set("key", "value")
  ## echo client.exists("key")    # true
  ## echo client.exists("missing")  # false
  ## ```
  if client.currentBarrel.len == 0:
    raise newException(ClientError, "No barrel selected. Call useBarrel() first.")

  if not client.connected:
    client.connect()

  let req = Request(command: cmdExists, key: key)
  let resp = client.sendAndWait(req)
  return resp.status == statusOk and resp.value == "true"

proc count*(client: var BitBarrelClient): int =
  ## Count keys in the current barrel
  ##
  ## Raises ClientError if no barrel is selected.
  ##
  ## **Example:**
  ## ```nim
  ## let keyCount = client.count()
  ## echo "Barrel has ", keyCount, " keys"
  ## ```
  if client.currentBarrel.len == 0:
    raise newException(ClientError, "No barrel selected. Call useBarrel() first.")

  if not client.connected:
    client.connect()

  let req = Request(command: cmdCount)
  let resp = client.sendAndWait(req)
  if resp.status == statusOk:
    return parseInt(resp.value)
  return 0

proc listKeys*(client: var BitBarrelClient): seq[string] =
  ## List all keys in the current barrel
  ##
  ## Raises ClientError if no barrel is selected.
  ##
  ## **Example:**
  ## ```nim
  ## let keys = client.listKeys()
  ## for key in keys:
  ##   echo key
  ## ```
  if client.currentBarrel.len == 0:
    raise newException(ClientError, "No barrel selected. Call useBarrel() first.")

  if not client.connected:
    client.connect()

  let req = Request(command: cmdListKeys)
  let resp = client.sendAndWait(req)
  if resp.status == statusOk and resp.value.len > 0:
    return resp.value.split(',')
  return @[]

proc ping*(client: var BitBarrelClient): bool =
  ## Ping the server to check connectivity
  ##
  ## Returns true if server responds with "pong".
  ##
  ## **Example:**
  ## ```nim
  ## var client = newClient()
  ## client.connect()
  ## if client.ping():
  ##   echo "Server is reachable"
  ## ```
  if not client.connected:
    client.connect()

  let req = Request(command: cmdPing)
  let resp = client.sendAndWait(req)
  return resp.status == statusOk and resp.value == "pong"

# Range query operations (require bmCritBit mode barrel)

proc rangeQuery*(client: var BitBarrelClient, startKey: string = "", endKey: string = "",
                 limit: int = 1000, cursor: string = ""): (seq[(string, string)], string, bool) =
  ## Query key-value pairs in range [startKey, endKey) with cursor-based pagination
  ##
  ## Requires barrel opened in bmCritBit mode.
  ## Use empty strings for startKey/endKey to query entire barrel
  ## Returns: (items, nextCursor, hasMore)
  ##
  ## **Example:**
  ## ```nim
  ## let (items, nextCursor, hasMore) = client.rangeQuery("user:0", "user:999", 100)
  ## if hasMore:
  ##   let (nextPage, _, _) = client.rangeQuery("user:0", "user:999", 100, nextCursor)
  ##
  ## # Query entire barrel with defaults
  ## let (allItems, _, _) = client.rangeQuery()
  ## ```
  if client.currentBarrel.len == 0:
    raise newException(ClientError, "No barrel selected. Call useBarrel() first.")

  if not client.connected:
    client.connect()

  let params = protocol.RangeRequest(
    startKey: startKey,
    endKey: endKey,
    limit: limit,
    cursor: cursor
  )

  let req = Request(command: cmdRangeQuery, value: protocol.encodeRangeRequest(params))
  let resp = client.sendAndWait(req)

  if resp.status != statusOk:
    raise newException(ClientError, fmt"Range query failed: {resp.status}")

  let rangeResp = protocol.decodeRangeResponse(resp.value)
  result = (rangeResp.items, rangeResp.nextCursor, rangeResp.hasMore)

proc prefixQuery*(client: var BitBarrelClient, prefix: string,
                  limit: int = 1000, cursor: string = ""): (seq[(string, string)], string, bool) =
  ## Query key-value pairs with prefix with cursor-based pagination
  ##
  ## Requires barrel opened in bmCritBit mode.
  ## Returns: (items, nextCursor, hasMore)
  ##
  ## **Example:**
  ## ```nim
  ## let (items, nextCursor, hasMore) = client.prefixQuery("user:", 100)
  ## ```
  if client.currentBarrel.len == 0:
    raise newException(ClientError, "No barrel selected. Call useBarrel() first.")

  if not client.connected:
    client.connect()

  let params = protocol.PrefixRequest(
    prefix: prefix,
    limit: limit,
    cursor: cursor
  )

  let req = Request(command: cmdPrefixQuery, value: protocol.encodePrefixRequest(params))
  let resp = client.sendAndWait(req)

  if resp.status != statusOk:
    raise newException(ClientError, fmt"Prefix query failed: {resp.status}")

  let rangeResp = protocol.decodeRangeResponse(resp.value)
  result = (rangeResp.items, rangeResp.nextCursor, rangeResp.hasMore)

proc rangeCount*(client: var BitBarrelClient, startKey: string = "", endKey: string = ""): int =
  ## Count keys in range [startKey, endKey)
  ##
  ## Requires barrel opened in bmCritBit mode.
  ## Use empty strings for startKey/endKey to count entire barrel
  ##
  ## **Example:**
  ## ```nim
  ## let count = client.rangeCount("user:0", "user:999")
  ##
  ## # Count all keys in barrel
  ## let total = client.rangeCount()
  ## ```
  if client.currentBarrel.len == 0:
    raise newException(ClientError, "No barrel selected. Call useBarrel() first.")

  if not client.connected:
    client.connect()

  let params = protocol.RangeRequest(
    startKey: startKey,
    endKey: endKey,
    limit: 0,
    cursor: ""
  )

  let req = Request(command: cmdRangeCount, value: protocol.encodeRangeRequest(params))
  let resp = client.sendAndWait(req)

  if resp.status != statusOk:
    raise newException(ClientError, fmt"Range count failed: {resp.status}")

  result = parseInt(resp.value)

# Keys-only range query operations (require bmCritBit mode barrel)

proc rangeQueryKeys*(client: var BitBarrelClient, startKey: string = "", endKey: string = "",
                     limit: int = 1000, cursor: string = ""): (seq[string], string, bool) =
  ## Query keys in range [startKey, endKey) with cursor-based pagination
  ##
  ## Requires barrel opened in bmCritBit mode.
  ## Use empty strings for startKey/endKey to query entire barrel
  ## Returns: (keys, nextCursor, hasMore)
  ##
  ## **Example:**
  ## ```nim
  ## let (keys, nextCursor, hasMore) = client.rangeQueryKeys("user:0", "user:999", 100)
  ## if hasMore:
  ##   let (nextPage, _, _) = client.rangeQueryKeys("user:0", "user:999", 100, nextCursor)
  ##
  ## # Get all keys in barrel
  ## let (allKeys, _, _) = client.rangeQueryKeys()
  ## ```
  if client.currentBarrel.len == 0:
    raise newException(ClientError, "No barrel selected. Call useBarrel() first.")

  if not client.connected:
    client.connect()

  let params = protocol.RangeRequest(
    startKey: startKey,
    endKey: endKey,
    limit: limit,
    cursor: cursor
  )

  let req = Request(command: cmdRangeKeys, value: protocol.encodeRangeRequest(params))
  let resp = client.sendAndWait(req)

  if resp.status != statusOk:
    raise newException(ClientError, fmt"Range keys query failed: {resp.status}")

  let keysResp = protocol.decodeKeysResponse(resp.value)
  result = (keysResp.keys, keysResp.nextCursor, keysResp.hasMore)

proc prefixQueryKeys*(client: var BitBarrelClient, prefix: string,
                      limit: int = 1000, cursor: string = ""): (seq[string], string, bool) =
  ## Query keys with prefix with cursor-based pagination
  ##
  ## Requires barrel opened in bmCritBit mode.
  ## Returns: (keys, nextCursor, hasMore)
  ##
  ## **Example:**
  ## ```nim
  ## let (keys, nextCursor, hasMore) = client.prefixQueryKeys("user:", 100)
  ## ```
  if client.currentBarrel.len == 0:
    raise newException(ClientError, "No barrel selected. Call useBarrel() first.")

  if not client.connected:
    client.connect()

  let params = protocol.PrefixRequest(
    prefix: prefix,
    limit: limit,
    cursor: cursor
  )

  let req = Request(command: cmdPrefixKeys, value: protocol.encodePrefixRequest(params))
  let resp = client.sendAndWait(req)

  if resp.status != statusOk:
    raise newException(ClientError, fmt"Prefix keys query failed: {resp.status}")

  let keysResp = protocol.decodeKeysResponse(resp.value)
  result = (keysResp.keys, keysResp.nextCursor, keysResp.hasMore)

# Reference traversal operations

proc traverse*(client: var BitBarrelClient, key: string, pathSpec: string,
               options: TraverseOptions): seq[protocol.TraverseResult] =
  ## Traverse references from a key using path specification
  ##
  ## PathSpec syntax: `*` for all references, `->` to follow
  ##
  ## **Example:**
  ## ```nim
  ## let options = TraverseOptions(includeFullData: true)
  ## let results = client.traverse("user:1", "->friend", options)
  ## ```
  if client.currentBarrel.len == 0:
    raise newException(ClientError, "No barrel selected. Call useBarrel() first.")

  if not client.connected:
    client.connect()

  var optionsByte: uint8 = 0
  if options.includeFullData:
    optionsByte = optionsByte or 0x01
  if options.extractArrays:
    optionsByte = optionsByte or 0x02
  if options.firstOnly:
    optionsByte = optionsByte or 0x04

  let tReq = TraverseRequest(
    seq: client.seqCounter,
    key: key,
    pathSpec: pathSpec,
    options: optionsByte
  )
  client.seqCounter += 1

  let encoded = encodeTraverseRequest(tReq)
  let req = Request(command: cmdTraverse, value: encoded)
  let resp = client.sendAndWait(req)

  if resp.status != statusOk:
    raise newException(ClientError, fmt"Traversal failed: {resp.status}")

  let (status, _, results) = decodeTraverseResults(resp.value)
  if status != statusOk:
    raise newException(ClientError, "Invalid traversal response")

  result = newSeq[protocol.TraverseResult](results.len)
  for i, res in results:
    result[i] = protocol.TraverseResult(
      path: res.path,
      key: res.key,
      value: res.value,
      extractedData: res.extractedData
    )

proc traversePath*(client: var BitBarrelClient, key: string,
                   pathSpec: string): seq[protocol.TraverseResult] =
  ## Traverse with default options (include full data)
  let options = TraverseOptions(
    includeFullData: true,
    extractArrays: false,
    firstOnly: false
  )
  result = client.traverse(key, pathSpec, options)

## ============================================================================
## Pub/Sub Methods (Stubs - to be implemented)
## ============================================================================

proc subscribe*(client: var BitBarrelClient, topic: string,
                options: SubscriptionOptions): string =
  ## Subscribe to topic with options (supports pattern matching with *)
  ## Returns subscription ID
  ##
  ## **Example:**
  ## ```nim
  ## # Subscribe to exact topic
  ## let sub1 = client.subscribe("user/login")
  ##
  ## # Subscribe with pattern
  ## let sub2 = client.subscribe("user/*")
  ##
  ## # Subscribe with options
  ## var opts = SubscriptionOptions(enablePresence: true)
  ## let sub3 = client.subscribe("chat/room1", opts)
  ## ```
  if not client.connected:
    client.connect()

  # Determine if this is a pattern subscription (contains *)
  let isPattern = "*" in topic
  let actualTopic = if isPattern: "" else: topic
  let actualPattern = if isPattern: topic else: ""

  # Encode subscribe request
  let subscribeData = encodeSubscribeRequest(actualTopic, actualPattern, options)

  # Send request
  let req = Request(command: cmdSubscribe, value: subscribeData)
  let resp = client.sendAndWait(req)

  if resp.status != statusOk:
    raise newException(ClientError, fmt"Subscribe failed: {resp.status}")

  # Response value is the subscription ID
  let subId = decodeSubscribeResponse(resp.value)

  # Track subscription
  withLock client.lock:
    client.subscriptions[subId] = true

  return subId

proc subscribe*(client: var BitBarrelClient, topic: string): string =
  ## Subscribe to exact topic with default options
  ## Returns subscription ID
  let defaultOptions = SubscriptionOptions(
    enableKvEvents: false,
    enablePresence: false,
    replayHistory: false
  )
  return client.subscribe(topic, defaultOptions)

proc isSubscribed*(client: var BitBarrelClient, subId: string): bool =
  ## Check if subscription is active
  withLock client.lock:
    return subId in client.subscriptions and client.subscriptions[subId]

proc unsubscribe*(client: var BitBarrelClient, subId: string): bool =
  ## Unsubscribe from subscription
  ## Returns true if subscription existed
  if not client.connected:
    return false

  # Check if subscription exists
  var exists = false
  withLock client.lock:
    exists = subId in client.subscriptions

  if not exists:
    return false

  # Send unsubscribe request (subId in key field)
  let req = Request(command: cmdUnsubscribe, key: subId)
  let resp = client.sendAndWait(req)

  if resp.status == statusOk:
    withLock client.lock:
      client.subscriptions.del(subId)
    return true
  else:
    return false

proc unsubscribeAll*(client: var BitBarrelClient): int =
  ## Unsubscribe from all subscriptions
  ## Returns number of subscriptions removed
  var subIds: seq[string]

  withLock client.lock:
    for subId in client.subscriptions.keys:
      subIds.add(subId)

  result = 0
  for subId in subIds:
    if client.unsubscribe(subId):
      inc result

proc publish*(client: var BitBarrelClient, topic: string,
              messageType: PubSubMessageType, payload: string,
              headers: string): uint64 =
  ## Publish message with type and headers to topic
  ## Returns sequence number
  ##
  ## **Example:**
  ## ```nim
  ## # Publish simple message
  ## let seq1 = client.publish("events/user", "user logged in")
  ##
  ## # Publish with message type
  ## let seq2 = client.publish("events/system", mtData, "system started")
  ##
  ## # Publish with headers
  ## let headers = """{"userId": "123", "source": "web"}"""
  ## let seq3 = client.publish("events/action", mtData, "button clicked", headers)
  ## ```
  if not client.connected:
    client.connect()

  # Encode publish request
  let publishData = encodePublishRequest(topic, messageType, payload, headers)

  # Send request
  let req = Request(command: cmdPublish, value: publishData)
  let resp = client.sendAndWait(req)

  if resp.status != statusOk:
    raise newException(ClientError, fmt"Publish failed: {resp.status}")

  # Response value contains the sequence number as uint64
  return decodePublishResponse(resp.value)

proc publish*(client: var BitBarrelClient, topic: string,
              messageType: PubSubMessageType, payload: string): uint64 =
  ## Publish message with type to topic
  ## Returns sequence number
  return client.publish(topic, messageType, payload, "")

proc publish*(client: var BitBarrelClient, topic: string, payload: string): uint64 =
  ## Publish data message to topic
  ## Returns sequence number
  return client.publish(topic, mtData, payload, "")

proc listSubscribers*(client: var BitBarrelClient, topic: string): seq[SubscriptionInfo] =
  ## List subscribers for a topic
  ##
  ## Returns a sequence of subscription information including subscription ID,
  ## client ID, and topic/pattern details.
  ##
  ## **Example:**
  ## ```nim
  ## let subs = client.listSubscribers("chat:room1")
  ## for sub in subs:
  ##   echo &"Sub {sub.subscriptionId} by client {sub.clientId}"
  ## ```
  if not client.connected:
    client.connect()

  let req = Request(command: cmdListSubscribers, value: topic)
  let resp = client.sendAndWait(req)

  if resp.status != statusOk:
    raise newException(ClientError, fmt"List subscribers failed: {resp.status}")

  try:
    let js = parseJson(resp.value)
    result = newSeqOfCap[SubscriptionInfo](js.len)
    for item in js:
      var info: SubscriptionInfo
      info.id = item["subscriptionId"].getStr()
      info.clientId = uint64(item["clientId"].getBiggestInt())
      if "pattern" in item:
        info.pattern = item["pattern"].getStr()
      else:
        info.topic = item["topic"].getStr()
      result.add(info)
  except CatchableError as e:
    raise newException(ClientError, fmt"Failed to parse subscribers response: {e.msg}")

proc listTopics*(client: var BitBarrelClient): seq[TopicInfo] =
  ## List all topics
  ##
  ## Returns a sequence of topic information including name, sequence number,
  ## subscriber count, and message count.
  ##
  ## **Example:**
  ## ```nim
  ## let topics = client.listTopics()
  ## for topic in topics:
  ##   echo &"{topic.name}: {topic.subscriberCount} subscribers, {topic.messageCount} messages"
  ## ```
  if not client.connected:
    client.connect()

  let req = Request(command: cmdListTopics, value: "")
  let resp = client.sendAndWait(req)

  if resp.status != statusOk:
    raise newException(ClientError, fmt"List topics failed: {resp.status}")

  try:
    let js = parseJson(resp.value)
    result = newSeqOfCap[TopicInfo](js.len)
    for item in js:
      var info: TopicInfo
      info.name = item["name"].getStr()
      info.sequence = uint64(item["sequence"].getBiggestInt())
      info.subscriberCount = item["subscriberCount"].getBiggestInt()
      info.messageCount = int64(item["messageCount"].getBiggestInt())
      result.add(info)
  except CatchableError as e:
    raise newException(ClientError, fmt"Failed to parse topics response: {e.msg}")

proc getHistory*(client: var BitBarrelClient, topic: string,
                 limit: int = 100, sinceSeq: uint64 = 0): seq[PubSubEvent] =
  ## Get message history for topic
  ##
  ## Returns a sequence of historical pub/sub events.
  ## limit: Maximum number of messages to return (default: 100)
  ## sinceSeq: Only return messages with sequence >= this value (default: 0)
  ##
  ## **Example:**
  ## ```nim
  ## let history = client.getHistory("chat:room1", limit=10)
  ## for event in history:
  ##   echo &"[{event.sequence}] {event.topic}: {event.payload}"
  ## ```
  if not client.connected:
    client.connect()

  let histReq = HistoryRequest(topic: topic, count: limit, sinceSeq: sinceSeq)
  let req = Request(command: cmdHistory, value: protocol.encodeHistoryRequest(histReq))
  let resp = client.sendAndWait(req)

  if resp.status != statusOk:
    raise newException(ClientError, fmt"Get history failed: {resp.status}")

  try:
    let js = parseJson(resp.value)
    result = newSeqOfCap[PubSubEvent](js.len)
    for item in js:
      var event: PubSubEvent
      event.topic = item["topic"].getStr()
      event.messageType = PubSubMessageType(item["messageType"].getBiggestInt())
      event.payload = item["payload"].getStr()
      event.timestamp = item["timestamp"].getBiggestInt()
      event.sequence = uint64(item["sequence"].getBiggestInt())
      event.headers = $item["headers"]
      result.add(event)
  except CatchableError as e:
    raise newException(ClientError, fmt"Failed to parse history response: {e.msg}")

proc getPresence*(client: var BitBarrelClient, topic: string): PresenceInfo =
  ## Get presence info for topic
  ##
  ## Returns presence information for subscribers on a topic.
  ##
  ## **Example:**
  ## ```nim
  ## let presence = client.getPresence("chat:room1")
  ## echo &"{presence.members.len} members online"
  ## for member in presence.members:
  ##   echo &"  {member.username} (joined at {member.joinedAt})"
  ## ```
  if not client.connected:
    client.connect()

  let presReq = PresenceRequest(operation: 0)  # Get online
  let req = Request(command: cmdPresence, value: protocol.encodePresenceRequest(presReq))
  let resp = client.sendAndWait(req)

  if resp.status != statusOk:
    raise newException(ClientError, fmt"Get presence failed: {resp.status}")

  try:
    let js = parseJson(resp.value)
    result.topic = topic
    result.lastUpdate = int64(epochTime() * 1000)
    result.members = @[]

    for item in js:
      let itemTopic = item["topic"].getStr()

      if itemTopic == topic:
        # Single topic response - parse members directly
        let membersArray = if item.hasKey("members"): item["members"] else: newJArray()
        result.lastUpdate = if item.hasKey("lastUpdate"): item["lastUpdate"].getInt()
                             else: result.lastUpdate

        for m in membersArray:
          var member: PresenceMember
          member.clientId = if m.hasKey("clientId"): parseBiggestUInt($m["clientId"]) else: 0'u64
          member.username = if m.hasKey("username"): m["username"].getStr() else: ""
          member.joinedAt = if m.hasKey("joinedAt"): m["joinedAt"].getBiggestInt() else: 0'i64
          member.lastPing = if m.hasKey("lastPing"): m["lastPing"].getBiggestInt() else: 0'i64
          member.metadata = if m.hasKey("metadata"): $m["metadata"] else: ""
          result.members.add(member)
        break
  except CatchableError as e:
    raise newException(ClientError, fmt"Failed to parse presence response: {e.msg}")

# Lazy pagination iterator for Nim client

type
  RangeIterator*[T] = object
    client*: ptr BitBarrelClient
    queryType*: string
    startKey*: string
    endKey*: string
    prefix*: string
    pageSize*: int
    buffer*: seq[T]
    cursor*: string
    exhausted*: bool

proc fetchNextPage*[T](it: var RangeIterator[T]) =
  ## Fetch next page into buffer
  if it.exhausted:
    return

  if not it.client[].connected:
    it.client[].connect()

  try:
    case it.queryType
    of "range":
      when T is string:
        let (keys, nextCursor, hasMore) = it.client.rangeQueryKeys(
          it.startKey, it.endKey, it.pageSize, it.cursor)
        it.buffer = keys
        it.cursor = nextCursor
        it.exhausted = not hasMore
      else:
        let (items, nextCursor, hasMore) = it.client.rangeQuery(
          it.startKey, it.endKey, it.pageSize, it.cursor)
        it.buffer = cast[seq[T]](items)
        it.cursor = nextCursor
        it.exhausted = not hasMore
    of "prefix":
      when T is string:
        let (keys, nextCursor, hasMore) = it.client.prefixQueryKeys(
          it.prefix, it.pageSize, it.cursor)
        it.buffer = keys
        it.cursor = nextCursor
        it.exhausted = not hasMore
      else:
        let (items, nextCursor, hasMore) = it.client.prefixQuery(
          it.prefix, it.pageSize, it.cursor)
        it.buffer = cast[seq[T]](items)
        it.cursor = nextCursor
        it.exhausted = not hasMore
    else:
      it.exhausted = true
  except CatchableError:
    it.exhausted = true

iterator items*[T](it: var RangeIterator[T]): T =
  ## Lazy iterator over range query results
  defer: it.exhausted = true
  while not it.exhausted:
    if it.buffer.len == 0:
      it.fetchNextPage()
    if it.buffer.len == 0:
      break
    yield it.buffer[0]
    it.buffer.delete(0)

# Convenience procedures to create iterators

proc newRangeIterator*(client: var BitBarrelClient, startKey: string, endKey: string,
                       pageSize: int = 1000): RangeIterator[(string, string)] =
  ## Create a new lazy range query iterator for key-value pairs
  result = RangeIterator[(string, string)](
    client: addr(client),
    queryType: "range",
    startKey: startKey,
    endKey: endKey,
    pageSize: pageSize,
    buffer: @[],
    cursor: "",
    exhausted: false
  )

proc newKeysIterator*(client: var BitBarrelClient, startKey: string, endKey: string,
                      pageSize: int = 1000): RangeIterator[string] =
  ## Create a new lazy range query iterator for keys only
  result = RangeIterator[string](
    client: addr(client),
    queryType: "range",
    startKey: startKey,
    endKey: endKey,
    pageSize: pageSize,
    buffer: @[],
    cursor: "",
    exhausted: false
  )

proc newPrefixIterator*(client: var BitBarrelClient, prefix: string,
                        pageSize: int = 1000): RangeIterator[(string, string)] =
  ## Create a new lazy prefix query iterator for key-value pairs
  result = RangeIterator[(string, string)](
    client: addr(client),
    queryType: "prefix",
    prefix: prefix,
    pageSize: pageSize,
    buffer: @[],
    cursor: "",
    exhausted: false
  )

proc newKeysPrefixIterator*(client: var BitBarrelClient, prefix: string,
                            pageSize: int = 1000): RangeIterator[string] =
  ## Create a new lazy prefix query iterator for keys only
  result = RangeIterator[string](
    client: addr(client),
    queryType: "prefix",
    prefix: prefix,
    pageSize: pageSize,
    buffer: @[],
    cursor: "",
    exhausted: false
  )

## Key watching

proc watch*(client: var BitBarrelClient, pattern: string, includeValues = false): string =
  ## Watch for changes to keys matching a pattern via Pub/Sub.
  ##
  ## When keys matching the pattern change (set or delete), you'll receive
  ## PubSub events via the message handler with message_type mtKvChange.
  ##
  ## Patterns use * as wildcard (e.g., "user:*" or "cache:*")
  ##
  ## Returns the watch ID which can be used with unwatchById for efficient unwatch.
  if client.currentBarrel.len == 0:
    raise newException(ClientError, "No barrel selected")

  let watchData = encodeWatchRequest("", pattern, includeValues)
  let req = Request(command: cmdWatchKey, key: "", value: watchData)
  let resp = client.sendAndWait(req)
  result = resp.value  # Response value is the watch ID

proc unwatch*(client: var BitBarrelClient, pattern: string) =
  ## Stop watching a previously registered pattern.
  ##
  ## This sends the pattern to unwatch. For more efficient unwatching
  ## using a watch ID, use unwatchById instead.
  if client.currentBarrel.len == 0:
    raise newException(ClientError, "No barrel selected")

  let watchData = encodeWatchRequest("", pattern, false)
  let req = Request(command: cmdUnwatchKey, key: "", value: watchData)
  discard client.sendAndWait(req)

proc unwatchById*(client: var BitBarrelClient, watchId: string) =
  ## Stop watching using a watch ID for efficient unwatch.
  ##
  ## This is more efficient than unwatch as it uses the watch ID directly
  ## instead of sending the pattern again.
  if client.currentBarrel.len == 0:
    raise newException(ClientError, "No barrel selected")

  let req = Request(command: cmdUnwatchKey, key: watchId, value: "")
  discard client.sendAndWait(req)

