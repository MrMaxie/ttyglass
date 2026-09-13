import std/[streams, unittest]

import ttyglass/ipc

suite "PTY host protocol":
  test "round-trips binary output without changing bytes":
    let stream = newStringStream()
    let payload = "\x00\x01terminal\xff"
    stream.writeFrame(OutputFrame, payload)
    stream.setPosition(0)
    let frame = stream.readFrame()
    check frame.kind == OutputFrame
    check frame.payload == payload

  test "serializes typed control messages with jsony":
    let original = StartControl(
      command: "demo",
      arguments: @["--flag", "value"],
      cwd: "workspace",
      cols: 88,
      rows: 26,
    )
    let parsed = parseStart(startPayload(original))
    check parsed.command == original.command
    check parsed.arguments == original.arguments
    check parsed.cols == 88
