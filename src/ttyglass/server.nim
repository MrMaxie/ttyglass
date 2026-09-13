import chronicles
import jsony
import mummy
import std/[atomics, base64, json, net, os, osproc, streams, strtabs, strutils, sysrand, times]
import std/locks

import ./[assets, diagnostics, ipc, messages]

type
  RunOptions* = object
    command*: string
    arguments*: seq[string]
    cwd*: string
    port*: int
    diagnosticsLimit*: int
    openBrowser*: bool

  TerminalSession = ref object
    process: Process
    input: Stream
    output: Stream
    errors: Stream
    socket: WebSocket
    writeLock: Lock
    readerThread: Thread[TerminalSession]
    errorThread: Thread[TerminalSession]
    processId: int
    stopped: Atomic[bool]

  ApplicationState = ref object
    lock: Lock
    lifecycleLock: Lock
    options: RunOptions
    token: string
    origin: string
    diagnostics: seq[DiagnosticRecord]
    socket: WebSocket
    session: TerminalSession
    server: Server

const
  LoopbackAddress = "127.0.0.1"
  MaximumDiagnosticBodyBytes = 64 * 1024
  MaximumWebSocketMessageBytes = 64 * 1024

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

proc tokenMatches(header, expected: string): bool =
  const prefix = "Bearer "
  if not header.startsWith(prefix):
    return false
  let candidate = header[prefix.len .. ^1]
  if candidate.len != expected.len:
    return false
  var difference = 0
  for index in 0 ..< expected.len:
    difference = difference or (ord(candidate[index]) xor ord(expected[index]))
  difference == 0

proc freshToken(): string =
  let bytes = urandom(32)
  if bytes.len != 32:
    raise newException(OSError, "The operating system did not provide a session token.")
  result = newStringOfCap(64)
  for value in bytes:
    result.add(toHex(value, 2).toLowerAscii())

proc send(socket: WebSocket, payload: string) =
  socket.send(payload, TextMessage)

proc sendToActive(payload: string) =
  var socket: WebSocket
  withLock application.lock:
    socket = application.socket
  if socket != default(WebSocket):
    socket.send(payload)

proc writeControl(session: TerminalSession, kind: FrameKind, payload = "") =
  if session.isNil or session.stopped.load(moRelaxed):
    return
  withLock session.writeLock:
    try:
      session.input.writeFrame(kind, payload)
    except IOError:
      discard

proc hostErrorReader(session: TerminalSession) {.thread, gcsafe.} =
  {.cast(gcsafe).}:
    try:
      var buffer: array[4096, char]
      while true:
        let count = session.errors.readData(addr buffer[0], buffer.len)
        if count <= 0:
          break
        stderr.write(buffer[0 ..< count])
        stderr.flushFile()
    except IOError:
      discard

proc hostFrameReader(session: TerminalSession) {.thread, gcsafe.} =
  {.cast(gcsafe).}:
    try:
      while true:
        let frame = session.output.readFrame()
        case frame.kind
        of StartedFrame:
          let started = frame.payload.parseStarted()
          session.processId = started.pid
          session.socket.send(runningJson(started.pid))
        of OutputFrame:
          session.socket.send(outputJson(frame.payload))
        of ExitedFrame:
          let exited = frame.payload.parseExited()
          session.socket.send(exitedJson(exited.pid, exited.exitCode))
          break
        of ErrorFrame:
          session.socket.send(failedJson(frame.payload))
          break
        else:
          discard
    except IOError, ValueError:
      if not session.stopped.load(moRelaxed):
        let error = getCurrentException()
        session.socket.send(failedJson("The native PTY host disconnected unexpectedly: " & error.msg))

proc childEnvironment(): StringTableRef =
  result = newStringTable(modeCaseInsensitive)
  for key, value in envPairs():
    result[key] = value
  result["TERM"] = "xterm-256color"
  result["COLORTERM"] = "truecolor"
  result["TTYGLASS_DIAGNOSTICS_URL"] = application.origin & "/api/diagnostics"
  result["TTYGLASS_DIAGNOSTICS_TOKEN"] = application.token
  result.del("NO_COLOR")

proc startTerminal(socket: WebSocket, cols = 100, rows = 30): TerminalSession =
  let host = startProcess(
    getAppFilename(),
    args = ["--internal-pty-host"],
    env = childEnvironment(),
    options = {poUsePath, poDaemon},
  )
  result = TerminalSession(
    process: host,
    input: host.inputStream(),
    output: host.outputStream(),
    errors: host.errorStream(),
    socket: socket,
  )
  result.stopped.store(false, moRelaxed)
  initLock(result.writeLock)
  result.writeControl(
    StartFrame,
    StartControl(
      command: application.options.command,
      arguments: application.options.arguments,
      cwd: application.options.cwd,
      cols: cols,
      rows: rows,
    ).startPayload(),
  )
  createThread(result.readerThread, hostFrameReader, result)
  createThread(result.errorThread, hostErrorReader, result)

proc stopTerminal(session: TerminalSession) =
  if session.isNil or session.stopped.exchange(true, moRelaxed):
    return
  withLock session.writeLock:
    try:
      session.input.writeFrame(StopFrame)
      session.input.close()
    except IOError:
      discard
  discard session.process.waitForExit(3000)
  joinThread(session.readerThread)
  joinThread(session.errorThread)
  try:
    session.process.close()
  except IOError, OSError:
    discard
  deinitLock(session.writeLock)

proc replaceTerminal(socket: WebSocket, cols = 100, rows = 30) =
  withLock application.lifecycleLock:
    var previous: TerminalSession
    withLock application.lock:
      previous = application.session
      application.session = nil
    stopTerminal(previous)
    let next = startTerminal(socket, cols, rows)
    withLock application.lock:
      application.session = next

proc closeTerminal(socket: WebSocket) =
  withLock application.lifecycleLock:
    var session: TerminalSession
    withLock application.lock:
      if application.socket != socket:
        return
      session = application.session
      application.session = nil
      application.socket = default(WebSocket)
    stopTerminal(session)

proc parseClientMessage(payload: string, socket: WebSocket) =
  if payload.len > MaximumWebSocketMessageBytes:
    return
  let message = payload.fromJson()
  if message.kind != JObject or "type" notin message or message["type"].kind != JString:
    return
  let kind = message["type"].getStr()
  var session: TerminalSession
  withLock application.lock:
    session = application.session

  case kind
  of "input":
    if "data" in message and message["data"].kind == JString:
      session.writeControl(InputFrame, message["data"].getStr())
  of "binary":
    if "data" in message and message["data"].kind == JString:
      try:
        session.writeControl(InputFrame, decode(message["data"].getStr()))
      except ValueError:
        discard
  of "resize":
    if "cols" in message and "rows" in message:
      let cols = message["cols"].getInt()
      let rows = message["rows"].getInt()
      if cols >= 2 and cols <= 1000 and rows >= 1 and rows <= 500:
        session.writeControl(ResizeFrame, ResizeControl(cols: cols, rows: rows).resizePayload())
  of "restart":
    let cols = if "cols" in message: message["cols"].getInt() else: 100
    let rows = if "rows" in message: message["rows"].getInt() else: 30
    replaceTerminal(socket, cols, rows)
  of "clearLogs":
    withLock application.lock:
      application.diagnostics.setLen(0)
    socket.send(logsClearedJson())
  else:
    discard

proc websocketHandler(
  socket: WebSocket,
  event: WebSocketEvent,
  message: Message,
) {.gcsafe.} =
  {.cast(gcsafe).}:
    case event
    of OpenEvent:
      var accepted = false
      var entries: seq[DiagnosticRecord]
      withLock application.lock:
        if application.socket == default(WebSocket):
          application.socket = socket
          entries = application.diagnostics
          accepted = true
      if not accepted:
        socket.close()
        return
      socket.send(metadataJson(application.options.command.extractFilename()))
      socket.send(logsJson(entries))
      try:
        replaceTerminal(socket)
      except CatchableError as error:
        error "Could not start PTY host", reason = error.msg
        socket.send(failedJson(error.msg))
    of MessageEvent:
      if message.kind == TextMessage:
        try:
          parseClientMessage(message.data, socket)
        except ValueError, jsony.JsonError:
          discard
    of CloseEvent, ErrorEvent:
      closeTerminal(socket)

proc addDiagnostics(records: openArray[DiagnosticRecord]) =
  var socket: WebSocket
  withLock application.lock:
    for record in records:
      application.diagnostics.add(record)
    if application.diagnostics.len > application.options.diagnosticsLimit:
      let first = application.diagnostics.len - application.options.diagnosticsLimit
      application.diagnostics = application.diagnostics[first .. ^1]
    socket = application.socket
  if socket != default(WebSocket):
    for record in records:
      socket.send(logJson(record))

proc requestHandler(request: Request) {.gcsafe.} =
  {.cast(gcsafe).}:
    if request.path == "/terminal":
      if request.httpMethod != "GET" or
          request.queryParams["token"] != application.token or
          request.headers["Origin"] != application.origin:
        request.respondText(403, "Forbidden")
        return
      try:
        discard request.upgradeToWebSocket()
      except MummyError:
        request.respondText(400, "Invalid WebSocket upgrade")
      return

    if request.path == "/api/diagnostics":
      if request.httpMethod != "POST":
        request.respondText(405, "Method not allowed")
        return
      if not tokenMatches(request.headers["Authorization"], application.token):
        request.respondText(401, "Unauthorized")
        return
      if request.body.len > MaximumDiagnosticBodyBytes:
        request.respondText(413, "Diagnostic request is too large.")
        return
      try:
        let records = parseDiagnosticRequest(
          request.body,
          request.headers["Content-Type"],
          application.options.command.extractFilename(),
        )
        addDiagnostics(records)
        request.respond(202, defaultHeaders("text/plain; charset=utf-8"))
      except DiagnosticError, jsony.JsonError, ValueError:
        let error = getCurrentException()
        request.respondText(400, error.msg)
      return

    if request.httpMethod != "GET":
      request.respondText(404, "Not found")
      return
    case request.path
    of "/", "/index.html":
      request.respond(200, pageHeaders("text/html; charset=utf-8"), IndexHtml)
    of "/assets/app.js":
      request.respond(200, pageHeaders("text/javascript; charset=utf-8"), ApplicationJavaScript)
    of "/assets/app.css":
      request.respond(200, pageHeaders("text/css; charset=utf-8"), ApplicationCss)
    of "/ttyglass-logo.svg":
      request.respond(200, pageHeaders("image/svg+xml"), TtyglassLogo)
    else:
      request.respondText(404, "Not found")

proc mummyLog(level: mummy.LogLevel, arguments: varargs[string]) {.gcsafe.} =
  {.cast(gcsafe).}:
    let message = arguments.join("")
    case level
    of DebugLevel:
      debug "Mummy", detail = message
    of InfoLevel:
      info "Mummy", detail = message
    of ErrorLevel:
      if stopRequested.load(moRelaxed):
        debug "Mummy stopped", detail = message
      else:
        error "Mummy", detail = message

proc reservePort(): int =
  let socket = newSocket()
  defer: socket.close()
  socket.setSockOpt(OptReuseAddr, true)
  socket.bindAddr(Port(0), LoopbackAddress)
  result = socket.getLocalAddr()[1].int

proc serverLoop(port: int) {.thread, gcsafe.} =
  {.cast(gcsafe).}:
    try:
      application.server.serve(Port(port), LoopbackAddress)
    except MummyError as error:
      withLock serverFailureLock:
        serverFailure = error.msg
      serverFailed.store(true, moRelaxed)

proc waitForServer(port: int) =
  let deadline = epochTime() + 5.0
  while epochTime() < deadline:
    if serverFailed.load(moRelaxed):
      withLock serverFailureLock:
        raise newException(OSError, serverFailure)
    let socket = newSocket()
    try:
      socket.connect(LoopbackAddress, Port(port), 100)
      socket.close()
      return
    except CatchableError:
      socket.close()
      sleep(25)
  raise newException(OSError, "ttyglass did not become ready on its loopback port.")

proc openInBrowser(url: string) =
  let command =
    when defined(windows): "rundll32.exe"
    elif defined(macosx): "open"
    else: "xdg-open"
  let arguments =
    when defined(windows): @["url.dll,FileProtocolHandler", url]
    else: @[url]
  try:
    let process = startProcess(
      command,
      args = arguments,
      options = {poUsePath, poParentStreams, poDaemon},
    )
    discard process.waitForExit(5000)
    process.close()
  except OSError, IOError:
    let error = getCurrentException()
    warn "Could not open browser", reason = error.msg

proc requestStop() {.noconv.} =
  if not stopRequested.exchange(true, moRelaxed) and not application.isNil:
    application.server.close()

proc runServer*(options: RunOptions): int =
  if options.port < 0 or options.port > 65535:
    raise newException(ValueError, "--port must be an integer from 0 to 65535.")
  if options.diagnosticsLimit < 1 or options.diagnosticsLimit > 5000:
    raise newException(ValueError, "--diagnostics-limit must be an integer from 1 to 5000.")
  if not dirExists(options.cwd):
    raise newException(ValueError, "Working directory does not exist: " & options.cwd)

  let port = if options.port == 0: reservePort() else: options.port
  application = ApplicationState(options: options, token: freshToken())
  initLock(application.lock)
  initLock(application.lifecycleLock)
  initLock(serverFailureLock)
  application.origin = "http://" & LoopbackAddress & ":" & $port
  application.server = newServer(
    requestHandler,
    websocketHandler,
    mummyLog,
    maxBodyLen = MaximumDiagnosticBodyBytes,
    maxMessageLen = MaximumWebSocketMessageBytes,
  )
  stopRequested.store(false, moRelaxed)
  serverFailed.store(false, moRelaxed)

  var thread: Thread[int]
  createThread(thread, serverLoop, port)
  try:
    waitForServer(port)
    let url = application.origin & "/#token=" & application.token
    stdout.writeLine("ttyglass: " & url)
    stdout.writeLine("command: " & options.command)
    stdout.writeLine("Press Ctrl+C to stop.")
    stdout.flushFile()
    if options.openBrowser:
      openInBrowser(url)
    setControlCHook(requestStop)
    while not stopRequested.load(moRelaxed) and not serverFailed.load(moRelaxed):
      sleep(50)
    if serverFailed.load(moRelaxed):
      withLock serverFailureLock:
        raise newException(OSError, serverFailure)
  finally:
    application.server.close()
    var session: TerminalSession
    withLock application.lock:
      session = application.session
      application.session = nil
    stopTerminal(session)
    joinThread(thread)
    deinitLock(application.lifecycleLock)
    deinitLock(application.lock)
    deinitLock(serverFailureLock)
