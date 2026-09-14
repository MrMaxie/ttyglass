import jsony
import std/json

type
  DiagnosticRecord* = object
    time*: string
    source*: string
    level*: string
    event*: string
    message*: string
    fields*: JsonNode

  MetadataMessage* = object
    `type`*: string
    sessionId*: string
    name*: string
    mode*: string
    argv*: JsonNode
    displayCommand*: string
    shell*: string
    restartable*: bool

  OutputMessage* = object
    `type`*: string
    data*: string

  StatusMessage* = object
    `type`*: string
    state*: string
    pid*: int
    exitCode*: int
    signal*: int
    message*: string

  LogMessage* = object
    `type`*: string
    entry*: DiagnosticRecord

  LogsMessage* = object
    `type`*: string
    entries*: seq[DiagnosticRecord]

  SimpleMessage* = object
    `type`*: string

  ResizeMessage* = object
    `type`*: string
    cols*: int
    rows*: int

proc metadataJson*(
  sessionId, name, mode: string,
  argv: JsonNode,
  displayCommand, shell: string,
  restartable: bool,
): string =
  MetadataMessage(
    `type`: "metadata",
    sessionId: sessionId,
    name: name,
    mode: mode,
    argv: argv,
    displayCommand: displayCommand,
    shell: shell,
    restartable: restartable,
  ).toJson()

proc outputJson*(data: string): string =
  OutputMessage(`type`: "output", data: data).toJson()

proc runningJson*(pid: int): string =
  StatusMessage(`type`: "status", state: "running", pid: pid).toJson()

proc exitedJson*(pid, exitCode: int): string =
  StatusMessage(
    `type`: "status",
    state: "exited",
    pid: pid,
    exitCode: exitCode,
  ).toJson()

proc failedJson*(message: string): string =
  StatusMessage(`type`: "status", state: "failed", message: message).toJson()

proc startingJson*(): string =
  StatusMessage(`type`: "status", state: "starting").toJson()

proc stoppedJson*(): string =
  StatusMessage(`type`: "status", state: "stopped").toJson()

proc resizedJson*(cols, rows: int): string =
  ResizeMessage(`type`: "resize", cols: cols, rows: rows).toJson()

proc logJson*(entry: DiagnosticRecord): string =
  LogMessage(`type`: "log", entry: entry).toJson()

proc logsJson*(entries: seq[DiagnosticRecord]): string =
  LogsMessage(`type`: "logs", entries: entries).toJson()

proc logsClearedJson*(): string =
  SimpleMessage(`type`: "logsCleared").toJson()
