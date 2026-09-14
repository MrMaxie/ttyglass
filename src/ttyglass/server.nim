import chronicles
import jsony
import mummy
import std/[atomics, base64, json, net, os, osproc, streams, strtabs, strutils, sysrand, tables, times]
import std/locks

import ./[assets, control_plane, diagnostics, ipc, messages, terminal_screen]

type
  SessionMode* = enum
    CommandMode = "command"
    TerminalMode = "terminal"

  ServiceOptions* = object
    port*: int
    diagnosticsLimit*: int
    outputLimit*: int
    foreground*: bool

  SessionRequest* = object
    name*: string
    mode*: SessionMode
    argv*: seq[string]
    shell*: string
    cwd*: string
    cols*: int
    rows*: int

  ManagedSession = ref object
    lock: Lock
    id: string
    token: string
    name: string
    mode: SessionMode
    argv: seq[string]
    displayCommand: string
    shell: string
    cwd: string
    restartable: bool
    cols: int
    rows: int
    status: string
    pid: int
    exitCode: int
    statusMessage: string
    diagnostics: seq[DiagnosticRecord]
    output: string
    outputStart: int64
    outputEnd: int64
    screen: TerminalScreen
    sockets: seq[WebSocket]
    externalClients: int
    lastDetachedAt: float64
    completedAt: float64
    terminal: TerminalProcess

  TerminalProcess = ref object
    process: Process
    input: Stream
    output: Stream
    errors: Stream
    owner: ManagedSession
    writeLock: Lock
    readerThread: Thread[TerminalProcess]
    errorThread: Thread[TerminalProcess]
    stopped: Atomic[bool]

  ApplicationState = ref object
    lock: Lock
    options: ServiceOptions
    token: string
    origin: string
    sessions: Table[string, ManagedSession]
    socketSessions: Table[WebSocket, ManagedSession]
    server: Server
    control: ControlServer
    startedAt: float64

const
  LoopbackAddress = "127.0.0.1"
  MaximumDiagnosticBodyBytes = 64 * 1024
  MaximumWebSocketMessageBytes = 64 * 1024
  DefaultRetentionSeconds = 5 * 60.0

var
  application: ApplicationState
  stopRequested: Atomic[bool]
  serverFailed: Atomic[bool]
  serverFailureLock: Lock
  serverFailure: string

proc defaultHeaders(contentType: string): HttpHeaders =
  result["Cache-Control"] = "no-store"
  result["Content-Type"] = contentType
  result["Referrer-Policy"] = "no-referrer"
  result["X-Content-Type-Options"] = "nosniff"

proc pageHeaders(contentType: string): HttpHeaders =
  result = defaultHeaders(contentType)
  result["Content-Security-Policy"] =
    "default-src 'self'; connect-src 'self' ws://127.0.0.1:*; " &
    "style-src 'self' 'unsafe-inline'; img-src 'self'; object-src 'none'; " &
    "base-uri 'none'; frame-ancestors 'none'; form-action 'none'"

proc respondText(request: Request, status: int, message: string) =
  request.respond(status, defaultHeaders("text/plain; charset=utf-8"), message & "\n")

proc tokenMatches(candidate, expected: string): bool =
  if candidate.len != expected.len:
    return false
  var difference = 0
  for index in 0 ..< expected.len:
    difference = difference or (ord(candidate[index]) xor ord(expected[index]))
  difference == 0

proc bearerMatches(header, expected: string): bool =
  const prefix = "Bearer "
  header.startsWith(prefix) and tokenMatches(header[prefix.len .. ^1], expected)

proc freshToken(bytes = 32): string =
  let values = urandom(bytes)
  if values.len != bytes:
    raise newException(OSError, "The operating system did not provide a session token.")
  result = newStringOfCap(bytes * 2)
  for value in values:
    result.add(toHex(value, 2).toLowerAscii())

proc freshSessionId(): string = freshToken(12)

proc quoteDisplayArgument(value: string): string =
  if value.len > 0 and value.allCharsInSet(
    {'a'..'z', 'A'..'Z', '0'..'9', '_', '-', '.', '/', '\\', ':', '@', '%', '+', '=', ','},
  ):
    return value
  "'" & value.replace("'", "'\\''") & "'"

proc displayCommand*(argv: openArray[string]): string =
  for index, value in argv:
    if index > 0:
      result.add(' ')
    result.add(quoteDisplayArgument(value))

proc retentionSeconds(): float64 =
  try:
    let milliseconds = parseInt(getEnv("TTYGLASS_RETENTION_MS", "300000"))
    max(100, milliseconds).float64 / 1000.0
  except ValueError:
    DefaultRetentionSeconds

proc safeSend(socket: WebSocket, payload: string) =
  try:
    socket.send(payload, TextMessage)
  except CatchableError:
    discard

proc broadcast(session: ManagedSession, payload: string) =
  var sockets: seq[WebSocket]
  withLock session.lock:
    sockets = session.sockets
  for socket in sockets:
    socket.safeSend(payload)

proc metadataNode(session: ManagedSession, includeToken = false): JsonNode =
  withLock session.lock:
    result = %*{
      "sessionId": session.id,
      "name": session.name,
      "mode": $session.mode,
      "argv": session.argv,
      "displayCommand": session.displayCommand,
      "shell": session.shell,
      "restartable": session.restartable,
      "cols": session.cols,
      "rows": session.rows,
    }
    if includeToken:
      result["token"] = %session.token
      result["url"] = %(application.origin & "/sessions/" & session.id & "#token=" & session.token)

proc statusNode(session: ManagedSession): JsonNode =
  withLock session.lock:
    result = %*{
      "sessionId": session.id,
      "state": session.status,
      "pid": session.pid,
      "exitCode": session.exitCode,
      "message": session.statusMessage,
      "cols": session.cols,
      "rows": session.rows,
    }

proc snapshotNode(session: ManagedSession): JsonNode =
  withLock session.lock:
    result = %*{
      "sessionId": session.id,
      "revision": session.screen.revision,
      "cols": session.screen.cols,
      "rows": session.screen.rows,
      "lines": session.screen.lines(),
      "cursor": {
        "row": session.screen.cursor.row,
        "col": session.screen.cursor.col,
        "visible": session.screen.cursor.visible,
      },
      "status": session.status,
    }

proc outputNode(session: ManagedSession, requestedOffset: int64): JsonNode =
  withLock session.lock:
    let start = max(requestedOffset, session.outputStart)
    let relative = max(0'i64, start - session.outputStart).int
    let retained = if relative < session.output.len: session.output[relative .. ^1] else: ""
    result = %*{
      "sessionId": session.id,
      "startOffset": start,
      "endOffset": session.outputEnd,
      "truncated": requestedOffset < session.outputStart,
      "data": encode(retained),
    }

proc diagnosticsNode(session: ManagedSession): JsonNode =
  withLock session.lock:
    result = %*{"sessionId": session.id, "entries": session.diagnostics}

proc sessionListNode(includeUrls = false): JsonNode =
  result = newJArray()
  var sessions: seq[ManagedSession]
  withLock application.lock:
    for session in application.sessions.values:
      sessions.add(session)
  for session in sessions:
    let metadata = session.metadataNode(includeUrls)
    let status = session.statusNode()
    metadata["status"] = status["state"]
    metadata["pid"] = status["pid"]
    result.add(metadata)

proc writeControl(terminal: TerminalProcess, kind: FrameKind, payload = "") =
  if terminal.isNil or terminal.stopped.load(moRelaxed):
    return
  withLock terminal.writeLock:
    try:
      terminal.input.writeFrame(kind, payload)
    except IOError, OSError:
      discard

proc appendOutput(session: ManagedSession, payload: string) =
  withLock session.lock:
    session.output.add(payload)
    session.outputEnd += payload.len.int64
    if session.output.len > application.options.outputLimit:
      let removed = session.output.len - application.options.outputLimit
      session.output.delete(0 .. removed - 1)
      session.outputStart += removed.int64
    session.screen.feed(payload)

proc hostErrorReader(terminal: TerminalProcess) {.thread, gcsafe.} =
  {.cast(gcsafe).}:
    try:
      var buffer: array[4096, char]
      while true:
        let count = terminal.errors.readData(addr buffer[0], buffer.len)
        if count <= 0:
          break
        stderr.write(buffer[0 ..< count])
        stderr.flushFile()
    except IOError, OSError:
      discard

proc hostFrameReader(terminal: TerminalProcess) {.thread, gcsafe.} =
  {.cast(gcsafe).}:
    let session = terminal.owner
    try:
      while true:
        let frame = terminal.output.readFrame()
        case frame.kind
        of StartedFrame:
          let started = frame.payload.parseStarted()
          withLock session.lock:
            session.pid = started.pid
            session.status = "running"
          session.broadcast(runningJson(started.pid))
        of OutputFrame:
          session.appendOutput(frame.payload)
          session.broadcast(outputJson(frame.payload))
        of ExitedFrame:
          let exited = frame.payload.parseExited()
          withLock session.lock:
            session.pid = exited.pid
            session.exitCode = exited.exitCode
            session.status = "exited"
            session.completedAt = epochTime()
          session.broadcast(exitedJson(exited.pid, exited.exitCode))
          break
        of ErrorFrame:
          withLock session.lock:
            session.status = "failed"
            session.statusMessage = frame.payload
            session.completedAt = epochTime()
          session.broadcast(failedJson(frame.payload))
          break
        else:
          discard
    except IOError, OSError, ValueError:
      if not terminal.stopped.load(moRelaxed):
        let detail = "The native PTY host disconnected unexpectedly: " & getCurrentException().msg
        withLock session.lock:
          session.status = "failed"
          session.statusMessage = detail
          session.completedAt = epochTime()
        session.broadcast(failedJson(detail))

proc childEnvironment(session: ManagedSession): StringTableRef =
  result = newStringTable(modeCaseInsensitive)
  for key, value in envPairs():
    result[key] = value
  result["TERM"] = "xterm-256color"
  result["COLORTERM"] = "truecolor"
  result["TTYGLASS_SESSION_ID"] = session.id
  result["TTYGLASS_DIAGNOSTICS_URL"] =
    application.origin & "/api/sessions/" & session.id & "/diagnostics"
  result["TTYGLASS_DIAGNOSTICS_TOKEN"] = session.token
  result.del("NO_COLOR")

proc startTerminal(session: ManagedSession): TerminalProcess =
  let host = startProcess(
    getAppFilename(),
    args = ["--internal-pty-host"],
    env = childEnvironment(session),
    options = {poUsePath, poDaemon},
  )
  result = TerminalProcess(
    process: host,
    input: host.inputStream(),
    output: host.outputStream(),
    errors: host.errorStream(),
    owner: session,
  )
  result.stopped.store(false, moRelaxed)
  initLock(result.writeLock)
  withLock session.lock:
    session.status = "starting"
    session.statusMessage = ""
    session.pid = 0
    session.exitCode = 0
    session.completedAt = 0
  result.writeControl(
    StartFrame,
    StartControl(
      command: session.argv[0],
      arguments: if session.argv.len > 1: session.argv[1 .. ^1] else: @[],
      cwd: session.cwd,
      cols: session.cols,
      rows: session.rows,
    ).startPayload(),
  )
  createThread(result.readerThread, hostFrameReader, result)
  createThread(result.errorThread, hostErrorReader, result)

proc stopTerminal(terminal: TerminalProcess) =
  if terminal.isNil or terminal.stopped.exchange(true, moRelaxed):
    return
  withLock terminal.writeLock:
    try:
      terminal.input.writeFrame(StopFrame)
      terminal.input.close()
    except IOError, OSError:
      discard
  try:
    discard terminal.process.waitForExit(3000)
  except IOError, OSError:
    discard
  joinThread(terminal.readerThread)
  joinThread(terminal.errorThread)
  try:
    terminal.process.close()
  except IOError, OSError:
    discard
  deinitLock(terminal.writeLock)

proc startManagedSession(request: SessionRequest): ManagedSession =
  if request.argv.len == 0:
    raise newException(ValueError, "A session command is required.")
  if not dirExists(request.cwd):
    raise newException(ValueError, "Working directory does not exist: " & request.cwd)
  let cols = max(2, min(1000, request.cols))
  let rows = max(1, min(500, request.rows))
  result = ManagedSession(
    id: freshSessionId(),
    token: freshToken(),
    name: request.name.strip(),
    mode: request.mode,
    argv: request.argv,
    displayCommand: if request.mode == TerminalMode: "No command" else: displayCommand(request.argv),
    shell: request.shell,
    cwd: request.cwd,
    restartable: request.mode == CommandMode,
    cols: cols,
    rows: rows,
    status: "starting",
    screen: newTerminalScreen(cols, rows),
    lastDetachedAt: epochTime(),
  )
  initLock(result.lock)
  withLock application.lock:
    while result.id in application.sessions:
      result.id = freshSessionId()
    application.sessions[result.id] = result
  try:
    result.terminal = startTerminal(result)
  except CatchableError:
    withLock application.lock:
      application.sessions.del(result.id)
    deinitLock(result.lock)
    raise

proc findSession(id: string): ManagedSession =
  withLock application.lock:
    if id in application.sessions:
      return application.sessions[id]
  raise newException(ValueError, "Unknown ttyglass session: " & id)

proc attach(session: ManagedSession) =
  withLock session.lock:
    inc session.externalClients
    session.lastDetachedAt = 0

proc detach(session: ManagedSession) =
  withLock session.lock:
    session.externalClients = max(0, session.externalClients - 1)
    if session.externalClients == 0 and session.sockets.len == 0:
      session.lastDetachedAt = epochTime()

proc resizeSession(session: ManagedSession, cols, rows: int) =
  if cols < 2 or cols > 1000 or rows < 1 or rows > 500:
    raise newException(ValueError, "Terminal size is outside the supported range.")
  var terminal: TerminalProcess
  withLock session.lock:
    session.cols = cols
    session.rows = rows
    session.screen.resize(cols, rows)
    terminal = session.terminal
  terminal.writeControl(ResizeFrame, ResizeControl(cols: cols, rows: rows).resizePayload())
  session.broadcast(resizedJson(cols, rows))

proc restartSession(session: ManagedSession) =
  if not session.restartable:
    raise newException(ValueError, "Terminal sessions cannot be restarted.")
  var previous: TerminalProcess
  withLock session.lock:
    previous = session.terminal
    session.terminal = nil
    session.output.setLen(0)
    session.outputStart = session.outputEnd
    session.screen = newTerminalScreen(session.cols, session.rows)
  stopTerminal(previous)
  let next = startTerminal(session)
  withLock session.lock:
    session.terminal = next

proc stopSession(session: ManagedSession) =
  var terminal: TerminalProcess
  withLock session.lock:
    terminal = session.terminal
    session.terminal = nil
    if session.status notin ["exited", "failed", "stopped"]:
      session.status = "stopped"
      session.completedAt = epochTime()
  stopTerminal(terminal)
  session.broadcast(stoppedJson())

proc removeSession(id: string) =
  var session: ManagedSession
  withLock application.lock:
    if id notin application.sessions:
      return
    session = application.sessions[id]
    application.sessions.del(id)
  session.stopSession()
  deinitLock(session.lock)

proc controlSuccess(value: JsonNode): string = $(%*{"ok": true, "result": value})
proc controlFailure(message: string): string = $(%*{"ok": false, "error": message})

proc requiredString(parameters: JsonNode, key: string): string =
  if parameters.kind != JObject or key notin parameters or parameters[key].kind != JString:
    raise newException(ValueError, "Missing string parameter: " & key)
  parameters[key].getStr()

proc handleControl(payload: string): string {.gcsafe.} =
  {.cast(gcsafe).}:
    try:
      let request = parseJson(payload)
      if request.kind != JObject or request{"token"}.getStr() != application.token:
        return controlFailure("Unauthorized")
      let operation = request{"method"}.getStr()
      let parameters = if "params" in request: request["params"] else: newJObject()
      case operation
      of "ping": controlSuccess(%*{"pid": getCurrentProcessId(), "origin": application.origin})
      of "list": controlSuccess(sessionListNode())
      of "start":
        var mode = if parameters{"mode"}.getStr() == "terminal": TerminalMode else: CommandMode
        var argv: seq[string]
        if "argv" in parameters and parameters["argv"].kind == JArray:
          for value in parameters["argv"]:
            if value.kind != JString:
              raise newException(ValueError, "Every argv value must be a string.")
            argv.add(value.getStr())
        let shell = parameters{"shell"}.getStr()
        if mode == TerminalMode and argv.len == 0:
          if shell.len == 0:
            raise newException(ValueError, "Terminal mode requires a resolved shell.")
          argv = @[shell]
        let session = startManagedSession(SessionRequest(
          name: parameters{"name"}.getStr(),
          mode: mode,
          argv: argv,
          shell: if mode == TerminalMode: shell else: "",
          cwd: parameters{"cwd"}.getStr(getCurrentDir()),
          cols: parameters{"cols"}.getInt(100),
          rows: parameters{"rows"}.getInt(30),
        ))
        controlSuccess(session.metadataNode(true))
      of "attach":
        let session = findSession(parameters.requiredString("sessionId"))
        session.attach()
        controlSuccess(session.metadataNode())
      of "detach":
        let session = findSession(parameters.requiredString("sessionId"))
        session.detach()
        controlSuccess(%*{"sessionId": session.id})
      of "metadata": controlSuccess(findSession(parameters.requiredString("sessionId")).metadataNode())
      of "open": controlSuccess(findSession(parameters.requiredString("sessionId")).metadataNode(true))
      of "status": controlSuccess(findSession(parameters.requiredString("sessionId")).statusNode())
      of "screen": controlSuccess(findSession(parameters.requiredString("sessionId")).snapshotNode())
      of "output":
        controlSuccess(findSession(parameters.requiredString("sessionId")).outputNode(parameters{"from"}.getBiggestInt(0).int64))
      of "input":
        let session = findSession(parameters.requiredString("sessionId"))
        let data = decode(parameters.requiredString("data"))
        var terminal: TerminalProcess
        withLock session.lock:
          terminal = session.terminal
        terminal.writeControl(InputFrame, data)
        controlSuccess(%*{"sessionId": session.id, "bytes": data.len})
      of "resize":
        let session = findSession(parameters.requiredString("sessionId"))
        session.resizeSession(parameters{"cols"}.getInt(), parameters{"rows"}.getInt())
        controlSuccess(session.snapshotNode())
      of "diagnostics": controlSuccess(findSession(parameters.requiredString("sessionId")).diagnosticsNode())
      of "restart":
        let session = findSession(parameters.requiredString("sessionId"))
        session.restartSession()
        controlSuccess(session.statusNode())
      of "stop":
        let session = findSession(parameters.requiredString("sessionId"))
        session.stopSession()
        controlSuccess(session.statusNode())
      else: controlFailure("Unknown control method: " & operation)
    except CatchableError:
      controlFailure(getCurrentException().msg)

proc sendBootstrap(socket: WebSocket, session: ManagedSession) =
  let metadata = session.metadataNode()
  socket.safeSend(metadataJson(
    metadata["sessionId"].getStr(), metadata["name"].getStr(), metadata["mode"].getStr(), metadata["argv"],
    metadata["displayCommand"].getStr(), metadata["shell"].getStr(), metadata["restartable"].getBool(),
  ))
  var output: string
  var entries: seq[DiagnosticRecord]
  var state: string
  var pid, exitCode, cols, rows: int
  withLock session.lock:
    output = session.output
    entries = session.diagnostics
    state = session.status
    pid = session.pid
    exitCode = session.exitCode
    cols = session.cols
    rows = session.rows
  socket.safeSend(resizedJson(cols, rows))
  if output.len > 0: socket.safeSend(outputJson(output))
  socket.safeSend(logsJson(entries))
  case state
  of "running": socket.safeSend(runningJson(pid))
  of "exited": socket.safeSend(exitedJson(pid, exitCode))
  of "failed": socket.safeSend(failedJson("The session failed."))
  of "stopped": socket.safeSend(stoppedJson())
  else: socket.safeSend(startingJson())

proc parseClientMessage(payload: string, session: ManagedSession) =
  if payload.len > MaximumWebSocketMessageBytes: return
  let message = parseJson(payload)
  if message.kind != JObject or "type" notin message or message["type"].kind != JString: return
  case message["type"].getStr()
  of "input":
    if "data" in message and message["data"].kind == JString:
      var terminal: TerminalProcess
      withLock session.lock: terminal = session.terminal
      terminal.writeControl(InputFrame, message["data"].getStr())
  of "binary":
    if "data" in message and message["data"].kind == JString:
      try:
        let data = decode(message["data"].getStr())
        var terminal: TerminalProcess
        withLock session.lock: terminal = session.terminal
        terminal.writeControl(InputFrame, data)
      except ValueError: discard
  of "resize": session.resizeSession(message{"cols"}.getInt(), message{"rows"}.getInt())
  of "restart": session.restartSession()
  of "clearLogs":
    withLock session.lock: session.diagnostics.setLen(0)
    session.broadcast(logsClearedJson())
  else: discard

proc websocketHandler(socket: WebSocket, event: WebSocketEvent, message: Message) {.gcsafe.} =
  {.cast(gcsafe).}:
    var session: ManagedSession
    let mappingDeadline = epochTime() + 1.0
    while session.isNil:
      withLock application.lock:
        if socket in application.socketSessions: session = application.socketSessions[socket]
      if not session.isNil or event != OpenEvent or epochTime() >= mappingDeadline:
        break
      sleep(1)
    if session.isNil:
      socket.close()
      return
    case event
    of OpenEvent:
      withLock session.lock:
        if socket notin session.sockets: session.sockets.add(socket)
        session.lastDetachedAt = 0
      socket.sendBootstrap(session)
    of MessageEvent:
      if message.kind == TextMessage:
        try: parseClientMessage(message.data, session)
        except CatchableError: socket.safeSend(failedJson(getCurrentException().msg))
    of CloseEvent, ErrorEvent:
      withLock session.lock:
        let index = session.sockets.find(socket)
        if index >= 0: session.sockets.delete(index)
        if session.sockets.len == 0 and session.externalClients == 0: session.lastDetachedAt = epochTime()
      withLock application.lock: application.socketSessions.del(socket)

proc addDiagnostics(session: ManagedSession, records: openArray[DiagnosticRecord]) =
  withLock session.lock:
    for record in records: session.diagnostics.add(record)
    if session.diagnostics.len > application.options.diagnosticsLimit:
      let first = session.diagnostics.len - application.options.diagnosticsLimit
      session.diagnostics = session.diagnostics[first .. ^1]
  for record in records: session.broadcast(logJson(record))

proc sessionIdFromDiagnosticsPath(path: string): string =
  const prefix = "/api/sessions/"
  const suffix = "/diagnostics"
  if path.startsWith(prefix) and path.endsWith(suffix):
    result = path[prefix.len ..< path.len - suffix.len]

proc requestHandler(request: Request) {.gcsafe.} =
  {.cast(gcsafe).}:
    if request.path == "/terminal":
      if request.httpMethod != "GET" or request.headers["Origin"] != application.origin:
        request.respondText(403, "Forbidden")
        return
      try:
        let session = findSession(request.queryParams["session"])
        if not tokenMatches(request.queryParams["token"], session.token):
          request.respondText(403, "Forbidden")
          return
        let socket = request.upgradeToWebSocket()
        withLock application.lock: application.socketSessions[socket] = session
      except ValueError: request.respondText(404, "Session not found")
      except MummyError: request.respondText(400, "Invalid WebSocket upgrade")
      return

    if request.path == "/api/sessions":
      if request.httpMethod != "GET": request.respondText(405, "Method not allowed")
      elif not bearerMatches(request.headers["Authorization"], application.token): request.respondText(401, "Unauthorized")
      else: request.respond(200, defaultHeaders("application/json; charset=utf-8"), $sessionListNode(true))
      return

    let diagnosticSessionId = sessionIdFromDiagnosticsPath(request.path)
    if diagnosticSessionId.len > 0:
      if request.httpMethod != "POST":
        request.respondText(405, "Method not allowed")
        return
      try:
        let session = findSession(diagnosticSessionId)
        if not bearerMatches(request.headers["Authorization"], session.token):
          request.respondText(401, "Unauthorized")
          return
        if request.body.len > MaximumDiagnosticBodyBytes:
          request.respondText(413, "Diagnostic request is too large.")
          return
        let records = parseDiagnosticRequest(request.body, request.headers["Content-Type"], session.displayCommand)
        session.addDiagnostics(records)
        request.respond(202, defaultHeaders("text/plain; charset=utf-8"))
      except ValueError: request.respondText(404, "Session not found")
      except DiagnosticError, jsony.JsonError: request.respondText(400, getCurrentException().msg)
      return

    if request.httpMethod != "GET":
      request.respondText(404, "Not found")
      return
    case request.path
    of "/", "/index.html": request.respond(200, pageHeaders("text/html; charset=utf-8"), IndexHtml)
    of "/assets/app.js": request.respond(200, pageHeaders("text/javascript; charset=utf-8"), ApplicationJavaScript)
    of "/assets/app.css": request.respond(200, pageHeaders("text/css; charset=utf-8"), ApplicationCss)
    of "/ttyglass-logo.svg": request.respond(200, pageHeaders("image/svg+xml"), TtyglassLogo)
    else:
      if request.path.startsWith("/sessions/") and request.path.len > "/sessions/".len:
        request.respond(200, pageHeaders("text/html; charset=utf-8"), IndexHtml)
      else: request.respondText(404, "Not found")

proc mummyLog(level: mummy.LogLevel, arguments: varargs[string]) {.gcsafe.} =
  {.cast(gcsafe).}:
    let message = arguments.join("")
    case level
    of DebugLevel: debug "Mummy", detail = message
    of InfoLevel: info "Mummy", detail = message
    of ErrorLevel:
      if stopRequested.load(moRelaxed): debug "Mummy stopped", detail = message
      else: error "Mummy", detail = message

proc reservePort(): int =
  let socket = newSocket()
  defer: socket.close()
  socket.setSockOpt(OptReuseAddr, true)
  socket.bindAddr(Port(0), LoopbackAddress)
  result = socket.getLocalAddr()[1].int

proc serverLoop(port: int) {.thread, gcsafe.} =
  {.cast(gcsafe).}:
    try: application.server.serve(Port(port), LoopbackAddress)
    except MummyError as failure:
      withLock serverFailureLock: serverFailure = failure.msg
      serverFailed.store(true, moRelaxed)

proc waitForServer(port: int) =
  let deadline = epochTime() + 5.0
  while epochTime() < deadline:
    if serverFailed.load(moRelaxed):
      withLock serverFailureLock: raise newException(OSError, serverFailure)
    let socket = newSocket()
    try:
      socket.connect(LoopbackAddress, Port(port), 100)
      socket.close()
      return
    except CatchableError:
      socket.close()
      sleep(25)
  raise newException(OSError, "ttyglass did not become ready on its loopback port.")

proc requestStop() {.noconv.} =
  if not stopRequested.exchange(true, moRelaxed) and not application.isNil: application.server.close()

proc cleanupExpiredSessions() =
  let now = epochTime()
  let retention = retentionSeconds()
  var expired: seq[string]
  var sessions: seq[ManagedSession]
  withLock application.lock:
    for session in application.sessions.values: sessions.add(session)
  for session in sessions:
    withLock session.lock:
      let noClients = session.sockets.len == 0 and session.externalClients == 0
      if noClients and session.completedAt > 0 and now - session.completedAt >= retention: expired.add(session.id)
      elif noClients and session.completedAt == 0 and session.lastDetachedAt > 0 and now - session.lastDetachedAt >= retention: expired.add(session.id)
  for id in expired: removeSession(id)

proc runService*(options: ServiceOptions): int =
  if options.port < 0 or options.port > 65535: raise newException(ValueError, "--port must be an integer from 0 to 65535.")
  if options.diagnosticsLimit < 1 or options.diagnosticsLimit > 5000: raise newException(ValueError, "--diagnostics-limit must be an integer from 1 to 5000.")
  if options.outputLimit < 1024 or options.outputLimit > 64 * 1024 * 1024: raise newException(ValueError, "--output-limit must be between 1024 and 67108864 bytes.")

  var serviceLock = acquireServiceLock()
  defer: serviceLock.release()
  let port = if options.port == 0: reservePort() else: options.port
  application = ApplicationState(options: options, token: freshToken(), sessions: initTable[string, ManagedSession](), socketSessions: initTable[WebSocket, ManagedSession](), startedAt: epochTime())
  initLock(application.lock)
  initLock(serverFailureLock)
  application.origin = "http://" & LoopbackAddress & ":" & $port
  application.server = newServer(requestHandler, websocketHandler, mummyLog, maxBodyLen = MaximumDiagnosticBodyBytes, maxMessageLen = MaximumWebSocketMessageBytes)
  stopRequested.store(false, moRelaxed)
  serverFailed.store(false, moRelaxed)

  var thread: Thread[int]
  createThread(thread, serverLoop, port)
  try:
    waitForServer(port)
    application.control = startControlServer(handleControl)
    writeDescriptor(ServiceDescriptor(pid: getCurrentProcessId(), endpoint: application.control.endpoint, origin: application.origin, token: application.token))
    if options.foreground:
      stdout.writeLine("ttyglass service: " & application.origin & "/#token=" & application.token)
      stdout.writeLine("Press Ctrl+C to stop.")
      stdout.flushFile()
    setControlCHook(requestStop)
    while not stopRequested.load(moRelaxed) and not serverFailed.load(moRelaxed):
      cleanupExpiredSessions()
      if not options.foreground and epochTime() - application.startedAt > 2.0:
        withLock application.lock:
          if application.sessions.len == 0: requestStop()
      sleep(50)
    if serverFailed.load(moRelaxed):
      withLock serverFailureLock: raise newException(OSError, serverFailure)
  finally:
    removeDescriptor()
    application.control.stop()
    application.server.close()
    var ids: seq[string]
    withLock application.lock:
      for id in application.sessions.keys: ids.add(id)
    for id in ids: removeSession(id)
    joinThread(thread)
    deinitLock(application.lock)
    deinitLock(serverFailureLock)
