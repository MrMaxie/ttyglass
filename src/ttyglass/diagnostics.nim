import jsony
import std/[json, strutils, times]

import ./messages

type DiagnosticError* = object of CatchableError

const
  MaximumArrayItems* = 32
  MaximumFields* = 32
  MaximumDepth* = 3
  MaximumKeyLength* = 128
  MaximumStringLength* = 2048
  MaximumRecordsPerRequest* = 100

proc truncate(value: string, maximum: int): string =
  if value.len <= maximum:
    value
  else:
    value[0 ..< maximum]

proc safeText(node: JsonNode, key: string, maximum: int): string =
  if node.kind != JObject or key notin node or node[key].kind != JString:
    return ""
  result = node[key].getStr().strip().truncate(maximum)

proc normalizeLevel(node: JsonNode): string =
  if node.kind == JString:
    let candidate = node.getStr()
    if candidate in ["trace", "debug", "info", "warn", "error", "fatal"]:
      return candidate
  elif node.kind in {JInt, JFloat}:
    let value = node.getFloat()
    if value >= 60: return "fatal"
    if value >= 50: return "error"
    if value >= 40: return "warn"
    if value >= 30: return "info"
    if value >= 20: return "debug"
    return "trace"
  "info"

proc timestamp(node: JsonNode): string =
  var value = now().utc()
  try:
    case node.kind
    of JInt, JFloat:
      value = fromUnixFloat(node.getFloat() / 1000).utc()
    of JString:
      let parsed = parse(node.getStr(), "yyyy-MM-dd'T'HH:mm:ss'.'fffzzz")
      value = parsed.utc()
    else:
      discard
  except ValueError:
    discard
  value.format("yyyy-MM-dd'T'HH:mm:ss'.'fff'Z'")

proc normalizeValue(node: JsonNode, depth: int): JsonNode =
  case node.kind
  of JNull, JBool, JInt, JFloat:
    result = node
  of JString:
    result = %node.getStr().truncate(MaximumStringLength)
  of JArray:
    if node.len > MaximumArrayItems:
      raise newException(DiagnosticError, "Diagnostic arrays may contain at most 32 items.")
    if depth >= MaximumDepth:
      raise newException(DiagnosticError, "Diagnostic fields exceed the maximum depth.")
    result = newJArray()
    for item in node:
      result.add(item.normalizeValue(depth + 1))
  of JObject:
    if node.len > MaximumFields:
      raise newException(DiagnosticError, "Diagnostic objects may contain at most 32 fields.")
    if depth >= MaximumDepth:
      raise newException(DiagnosticError, "Diagnostic fields exceed the maximum depth.")
    result = newJObject()
    for key, value in node:
      result[key.truncate(MaximumKeyLength)] = value.normalizeValue(depth + 1)

proc normalizeDiagnostic*(payload: string, defaultSource: string): DiagnosticRecord =
  let node = payload.fromJson()
  if node.kind != JObject:
    raise newException(DiagnosticError, "Each diagnostic record must be a JSON object.")

  var fields = newJObject()
  if "fields" in node:
    fields = node["fields"].normalizeValue(0)
    if fields.kind != JObject:
      raise newException(DiagnosticError, "Diagnostic fields must be a JSON object.")

  let source = node.safeText("source", 64)
  let event = node.safeText("event", 128)
  result = DiagnosticRecord(
    time: timestamp(if "time" in node: node["time"] else: newJNull()),
    source: if source.len > 0: source else: defaultSource,
    level: normalizeLevel(if "level" in node: node["level"] else: %"info"),
    event: if event.len > 0: event else: "message",
    message: node.safeText("message", MaximumStringLength),
    fields: fields,
  )

proc parseDiagnosticRequest*(body, contentType, defaultSource: string): seq[DiagnosticRecord] =
  if body.strip().len == 0:
    raise newException(DiagnosticError, "Diagnostic request body is empty.")

  if contentType.toLowerAscii().startsWith("application/json"):
    return @[normalizeDiagnostic(body, defaultSource)]

  for line in body.splitLines():
    if line.strip().len == 0:
      continue
    if result.len >= MaximumRecordsPerRequest:
      raise newException(DiagnosticError, "A diagnostic request may contain at most 100 records.")
    result.add(normalizeDiagnostic(line, defaultSource))
