import std/streams

import ./ipc

when defined(windows):
  import ./pty_windows
else:
  import ./pty_posix

proc runPtyHost*(): int =
  let input = newFileStream(stdin)
  let output = newFileStream(stdout)
  try:
    let frame = input.readFrame()
    if frame.kind != StartFrame:
      output.writeFrame(ErrorFrame, "The PTY host expected a start frame.")
      return 2
    let start = frame.payload.parseStart()
    when defined(windows):
      result = runWindowsPtyHost(start, input, output)
    else:
      result = runPosixPtyHost(start, input, output)
  except CatchableError as error:
    try:
      output.writeFrame(ErrorFrame, error.msg)
    except CatchableError:
      discard
    result = 1
