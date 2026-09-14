import std/[atomics, base64, json, os, osproc, sequtils, sets, strutils, times]

import ./control_plane

when defined(windows):
  import std/[widestrs, winlean]

type
  CommonOptions* = object
    cwd*: string
    port*: int
    diagnosticsLimit*: int
    outputLimit*: int
    shell*: string
    openBrowser*: bool

var foregroundInterrupted: Atomic[bool]

proc interruptForeground() {.noconv.} = foregroundInterrupted.store(true, moRelaxed)

proc request(descriptor: ServiceDescriptor, operation: string, parameters = newJObject()): JsonNode =
  let payload = $(%*{"token": descriptor.token, "method": operation, "params": parameters})
  let response = parseJson(controlCall(descriptor, payload))
  if response.kind != JObject or not response{"ok"}.getBool():
    raise newException(IOError, response{"error"}.getStr("Invalid response from the ttyglass service."))
  response["result"]

proc liveDescriptor(): ServiceDescriptor =
  result = readDescriptor()
  discard result.request("ping")

when defined(windows):
  const DetachedProcess = 0x00000008'i32

  proc quoteWindowsArgument(value: string): string =
    if value.len > 0 and value.allCharsInSet({char(33)..char(126)} - {' ', '\t', '"'}): return value
    result = "\""
    var backslashes = 0
    for character in value:
      if character == '\\':
        inc backslashes
      elif character == '"':
        result.add('\\'.repeat(backslashes * 2 + 1))
        result.add(character)
        backslashes = 0
      else:
        result.add('\\'.repeat(backslashes))
        result.add(character)
        backslashes = 0
    result.add('\\'.repeat(backslashes * 2))
    result.add('"')

  proc spawnService(options: CommonOptions) =
    let arguments = @[
      getAppFilename(), "--internal-service", "--port", $options.port,
      "--diagnostics-limit", $options.diagnosticsLimit, "--output-limit", $options.outputLimit,
    ]
    var commandLine = arguments.mapIt(quoteWindowsArgument(it)).join(" ")
    var startup: STARTUPINFO
    var processInformation: PROCESS_INFORMATION
    startup.cb = sizeof(startup).int32
    let mutableCommandLine = newWideCString(commandLine)
    if winlean.createProcessW(
      nil, mutableCommandLine, nil, nil, 0,
      CREATE_NO_WINDOW or DetachedProcess,
      nil, nil, startup, processInformation,
    ) == 0:
      raise newException(OSError, "Could not start the ttyglass service.")
    discard closeHandle(processInformation.hThread)
    discard closeHandle(processInformation.hProcess)

else:
  import std/strtabs

  proc serviceEnvironment(options: CommonOptions): StringTableRef =
    result = newStringTable(modeCaseInsensitive)
    for key, value in envPairs(): result[key] = value
    result["TTYGLASS_SERVICE_PORT"] = $options.port
    result["TTYGLASS_DIAGNOSTICS_LIMIT"] = $options.diagnosticsLimit
    result["TTYGLASS_OUTPUT_LIMIT"] = $options.outputLimit

  proc spawnService(options: CommonOptions) =
    let service = startProcess(
      getAppFilename(),
      args = ["--internal-service"],
      env = serviceEnvironment(options),
      options = {poUsePath, poDaemon},
    )
    try: service.close()
    except IOError, OSError: discard

proc ensureService*(options: CommonOptions): ServiceDescriptor =
  try:
    return liveDescriptor()
  except CatchableError:
    removeDescriptor()

  let deadline = epochTime() + 8.0
  var lastError = ""
  var nextSpawnAt = 0.0
  while epochTime() < deadline:
    try:
      return liveDescriptor()
    except CatchableError:
      lastError = getCurrentException().msg
      removeDescriptor()
    let now = epochTime()
    if now >= nextSpawnAt:
      spawnService(options)
      nextSpawnAt = now + 0.25
    sleep(25)
  raise newException(IOError, "ttyglass service did not become ready: " & lastError)

proc resolveShell*(requested = ""): string =
  if requested.len > 0:
    let resolved = findExe(requested)
    return if resolved.len > 0: resolved else: requested
  let environmentShell = getEnv("SHELL")
  if environmentShell.len > 0:
    let resolved = findExe(environmentShell)
    return if resolved.len > 0: resolved else: environmentShell
  when defined(windows):
    for candidate in ["pwsh", "powershell.exe"]:
      let resolved = findExe(candidate)
      if resolved.len > 0: return resolved
    let commandProcessor = getEnv("ComSpec")
    if commandProcessor.len > 0: return commandProcessor
    raise newException(IOError, "Could not resolve a user shell. Use --shell <executable>.")
  else:
    "/bin/sh"

proc openInBrowser*(url: string) =
  let command =
    when defined(windows): "rundll32.exe"
    elif defined(macosx): "open"
    else: "xdg-open"
  let arguments =
    when defined(windows): @["url.dll,FileProtocolHandler", url]
    else: @[url]
  try:
    let process = startProcess(command, args = arguments, options = {poUsePath, poParentStreams, poDaemon})
    discard process.waitForExit(5000)
    process.close()
  except OSError, IOError:
    stderr.writeLine("ttyglass: could not open the browser: " & getCurrentException().msg)

proc sessionParameters(options: CommonOptions, command: seq[string], name = ""): JsonNode =
  let terminalMode = command.len == 0
  result = %*{
    "mode": if terminalMode: "terminal" else: "command",
    "name": name,
    "argv": command,
    "shell": if terminalMode: resolveShell(options.shell) else: "",
    "cwd": if options.cwd.len == 0: getCurrentDir() else: absolutePath(options.cwd),
    "cols": 100,
    "rows": 30,
  }

proc startSession*(options: CommonOptions, command: seq[string], name = ""): tuple[descriptor: ServiceDescriptor, session: JsonNode] =
  let parameters = sessionParameters(options, command, name)
  result.descriptor = ensureService(options)
  try:
    result.session = result.descriptor.request("start", parameters)
  except IOError, OSError:
    removeDescriptor()
    result.descriptor = ensureService(options)
    result.session = result.descriptor.request("start", parameters)

proc printStarted(session: JsonNode, asJson = false) =
  if asJson:
    stdout.writeLine($session)
  else:
    stdout.writeLine("session: " & session{"sessionId"}.getStr())
    if session{"name"}.getStr().len > 0: stdout.writeLine("name: " & session{"name"}.getStr())
    stdout.writeLine("ttyglass: " & session{"url"}.getStr())
    stdout.writeLine("command: " & session{"displayCommand"}.getStr())
  stdout.flushFile()

proc runForeground*(options: CommonOptions, command: seq[string], name = ""): int =
  let started = startSession(options, command, name)
  let sessionId = started.session{"sessionId"}.getStr()
  discard started.descriptor.request("attach", %*{"sessionId": sessionId})
  printStarted(started.session)
  stdout.writeLine("Press Ctrl+C to stop.")
  stdout.flushFile()
  if options.openBrowser: openInBrowser(started.session{"url"}.getStr())
  foregroundInterrupted.store(false, moRelaxed)
  setControlCHook(interruptForeground)
  try:
    while not foregroundInterrupted.load(moRelaxed):
      let status = started.descriptor.request("status", %*{"sessionId": sessionId})
      if status{"state"}.getStr() in ["exited", "failed", "stopped"]:
        return status{"exitCode"}.getInt()
      sleep(100)
    discard started.descriptor.request("stop", %*{"sessionId": sessionId})
    result = 130
  finally:
    try: discard started.descriptor.request("detach", %*{"sessionId": sessionId})
    except CatchableError: discard

proc runStart*(options: CommonOptions, command: seq[string], name = "", asJson = false): int =
  let started = startSession(options, command, name)
  printStarted(started.session, asJson)
  if options.openBrowser: openInBrowser(started.session{"url"}.getStr())

proc sessions*(options: CommonOptions, asJson = false): int =
  let value = ensureService(options).request("list")
  if asJson:
    stdout.writeLine($value)
  elif value.len == 0:
    stdout.writeLine("No sessions.")
  else:
    for session in value:
      let label = if session{"name"}.getStr().len > 0: session{"name"}.getStr() else: session{"displayCommand"}.getStr()
      stdout.writeLine(
        session{"sessionId"}.getStr() & "\t" & session{"status"}.getStr() & "\t" &
          label,
      )

proc oneSession*(options: CommonOptions, operation, sessionId: string, asJson = false, offset = 0'i64): int =
  let descriptor = ensureService(options)
  var parameters = %*{"sessionId": sessionId}
  if operation == "output": parameters["from"] = %offset
  let value = descriptor.request(operation, parameters)
  if asJson:
    stdout.writeLine($value)
  elif operation == "screen":
    for line in value{"lines"}: stdout.writeLine(line.getStr())
  elif operation == "output":
    stdout.write(decode(value{"data"}.getStr()))
    stdout.flushFile()
  elif operation == "diagnostics":
    for entry in value{"entries"}: stdout.writeLine($entry)
  else:
    stdout.writeLine($value)

proc sendInput*(options: CommonOptions, sessionId, data: string): int =
  discard ensureService(options).request("input", %*{"sessionId": sessionId, "data": encode(data)})

proc resize*(options: CommonOptions, sessionId: string, cols, rows: int): int =
  discard ensureService(options).request("resize", %*{"sessionId": sessionId, "cols": cols, "rows": rows})

proc openSession*(options: CommonOptions, sessionId = ""): int =
  let descriptor = ensureService(options)
  let url =
    if sessionId.len == 0:
      descriptor.origin & "/#token=" & descriptor.token
    else:
      descriptor.request("open", %*{"sessionId": sessionId}){"url"}.getStr()
  openInBrowser(url)

proc rpcOperation(name: string): string =
  case name
  of "list_sessions": "list"
  of "start_session": "start"
  of "attach_session": "attach"
  of "detach_session": "detach"
  of "get_status": "status"
  of "read_screen": "screen"
  of "read_output": "output"
  of "send_input": "input"
  of "resize_terminal": "resize"
  of "read_diagnostics": "diagnostics"
  of "restart_session": "restart"
  of "stop_session": "stop"
  else: name

proc normalizedParameters(name: string, value: JsonNode, options: CommonOptions): JsonNode =
  result = if value.kind == JObject: value.copy() else: newJObject()
  if name == "start_session":
    let mode = result{"mode"}.getStr("command")
    if "argv" notin result:
      result["argv"] = newJArray()
      if "command" in result and result["command"].kind == JString:
        result["argv"].add(result["command"])
        if "arguments" in result and result["arguments"].kind == JArray:
          for argument in result["arguments"]: result["argv"].add(argument)
    result["mode"] = %mode
    if mode == "terminal" and result{"shell"}.getStr().len == 0:
      result["shell"] = %resolveShell(options.shell)
    if result{"cwd"}.getStr().len == 0: result["cwd"] = %getCurrentDir()
    if "cols" notin result: result["cols"] = %100
    if "rows" notin result: result["rows"] = %30
  elif name == "send_input":
    if "data" in result and result["data"].kind == JString:
      result["data"] = %encode(result["data"].getStr())
    elif "text" in result and result["text"].kind == JString:
      result["data"] = %encode(result["text"].getStr())

proc jsonRpcError(id: JsonNode, code: int, message: string): JsonNode =
  %*{"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": message}}

proc jsonRpcResult(id, value: JsonNode): JsonNode =
  %*{"jsonrpc": "2.0", "id": id, "result": value}

proc handleAgentRequest(descriptor: ServiceDescriptor, requestValue: JsonNode, options: CommonOptions): JsonNode =
  let id = if "id" in requestValue: requestValue["id"] else: newJNull()
  try:
    if requestValue{"jsonrpc"}.getStr() != "2.0" or requestValue{"method"}.kind != JString:
      return jsonRpcError(id, -32600, "Invalid Request")
    let name = requestValue["method"].getStr()
    let parameters = normalizedParameters(name, requestValue{"params"}, options)
    jsonRpcResult(id, descriptor.request(rpcOperation(name), parameters))
  except CatchableError:
    jsonRpcError(id, -32000, getCurrentException().msg)

proc runAgent*(options: CommonOptions): int =
  let descriptor = ensureService(options)
  var attached = initHashSet[string]()
  try:
    for line in stdin.lines:
      if line.strip().len == 0: continue
      var response: JsonNode
      try:
        let requestValue = parseJson(line)
        response = handleAgentRequest(descriptor, requestValue, options)
        let methodName = requestValue{"method"}.getStr()
        let sessionId = requestValue{"params"}{"sessionId"}.getStr()
        if methodName == "attach_session" and "error" notin response: attached.incl(sessionId)
        elif methodName == "detach_session": attached.excl(sessionId)
      except CatchableError:
        response = jsonRpcError(newJNull(), -32700, "Parse error")
      stdout.writeLine($response)
      stdout.flushFile()
  finally:
    for sessionId in attached:
      try: discard descriptor.request("detach", %*{"sessionId": sessionId})
      except CatchableError: discard

const McpProtocolVersion = "2025-11-25"

proc toolDefinition(name, description: string, properties: JsonNode, required: seq[string] = @[]): JsonNode =
  %*{
    "name": name,
    "description": description,
    "inputSchema": {"type": "object", "properties": properties, "required": required, "additionalProperties": false},
  }

proc mcpTools(): JsonNode =
  let sessionId = %*{"sessionId": {"type": "string"}}
  result = %*[
    toolDefinition("list_sessions", "List ttyglass sessions.", newJObject()),
    toolDefinition("start_session", "Start a command or terminal session.", %*{
      "mode": {"type": "string", "enum": ["command", "terminal"]},
      "name": {"type": "string"},
      "command": {"type": "string"}, "arguments": {"type": "array", "items": {"type": "string"}},
      "shell": {"type": "string"}, "cwd": {"type": "string"},
      "cols": {"type": "integer"}, "rows": {"type": "integer"}
    }),
    toolDefinition("attach_session", "Retain and attach to a session.", sessionId, @["sessionId"]),
    toolDefinition("detach_session", "Detach from a retained session.", sessionId, @["sessionId"]),
    toolDefinition("get_status", "Read session process status.", sessionId, @["sessionId"]),
    toolDefinition("read_screen", "Read the current terminal screen snapshot.", sessionId, @["sessionId"]),
    toolDefinition("read_output", "Read raw ANSI output as Base64.", %*{"sessionId": {"type": "string"}, "from": {"type": "integer"}}, @["sessionId"]),
    toolDefinition("send_input", "Send text input to a session.", %*{"sessionId": {"type": "string"}, "text": {"type": "string"}}, @["sessionId", "text"]),
    toolDefinition("resize_terminal", "Resize a session terminal.", %*{"sessionId": {"type": "string"}, "cols": {"type": "integer"}, "rows": {"type": "integer"}}, @["sessionId", "cols", "rows"]),
    toolDefinition("read_diagnostics", "Read session diagnostics.", sessionId, @["sessionId"]),
    toolDefinition("restart_session", "Restart a command session.", sessionId, @["sessionId"]),
    toolDefinition("stop_session", "Stop a session process tree.", sessionId, @["sessionId"]),
  ]

proc mcpResponse(descriptor: ServiceDescriptor, requestValue: JsonNode, options: CommonOptions): JsonNode =
  let id = if "id" in requestValue: requestValue["id"] else: newJNull()
  let methodName = requestValue{"method"}.getStr()
  try:
    case methodName
    of "initialize":
      jsonRpcResult(id, %*{
        "protocolVersion": McpProtocolVersion,
        "capabilities": {"tools": {"listChanged": false}},
        "serverInfo": {"name": "ttyglass", "version": "1.1.0"},
      })
    of "ping": jsonRpcResult(id, newJObject())
    of "tools/list": jsonRpcResult(id, %*{"tools": mcpTools()})
    of "tools/call":
      let name = requestValue{"params"}{"name"}.getStr()
      let parameters = normalizedParameters(name, requestValue{"params"}{"arguments"}, options)
      let value = descriptor.request(rpcOperation(name), parameters)
      jsonRpcResult(id, %*{"content": [{"type": "text", "text": $value}]})
    else: jsonRpcError(id, -32601, "Method not found")
  except CatchableError:
    jsonRpcResult(id, %*{"content": [{"type": "text", "text": getCurrentException().msg}], "isError": true})

proc runMcp*(options: CommonOptions): int =
  let descriptor = ensureService(options)
  for line in stdin.lines:
    if line.strip().len == 0: continue
    var response: JsonNode
    try:
      let requestValue = parseJson(line)
      if requestValue{"method"}.getStr() == "notifications/initialized": continue
      response = mcpResponse(descriptor, requestValue, options)
    except CatchableError:
      response = jsonRpcError(newJNull(), -32700, "Parse error")
    stdout.writeLine($response)
    stdout.flushFile()
