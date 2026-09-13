import std/[json, strutils, unittest]

import ttyglass/[diagnostics, messages]

suite "application diagnostics":
  test "normalizes a typed JSON record with jsony":
    let record = normalizeDiagnostic(
      """{"time":1700000000000,"source":"demo","level":40,"event":"ready","message":"ok","fields":{"count":2}}""",
      "fallback",
    )
    check record.source == "demo"
    check record.level == "warn"
    check record.event == "ready"
    check record.message == "ok"
    check record.fields["count"].getInt() == 2
    check logJson(record).contains("\"type\":\"log\"")

  test "rejects diagnostics that exceed the field depth":
    expect DiagnosticError:
      discard normalizeDiagnostic(
        """{"event":"deep","fields":{"a":{"b":{"c":{"d":1}}}}}""",
        "fixture",
      )

  test "parses bounded newline-delimited records":
    let records = parseDiagnosticRequest(
      """{"event":"one"}
{"event":"two"}""",
      "application/x-ndjson",
      "fixture",
    )
    check records.len == 2
    check records[1].event == "two"
