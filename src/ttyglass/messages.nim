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
    command*: string

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

proc metadataJson*(command: string): string =
  MetadataMessage(`type`: "metadata", command: command).toJson()

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

proc logJson*(entry: DiagnosticRecord): string =
  LogMessage(`type`: "log", entry: entry).toJson()

proc logsJson*(entries: seq[DiagnosticRecord]): string =
  LogsMessage(`type`: "logs", entries: entries).toJson()

proc logsClearedJson*(): string =
  SimpleMessage(`type`: "logsCleared").toJson()
