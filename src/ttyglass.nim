import std/[base64, os, strutils]

import ttyglass/[client, pty_host, server]

const TtyglassVersion* = "1.1.0"

const HelpText = """ttyglass 1.1.0

Usage:
  ttyglass [options] [-- <command> [arguments...]]
  ttyglass serve [options]
  ttyglass start [options] [-- <command> [arguments...]]
  ttyglass sessions [--json]
  ttyglass status <session-id> [--json]
  ttyglass screen <session-id> [--json]
  ttyglass output <session-id> [--from <offset>] [--json]
  ttyglass input <session-id> (--text <value> | --base64 <value> | --stdin)
  ttyglass resize <session-id> --cols <count> --rows <count>
  ttyglass diagnostics <session-id> [--json]
  ttyglass restart <session-id>
  ttyglass stop <session-id>
  ttyglass open [session-id]
  ttyglass agent
  ttyglass mcp

Options:
  --cwd <path>                 Run the session from this directory
  --name <name>                Name the new session
  --port <number>              Use a fixed loopback port when starting the service
  --diagnostics-limit <count>  Keep 1-5000 application diagnostic entries
  --output-limit <bytes>       Keep raw ANSI output bytes (default: 1048576)
  --shell <executable>         Select the terminal-mode shell
  --open                       Open the browser after creating a session
  --no-open                    Do not open the browser (default)
  -h, --help                   Show command help
  --version                    Show version
"""

proc defaultOptions(): CommonOptions =
  CommonOptions(diagnosticsLimit: 500, outputLimit: 1024 * 1024)

proc valueAfter(arguments: seq[string], index: var int, option: string): string =
  inc index
  if index >= arguments.len:
    raise newException(ValueError, option & " requires a value.")
  arguments[index]

proc parseNumber(value, option: string): int =
  try: parseInt(value)
  except ValueError: raise newException(ValueError, option & " requires an integer.")

proc parseCommon(arguments: seq[string], index: var int, options: var CommonOptions): bool =
  case arguments[index]
  of "--cwd": options.cwd = arguments.valueAfter(index, "--cwd")
  of "--port": options.port = parseNumber(arguments.valueAfter(index, "--port"), "--port")
  of "--diagnostics-limit":
    options.diagnosticsLimit = parseNumber(arguments.valueAfter(index, "--diagnostics-limit"), "--diagnostics-limit")
  of "--output-limit":
    options.outputLimit = parseNumber(arguments.valueAfter(index, "--output-limit"), "--output-limit")
  of "--shell": options.shell = arguments.valueAfter(index, "--shell")
  of "--open": options.openBrowser = true
  of "--no-open": options.openBrowser = false
  else: return false
  true

proc parseSessionCreation(arguments: seq[string], startIndex: int): tuple[options: CommonOptions, command: seq[string], name: string] =
  result.options = defaultOptions()
  var index = startIndex
  while index < arguments.len:
    if arguments[index] == "--":
      if index + 1 >= arguments.len:
        raise newException(ValueError, "No command follows --. Remove the separator to start a terminal session.")
      result.command = arguments[index + 1 .. ^1]
      return
    if arguments[index] == "--json":
      inc index
      continue
    if arguments[index] == "--name":
      result.name = arguments.valueAfter(index, "--name").strip()
      if result.name.len == 0: raise newException(ValueError, "--name requires a non-empty value.")
      inc index
      continue
    if not parseCommon(arguments, index, result.options):
      raise newException(ValueError, "Separate ttyglass options from the command with --.")
    inc index

proc hasFlag(arguments: seq[string], flag: string): bool = flag in arguments

proc requireSessionId(arguments: seq[string], index = 1): string =
  if arguments.len <= index or arguments[index].startsWith("--"):
    raise newException(ValueError, "A session id is required.")
  arguments[index]

proc parseInternalInt(name: string, fallback: int): int =
  try: parseInt(getEnv(name, $fallback))
  except ValueError: fallback

proc reopen(filename, mode: cstring, stream: File): File
  {.importc: "freopen", header: "<stdio.h>".}

proc detachServiceStreams() =
  when defined(windows):
    const NullDevice = "NUL"
  else:
    const NullDevice = "/dev/null"
  discard reopen(NullDevice, "r", stdin)
  discard reopen(NullDevice, "w", stdout)
  discard reopen(NullDevice, "w", stderr)

proc main(arguments: seq[string]): int =
  if arguments == @["--internal-pty-host"]: return runPtyHost()
  if arguments.len >= 1 and arguments[0] == "--internal-service":
    detachServiceStreams()
    var port = parseInternalInt("TTYGLASS_SERVICE_PORT", 0)
    var diagnosticsLimit = parseInternalInt("TTYGLASS_DIAGNOSTICS_LIMIT", 500)
    var outputLimit = parseInternalInt("TTYGLASS_OUTPUT_LIMIT", 1024 * 1024)
    var index = 1
    while index + 1 < arguments.len:
      case arguments[index]
      of "--port": port = parseNumber(arguments[index + 1], "--port")
      of "--diagnostics-limit": diagnosticsLimit = parseNumber(arguments[index + 1], "--diagnostics-limit")
      of "--output-limit": outputLimit = parseNumber(arguments[index + 1], "--output-limit")
      else: discard
      index += 2
    return runService(ServiceOptions(
      port: port,
      diagnosticsLimit: diagnosticsLimit,
      outputLimit: outputLimit,
      foreground: false,
    ))
  if arguments.len == 1 and arguments[0] == "--version":
    stdout.writeLine(TtyglassVersion)
    return 0
  if arguments.len == 1 and arguments[0] in ["--help", "-h"]:
    stdout.write(HelpText)
    return 0

  if arguments.len == 0 or arguments[0].startsWith("-"):
    let parsed = parseSessionCreation(arguments, 0)
    return runForeground(parsed.options, parsed.command, parsed.name)

  case arguments[0]
  of "serve":
    var options = defaultOptions()
    var index = 1
    while index < arguments.len:
      if not parseCommon(arguments, index, options):
        raise newException(ValueError, "Unknown serve option: " & arguments[index])
      inc index
    runService(ServiceOptions(port: options.port, diagnosticsLimit: options.diagnosticsLimit, outputLimit: options.outputLimit, foreground: true))
  of "start":
    let parsed = parseSessionCreation(arguments, 1)
    runStart(parsed.options, parsed.command, parsed.name, arguments.hasFlag("--json"))
  of "sessions": sessions(defaultOptions(), arguments.hasFlag("--json"))
  of "status", "screen", "diagnostics", "restart", "stop":
    let sessionId = requireSessionId(arguments)
    oneSession(defaultOptions(), arguments[0], sessionId, arguments.hasFlag("--json"))
  of "output":
    let sessionId = requireSessionId(arguments)
    var offset = 0'i64
    let offsetIndex = arguments.find("--from")
    if offsetIndex >= 0:
      if offsetIndex + 1 >= arguments.len: raise newException(ValueError, "--from requires an offset.")
      offset = parseNumber(arguments[offsetIndex + 1], "--from").int64
    oneSession(defaultOptions(), "output", sessionId, arguments.hasFlag("--json"), offset)
  of "input":
    let sessionId = requireSessionId(arguments)
    var data = ""
    let textIndex = arguments.find("--text")
    let base64Index = arguments.find("--base64")
    if textIndex >= 0:
      if textIndex + 1 >= arguments.len: raise newException(ValueError, "--text requires a value.")
      data = arguments[textIndex + 1]
    elif base64Index >= 0:
      if base64Index + 1 >= arguments.len: raise newException(ValueError, "--base64 requires a value.")
      data = base64.decode(arguments[base64Index + 1])
    elif "--stdin" in arguments:
      data = stdin.readAll()
    else:
      raise newException(ValueError, "Choose exactly one of --text, --base64, or --stdin.")
    sendInput(defaultOptions(), sessionId, data)
  of "resize":
    let sessionId = requireSessionId(arguments)
    let colsIndex = arguments.find("--cols")
    let rowsIndex = arguments.find("--rows")
    if colsIndex < 0 or rowsIndex < 0 or colsIndex + 1 >= arguments.len or rowsIndex + 1 >= arguments.len:
      raise newException(ValueError, "resize requires --cols and --rows.")
    resize(defaultOptions(), sessionId, parseNumber(arguments[colsIndex + 1], "--cols"), parseNumber(arguments[rowsIndex + 1], "--rows"))
  of "open": openSession(defaultOptions(), if arguments.len > 1: arguments[1] else: "")
  of "agent": runAgent(defaultOptions())
  of "mcp": runMcp(defaultOptions())
  else:
    raise newException(ValueError, "Separate ttyglass options from the command with --.")

when isMainModule:
  try:
    quit(main(commandLineParams()))
  except CatchableError:
    stderr.writeLine("ttyglass: " & getCurrentException().msg)
    quit(2)
