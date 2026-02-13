## Binary protocol for BitBarrel network communication
##
## Request Format: ``[type:1][seq:4][keyLen:2][key:N][valLen:4][value:M]``
## Response Format: ``[status:1][seq:4][valLen:4][value:M]``
##
## All multi-byte integers use big-endian encoding.

import std/strutils

type
  Command* = enum
    ## Data operations
    cmdGet = 0x01
    cmdSet = 0x02
    cmdDelete = 0x03
    cmdExists = 0x04
    cmdCount = 0x05
    cmdListKeys = 0x06
    cmdPing = 0x09
    ## Barrel management
    cmdCreateBarrel = 0x10
    cmdOpenBarrel = 0x11
    cmdUseBarrel = 0x12
    cmdCloseBarrel = 0x13
    cmdListBarrels = 0x14
    cmdDropBarrel = 0x15
    ## Configuration commands
    cmdGetBarrelConfig = 0x16
    cmdSetBarrelConfig = 0x17
    cmdGetBarrelStats = 0x18
    ## Range queries
    cmdRangeQuery = 0x21
    cmdPrefixQuery = 0x22
    cmdRangeCount = 0x23
    cmdRangeKeys = 0x24
    cmdPrefixKeys = 0x25
    ## Batch operations
    cmdBatchGet = 0x26
    cmdBatchSet = 0x27
    cmdBatchDelete = 0x28
    ## Reference traversal
    cmdTraverse = 0x20
    ## Pub/Sub commands
    cmdSubscribe = 0x40
    cmdUnsubscribe = 0x41
    cmdPublish = 0x42
    cmdListSubscribers = 0x43
    cmdHistory = 0x44
    cmdListTopics = 0x45
    cmdPresence = 0x46
    ## Key watching commands
    cmdWatchKey = 0x60
    cmdUnwatchKey = 0x61

  PubSubMessageType* = enum
    mtData = 0
    mtPresence = 1
    mtKvChange = 2

  ResponseStatus* = enum
    statusOk = 0x00
    statusNotFound = 0x01
    statusError = 0x02
    statusInvalid = 0x03
    statusNoBarrel = 0x04
    statusBarrelExists = 0x05
    statusBarrelNotFound = 0x06
    statusUnauthorized = 0x07

  Request* = object
    command*: Command
    seq*: uint32
    key*: string      ## Also used for barrel name
    value*: string    ## Also used for barrel config JSON

  Response* = object
    status*: ResponseStatus
    seq*: uint32
    value*: string

  PubSubEvent* = object
    topic*: string
    messageType*: PubSubMessageType
    sequence*: uint64
    timestamp*: int64
    headers*: string
    payload*: string

  SubscriptionOptions* = object
    enableKvEvents*: bool
    enablePresence*: bool
    replayHistory*: bool

  PresenceMember* = object
    clientId*: uint64
    username*: string
    joinedAt*: int64
    lastPing*: int64
    metadata*: string

  PresenceInfo* = object
    topic*: string
    members*: seq[PresenceMember]
    lastUpdate*: int64

  SubscriptionInfo* = object
    id*: string
    clientId*: uint64
    topic*: string
    pattern*: string

  TopicInfo* = object
    name*: string
    sequence*: uint64
    subscriberCount*: int
    messageCount*: int64

  HistoryRequest* = object
    topic*: string
    count*: int
    sinceSeq*: uint64

  PresenceRequest* = object
    operation*: uint8              ## 0 = get_online, 1 = broadcast_update

  ## Batch operation request/response types
  BatchGetRequest* = object
    seq*: uint32
    keys*: seq[string]

  BatchGetResponse* = object
    seq*: uint32
    results*: seq[tuple[status: uint8, value: string]]

  BatchSetRequest* = object
    seq*: uint32
    pairs*: seq[tuple[key: string, value: string]]

  BatchSetResponse* = object
    seq*: uint32
    statuses*: seq[uint8]

  BatchDeleteRequest* = object
    seq*: uint32
    keys*: seq[string]

  BatchDeleteResponse* = object
    seq*: uint32
    statuses*: seq[uint8]

  ProtocolError* = object of CatchableError

const
  MaxKeySize* = 65535       ## 64KB max key size (2 bytes for length)
  MaxValueSize* = 32 * 1024 * 1024  ## 32MB max value size
  MaxBatchItems* = 10000    ## Maximum number of items in a batch operation


proc writeByte(s: var string, b: byte) =
  s.add(char(b))

proc writeUint16BE(s: var string, v: uint16) =
  s.add(char((v shr 8) and 0xFF))
  s.add(char(v and 0xFF))

proc writeUint32BE(s: var string, v: uint32) =
  s.add(char((v shr 24) and 0xFF))
  s.add(char((v shr 16) and 0xFF))
  s.add(char((v shr 8) and 0xFF))
  s.add(char(v and 0xFF))

proc writeUint64BE(s: var string, v: uint64) =
  s.add(char((v shr 56) and 0xFF))
  s.add(char((v shr 48) and 0xFF))
  s.add(char((v shr 40) and 0xFF))
  s.add(char((v shr 32) and 0xFF))
  s.add(char((v shr 24) and 0xFF))
  s.add(char((v shr 16) and 0xFF))
  s.add(char((v shr 8) and 0xFF))
  s.add(char(v and 0xFF))

proc readByte(data: string, pos: var int): byte =
  if pos >= data.len:
    raise newException(ProtocolError, "Unexpected end of data reading byte")
  result = byte(data[pos])
  inc pos

proc readUint16BE(data: string, pos: var int): uint16 =
  if pos + 2 > data.len:
    raise newException(ProtocolError, "Unexpected end of data reading uint16")
  result = (uint16(data[pos]) shl 8) or uint16(data[pos + 1])
  pos += 2

proc readUint32BE(data: string, pos: var int): uint32 =
  if pos + 4 > data.len:
    raise newException(ProtocolError, "Unexpected end of data reading uint32")
  result = (uint32(data[pos]) shl 24) or
           (uint32(data[pos + 1]) shl 16) or
           (uint32(data[pos + 2]) shl 8) or
           uint32(data[pos + 3])
  pos += 4

proc readUint64BE(data: string, pos: var int): uint64 =
  if pos + 8 > data.len:
    raise newException(ProtocolError, "Unexpected end of data reading uint64")
  result = (uint64(data[pos]) shl 56) or
           (uint64(data[pos + 1]) shl 48) or
           (uint64(data[pos + 2]) shl 40) or
           (uint64(data[pos + 3]) shl 32) or
           (uint64(data[pos + 4]) shl 24) or
           (uint64(data[pos + 5]) shl 16) or
           (uint64(data[pos + 6]) shl 8) or
           uint64(data[pos + 7])
  pos += 8

proc readString(data: string, pos: var int, length: int): string =
  if pos + length > data.len:
    raise newException(ProtocolError, "Unexpected end of data reading string")
  result = data[pos ..< pos + length]
  pos += length


proc encodeRequest*(req: Request): string =
  ## Encode a request to binary format (v1.1).
  ## Format: ``[type:1][seq:4][flags:1][keyLen:2][key:N][valLen:4][value:M]``
  if req.key.len > MaxKeySize:
    raise newException(ProtocolError, "Key too large: " & $req.key.len)
  if req.value.len > MaxValueSize:
    raise newException(ProtocolError, "Value too large: " & $req.value.len)

  result = newStringOfCap(1 + 4 + 1 + 2 + req.key.len + 4 + req.value.len)
  result.writeByte(byte(ord(req.command)))
  result.writeUint32BE(req.seq)
  result.writeByte(0)  # flags - always 0 for now
  result.writeUint16BE(uint16(req.key.len))
  result.add(req.key)
  result.writeUint32BE(uint32(req.value.len))
  result.add(req.value)

proc decodeRequest*(data: string): Request =
  ## Decode a request from binary format (v1.1).
  ## Format: ``[type:1][seq:4][flags:1][keyLen:2][key:N][valLen:4][value:M]``
  var pos = 0

  let cmdByte = readByte(data, pos)
  # Validate command byte - must include all Command enum values
  if cmdByte notin {0x01'u8, 0x02, 0x03, 0x04, 0x05, 0x06, 0x09,  # Data ops + ping
                     0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17,  # Barrel ops + config
                     0x20,                                       # Traverse
                     0x21, 0x22, 0x23,                          # Range queries
                     0x26, 0x27, 0x28}:                         # Batch operations
    raise newException(ProtocolError, "Invalid command: 0x" & cmdByte.toHex)

  result.command = cast[Command](cmdByte)
  result.seq = readUint32BE(data, pos)
  discard readByte(data, pos)  # flags - not stored in Request object

  let keyLen = readUint16BE(data, pos)
  if keyLen > MaxKeySize:
    raise newException(ProtocolError, "Key too large: " & $keyLen)
  result.key = readString(data, pos, int(keyLen))

  let valLen = readUint32BE(data, pos)
  if valLen > MaxValueSize:
    raise newException(ProtocolError, "Value too large: " & $valLen)
  result.value = readString(data, pos, int(valLen))

proc encodeResponse*(resp: Response): string =
  ## Encode a response to binary format.
  ## Format: ``[status:1][seq:4][valLen:4][value:M]``
  if resp.value.len > MaxValueSize:
    raise newException(ProtocolError, "Value too large: " & $resp.value.len)

  result = newStringOfCap(1 + 4 + 4 + resp.value.len)
  result.writeByte(byte(ord(resp.status)))
  result.writeUint32BE(resp.seq)
  result.writeUint32BE(uint32(resp.value.len))
  result.add(resp.value)

proc decodeResponse*(data: string): Response =
  ## Decode a response from binary format.
  var pos = 0

  let statusByte = readByte(data, pos)
  if statusByte > byte(0x07):
    raise newException(ProtocolError, "Invalid status: 0x" & statusByte.toHex)

  result.status = ResponseStatus(statusByte)
  result.seq = readUint32BE(data, pos)

  let valLen = readUint32BE(data, pos)
  if valLen > MaxValueSize:
    raise newException(ProtocolError, "Value too large: " & $valLen)
  result.value = readString(data, pos, int(valLen))


## Traversal request/response extensions

type
  TraverseRequest* = object
    seq*: uint32
    key*: string           ## Starting key for traversal
    pathSpec*: string      ## Path specification string
    options*: uint8        ## Options bitfield

  TraverseResult* = object
    path*: string          ## Full traversal path
    key*: string           ## Key of the result
    value*: string         ## Value at the path end (if requested)
    extractedData*: string ## Extracted array data (if requested)

proc encodeTraverseRequest*(req: TraverseRequest): string =
  ## Encode a traversal request
  ## Format: ``[seq:4][keyLen:2][key:N][pathLen:2][path:N][options:1]``
  result = newStringOfCap(4 + 2 + req.key.len + 2 + req.pathSpec.len + 1)
  result.writeUint32BE(req.seq)
  result.writeUint16BE(uint16(req.key.len))
  result.add(req.key)
  result.writeUint16BE(uint16(req.pathSpec.len))
  result.add(req.pathSpec)
  result.writeByte(byte(req.options))

proc decodeTraverseRequest*(data: string): TraverseRequest =
  ## Decode a traversal request
  var pos = 0
  result.seq = readUint32BE(data, pos)

  let keyLen = readUint16BE(data, pos)
  if keyLen > MaxKeySize:
    raise newException(ProtocolError, "Key too large: " & $keyLen)
  result.key = readString(data, pos, int(keyLen))

  let pathLen = readUint16BE(data, pos)
  if pathLen > 1024:  # Reasonable limit for path spec
    raise newException(ProtocolError, "Path spec too large: " & $pathLen)
  result.pathSpec = readString(data, pos, int(pathLen))

  result.options = uint8(readByte(data, pos))

proc encodeTraverseResults*(results: seq[TraverseResult], seq: uint32): string =
  ## Encode traversal results
  ## Format: ``[status:1][seq:4][count:4][results...]``
  ## Each result: ``[pathLen:2][path:N][valLen:4][val:M][extFlags:1][extLen:4][ext:M]``
  result = newStringOfCap(1 + 4 + 4)
  result.writeByte(byte(ord(statusOk)))
  result.writeUint32BE(seq)
  result.writeUint32BE(uint32(results.len))

  for res in results:
    # Path
    result.writeUint16BE(uint16(res.path.len))
    result.add(res.path)

    # Value (if present)
    result.writeUint32BE(uint32(res.value.len))
    if res.value.len > 0:
      result.add(res.value)

    # Extracted data flag and length
    let hasExtracted = if res.extractedData.len > 0: 1'u8 else: 0'u8
    result.writeByte(byte(hasExtracted))
    result.writeUint32BE(uint32(res.extractedData.len))
    if res.extractedData.len > 0:
      result.add(res.extractedData)

proc decodeTraverseResults*(data: string): (ResponseStatus, uint32, seq[TraverseResult]) =
  ## Decode traversal results
  var pos = 0

  let statusByte = readByte(data, pos)
  if statusByte > byte(ord(high(ResponseStatus))):
    raise newException(ProtocolError, "Invalid status: 0x" & statusByte.toHex)

  result[0] = ResponseStatus(statusByte)
  result[1] = readUint32BE(data, pos)

  let count = readUint32BE(data, pos)
  result[2] = newSeq[TraverseResult](count)

  for i in 0..<count:
    var res: TraverseResult

    # Path
    let pathLen = readUint16BE(data, pos)
    res.path = readString(data, pos, int(pathLen))

    # Value
    let valLen = readUint32BE(data, pos)
    if valLen > 0:
      res.value = readString(data, pos, int(valLen))

    # Extracted data
    let hasExtracted = readByte(data, pos)
    let extLen = readUint32BE(data, pos)
    if hasExtracted != 0 and extLen > 0:
      res.extractedData = readString(data, pos, int(extLen))

    result[2][i] = res


## Range query request/response extensions

type
  RangeRequest* = object
    startKey*: string
    endKey*: string
    limit*: int
    cursor*: string

  PrefixRequest* = object
    prefix*: string
    limit*: int
    cursor*: string

  RangeResponse* = object
    items*: seq[(string, string)]
    nextCursor*: string
    hasMore*: bool

  KeysResponse* = object
    keys*: seq[string]
    nextCursor*: string
    hasMore*: bool

proc encodeRangeRequest*(req: RangeRequest): string =
  ## Encode a range query request
  ## Format: ``[startKeyLen:2][startKey:N][endKeyLen:2][endKey:N][limit:4][cursorLen:2][cursor:M]``
  result = newStringOfCap(2 + req.startKey.len + 2 + req.endKey.len + 4 + 2 + req.cursor.len)
  result.writeUint16BE(uint16(req.startKey.len))
  result.add(req.startKey)
  result.writeUint16BE(uint16(req.endKey.len))
  result.add(req.endKey)
  result.writeUint32BE(uint32(req.limit))
  result.writeUint16BE(uint16(req.cursor.len))
  result.add(req.cursor)

proc decodeRangeRequest*(data: string): RangeRequest =
  ## Decode a range query request
  var pos = 0
  let startKeyLen = readUint16BE(data, pos)
  if startKeyLen > MaxKeySize:
    raise newException(ProtocolError, "Start key too large: " & $startKeyLen)
  result.startKey = readString(data, pos, int(startKeyLen))

  let endKeyLen = readUint16BE(data, pos)
  if endKeyLen > MaxKeySize:
    raise newException(ProtocolError, "End key too large: " & $endKeyLen)
  result.endKey = readString(data, pos, int(endKeyLen))

  result.limit = int(readUint32BE(data, pos))

  let cursorLen = readUint16BE(data, pos)
  if cursorLen > MaxKeySize:
    raise newException(ProtocolError, "Cursor too large: " & $cursorLen)
  result.cursor = readString(data, pos, int(cursorLen))

proc encodePrefixRequest*(req: PrefixRequest): string =
  ## Encode a prefix query request
  ## Format: ``[prefixLen:2][prefix:N][limit:4][cursorLen:2][cursor:M]``
  result = newStringOfCap(2 + req.prefix.len + 4 + 2 + req.cursor.len)
  result.writeUint16BE(uint16(req.prefix.len))
  result.add(req.prefix)
  result.writeUint32BE(uint32(req.limit))
  result.writeUint16BE(uint16(req.cursor.len))
  result.add(req.cursor)

proc decodePrefixRequest*(data: string): PrefixRequest =
  ## Decode a prefix query request
  var pos = 0
  let prefixLen = readUint16BE(data, pos)
  if prefixLen > MaxKeySize:
    raise newException(ProtocolError, "Prefix too large: " & $prefixLen)
  result.prefix = readString(data, pos, int(prefixLen))

  result.limit = int(readUint32BE(data, pos))

  let cursorLen = readUint16BE(data, pos)
  if cursorLen > MaxKeySize:
    raise newException(ProtocolError, "Cursor too large: " & $cursorLen)
  result.cursor = readString(data, pos, int(cursorLen))

proc encodeRangeResponse*(resp: RangeResponse): string =
  ## Encode a range query response
  ## Format: ``[count:4][items...][hasMore:1][nextCursorLen:2][nextCursor:N]``
  result = newStringOfCap(4 + resp.nextCursor.len + 20)  # Reasonable capacity
  result.writeUint32BE(uint32(resp.items.len))

  for item in resp.items:
    result.writeUint16BE(uint16(item[0].len))
    result.add(item[0])
    result.writeUint32BE(uint32(item[1].len))
    result.add(item[1])

  result.writeByte(byte(if resp.hasMore: 1 else: 0))
  result.writeUint16BE(uint16(resp.nextCursor.len))
  result.add(resp.nextCursor)

proc decodeRangeResponse*(data: string): RangeResponse =
  ## Decode a range query response
  var pos = 0
  let count = readUint32BE(data, pos)
  result.items = newSeq[(string, string)](count)

  for i in 0..<count:
    let keyLen = readUint16BE(data, pos)
    if keyLen > MaxKeySize:
      raise newException(ProtocolError, "Key too large: " & $keyLen)
    let key = readString(data, pos, int(keyLen))

    let valLen = readUint32BE(data, pos)
    if valLen > MaxValueSize:
      raise newException(ProtocolError, "Value too large: " & $valLen)
    let value = readString(data, pos, int(valLen))

    result.items[i] = (key, value)

  let hasMoreByte = readByte(data, pos)
  result.hasMore = hasMoreByte != 0

  let nextCursorLen = readUint16BE(data, pos)
  if nextCursorLen > MaxKeySize:
    raise newException(ProtocolError, "Next cursor too large: " & $nextCursorLen)
  result.nextCursor = readString(data, pos, int(nextCursorLen))

proc decodeKeysResponse*(data: string): KeysResponse =
  ## Decode a keys-only query response
  var pos = 0
  let count = readUint32BE(data, pos)
  result.keys = newSeq[string](count)

  for i in 0..<count:
    let keyLen = readUint16BE(data, pos)
    if keyLen > MaxKeySize:
      raise newException(ProtocolError, "Key too large: " & $keyLen)
    result.keys[i] = readString(data, pos, int(keyLen))

  let hasMoreByte = readByte(data, pos)
  result.hasMore = hasMoreByte != 0

  let nextCursorLen = readUint16BE(data, pos)
  if nextCursorLen > MaxKeySize:
    raise newException(ProtocolError, "Next cursor too large: " & $nextCursorLen)
  result.nextCursor = readString(data, pos, int(nextCursorLen))


proc newRequest*(command: Command, key: string = "", value: string = "", seq: uint32 = 0): Request =
  ## Create a new request.
  Request(command: command, seq: seq, key: key, value: value)

proc newResponse*(status: ResponseStatus, seq: uint32, value: string = ""): Response =
  ## Create a new response.
  Response(status: status, seq: seq, value: value)

proc okResponse*(seq: uint32, value: string = ""): Response =
  ## Create an OK response.
  newResponse(statusOk, seq, value)

proc errorResponse*(seq: uint32, message: string = ""): Response =
  ## Create an error response.
  newResponse(statusError, seq, message)

proc notFoundResponse*(seq: uint32): Response =
  ## Create a not found response.
  newResponse(statusNotFound, seq)

proc noBarrelResponse*(seq: uint32): Response =
  ## Create a no barrel selected response.
  newResponse(statusNoBarrel, seq)

proc barrelExistsResponse*(seq: uint32): Response =
  ## Create a barrel already exists response.
  newResponse(statusBarrelExists, seq)

proc barrelNotFoundResponse*(seq: uint32): Response =
  ## Create a barrel not found response.
  newResponse(statusBarrelNotFound, seq)

proc invalidResponse*(seq: uint32, message: string = ""): Response =
  ## Create an invalid request response.
  newResponse(statusInvalid, seq, message)

proc unauthorizedResponse*(seq: uint32, message: string = ""): Response =
  ## Create an unauthorized response.
  newResponse(statusUnauthorized, seq, message)


proc `$`*(cmd: Command): string =
  ## String representation of command.
  case cmd
  of cmdGet: "GET"
  of cmdSet: "SET"
  of cmdDelete: "DELETE"
  of cmdExists: "EXISTS"
  of cmdCount: "COUNT"
  of cmdListKeys: "LIST_KEYS"
  of cmdPing: "PING"
  of cmdRangeQuery: "RANGE_QUERY"
  of cmdPrefixQuery: "PREFIX_QUERY"
  of cmdRangeCount: "RANGE_COUNT"
  of cmdRangeKeys: "RANGE_KEYS"
  of cmdPrefixKeys: "PREFIX_KEYS"
  of cmdBatchGet: "BATCH_GET"
  of cmdBatchSet: "BATCH_SET"
  of cmdBatchDelete: "BATCH_DELETE"
  of cmdCreateBarrel: "CREATE_BARREL"
  of cmdOpenBarrel: "OPEN_BARREL"
  of cmdUseBarrel: "USE_BARREL"
  of cmdCloseBarrel: "CLOSE_BARREL"
  of cmdListBarrels: "LIST_BARRELS"
  of cmdDropBarrel: "DROP_BARREL"
  of cmdGetBarrelConfig: "GET_BARREL_CONFIG"
  of cmdSetBarrelConfig: "SET_BARREL_CONFIG"
  of cmdGetBarrelStats: "GET_BARREL_STATS"
  of cmdTraverse: "TRAVERSE"
  of cmdSubscribe: "SUBSCRIBE"
  of cmdUnsubscribe: "UNSUBSCRIBE"
  of cmdPublish: "PUBLISH"
  of cmdListSubscribers: "LIST_SUBSCRIBERS"
  of cmdHistory: "HISTORY"
  of cmdListTopics: "LIST_TOPICS"
  of cmdPresence: "PRESENCE"
  of cmdWatchKey: "WATCH_KEY"
  of cmdUnwatchKey: "UNWATCH_KEY"

proc `$`*(status: ResponseStatus): string =
  ## String representation of status.
  case status
  of statusOk: "OK"
  of statusNotFound: "NOT_FOUND"
  of statusError: "ERROR"
  of statusInvalid: "INVALID"
  of statusNoBarrel: "NO_BARREL"
  of statusBarrelExists: "BARREL_EXISTS"
  of statusBarrelNotFound: "BARREL_NOT_FOUND"
  of statusUnauthorized: "UNAUTHORIZED"

proc `$`*(req: Request): string =
  ## String representation of request.
  result = $req.command & "(seq=" & $req.seq
  if req.key.len > 0:
    result.add(", key=\"" & req.key & "\"")
  if req.value.len > 0:
    if req.value.len <= 50:
      result.add(", value=\"" & req.value & "\"")
    else:
      result.add(", value=<" & $req.value.len & " bytes>")
  result.add(")")

proc `$`*(resp: Response): string =
  ## String representation of response.
  result = $resp.status & "(seq=" & $resp.seq
  if resp.value.len > 0:
    if resp.value.len <= 50:
      result.add(", value=\"" & resp.value & "\"")
    else:
      result.add(", value=<" & $resp.value.len & " bytes>")
  result.add(")")

## ============================================================================
## Pub/Sub Protocol Functions
## ============================================================================

proc encodeSubscribeRequest*(topic: string, pattern: string, options: SubscriptionOptions): string =
  ## Encode a subscribe request
  ## Format: ``[options:1][topicLen:2][topic:N][patternLen:2][pattern:M]``

  var optionsByte: byte = 0
  if options.enableKvEvents:
    optionsByte = optionsByte or 0x01
  if options.enablePresence:
    optionsByte = optionsByte or 0x02
  if options.replayHistory:
    optionsByte = optionsByte or 0x04

  result = newStringOfCap(1 + 2 + topic.len + 2 + pattern.len)
  result.writeByte(optionsByte)
  result.writeUint16BE(uint16(topic.len))
  result.add(topic)
  result.writeUint16BE(uint16(pattern.len))
  result.add(pattern)

proc decodeSubscribeResponse*(data: string): string =
  ## Decode subscribe response - returns subscription ID
  ## The subscription ID is the entire response value
  data

proc encodePublishRequest*(topic: string, messageType: PubSubMessageType,
                           payload: string, headers: string = ""): string =
  ## Encode a publish request
  ## Format: ``[topicLen:2][topic:N][msgType:1][headersLen:4][headers:M][payloadLen:4][payload:P]``

  result = newStringOfCap(2 + topic.len + 1 + 4 + headers.len + 4 + payload.len)
  result.writeUint16BE(uint16(topic.len))
  result.add(topic)
  result.writeByte(byte(ord(messageType)))
  result.writeUint32BE(uint32(headers.len))
  if headers.len > 0:
    result.add(headers)
  result.writeUint32BE(uint32(payload.len))
  if payload.len > 0:
    result.add(payload)

proc decodePublishResponse*(data: string): uint64 =
  ## Decode publish response - returns sequence number
  ## The sequence number is encoded as uint64 in the response value
  var pos = 0
  readUint64BE(data, pos)

proc decodePubSubEvent*(data: string): PubSubEvent =
  ## Decode a pub/sub event message (command 0xFF)
  ## Format: ``[cmd:1][seq:4][topicLen:2][topic][msgType:1][seq:8][ts:8][headersLen:4][headers][payloadLen:4][payload]``
  var pos = 0

  # Skip command byte (already consumed by caller)
  # Skip seq field (request sequence, not used for events)
  pos += 5

  # Read topic
  let topicLen = readUint16BE(data, pos)
  if topicLen > MaxKeySize:
    raise newException(ProtocolError, "Topic too large: " & $topicLen)
  result.topic = readString(data, pos, int(topicLen))

  # Read message type
  result.messageType = PubSubMessageType(readByte(data, pos))

  # Read sequence number
  result.sequence = readUint64BE(data, pos)

  # Read timestamp
  result.timestamp = int64(readUint64BE(data, pos))

  # Read headers
  let headersLen = readUint32BE(data, pos)
  if headersLen > MaxValueSize:
    raise newException(ProtocolError, "Headers too large: " & $headersLen)
  if headersLen > 0:
    result.headers = readString(data, pos, int(headersLen))
  else:
    result.headers = ""

  # Read payload
  let payloadLen = readUint32BE(data, pos)
  if payloadLen > MaxValueSize:
    raise newException(ProtocolError, "Payload too large: " & $payloadLen)
  if payloadLen > 0:
    result.payload = readString(data, pos, int(payloadLen))
  else:
    result.payload = ""

proc isPubSubEvent*(data: string): bool =
  ## Check if binary data is a pub/sub event (command 0xFF)
  ## Returns true if this is an event, false if it's a response
  if data.len == 0:
    return false
  # First byte of event is command (0xFF)
  # First byte of response is status (< 0x10)
  return byte(data[0]) == 0xFF'u8

proc encodeHistoryRequest*(req: HistoryRequest): string =
  ## Encode a history request
  ## Format: ``[topicLen:2][topic:N][count:4][sinceSeq:8]``
  result = newStringOfCap(2 + req.topic.len + 4 + 8)
  result.writeUint16BE(uint16(req.topic.len))
  result.add(req.topic)
  result.writeUint32BE(uint32(req.count))
  result.writeUint64BE(req.sinceSeq)

proc encodePresenceRequest*(req: PresenceRequest): string =
  ## Encode a presence request
  ## Format: ``[operation:1]``
  result = newStringOfCap(1)
  result.writeByte(req.operation)

## Batch operation encoding/decoding

proc encodeBatchGetRequest*(req: BatchGetRequest): string =
  ## Encode a batch get request for use as the value field of a Request.
  ## Format: ``[count:4][keyLen1:2][key1:N]...[keyLenN:2][keyN:M]``
  ## Note: Command byte and sequence should be in the outer Request, not here.
  if req.keys.len > MaxBatchItems:
    raise newException(ProtocolError, "Too many keys in batch get: " & $req.keys.len)

  result = newStringOfCap(4)
  result.writeUint32BE(uint32(req.keys.len))

  for key in req.keys:
    if key.len > MaxKeySize:
      raise newException(ProtocolError, "Key too large: " & $key.len)
    result.writeUint16BE(uint16(key.len))
    result.add(key)

proc decodeBatchGetRequest*(data: string): BatchGetRequest =
  ## Decode a batch get request
  var pos = 0

  let cmdByte = readByte(data, pos)
  if cmdByte != byte(ord(cmdBatchGet)):
    raise newException(ProtocolError, "Invalid command for batch get: 0x" & cmdByte.toHex)

  result.seq = readUint32BE(data, pos)
  let count = readUint32BE(data, pos)

  if count > MaxBatchItems:
    raise newException(ProtocolError, "Batch get count too large: " & $count)

  result.keys = newSeq[string](int(count))
  for i in 0..<count:
    let keyLen = readUint16BE(data, pos)
    if keyLen > MaxKeySize:
      raise newException(ProtocolError, "Key too large: " & $keyLen)
    result.keys[i] = readString(data, pos, int(keyLen))

proc encodeBatchGetResponse*(resp: BatchGetResponse): string =
  ## Encode a batch get response
  ## Format: ``[status:1=0x00][seq:4][count:4][status1:1][valLen1:4][val1:N]...[statusN:1][valLenN:4][valN:M]``
  result = newStringOfCap(1 + 4 + 4)
  result.writeByte(byte(ord(statusOk)))
  result.writeUint32BE(resp.seq)
  result.writeUint32BE(uint32(resp.results.len))

  for item in resp.results:
    result.writeByte(byte(item.status))
    result.writeUint32BE(uint32(item.value.len))
    if item.value.len > 0:
      result.add(item.value)

proc decodeBatchGetResponse*(data: string): BatchGetResponse =
  ## Decode a batch get response
  var pos = 0

  let statusByte = readByte(data, pos)
  if statusByte != byte(ord(statusOk)):
    raise newException(ProtocolError, "Invalid status for batch get response")

  result.seq = readUint32BE(data, pos)
  let count = readUint32BE(data, pos)

  result.results = newSeq[tuple[status: uint8, value: string]](int(count))
  for i in 0..<count:
    let itemStatus = readByte(data, pos)
    let valLen = readUint32BE(data, pos)
    if valLen > MaxValueSize:
      raise newException(ProtocolError, "Value too large: " & $valLen)
    result.results[i].status = itemStatus
    result.results[i].value = readString(data, pos, int(valLen))

proc encodeBatchSetRequest*(req: BatchSetRequest): string =
  ## Encode a batch set request for use as the value field of a Request.
  ## Format: ``[count:4][keyLen1:2][key1:N][valLen1:4][val1:M]...``
  ## Note: Command byte and sequence should be in the outer Request, not here.
  if req.pairs.len > MaxBatchItems:
    raise newException(ProtocolError, "Too many pairs in batch set: " & $req.pairs.len)

  result = newStringOfCap(4)
  result.writeUint32BE(uint32(req.pairs.len))

  for (key, value) in req.pairs:
    if key.len > MaxKeySize:
      raise newException(ProtocolError, "Key too large: " & $key.len)
    if value.len > MaxValueSize:
      raise newException(ProtocolError, "Value too large: " & $value.len)
    result.writeUint16BE(uint16(key.len))
    result.add(key)
    result.writeUint32BE(uint32(value.len))
    result.add(value)

proc decodeBatchSetRequest*(data: string): BatchSetRequest =
  ## Decode a batch set request
  var pos = 0

  let cmdByte = readByte(data, pos)
  if cmdByte != byte(ord(cmdBatchSet)):
    raise newException(ProtocolError, "Invalid command for batch set: 0x" & cmdByte.toHex)

  result.seq = readUint32BE(data, pos)
  let count = readUint32BE(data, pos)

  if count > MaxBatchItems:
    raise newException(ProtocolError, "Batch set count too large: " & $count)

  result.pairs = newSeq[tuple[key: string, value: string]](int(count))
  for i in 0..<count:
    let keyLen = readUint16BE(data, pos)
    if keyLen > MaxKeySize:
      raise newException(ProtocolError, "Key too large: " & $keyLen)
    result.pairs[i].key = readString(data, pos, int(keyLen))

    let valLen = readUint32BE(data, pos)
    if valLen > MaxValueSize:
      raise newException(ProtocolError, "Value too large: " & $valLen)
    result.pairs[i].value = readString(data, pos, int(valLen))

proc encodeBatchSetResponse*(resp: BatchSetResponse): string =
  ## Encode a batch set response
  ## Format: ``[status:1=0x00][seq:4][count:4][status1:1]...[statusN:1]``
  result = newStringOfCap(1 + 4 + 4)
  result.writeByte(byte(ord(statusOk)))
  result.writeUint32BE(resp.seq)
  result.writeUint32BE(uint32(resp.statuses.len))

  for status in resp.statuses:
    result.writeByte(byte(status))

proc decodeBatchSetResponse*(data: string): BatchSetResponse =
  ## Decode a batch set response
  var pos = 0

  let statusByte = readByte(data, pos)
  if statusByte != byte(ord(statusOk)):
    raise newException(ProtocolError, "Invalid status for batch set response")

  result.seq = readUint32BE(data, pos)
  let count = readUint32BE(data, pos)

  result.statuses = newSeq[uint8](int(count))
  for i in 0..<count:
    result.statuses[i] = readByte(data, pos)

proc encodeBatchDeleteRequest*(req: BatchDeleteRequest): string =
  ## Encode a batch delete request for use as the value field of a Request.
  ## Format: ``[count:4][keyLen1:2][key1:N]...[keyLenN:2][keyN:M]``
  ## Note: Command byte and sequence should be in the outer Request, not here.
  if req.keys.len > MaxBatchItems:
    raise newException(ProtocolError, "Too many keys in batch delete: " & $req.keys.len)

  result = newStringOfCap(4)
  result.writeUint32BE(uint32(req.keys.len))

  for key in req.keys:
    if key.len > MaxKeySize:
      raise newException(ProtocolError, "Key too large: " & $key.len)
    result.writeUint16BE(uint16(key.len))
    result.add(key)

proc decodeBatchDeleteRequest*(data: string): BatchDeleteRequest =
  ## Decode a batch delete request
  var pos = 0

  let cmdByte = readByte(data, pos)
  if cmdByte != byte(ord(cmdBatchDelete)):
    raise newException(ProtocolError, "Invalid command for batch delete: 0x" & cmdByte.toHex)

  result.seq = readUint32BE(data, pos)
  let count = readUint32BE(data, pos)

  if count > MaxBatchItems:
    raise newException(ProtocolError, "Batch delete count too large: " & $count)

  result.keys = newSeq[string](int(count))
  for i in 0..<count:
    let keyLen = readUint16BE(data, pos)
    if keyLen > MaxKeySize:
      raise newException(ProtocolError, "Key too large: " & $keyLen)
    result.keys[i] = readString(data, pos, int(keyLen))

proc encodeBatchDeleteResponse*(resp: BatchDeleteResponse): string =
  ## Encode a batch delete response
  ## Format: ``[status:1=0x00][seq:4][count:4][status1:1]...[statusN:1]``
  result = newStringOfCap(1 + 4 + 4)
  result.writeByte(byte(ord(statusOk)))
  result.writeUint32BE(resp.seq)
  result.writeUint32BE(uint32(resp.statuses.len))

  for status in resp.statuses:
    result.writeByte(byte(status))

proc decodeBatchDeleteResponse*(data: string): BatchDeleteResponse =
  ## Decode a batch delete response
  var pos = 0

  let statusByte = readByte(data, pos)
  if statusByte != byte(ord(statusOk)):
    raise newException(ProtocolError, "Invalid status for batch delete response")

  result.seq = readUint32BE(data, pos)
  let count = readUint32BE(data, pos)

  result.statuses = newSeq[uint8](int(count))
  for i in 0..<count:
    result.statuses[i] = readByte(data, pos)

## Handshake encoding/decoding

type
  ServerHandshake* = object
    ## Server handshake sent on connection
    versionMajor*: uint8
    versionMinor*: uint8
    serverId*: string          ## Unique server identifier
    plugins*: seq[string]      ## Available plugins

proc decodeHandshake*(data: string): ServerHandshake =
  ## Decode a server handshake from binary format.
  ## Format: ``[versionMajor:1][versionMinor:1][serverIdLen:2][serverId:N][pluginCount:1][pluginNameLen:2][pluginName1]...``
  var pos = 0

  if pos >= data.len:
    raise newException(ProtocolError, "Unexpected end of data reading versionMajor")

  result.versionMajor = readByte(data, pos)
  result.versionMinor = readByte(data, pos)

  let serverIdLen = readUint16BE(data, pos)
  if serverIdLen > MaxKeySize:
    raise newException(ProtocolError, "Server ID too large: " & $serverIdLen)
  result.serverId = readString(data, pos, int(serverIdLen))

  let pluginCount = readByte(data, pos)
  if pluginCount > 0 and pos < data.len:
    result.plugins = newSeq[string](pluginCount)
    for i in 0 ..< int(pluginCount):
      let pluginNameLen = readUint16BE(data, pos)
      if pluginNameLen > 255:
        raise newException(ProtocolError, "Plugin name too long: " & $pluginNameLen)
      result.plugins[i] = readString(data, pos, int(pluginNameLen))
  else:
    result.plugins = @[]

## Watch request encoding/decoding

proc encodeWatchRequest*(barrelName: string, pattern: string, includeValues: bool): string =
  ## Encode a watch request to binary format.
  ## Format: ``[barrelLen:2][barrel][patternLen:2][pattern][options:1]``
  if barrelName.len > MaxKeySize:
    raise newException(ProtocolError, "Barrel name too large: " & $barrelName.len)
  if pattern.len > MaxKeySize:
    raise newException(ProtocolError, "Pattern too large: " & $pattern.len)

  result = newStringOfCap(2 + barrelName.len + 2 + pattern.len + 1)
  result.writeUint16BE(uint16(barrelName.len))
  result.add(barrelName)
  result.writeUint16BE(uint16(pattern.len))
  result.add(pattern)

  var options: byte = 0
  if includeValues:
    options = options or 0x01
  result.add(char(options))



